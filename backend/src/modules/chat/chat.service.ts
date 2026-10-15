import { randomUUID } from 'node:crypto';

import { tx, type Db, type Tx } from '../../core/database.js';
import { HttpError, notFound } from '../../core/errors.js';
import type { RealtimeHub } from '../../core/realtime.js';
import { imageType, PhotoStorage } from '../../core/storage.js';
import type { ConversationJson, MessageJson, Participant, SendInput } from './chat.model.js';

/** Conversas de que [$1] faz parte; [$2] (opcional) filtra uma. */
const conversationsQuery = `
  with mine as (
    select c.* from conversations c
    where ($2::uuid is null or c.id = $2)
      and ($1 in (c.user_a, c.user_b)
           or c.group_id in (select id from gift_groups where created_by = $1
                             union select group_id from group_members where user_id = $1))
  )
  select c.id,
    case when c.group_id is null then 'direct' else 'group' end as kind,
    c.group_id,
    coalesce(g.title, op.display_name, '') as title,
    g.celebrant_name,
    case when c.group_id is null then
      json_build_object('user_id', op.id, 'display_name', op.display_name, 'username', op.username,
                        'photo_path', op.photo_path, 'last_seen_at', op.last_seen_at)
    end as other_user,
    c.last_message_at, c.created_at,
    (select count(*)::int from chat_messages m
     where m.conversation_id = c.id and m.deleted_at is null and m.sender_id is distinct from $1
       and m.created_at > coalesce(r.last_read_at, '-infinity'::timestamptz)) as unread_count,
    (select json_build_object(
        'id', m.id, 'sender_id', m.sender_id, 'sender_name', sp.display_name, 'kind', m.kind,
        'body', case when m.deleted_at is null then left(m.body, 200) else '' end,
        'created_at', m.created_at, 'deleted', m.deleted_at is not null)
     from chat_messages m left join profiles sp on sp.id = m.sender_id
     where m.conversation_id = c.id order by m.created_at desc, m.id desc limit 1) as last_message,
    (select coalesce(json_agg(json_build_object('user_id', rp.id, 'display_name', rp.display_name)
                              order by r2.last_read_at), '[]')
     from conversation_reads r2 join profiles rp on rp.id = r2.user_id
     where r2.conversation_id = c.id and r2.user_id <> $1
       and c.last_message_at is not null and r2.last_read_at >= c.last_message_at
       and r2.user_id in (select u.id from conversation_user_ids(c.id) as u(id))) as seen_by
  from mine c
  left join gift_groups g on g.id = c.group_id
  left join profiles op on c.group_id is null and op.id = case when c.user_a = $1 then c.user_b else c.user_a end
  left join conversation_reads r on r.conversation_id = c.id and r.user_id = $1
  order by coalesce(c.last_message_at, c.created_at) desc`;

/** Mensagens com remetente, resposta e reações. */
const messagesSelect = `
  select m.id, m.conversation_id, m.sender_id, p.display_name as sender_name, p.photo_path as sender_photo_path, m.kind,
    case when m.deleted_at is null then m.body else '' end as body,
    m.media_key, m.media_url, m.width, m.height, m.created_at, m.deleted_at is not null as deleted,
    (select json_build_object('id', q.id, 'sender_name', qp.display_name, 'kind', q.kind,
              'body', case when q.deleted_at is null then left(q.body, 200) else '' end,
              'deleted', q.deleted_at is not null)
     from chat_messages q left join profiles qp on qp.id = q.sender_id where q.id = m.reply_to) as reply,
    coalesce((select json_agg(json_build_object('emoji', r.emoji, 'user_id', r.user_id) order by r.created_at)
              from chat_reactions r where r.message_id = m.id), '[]') as reactions
  from chat_messages m left join profiles p on p.id = m.sender_id`;

type MessageRow = Omit<MessageJson, 'media_url' | 'sender_photo_url'> & {
  media_key: string | null;
  media_url: string | null;
  sender_photo_path: string | null;
};

type ConversationRow = Omit<ConversationJson, 'other_user'> & {
  other_user:
    | (Omit<NonNullable<ConversationJson['other_user']>, 'photo_url' | 'online'> & { photo_path: string | null })
    | null;
};

/**
 * Conversas dos grupos e privadas entre amigos. Os dados vão e vêm pela API
 * REST; depois de cada alteração os participantes ligados recebem um evento
 * pelo [RealtimeHub].
 */
export class ChatService {
  constructor(
    private readonly db: Db,
    private readonly storage: PhotoStorage,
    private readonly hub: RealtimeHub,
  ) {}

