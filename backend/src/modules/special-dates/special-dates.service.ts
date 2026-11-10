import type { Db, Tx } from '../../core/database.js';
import { notFound } from '../../core/errors.js';
import type { SpecialDateInput, SpecialDateRow } from './special-dates.model.js';

export class SpecialDatesService {
  constructor(private readonly db: Db) {}

  async listIn(c: Tx, userId: string): Promise<SpecialDateRow[]> {
    const { rows } = await c.query<SpecialDateRow>(
      'select * from special_dates where user_id = $1 order by month, day',
      [userId],
    );
    return rows;
  }

  /** Insere ou atualiza; nunca toca em linhas de outro utilizador. */
  async save(userId: string, d: SpecialDateInput): Promise<SpecialDateRow> {
    const { rows } = await this.db.query<SpecialDateRow>(
      `insert into special_dates (id, user_id, title, kind, day, month, year, person_id, notes, reminder_days, created_at)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, coalesce($11, now()))
       on conflict (id) do update set
         title = excluded.title, kind = excluded.kind, day = excluded.day, month = excluded.month,
         year = excluded.year, person_id = excluded.person_id, notes = excluded.notes,
         reminder_days = excluded.reminder_days
       where special_dates.user_id = excluded.user_id
       returning *`,
      [
        d.id, userId, d.title, d.kind, d.day, d.month, d.year ?? null, d.person_id ?? null, d.notes,
        d.reminder_days ?? null, d.created_at ?? null,
      ],
    );
    if (!rows[0]) throw notFound();
    return rows[0];
  }

  async remove(userId: string, dateId: string): Promise<void> {
    await this.db.query('delete from special_dates where id = $1 and user_id = $2', [dateId, userId]);
  }
}
