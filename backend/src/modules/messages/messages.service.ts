import { randomUUID } from 'node:crypto';

import type { Db, Tx } from '../../core/database.js';
import { HttpError, notFound } from '../../core/errors.js';
import type { RealtimeHub } from '../../core/realtime.js';
import type { CardsService } from '../cards/cards.service.js';
import type { PushService } from '../push/push.service.js';
import type { MessageInput, MessageRow } from './messages.model.js';

/** O que o envio agendado usa (ligado no container, depois de criados os serviços). */
export interface ScheduledDeps {
  cards: CardsService;
  push: PushService;
  hub: RealtimeHub;
}

export class MessagesService {
  scheduled?: ScheduledDeps;

  constructor(private readonly db: Db) {}

  async listIn(c: Tx, userId: string): Promise<MessageRow[]> {
    const { rows } = await c.query<MessageRow>(
      'select * from messages where user_id = $1 order by updated_at desc',
      [userId],
    );
    return rows;
  }

  /**
   * A pessoa tem de ser do mesmo utilizador (trigger check_owner_refs). Mudar a
   * hora marcada volta a pôr a mensagem por enviar.
   */
  async save(userId: string, m: MessageInput): Promise<MessageRow> {
    const scheduledAt = m.scheduled_at && m.schedule_via ? m.scheduled_at : null;
    const via = scheduledAt ? m.schedule_via! : null;
    const friendId = via === 'wall' ? (m.schedule_friend_id ?? null) : null;
    if (via === 'wall') {
      if (!friendId) throw new HttpError(422, 'invalid_value', 'schedule_friend_id');
      const { rows } = await this.db.query<{ ok: boolean }>('select are_friends($1, $2) as ok', [userId, friendId]);
      if (!rows[0]?.ok) throw new HttpError(403, 'not_friends');
    }
    const { rows } = await this.db.query<MessageRow>(
      `insert into messages (id, user_id, person_id, body, tone, scheduled_at, schedule_via, schedule_friend_id, schedule_media_key)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       on conflict (id) do update set
         person_id = excluded.person_id, body = excluded.body, tone = excluded.tone,
         scheduled_at = excluded.scheduled_at, schedule_via = excluded.schedule_via,
         schedule_friend_id = excluded.schedule_friend_id, schedule_media_key = excluded.schedule_media_key,
         sent_at = case when messages.scheduled_at is not distinct from excluded.scheduled_at
                         and messages.schedule_via is not distinct from excluded.schedule_via
                        then messages.sent_at end,
         send_error = case when messages.scheduled_at is not distinct from excluded.scheduled_at
                            and messages.schedule_via is not distinct from excluded.schedule_via
                           then messages.send_error end
       where messages.user_id = excluded.user_id
       returning *`,
      [m.id, userId, m.person_id, m.body, m.tone, scheduledAt, via, friendId, via === 'wall' ? (m.schedule_media_key ?? null) : null],
    );
    if (!rows[0]) throw notFound();
    return rows[0];
  }

  async remove(userId: string, messageId: string): Promise<void> {
    await this.db.query('delete from messages where id = $1 and user_id = $2', [messageId, userId]);
  }

  /**
   * Publica no mural as mensagens agendadas cuja hora chegou (corre a cada
   * minuto). Cada uma é marcada como enviada antes de sair, por isso nunca vai
   * duas vezes; se falhar, fica o motivo e quem a agendou é avisado.
   */
  async sendDue(): Promise<number> {
    const deps = this.scheduled;
    if (!deps) return 0;
    const { rows } = await this.db.query<{
      id: string;
      user_id: string;
      person_id: string;
      body: string;
      friend_id: string | null;
      media_key: string | null;
      person_name: string;
    }>(
      `update messages m set sent_at = now(), send_error = null
       from people p
       where p.id = m.person_id and m.id in (
         select id from messages
         where schedule_via = 'wall' and sent_at is null and scheduled_at <= now()
         order by scheduled_at limit 50
         for update skip locked)
       returning m.id, m.user_id, m.person_id, m.body, m.schedule_friend_id as friend_id,
                 m.schedule_media_key as media_key, p.name as person_name`,
    );
    for (const m of rows) {
      const firstName = m.person_name.trim().split(/\s+/)[0] || m.person_name;
      let ok = true;
      try {
        if (!m.friend_id) throw new HttpError(409, 'friend_gone');
        await deps.cards.create(m.user_id, {
          id: randomUUID(),
          person_id: m.person_id,
          recipient_name: firstName,
          body: m.body,
          recipient_id: m.friend_id,
          ...(m.media_key ? { media_key: m.media_key } : {}),
        });
      } catch (e) {
        ok = false;
        const code = e instanceof HttpError ? e.code : 'send_failed';
        await this.db.query('update messages set send_error = $2 where id = $1', [m.id, code]);
      }
      deps.hub.send([m.user_id], { type: 'data' });
      await deps.push.scheduledMessage(m.user_id, { personId: m.person_id, personName: firstName, ok }).catch(() => {});
    }
    return rows.length;
  }
}