  private as<T>(userId: string, fn: (c: Tx) => Promise<T>) {
    return tx(this.db, userId, fn);
  }

  private message(row: MessageRow): MessageJson {
    const { media_key, sender_photo_path, ...rest } = row;
    return {
      ...rest,
      sender_photo_url: this.storage.urlOf(sender_photo_path),
      media_url: !row.deleted && media_key ? this.storage.signedUrl(media_key) : row.deleted ? null : row.media_url,
    };
  }

  private conversation(row: ConversationRow): ConversationJson {
    if (!row.other_user) return { ...row, other_user: null };
    const { photo_path, ...other } = row.other_user;
    return {
      ...row,
      other_user: { ...other, photo_url: this.storage.urlOf(photo_path), online: this.hub.isOnline(other.user_id) },
    };
  }

  private async conversationsIn(c: Tx, userId: string, conversationId: string | null): Promise<ConversationJson[]> {
    const { rows } = await c.query<ConversationRow>(conversationsQuery, [userId, conversationId]);
    return rows.map((r) => this.conversation(r));
  }

  private async messageIn(c: Tx, messageId: string): Promise<MessageJson> {
    const { rows } = await c.query<MessageRow>(`${messagesSelect} where m.id = $1`, [messageId]);
    if (!rows[0]) throw notFound();
    return this.message(rows[0]);
  }

  private static async participantIds(c: Tx, conversationId: string): Promise<string[]> {
    const { rows } = await c.query<{ id: string }>('select id from conversation_user_ids($1) as u(id)', [conversationId]);
    return rows.map((r) => r.id);
  }

  /** Falha com 404 sem acesso; nas privadas, só se escreve a quem ainda é amigo. */
  private static async requireAccess(c: Tx, conversationId: string, { write = false } = {}) {
    const { rows } = await c.query<{ ok: boolean; direct: boolean; friends: boolean }>(
      `select can_chat(id) as ok, group_id is null as direct, coalesce(are_friends(user_a, user_b), false) as friends
       from conversations where id = $1`,
      [conversationId],
    );
    const conv = rows[0];
    if (!conv?.ok) throw notFound();
    if (write && conv.direct && !conv.friends) throw new HttpError(403, 'not_friends');
  }

  // Conversas ---------------------------------------------------------------

  list(userId: string): Promise<ConversationJson[]> {
    return this.as(userId, (c) => this.conversationsIn(c, userId, null));
  }

  get(userId: string, conversationId: string): Promise<ConversationJson & { participants: Participant[] }> {
    return this.as(userId, async (c) => {
      const conv = (await this.conversationsIn(c, userId, conversationId))[0];
      if (!conv) throw notFound();
      const { rows } = await c.query<Omit<Participant, 'photo_url' | 'online'> & { photo_path: string | null }>(
        `select p.id as user_id, p.display_name, p.username, p.photo_path, p.last_seen_at, r.last_read_at
         from conversation_user_ids($1) as u(id)
         join profiles p on p.id = u.id
         left join conversation_reads r on r.conversation_id = $1 and r.user_id = p.id
         order by lower(p.display_name)`,
        [conversationId],
      );
      return {
        ...conv,
        participants: rows.map(({ photo_path, ...p }) => ({
          ...p,
          photo_url: this.storage.urlOf(photo_path),
          online: this.hub.isOnline(p.user_id),
        })),
      };
    });
  }

  /** Abre (ou cria) a conversa privada com um amigo. */
  openDirect(userId: string, otherId: string): Promise<ConversationJson> {
    return this.as(userId, async (c) => {
      const friends = await c.query<{ ok: boolean }>('select are_friends($1, $2) as ok', [userId, otherId]);
      if (!friends.rows[0]?.ok) throw new HttpError(403, 'not_friends');
      const [a, b] = [userId, otherId].sort();
      await c.query(
        `insert into conversations (user_a, user_b) values ($1, $2)
         on conflict (user_a, user_b) where group_id is null do nothing`,
        [a, b],
      );
      const { rows } = await c.query<{ id: string }>(
        'select id from conversations where group_id is null and user_a = $1 and user_b = $2',
        [a, b],
      );
      return (await this.conversationsIn(c, userId, rows[0]!.id))[0]!;
    });
  }

