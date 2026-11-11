import { tx, type Db } from '../../core/database.js';
import { notFound } from '../../core/errors.js';
import type { FriendWishlist, WishInput, WishRow } from './wishlist.model.js';

const columns = 'id, title, price, link, notes, created_at';

export class WishlistService {
  constructor(private readonly db: Db) {}

  async mine(userId: string): Promise<WishRow[]> {
    const { rows } = await this.db.query<WishRow>(
      `select ${columns} from wishlist_items where user_id = $1 order by created_at`,
      [userId],
    );
    return rows;
  }

  async save(userId: string, w: WishInput): Promise<WishRow> {
    const { rows } = await this.db.query<WishRow>(
      `insert into wishlist_items (id, user_id, title, price, link, notes, created_at)
       values ($1, $2, $3, $4, $5, $6, coalesce($7, now()))
       on conflict (id) do update set
         title = excluded.title, price = excluded.price, link = excluded.link, notes = excluded.notes
       where wishlist_items.user_id = excluded.user_id
       returning ${columns}`,
      [w.id, userId, w.title, w.price ?? null, w.link, w.notes, w.created_at ?? null],
    );
    if (!rows[0]) throw notFound();
    return rows[0];
  }

  async remove(userId: string, wishId: string): Promise<void> {
    await this.db.query('delete from wishlist_items where id = $1 and user_id = $2', [wishId, userId]);
  }

  /** Só para amigos (amizade aceite); a quem não é, responde como se não existisse. */
  ofFriend(userId: string, friendId: string): Promise<FriendWishlist> {
    return tx(this.db, userId, async (c) => {
      const { rows } = await c.query<{ interests: string[] }>(
        `select p.interests from profiles p
         where p.id = $2 and exists (
           select 1 from friendships f
           where f.status = 'accepted'
             and ((f.requester_id = $1 and f.addressee_id = $2) or (f.requester_id = $2 and f.addressee_id = $1)))`,
        [userId, friendId],
      );
      if (!rows[0]) throw notFound();
      const items = await c.query<WishRow>(
        `select ${columns} from wishlist_items where user_id = $1 order by created_at`,
        [friendId],
      );
      return { interests: rows[0].interests, items: items.rows };
    });
  }
}
