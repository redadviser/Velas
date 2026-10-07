import { tx, type Db, type Tx } from '../../core/database.js';
import { HttpError, notFound } from '../../core/errors.js';
import { imageType, type PhotoStorage } from '../../core/storage.js';
import type { PersonInput, PersonJson, PersonRow, PhotoJson } from './people.model.js';

export class PeopleService {
  constructor(
    private readonly db: Db,
    private readonly storage: PhotoStorage,
  ) {}

  private toJson = (p: PersonRow): PersonJson => ({
    ...p,
    photo_url: p.photo_path ? this.storage.signedUrl(p.photo_path) : null,
  });

  async listIn(c: Tx, userId: string): Promise<PersonJson[]> {
    const { rows } = await c.query<PersonRow>('select * from people where user_id = $1 order by name', [userId]);
    return rows.map(this.toJson);
  }

  /** Insere ou atualiza; nunca toca em linhas de outro utilizador. */
  private async upsertIn(c: Tx, userId: string, p: PersonInput): Promise<PersonRow> {
    // photo_path não vem da app: só muda pelas rotas de fotografia.
    const { rows } = await c.query<PersonRow>(
      `insert into people (id, user_id, name, birth_day, birth_month, birth_year, relation, category_id,
                           notes, gift_budget, reminder_days, created_at)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, coalesce($12, now()))
       on conflict (id) do update set
         name = excluded.name, birth_day = excluded.birth_day, birth_month = excluded.birth_month,
         birth_year = excluded.birth_year, relation = excluded.relation, category_id = excluded.category_id,
         notes = excluded.notes, gift_budget = excluded.gift_budget, reminder_days = excluded.reminder_days
       where people.user_id = excluded.user_id
       returning *`,
      [
        p.id, userId, p.name, p.birth_day, p.birth_month, p.birth_year ?? null, p.relation, p.category_id ?? null,
        p.notes, p.gift_budget ?? null, p.reminder_days ?? null, p.created_at ?? null,
      ],
    );
    if (!rows[0]) throw notFound();
    return rows[0];
  }

  async save(userId: string, person: PersonInput): Promise<PersonJson> {
    return this.toJson(await tx(this.db, userId, (c) => this.upsertIn(c, userId, person)));
  }

  /** Várias pessoas numa só transação (importação de contactos). */
  async importMany(userId: string, people: PersonInput[]): Promise<PersonJson[]> {
    const saved = await tx(this.db, userId, async (c) => {
      const out: PersonRow[] = [];
      for (const p of people) out.push(await this.upsertIn(c, userId, p));
      return out;
    });
    return saved.map(this.toJson);
  }

  /** As prendas e mensagens da pessoa são apagadas em cascata. */
  async remove(userId: string, personId: string): Promise<void> {
    const { rows } = await this.db.query<{ photo_path: string | null }>(
      'delete from people where id = $1 and user_id = $2 returning photo_path',
      [personId, userId],
    );
    if (rows[0]?.photo_path) await this.storage.remove(rows[0].photo_path);
  }

  async setPhoto(userId: string, personId: string, data: Buffer): Promise<PhotoJson> {
    const type = imageType(data);
    if (!type) throw new HttpError(415, 'unsupported_media_type');

    const current = await this.db.query<{ photo_path: string | null }>(
      'select photo_path from people where id = $1 and user_id = $2',
      [personId, userId],
    );
    if (!current.rowCount) throw notFound();

    const key = `${userId}/${personId}-${Date.now()}.${type.ext}`;
    await this.storage.put(key, data);
    const updated = await this.db.query('update people set photo_path = $3 where id = $1 and user_id = $2', [
      personId,
      userId,
      key,
    ]);
    if (!updated.rowCount) {
      await this.storage.remove(key);
      throw notFound();
    }
    const previous = current.rows[0]!.photo_path;
    if (previous && previous !== key) await this.storage.remove(previous);
    return { photo_path: key, photo_url: this.storage.signedUrl(key) };
  }

  async removePhoto(userId: string, personId: string): Promise<void> {
    const { rows } = await this.db.query<{ old: string | null }>(
      `update people p set photo_path = null
       from (select photo_path as old from people where id = $1 and user_id = $2) prev
       where p.id = $1 and p.user_id = $2
       returning prev.old`,
      [personId, userId],
    );
    if (rows[0]?.old) await this.storage.remove(rows[0].old);
  }
}
