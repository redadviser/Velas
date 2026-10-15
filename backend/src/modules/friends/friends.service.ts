import { tx, type Db } from '../../core/database.js';
import { HttpError } from '../../core/errors.js';
import type { RealtimeHub } from '../../core/realtime.js';
import type { PhotoStorage } from '../../core/storage.js';
import type { FriendRequestResult, FriendsList } from './friends.model.js';

/** Pedidos de amizade e lista de amigos. */
export class FriendsService {
  constructor(
    private readonly db: Db,
    private readonly hub: RealtimeHub,
    private readonly storage: PhotoStorage,
  ) {}

  list(userId: string): Promise<FriendsList> {
    return tx(this.db, userId, async (c) => {
      const { rows } = await c.query<{
        id: string;
        status: string;
        incoming: boolean;
        user_id: string;
        display_name: string;
        username: string | null;
        photo_path: string | null;
        created_at: string;
        responded_at: string | null;
      }>(
        `select f.id, f.status, f.addressee_id = $1 as incoming, p.id as user_id, p.display_name, p.username,
                p.photo_path, f.created_at, f.responded_at
         from friendships f
         join profiles p on p.id = case when f.requester_id = $1 then f.addressee_id else f.requester_id end
         where $1 in (f.requester_id, f.addressee_id)
         order by lower(p.display_name), f.created_at`,
        [userId],
      );
      const user = (r: (typeof rows)[number]) => ({
        user_id: r.user_id,
        display_name: r.display_name,
        username: r.username,
        photo_url: this.storage.urlOf(r.photo_path),
      });
      return {
        friends: rows.filter((r) => r.status === 'accepted').map((r) => ({ ...user(r), since: r.responded_at ?? r.created_at })),
        incoming: rows
          .filter((r) => r.status === 'pending' && r.incoming)
          .map((r) => ({ ...user(r), id: r.id, created_at: r.created_at })),
        outgoing: rows
          .filter((r) => r.status === 'pending' && !r.incoming)
          .map((r) => ({ ...user(r), id: r.id, created_at: r.created_at })),
      };
    });
  }

  /** Pedir amizade. Se a outra pessoa já me tinha pedido, fica aceite. */
  async request(userId: string, otherId: string): Promise<FriendRequestResult> {
    if (otherId === userId) return 'self';
    const result = await tx(this.db, userId, async (c): Promise<FriendRequestResult> => {
      if (!(await c.query('select 1 from profiles where id = $1', [otherId])).rowCount) return 'not_found';
      const { rows } = await c.query<{ id: string; status: string; requester_id: string }>(
        `select id, status, requester_id from friendships
         where least(requester_id, addressee_id) = least($1::uuid, $2::uuid)
           and greatest(requester_id, addressee_id) = greatest($1::uuid, $2::uuid)`,
        [userId, otherId],
      );
      const f = rows[0];
      if (f?.status === 'accepted') return 'already_friends';
      if (f && f.requester_id === userId) return 'already_sent';
      if (f) {
        await c.query(`update friendships set status = 'accepted', responded_at = now() where id = $1`, [f.id]);
        return 'accepted';
      }
      await c.query('insert into friendships (requester_id, addressee_id) values ($1, $2)', [userId, otherId]);
      return 'sent';
    });
    if (result === 'sent' || result === 'accepted') this.hub.send([userId, otherId], { type: 'friends' });
    return result;
  }

  /** Aceitar ou recusar um pedido recebido. */
  async respond(userId: string, requestId: string, accept: boolean): Promise<void> {
    const other = await tx(this.db, userId, async (c) => {
      const { rows } = accept
        ? await c.query<{ requester_id: string }>(
            `update friendships set status = 'accepted', responded_at = now()
             where id = $1 and addressee_id = $2 and status = 'pending' returning requester_id`,
            [requestId, userId],
          )
        : await c.query<{ requester_id: string }>(
            `delete from friendships where id = $1 and addressee_id = $2 and status = 'pending' returning requester_id`,
            [requestId, userId],
          );
      if (!rows[0]) throw new HttpError(404, 'friend_request_not_found');
      return rows[0].requester_id;
    });
    this.hub.send([userId, other], { type: 'friends' });
  }

  /** Deixar de ser amigo, ou cancelar um pedido (feito ou recebido). */
  async remove(userId: string, otherId: string): Promise<void> {
    await tx(this.db, userId, (c) =>
      c.query(
        `delete from friendships
         where least(requester_id, addressee_id) = least($1::uuid, $2::uuid)
           and greatest(requester_id, addressee_id) = greatest($1::uuid, $2::uuid)`,
        [userId, otherId],
      ),
    );
    this.hub.send([userId, otherId], { type: 'friends' });
  }
}
