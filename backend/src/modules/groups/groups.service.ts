import { tx, type Db, type Tx } from '../../core/database.js';
import { HttpError, notFound } from '../../core/errors.js';
import type { RealtimeHub } from '../../core/realtime.js';
import { imageType, type PhotoStorage } from '../../core/storage.js';
import type { PaymentMethods } from '../../core/validation.js';
import type { GroupInput, GroupJson, MemberInfo, NewMemberInput, PaymentMethod } from './groups.model.js';

/** Grupos com membros, convites e a conversa do grupo. */
const groupsQuery = `
  select g.*,
    (select c.id from conversations c where c.group_id = g.id) as conversation_id,
    coalesce((select json_agg(to_jsonb(m) || jsonb_build_object('photo_path', pp.photo_path) order by m.created_at)
              from group_members m left join profiles pp on pp.id = m.user_id
              where m.group_id = g.id), '[]') as group_members,
    coalesce((select json_agg(i order by i.created_at) from group_invitations i where i.group_id = g.id), '[]') as group_invitations
  from gift_groups g`;

/**
 * Prendas em grupo. Quem vê e quem altera é verificado aqui com
 * is_group_member()/is_group_admin(); as regras por coluna (quem pode mudar
 * o quê) estão nos triggers guard_* (migrations/002_gift_groups.sql).
 */
export class GroupsService {
  constructor(
    private readonly db: Db,
    private readonly storage: PhotoStorage,
    private readonly hub?: RealtimeHub,
  ) {}

  /** Executa como [userId], para os triggers e funções SQL saberem quem é. */
  private as<T>(userId: string, fn: (c: Tx) => Promise<T>) {
    return tx(this.db, userId, fn);
  }

  /** Falha com 404 quando a alteração não tocou em nenhuma linha (sem acesso). */
  private static touched(res: { rowCount: number | null }) {
    if (!res.rowCount) throw notFound();
  }

  /** A fotografia do grupo e a de cada membro com conta, como URLs assinados. */
  private withPhotos({ photo_path, ...g }: GroupJson): GroupJson {
    return {
      ...g,
      photo_url: this.storage.urlOf(photo_path as string | null),
      group_members: g.group_members.map(({ photo_path, ...m }) => ({
        ...m,
        photo_url: this.storage.urlOf(photo_path as string | null),
      })),
    };
  }

  list(userId: string): Promise<GroupJson[]> {
    return this.as(userId, async (c) => {
      const { rows } = await c.query<GroupJson>(`${groupsQuery} where is_group_member(g.id) order by g.created_at desc`);
      return rows.map((g) => this.withPhotos(g));
    });
  }