  /** Marca a conversa como lida até agora. */
  async markRead(userId: string, conversationId: string): Promise<void> {
    const { at, ids, name } = await this.as(userId, async (c) => {
      await ChatService.requireAccess(c, conversationId);
      const { rows } = await c.query<{ last_read_at: Date }>(
        `insert into conversation_reads (conversation_id, user_id) values ($1, $2)
         on conflict (conversation_id, user_id) do update set last_read_at = now()
         returning last_read_at`,
        [conversationId, userId],
      );
      const me = await c.query<{ display_name: string }>('select display_name from profiles where id = $1', [userId]);
      return {
        at: rows[0]!.last_read_at,
        ids: await ChatService.participantIds(c, conversationId),
        name: me.rows[0]?.display_name ?? '',
      };
    });
    this.hub.send(
      ids,
      { type: 'read', conversation_id: conversationId, user_id: userId, name, last_read_at: new Date(at).toISOString() },
      userId,
    );
  }

  /**
   * Ficou online/offline (chamado pelo WebSocket): avisa os amigos e quem
   * partilha conversas com a pessoa. Ao sair guarda a hora ("visto por último").
   */
  async presence(userId: string, online: boolean): Promise<void> {
    const seen = online
      ? await this.db.query<{ last_seen_at: Date | null }>('select last_seen_at from profiles where id = $1', [userId])
      : await this.db.query<{ last_seen_at: Date | null }>(
          'update profiles set last_seen_at = now() where id = $1 returning last_seen_at',
          [userId],
        );
    const { rows } = await this.db.query<{ id: string }>(
      `select case when requester_id = $1 then addressee_id else requester_id end as id
       from friendships where status = 'accepted' and $1 in (requester_id, addressee_id)
       union
       select u.id from conversations c, conversation_user_ids(c.id) as u(id)
       where $1 in (c.user_a, c.user_b)
          or c.group_id in (select id from gift_groups where created_by = $1
                            union select group_id from group_members where user_id = $1)`,
      [userId],
    );
    const at = seen.rows[0]?.last_seen_at;
    this.hub.send(
      rows.map((r) => r.id),
      { type: 'presence', user_id: userId, online, last_seen_at: at ? new Date(at).toISOString() : null },
      userId,
    );
  }

  /** "Está a escrever…" (chamado pelo WebSocket). */
  async typing(userId: string, conversationId: string): Promise<void> {
    const { name, ids } = await this.as(userId, async (c) => {
      await ChatService.requireAccess(c, conversationId);
      const { rows } = await c.query<{ display_name: string }>('select display_name from profiles where id = $1', [userId]);
      return { name: rows[0]?.display_name ?? '', ids: await ChatService.participantIds(c, conversationId) };
    });
    this.hub.send(ids, { type: 'typing', conversation_id: conversationId, user_id: userId, name }, userId);
  }

  // Mensagens ---------------------------------------------------------------

  /** Mais recentes primeiro. */
  messages(userId: string, conversationId: string, before: string | undefined, limit: number) {
    return this.as(userId, async (c) => {
      await ChatService.requireAccess(c, conversationId);
      const { rows } = await c.query<MessageRow>(
        `${messagesSelect}
         where m.conversation_id = $1
           and ($2::uuid is null or (m.created_at, m.id) < (select created_at, id from chat_messages where id = $2))
         order by m.created_at desc, m.id desc
         limit $3`,
        [conversationId, before ?? null, limit + 1],
      );
      return { messages: rows.slice(0, limit).map((r) => this.message(r)), has_more: rows.length > limit };
    });
  }

  /** Recebe a imagem (bytes) antes de a enviar numa mensagem. */
  async upload(userId: string, conversationId: string, data: Buffer) {
    const type = imageType(data);
    if (!type) throw new HttpError(415, 'unsupported_media_type');
    await this.as(userId, (c) => ChatService.requireAccess(c, conversationId, { write: true }));
    const key = `${conversationId}/${randomUUID()}.${type.ext}`;
    await this.storage.put(key, data);
    return { media_key: key, media_url: this.storage.signedUrl(key) };
  }

