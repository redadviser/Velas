import { tx, type Db, type Tx } from '../../core/database.js';
import { HttpError, notFound } from '../../core/errors.js';
import type { PartyInput, PartyJson, TaskInput } from './parties.model.js';

const partiesQuery = `
  select p.*,
    coalesce((select json_agg(g order by g.created_at) from party_guests g where g.party_id = p.id), '[]') as guests,
    coalesce((select json_agg(t order by t.created_at) from party_tasks t where t.party_id = p.id), '[]') as tasks
  from parties p`;

/** Festas surpresa: vê e altera quem criou; os convidados com conta veem, respondem e tratam das tarefas. */
export class PartiesService {
  constructor(private readonly db: Db) {}

  private as<T>(userId: string, fn: (c: Tx) => Promise<T>) {
    return tx(this.db, userId, fn);
  }

  private static async role(c: Tx, partyId: string, userId: string): Promise<'admin' | 'guest' | null> {
    const { rows } = await c.query<{ admin: boolean; guest: boolean }>(
      `select p.created_by = $2 as admin,
              exists (select 1 from party_guests g where g.party_id = p.id and g.user_id = $2) as guest
       from parties p where p.id = $1`,
      [partyId, userId],
    );
    const r = rows[0];
    return !r ? null : r.admin ? 'admin' : r.guest ? 'guest' : null;
  }

  private static async requireMember(c: Tx, partyId: string, userId: string) {
    const role = await PartiesService.role(c, partyId, userId);
    if (!role) throw notFound();
    return role;
  }

  private static async one(c: Tx, partyId: string, userId: string): Promise<PartyJson> {
    const { rows } = await c.query<PartyJson>(`${partiesQuery} where p.id = $1`, [partyId]);
    const p = rows[0];
    if (!p) throw notFound();
    // A pessoa ligada é da lista de quem criou: os outros não a recebem.
    return p.created_by === userId ? p : { ...p, person_id: null };
  }

  private static async addSelf(c: Tx, partyId: string, userId: string, rsvp: 'yes' | 'pending') {
    await c.query(
      `insert into party_guests (party_id, user_id, display_name, username, rsvp)
       select $1, p.id, p.display_name, p.username, $3 from profiles p where p.id = $2
       on conflict (party_id, user_id) do nothing`,
      [partyId, userId, rsvp],
    );
  }

  list(userId: string): Promise<PartyJson[]> {
    return this.as(userId, async (c) => {
      const { rows } = await c.query<PartyJson>(
        `${partiesQuery}
         where p.created_by = $1 or exists (select 1 from party_guests g where g.party_id = p.id and g.user_id = $1)
         order by p.starts_at nulls last, p.created_at`,
        [userId],
      );
      return rows.map((p) => (p.created_by === userId ? p : { ...p, person_id: null }));
    });
  }

  /** Cria ou atualiza (só quem criou). Ao criar, quem cria entra como convidado que vai. */
  save(userId: string, p: PartyInput): Promise<PartyJson> {
    return this.as(userId, async (c) => {
      const existing = await c.query<{ created_by: string }>('select created_by from parties where id = $1', [p.id]);
      if (existing.rows[0] && existing.rows[0].created_by !== userId) throw new HttpError(403, 'forbidden');
      let personId = p.person_id ?? null;
      if (personId) {
        const own = await c.query('select 1 from people where id = $1 and user_id = $2', [personId, userId]);
        if (!own.rowCount) personId = null;
      }
      const values = [p.id, p.title, p.celebrant_name, personId, p.starts_at ?? null, p.place, p.notes];
      if (existing.rowCount) {
        await c.query(
          `update parties set title = $2, celebrant_name = $3, person_id = $4, starts_at = $5, place = $6, notes = $7
           where id = $1`,
          values,
        );
      } else {
        await c.query(
          `insert into parties (id, title, celebrant_name, person_id, starts_at, place, notes, created_by)
           values ($1, $2, $3, $4, $5, $6, $7, $8)`,
          [...values, userId],
        );
        await PartiesService.addSelf(c, p.id, userId, 'yes');
      }
      return PartiesService.one(c, p.id, userId);
    });
  }