  /** Cria ou atualiza o grupo e acrescenta membros (só o administrador). */
  save(userId: string, g: GroupInput, newMembers: NewMemberInput[]): Promise<GroupJson> {
    return this.as(userId, async (c) => {
      const existing = await c.query<{ created_by: string }>('select created_by from gift_groups where id = $1', [g.id]);
      if (existing.rows[0] && existing.rows[0].created_by !== userId) throw new HttpError(403, 'forbidden');

      // A ligação à pessoa só faz sentido na lista do próprio administrador.
      let personId = g.person_id ?? null;
      if (personId) {
        const own = await c.query('select 1 from people where id = $1 and user_id = $2', [personId, userId]);
        if (!own.rowCount) personId = null;
      }

      const values = [
        g.id, g.title, g.celebrant_name, g.celebrant_day ?? null, g.celebrant_month ?? null, personId,
        g.gift_description, g.gift_link, g.target_amount, g.split_mode, g.deadline ?? null,
      ];
      if (existing.rowCount) {
        await c.query(
          `update gift_groups set title = $2, celebrant_name = $3, celebrant_day = $4, celebrant_month = $5,
             person_id = $6, gift_description = $7, gift_link = $8, target_amount = $9, split_mode = $10, deadline = $11
           where id = $1`,
          values,
        );
      } else {
        await c.query(
          `insert into gift_groups (id, title, celebrant_name, celebrant_day, celebrant_month, person_id,
             gift_description, gift_link, target_amount, split_mode, deadline, created_by)
           values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
          [...values, userId],
        );
      }

      // O administrador acrescenta-se a si próprio e a participantes sem conta;
      // as outras contas entram por convite ou link.
      for (const m of newMembers) {
        if (m.user_id && m.user_id !== userId) throw new HttpError(403, 'forbidden');
        await c.query(
          `insert into group_members (id, group_id, user_id, display_name, custom_amount, payment_methods)
           values ($1, $2, $3, $4, $5, $6)`,
          [m.id, g.id, m.user_id ?? null, m.display_name, m.custom_amount ?? null, JSON.stringify(m.payment_methods)],
        );
      }
      // O comprador tem de existir antes de ser referenciado.
      await c.query('update gift_groups set buyer_member_id = $2 where id = $1', [g.id, g.buyer_member_id ?? null]);

      const { rows } = await c.query<GroupJson>(`${groupsQuery} where g.id = $1`, [g.id]);
      return this.withPhotos(rows[0]!);
    });
  }

  async remove(userId: string, groupId: string): Promise<void> {
    const { rows } = await this.as(userId, (c) =>
      c.query<{ id: string }>(
        `with conv as (select id from conversations where group_id = $1),
              gone as (delete from gift_groups where id = $1 and created_by = $2 returning id)
         select conv.id from conv where exists (select 1 from gone)`,
        [groupId, userId],
      ),
    );
    // As imagens da conversa do grupo (e a fotografia do grupo) vão com ele.
    if (rows[0]) {
      await this.storage.removeFolder(rows[0].id);
      await this.storage.removeFolder(groupId);
    }
  }

  /** Fotografia do grupo (só o administrador). Substitui a anterior. */
  async setPhoto(userId: string, groupId: string, data: Buffer): Promise<GroupJson> {
    const type = imageType(data);
    if (!type) throw new HttpError(415, 'unsupported_media_type');
    const key = `${groupId}/photo-${Date.now()}.${type.ext}`;
    await this.as(userId, async (c) => {
      if (!(await c.query('select 1 from gift_groups where id = $1 and created_by = $2', [groupId, userId])).rowCount) {
        throw notFound();
      }
    });
    await this.storage.put(key, data);
    return this.replacePhoto(userId, groupId, key);
  }

  removePhoto(userId: string, groupId: string): Promise<GroupJson> {
    return this.replacePhoto(userId, groupId, null);
  }

  private async replacePhoto(userId: string, groupId: string, key: string | null): Promise<GroupJson> {
    const { previous, group, members } = await this.as(userId, async (c) => {
      const { rows } = await c.query<{ photo_path: string | null }>(
        'select photo_path from gift_groups where id = $1 and created_by = $2 for update',
        [groupId, userId],
      );
      if (!rows[0]) throw notFound();
      await c.query('update gift_groups set photo_path = $2 where id = $1', [groupId, key]);
      const { rows: g } = await c.query<GroupJson>(`${groupsQuery} where g.id = $1`, [groupId]);
      const { rows: m } = await c.query<{ id: string }>(
        `select user_id as id from group_members where group_id = $1 and user_id is not null`,
        [groupId],
      );
      return { previous: rows[0].photo_path, group: g[0]!, members: m.map((r) => r.id) };
    }).catch(async (e) => {
      if (key) await this.storage.remove(key);
      throw e;
    });
    if (previous && previous !== key) await this.storage.remove(previous);
    // Os outros membros veem a fotografia nova nas conversas.
    this.hub?.send(members, { type: 'conversations' }, userId);
    return this.withPhotos(group);
  }

  /** Marca a prenda como comprada (comprador ou administrador). */
  async setPurchased(userId: string, groupId: string, purchased: boolean): Promise<void> {
    GroupsService.touched(
      await this.as(userId, (c) =>
        c.query(
          `update gift_groups set purchased_at = case when $2 then now() else null end
           where id = $1 and (is_group_admin(id) or group_buyer_user(id) = app.uid())`,
          [groupId, purchased],
        ),
      ),
    );
  }

  /** Dados de pagamento de quem compra (só para membros). */
  /** Pagamentos na app ligados (Stripe) e a comissão por método. */
  inApp?: { enabled: boolean; fees: Record<string, { percent: number; fixed: number }>; serviceFee: number };

  async payee(userId: string, groupId: string): Promise<Record<string, unknown>> {
    const { rows } = await this.as(userId, (c) =>
      c.query<{ payee: PaymentMethods | null; ready: boolean | null }>(
        `select group_payee($1) as payee,
                (select payouts_enabled from profiles where id = group_buyer_user($1)) as ready`,
        [groupId],
      ),
    );
    const payee = rows[0]?.payee ?? {};
    // in_app: quem compra ligou a conta Stripe, por isso dá para pagar dentro da app.
    const inApp = Boolean(this.inApp?.enabled && rows[0]?.ready);
    return inApp
      ? { ...payee, in_app: true, in_app_fees: this.inApp!.fees, in_app_service_fee: this.inApp!.serviceFee }
      : payee;
  }

  // Membros -----------------------------------------------------------------

  async updateMember(userId: string, memberId: string, m: MemberInfo): Promise<void> {
    GroupsService.touched(
      await this.as(userId, (c) =>
        c.query(
          `update group_members set display_name = $2, custom_amount = $3, payment_methods = $4
           where id = $1 and is_group_member(group_id)`,
          [memberId, m.display_name, m.custom_amount, JSON.stringify(m.payment_methods)],
        ),
      ),
    );
  }

  /** "Já paguei". method = null anula (e anula a confirmação). */
  async setPaid(userId: string, memberId: string, method: PaymentMethod | null): Promise<void> {
    GroupsService.touched(
      await this.as(userId, (c) =>
        c.query(
          `update group_members set
             paid_at = case when $2::text is null then null else now() end,
             paid_method = $2,
             confirmed_at = case when $2::text is null then null else confirmed_at end
           where id = $1 and is_group_member(group_id)`,
          [memberId, method],
        ),
      ),
    );
  }

  /** "Recebi". Confirmar sem o membro ter marcado (ex.: pagou em mão) também conta como pago. */
  async setConfirmed(userId: string, memberId: string, confirmed: boolean): Promise<void> {
    GroupsService.touched(
      await this.as(userId, (c) =>
        c.query(
          `update group_members set
             confirmed_at = case when $2 then now() else null end,
             paid_method = case when $2 and paid_at is null then 'cash' else paid_method end,
             paid_at = case when $2 and paid_at is null then now() else paid_at end
           where id = $1 and is_group_member(group_id)`,
          [memberId, confirmed],
        ),
      ),
    );
  }

  /** O administrador remove alguém, ou o próprio sai. */
  async removeMember(userId: string, memberId: string): Promise<void> {
    await this.as(userId, (c) =>
      c.query('delete from group_members where id = $1 and (is_group_admin(group_id) or user_id = app.uid())', [memberId]),
    );
  }
}