  async send(userId: string, conversationId: string, m: SendInput): Promise<MessageJson> {
    const { message, ids, created } = await this.as(userId, async (c) => {
      await ChatService.requireAccess(c, conversationId, { write: true });

      // Reenvio da mesma mensagem (ex.: a rede falhou depois de gravar).
      const existing = await c.query<{ sender_id: string | null; conversation_id: string }>(
        'select sender_id, conversation_id from chat_messages where id = $1',
        [m.id],
      );
      if (existing.rows[0]) {
        const e = existing.rows[0];
        if (e.sender_id !== userId || e.conversation_id !== conversationId) throw new HttpError(409, 'conflict');
        return { message: await this.messageIn(c, m.id), ids: [], created: false };
      }

      const body = m.body.trim();
      let mediaKey: string | null = null;
      let mediaUrl: string | null = null;
      let { width = null, height = null } = m;
      switch (m.kind) {
        case 'text':
          if (!body) throw new HttpError(422, 'invalid_value', 'empty message');
          break;
        case 'image':
          if (!m.media_key || !PhotoStorage.isKey(m.media_key) || !m.media_key.startsWith(`${conversationId}/`)) {
            throw new HttpError(422, 'invalid_value', 'media_key');
          }
          mediaKey = m.media_key;
          break;
        case 'gif':
          if (!m.media_url) throw new HttpError(422, 'invalid_value', 'media_url');
          mediaUrl = m.media_url;
          break;
        case 'sticker':
          if (m.sticker_id) {
            const { rows } = await c.query<{ media_key: string | null; media_url: string | null; width: number | null; height: number | null }>(
              'select media_key, media_url, width, height from stickers where id = $1 and user_id = $2',
              [m.sticker_id, userId],
            );
            const s = rows[0];
            if (!s) throw notFound();
            ({ width, height } = s);
            mediaUrl = s.media_url;
            // Cópia na pasta da conversa: o sticker pode ser apagado depois.
            if (s.media_key) {
              mediaKey = `${conversationId}/${randomUUID()}.${s.media_key.split('.').pop()}`;
              if (!(await this.storage.copy(s.media_key, mediaKey))) throw notFound();
            }
          } else if (m.media_url) {
            mediaUrl = m.media_url;
          } else {
            throw new HttpError(422, 'invalid_value', 'sticker');
          }
          break;
      }

      const reply = m.reply_to
        ? (await c.query('select 1 from chat_messages where id = $1 and conversation_id = $2', [m.reply_to, conversationId])).rowCount
          ? m.reply_to
          : null
        : null;

      await c.query(
        `insert into chat_messages (id, conversation_id, sender_id, kind, body, media_key, media_url, width, height, reply_to)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
        [m.id, conversationId, userId, m.kind, m.kind === 'sticker' ? '' : body, mediaKey, mediaUrl, width, height, reply],
      );
      // Quem envia leu tudo até aqui.
      await c.query(
        `insert into conversation_reads (conversation_id, user_id) values ($1, $2)
         on conflict (conversation_id, user_id) do update set last_read_at = now()`,
        [conversationId, userId],
      );
      return { message: await this.messageIn(c, m.id), ids: await ChatService.participantIds(c, conversationId), created: true };
    });
    if (created) this.hub.send(ids, { type: 'message', message });
    return message;
  }

  /** Só quem enviou. Fica "mensagem apagada" para todos. */
  async remove(userId: string, messageId: string): Promise<void> {
    const result = await this.as(userId, async (c) => {
      const { rows } = await c.query<{ conversation_id: string; media_key: string | null }>(
        `select conversation_id, media_key from chat_messages
         where id = $1 and sender_id = $2 and deleted_at is null for update`,
        [messageId, userId],
      );
      if (!rows[0]) return null;
      await c.query(
        `update chat_messages set deleted_at = now(), body = '', media_url = null, media_key = null where id = $1`,
        [messageId],
      );
      await c.query('delete from chat_reactions where message_id = $1', [messageId]);
      return {
        ...rows[0],
        message: await this.messageIn(c, messageId),
        ids: await ChatService.participantIds(c, rows[0].conversation_id),
      };
    });
    if (!result) throw notFound();
    if (result.media_key) await this.storage.remove(result.media_key);
    this.hub.send(result.ids, { type: 'message_updated', message: result.message });
  }

  async react(userId: string, messageId: string, emoji: string | null): Promise<MessageJson> {
    const { message, ids } = await this.as(userId, async (c) => {
      const { rows } = await c.query<{ conversation_id: string }>(
        'select conversation_id from chat_messages where id = $1 and deleted_at is null and can_chat(conversation_id)',
        [messageId],
      );
      if (!rows[0]) throw notFound();
      if (emoji) {
        await c.query(
          `insert into chat_reactions (message_id, user_id, emoji) values ($1, $2, $3)
           on conflict (message_id, user_id) do update set emoji = excluded.emoji, created_at = now()`,
          [messageId, userId, emoji],
        );
      } else {
        await c.query('delete from chat_reactions where message_id = $1 and user_id = $2', [messageId, userId]);
      }
      return { message: await this.messageIn(c, messageId), ids: await ChatService.participantIds(c, rows[0].conversation_id) };
    });
    this.hub.send(ids, { type: 'message_updated', message });
    return message;
  }
}
