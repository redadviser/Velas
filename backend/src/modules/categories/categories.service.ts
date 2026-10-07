import type { Db, Tx } from '../../core/database.js';
import { notFound } from '../../core/errors.js';
import type { CategoryInput, CategoryRow } from './categories.model.js';

export class CategoriesService {
  constructor(private readonly db: Db) {}

  async listIn(c: Tx, userId: string): Promise<CategoryRow[]> {
    const { rows } = await c.query<CategoryRow>(
      'select * from categories where user_id = $1 order by sort, created_at',
      [userId],
    );
    return rows;
  }

  /** Insere ou atualiza; nunca toca em linhas de outro utilizador. */
  async save(userId: string, cat: CategoryInput): Promise<CategoryRow> {
    const { rows } = await this.db.query<CategoryRow>(
      `insert into categories (id, user_id, name, color, sort) values ($1, $2, $3, $4, $5)
       on conflict (id) do update set name = excluded.name, color = excluded.color, sort = excluded.sort
       where categories.user_id = excluded.user_id
       returning *`,
      [cat.id, userId, cat.name, cat.color, cat.sort],
    );
    if (!rows[0]) throw notFound();
    return rows[0];
  }

  /** As pessoas da categoria ficam sem categoria (on delete set null). */
  async remove(userId: string, categoryId: string): Promise<void> {
    await this.db.query('delete from categories where id = $1 and user_id = $2', [categoryId, userId]);
  }
}
