import type { Db, Tx } from '../../core/database.js';
import { notFound } from '../../core/errors.js';
import type { MessageInput, MessageRow } from './messages.model.js';

export class MessagesService {
  constructor(private readonly db: Db) {}

  async listIn(c: Tx, userId: string): Promise<MessageRow[]> {
    const { rows } = await c.query<MessageRow>(
      'select * from messages where user_id = $1 order by updated_at desc',
      [userId],
    );
    return rows;
  }

  /** A pessoa tem de ser do mesmo utilizador (trigger check_owner_refs). */
  async save(userId: string, m: MessageInput): Promise<MessageRow> {
    const { rows } = await this.db.query<MessageRow>(
      `insert into messages (id, user_id, person_id, body, tone) values ($1, $2, $3, $4, $5)
       on conflict (id) do update set person_id = excluded.person_id, body = excluded.body, tone = excluded.tone
       where messages.user_id = excluded.user_id
       returning *`,
      [m.id, userId, m.person_id, m.body, m.tone],
    );
    if (!rows[0]) throw notFound();
    return rows[0];
  }

  async remove(userId: string, messageId: string): Promise<void> {
    await this.db.query('delete from messages where id = $1 and user_id = $2', [messageId, userId]);
  }
}
