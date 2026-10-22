import { SignJWT, jwtVerify } from 'jose';
import { z } from 'zod';

import type { Db } from '../../core/database.js';
import { HttpError } from '../../core/errors.js';
import { id } from '../../core/validation.js';
import type { MessageJson } from '../chat/chat.model.js';
import { previewOf, pushCopy } from './push.copy.js';
import type { PushMessage, PushPlatform, PushSender } from './push.gateway.js';

export const pushTokenSchema = z.object({
  token: z.string().min(20).max(4096),
  platform: z.enum(['android', 'ios']),
  lang: z.enum(['pt', 'en', 'es', 'fr']).default('pt'),
});
export type PushTokenInput = z.infer<typeof pushTokenSchema>;

/** Responder a partir da notificação (sem sessão: o token da notificação basta). */
export const replySchema = z.object({
  token: z.string().max(2000),
  /** Gerado no telemóvel: repetir o pedido não duplica a mensagem. */
  id,
  body: z.string().trim().min(1).max(4000),
});
export const readSchema = z.object({ token: z.string().max(2000) });

/**
 * Token que vai em cada notificação de mensagem e só serve para responder ou
 * marcar como lida *aquela* conversa. Assim a resposta funciona com a app
 * fechada sem mexer na sessão (o refresh token roda e não pode ser usado à parte).
 */
export class ReplyTokens {
  private readonly key: Uint8Array;
  private static readonly audience = 'velas-push-reply';

  constructor(secret: string) {
    this.key = new TextEncoder().encode(secret);
  }

  sign(userId: string, conversationId: string): Promise<string> {
    return new SignJWT({ cid: conversationId })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(userId)
      .setAudience(ReplyTokens.audience)
      .setIssuedAt()
      .setExpirationTime('7d')
      .sign(this.key);
  }

  async verify(token: string): Promise<{ userId: string; conversationId: string }> {
    try {
      const { payload } = await jwtVerify(token, this.key, { algorithms: ['HS256'], audience: ReplyTokens.audience });
      if (!payload.sub || typeof payload.cid !== 'string') throw new Error('claims');
      return { userId: payload.sub, conversationId: payload.cid };
    } catch {
      throw new HttpError(401, 'invalid_token');
    }
  }
}

/** Notificações push (Firebase Cloud Messaging). Sem FIREBASE_SERVICE_ACCOUNT, não envia nada. */
export class PushService {
  /** Avisos de envios falhados (o log da app). */
  onError: (e: unknown) => void = () => {};
  /** Quem tem a app aberta (WebSocket ligado) já recebe tudo por lá. */
  isOnline: (userId: string) => boolean = () => false;

  constructor(
    private readonly db: Db,
    private readonly sender: PushSender | undefined,
    readonly replies: ReplyTokens,
  ) {}

  get enabled(): boolean {
    return Boolean(this.sender);
  }

  /** O telemóvel muda de conta: o token passa para quem tem a sessão agora. */
  async register(userId: string, input: PushTokenInput): Promise<void> {
    await this.db.query(
      `insert into push_tokens (token, user_id, platform, lang) values ($1, $2, $3, $4)
       on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform,
                                         lang = excluded.lang, updated_at = now()`,
      [input.token, userId, input.platform, input.lang],
    );
  }

  async unregister(userId: string, token: string): Promise<void> {
    await this.db.query('delete from push_tokens where token = $1 and user_id = $2', [token, userId]);
  }

  /** Envia a cada telemóvel destas pessoas a notificação feita para a sua língua. */
  private async deliver(
    userIds: string[],
    build: (userId: string, lang: string) => PushMessage | Promise<PushMessage>,
  ): Promise<void> {
    const sender = this.sender;
    if (!sender || userIds.length === 0) return;
    const { rows } = await this.db.query<{ token: string; user_id: string; platform: PushPlatform; lang: string }>(
      'select token, user_id, platform, lang from push_tokens where user_id = any($1)',
      [userIds],
    );
    await Promise.all(
      rows.map(async (t) => {
        try {
          const result = await sender.send(t.token, t.platform, await build(t.user_id, t.lang));
          if (result === 'unregistered') await this.db.query('delete from push_tokens where token = $1', [t.token]);
        } catch (e) {
          this.onError(e);
        }
      }),
    );
  }

  /**
   * Mensagem nova numa conversa: para quem não a tem aberta, respeitando as
   * notificações desligadas, as conversas silenciadas e os bloqueios.
   */
  async chatMessage(message: MessageJson, recipientIds: string[]): Promise<void> {
    if (!this.sender || !message.sender_id) return;
    const senderId = message.sender_id;
    const { rows } = await this.db.query<{ id: string; previews: boolean }>(
      `select p.id, p.message_previews as previews
       from profiles p
       left join conversation_prefs cp on cp.conversation_id = $1 and cp.user_id = p.id
       where p.id = any($2) and p.id <> $3 and p.message_notifications
         and (cp.muted_until is null or cp.muted_until <= now())
         and not is_blocked(p.id, $3)`,
      [message.conversation_id, recipientIds, senderId],
    );
    const targets = rows.filter((r) => !this.isOnline(r.id));
    if (targets.length === 0) return;
    const previews = new Map(targets.map((r) => [r.id, r.previews]));

    const { rows: conv } = await this.db.query<{ group_title: string | null }>(
      'select g.title as group_title from conversations c left join gift_groups g on g.id = c.group_id where c.id = $1',
      [message.conversation_id],
    );
    const groupTitle = conv[0]?.group_title ?? null;
    const name = message.sender_name ?? '';

    await this.deliver(
      targets.map((r) => r.id),
      async (userId, lang) => {
        const c = pushCopy(lang);
        const text = previewOf(c, message.kind, message.body);
        const body = !previews.get(userId) ? c.newMessage : groupTitle ? c.inGroup(name.split(' ')[0] ?? name, text) : text;
        return {
          title: groupTitle ?? name,
          body,
          // Sem categoria no iOS: o "Responder" de um push mostrado pelo sistema não
          // chega à app (no Android a app desenha a notificação e responde).
          threadId: message.conversation_id,
          data: {
            type: 'chat',
            conversation_id: message.conversation_id,
            message_id: message.id,
            reply_token: await this.replies.sign(userId, message.conversation_id),
          },
        };
      },
    );
  }

  /** A mensagem agendada foi publicada no mural (ou não conseguiu). */
  async scheduledMessage(userId: string, p: { personId: string; personName: string; ok: boolean }): Promise<void> {
    await this.deliver([userId], (_, lang) => {
      const c = pushCopy(lang);
      return {
        title: p.ok ? c.scheduledSent(p.personName) : c.scheduledFailed(p.personName),
        body: p.ok ? c.scheduledSentBody : c.scheduledFailedBody,
        data: { type: p.ok ? 'scheduled_sent' : 'scheduled_failed', person_id: p.personId },
      };
    });
  }
}
