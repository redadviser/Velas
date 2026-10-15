import websocket from '@fastify/websocket';
import type { FastifyInstance } from 'fastify';
import type { WebSocket } from 'ws';
import { z } from 'zod';

import type { AccessTokens } from '../modules/auth/tokens.js';

/** Evento enviado às apps ligadas (ver ui/lib/data/api/chat_socket.dart). */
export type RealtimeEvent =
  | { type: 'message'; message: unknown }
  | { type: 'message_updated'; message: unknown }
  | { type: 'read'; conversation_id: string; user_id: string; name: string; last_read_at: string }
  | { type: 'presence'; user_id: string; online: boolean; last_seen_at: string | null }
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

  /** Devolve true se é a primeira ligação deste utilizador (ficou online). */
  add(userId: string, socket: WebSocket): boolean {
    let set = this.sockets.get(userId);
    const first = !set;
    if (!set) this.sockets.set(userId, (set = new Set()));
    set.add(socket);
    return first;
  }

  /** Devolve true se era a última ligação deste utilizador (ficou offline). */
  remove(userId: string, socket: WebSocket): boolean {
    const set = this.sockets.get(userId);
    if (!set?.delete(socket)) return false;
    if (set.size > 0) return false;
    this.sockets.delete(userId);
    return true;
  }

  isOnline(userId: string): boolean {
    return this.sockets.has(userId);
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
  /** A pessoa ficou online ou offline (avisa amigos e quem partilha conversas). */
  presence?(userId: string, online: boolean): Promise<void>;
}

/**
 * Espera antes de dar alguém como offline: trocar de rede ou abrir a app
 * outra vez não deve aparecer como "saiu e voltou".
 */
const offlineGraceMs = 15_000;

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
  const goingOffline = new Map<string, NodeJS.Timeout>();
  app.addHook('onClose', async () => {
    for (const t of goingOffline.values()) clearTimeout(t);
  });

  const connected = (uid: string, socket: WebSocket) => {
    const first = hub.add(uid, socket);
    const pending = goingOffline.get(uid);
    if (pending) {
      // Voltou antes de contar como offline: para os outros nunca saiu.
      clearTimeout(pending);
      goingOffline.delete(uid);
    } else if (first) {
      handlers.presence?.(uid, true).catch(() => {});
    }
  };

  const disconnected = (uid: string, socket: WebSocket) => {
    if (!hub.remove(uid, socket)) return;
    goingOffline.set(
      uid,
      setTimeout(() => {
        goingOffline.delete(uid);
        if (!hub.isOnline(uid)) handlers.presence?.(uid, false).catch(() => {});
      }, offlineGraceMs).unref(),
    );
  };

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
      if (userId) disconnected(userId, socket);
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
        if (userId === uid) return socket.send(JSON.stringify({ type: 'ready' }));
        if (userId) disconnected(userId, socket);
        userId = uid;
        clearTimeout(authTimer);
        connected(uid, socket);
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
