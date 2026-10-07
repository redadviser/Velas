import type { Db, Tx } from '../../core/database.js';
import { notFound } from '../../core/errors.js';
import type { GiftInput, GiftRow } from './gifts.model.js';

export class GiftsService {
  constructor(private readonly db: Db) {}

  async listIn(c: Tx, userId: string): Promise<GiftRow[]> {
    const { rows } = await c.query<GiftRow>('select * from gift_ideas where user_id = $1 order by created_at', [userId]);
    return rows;
  }

  /** A pessoa tem de ser do mesmo utilizador (trigger check_owner_refs). */
  async save(userId: string, g: GiftInput): Promise<GiftRow> {
    const { rows } = await this.db.query<GiftRow>(
      `insert into gift_ideas (id, user_id, person_id, title, price, link, notes, purchased, created_at)
       values ($1, $2, $3, $4, $5, $6, $7, $8, coalesce($9, now()))
       on conflict (id) do update set
         person_id = excluded.person_id, title = excluded.title, price = excluded.price,
         link = excluded.link, notes = excluded.notes, purchased = excluded.purchased
       where gift_ideas.user_id = excluded.user_id
       returning *`,
      [g.id, userId, g.person_id, g.title, g.price ?? null, g.link, g.notes, g.purchased, g.created_at ?? null],
    );
    if (!rows[0]) throw notFound();
    return rows[0];
  }

  async remove(userId: string, giftId: string): Promise<void> {
    await this.db.query('delete from gift_ideas where id = $1 and user_id = $2', [giftId, userId]);
  }
}
