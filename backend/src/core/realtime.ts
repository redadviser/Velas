import websocket from '@fastify/websocket';
import type { FastifyInstance } from 'fastify';
import type { WebSocket } from 'ws';
import { z } from 'zod';

import type { AccessTokens } from '../modules/auth/tokens.js';

/** Evento enviado às apps ligadas (ver ui/lib/data/api/chat_socket.dart). */
export type RealtimeEvent =
  | { type: 'message'; message: unknown }
  | { type: 'message_updated'; message: unknown }
  | { type: 'read'; conversation_id: string; user_id: string; last_read_at: string }
  | { type: 'typing'; conversation_id: string; user_id: string; name: string }
  | { type: 'conversations' }
  | { type: 'friends' };

/**
 * Ligações WebSocket abertas, por utilizador. Vive na memória do processo:
 * chega para uma instância da API. Com várias instâncias, os eventos teriam
 * de passar por um canal comum (ex.: LISTEN/NOTIFY do Postgres).
 */
export class RealtimeHub {
  private readonly sockets = new Map<string, Set<WebSocket>>();

  add(userId: string, socket: WebSocket) {
    let set = this.sockets.get(userId);
    if (!set) this.sockets.set(userId, (set = new Set()));
    set.add(socket);
  }

  remove(userId: string, socket: WebSocket) {
    const set = this.sockets.get(userId);
    set?.delete(socket);
    if (set?.size === 0) this.sockets.delete(userId);
  }

  send(userIds: Iterable<string>, event: RealtimeEvent, except?: string) {
    const data = JSON.stringify(event);
    for (const id of new Set(userIds)) {
      if (id === except) continue;
      for (const socket of this.sockets.get(id) ?? []) {
        if (socket.readyState === socket.OPEN) socket.send(data);
      }
    }
  }

  get connections(): number {
    let n = 0;
    for (const set of this.sockets.values()) n += set.size;
    return n;
  }
}

const clientMessage = z.discriminatedUnion('type', [
  z.object({ type: z.literal('auth'), token: z.string().max(4000) }),
  z.object({ type: z.literal('typing'), conversation_id: z.guid() }),
  z.object({ type: z.literal('ping') }),
]);

export interface RealtimeHandlers {
  /** "Está a escrever…" — o serviço do chat valida o acesso e reencaminha. */
  typing(userId: string, conversationId: string): Promise<void>;
}

/** Tempo para a app se autenticar depois de abrir a ligação. */
const authTimeoutMs = 10_000;
/** Ping regular: mantém a ligação viva nos proxies e deteta ligações mortas. */
const heartbeatMs = 25_000;

/**
 * GET /ws — a app abre a ligação e envia `{ "type": "auth", "token": "<access token>" }`
 * (o token não vai no URL, para não ficar nos logs). Depois recebe os
 * [RealtimeEvent] e pode enviar `typing`. Os dados continuam a ser lidos e
 * escritos pela API REST; isto só avisa que há novidades.
 */
export async function realtimeRoutes(app: FastifyInstance, hub: RealtimeHub, tokens: AccessTokens, handlers: RealtimeHandlers) {
  await app.register(websocket, { options: { maxPayload: 16 * 1024 } });

  app.get('/ws', { websocket: true, schema: { hide: true } }, (socket) => {
    let userId: string | null = null;
    let alive = true;

    const authTimer = setTimeout(() => {
      if (!userId) socket.close(4401, 'unauthorized');
    }, authTimeoutMs);
    const heartbeat = setInterval(() => {
      if (!alive) return socket.terminate();
      alive = false;
      socket.ping();
    }, heartbeatMs);

    socket.on('pong', () => (alive = true));
    socket.on('close', () => {
      clearTimeout(authTimer);
      clearInterval(heartbeat);
      if (userId) hub.remove(userId, socket);
    });

    socket.on('message', async (raw) => {
      alive = true;
      let msg: z.infer<typeof clientMessage>;
      try {
        msg = clientMessage.parse(JSON.parse(raw.toString()));
      } catch {
        return;
      }
      if (msg.type === 'auth') {
        const uid = await tokens.verify(msg.token);
        if (!uid) return socket.close(4401, 'unauthorized');
        if (userId && userId !== uid) hub.remove(userId, socket);
        userId = uid;
        clearTimeout(authTimer);
        hub.add(uid, socket);
        socket.send(JSON.stringify({ type: 'ready' }));
      } else if (!userId) {
        socket.close(4401, 'unauthorized');
      } else if (msg.type === 'typing') {
        await handlers.typing(userId, msg.conversation_id).catch(() => {});
      } else {
        socket.send(JSON.stringify({ type: 'pong' }));
      }
    });
  });
}