  async remove(userId: string, partyId: string): Promise<void> {
    await this.db.query('delete from parties where id = $1 and created_by = $2', [partyId, userId]);
  }

  /** Entrar com o código de convite (fica "por responder"). */
  join(userId: string, code: string): Promise<PartyJson> {
    return this.as(userId, async (c) => {
      const { rows } = await c.query<{ id: string }>('select id from parties where invite_code = upper($1)', [code]);
      if (!rows[0]) throw notFound();
      await PartiesService.addSelf(c, rows[0].id, userId, 'pending');
      return PartiesService.one(c, rows[0].id, userId);
    });
  }

  rsvp(userId: string, partyId: string, rsvp: string): Promise<PartyJson> {
    return this.as(userId, async (c) => {
      const res = await c.query('update party_guests set rsvp = $3 where party_id = $1 and user_id = $2', [partyId, userId, rsvp]);
      if (!res.rowCount) throw notFound();
      return PartiesService.one(c, partyId, userId);
    });
  }

  /** Convidado sem conta (só quem criou). */
  addGuest(userId: string, partyId: string, name: string, guestId?: string): Promise<PartyJson> {
    return this.as(userId, async (c) => {
      if ((await PartiesService.requireMember(c, partyId, userId)) !== 'admin') throw new HttpError(403, 'forbidden');
      await c.query(
        'insert into party_guests (id, party_id, display_name) values (coalesce($1, gen_random_uuid()), $2, $3)',
        [guestId ?? null, partyId, name],
      );
      return PartiesService.one(c, partyId, userId);
    });
  }

  /** Quem criou tira qualquer convidado; cada um pode sair. Quem criou não sai (apaga a festa). */
  removeGuest(userId: string, guestId: string): Promise<void> {
    return this.as(userId, async (c) => {
      const { rows } = await c.query<{ party_id: string; user_id: string | null; created_by: string }>(
        'select g.party_id, g.user_id, p.created_by from party_guests g join parties p on p.id = g.party_id where g.id = $1',
        [guestId],
      );
      const g = rows[0];
      if (!g) throw notFound();
      const admin = g.created_by === userId;
      if (g.user_id === g.created_by) throw new HttpError(403, 'forbidden');
      if (!admin && g.user_id !== userId) {
        if (!(await PartiesService.role(c, g.party_id, userId))) throw notFound();
        throw new HttpError(403, 'forbidden');
      }
      await c.query('delete from party_guests where id = $1', [guestId]);
    });
  }

  /** Qualquer membro cria, edita ou marca tarefas. */
  saveTask(userId: string, partyId: string, taskId: string, t: TaskInput): Promise<PartyJson> {
    return this.as(userId, async (c) => {
      await PartiesService.requireMember(c, partyId, userId);
      if (t.assignee_id) {
        const ok = await c.query('select 1 from party_guests where id = $1 and party_id = $2', [t.assignee_id, partyId]);
        if (!ok.rowCount) throw new HttpError(400, 'invalid_assignee');
      }
      const res = await c.query(
        `insert into party_tasks (id, party_id, title, assignee_id, done) values ($1, $2, $3, $4, $5)
         on conflict (id) do update set title = excluded.title, assignee_id = excluded.assignee_id, done = excluded.done
         where party_tasks.party_id = excluded.party_id`,
        [taskId, partyId, t.title, t.assignee_id ?? null, t.done],
      );
      if (!res.rowCount) throw notFound();
      return PartiesService.one(c, partyId, userId);
    });
  }

  removeTask(userId: string, partyId: string, taskId: string): Promise<void> {
    return this.as(userId, async (c) => {
      await PartiesService.requireMember(c, partyId, userId);
      await c.query('delete from party_tasks where id = $1 and party_id = $2', [taskId, partyId]);
    });
  }
}
