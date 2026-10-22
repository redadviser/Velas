import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { rateLimits } from '../../core/auth-guard.js';
import { doc } from '../../core/openapi.js';
import { sendSchema } from '../chat/chat.model.js';
import type { ChatService } from '../chat/chat.service.js';
import { pushTokenSchema, readSchema, replySchema, type PushService } from './push.service.js';

const tag = 'Notificações';

/** Com sessão: o telemóvel regista (ou retira) o seu token do Firebase. */
export async function pushRoutes(app: FastifyInstance, push: PushService) {
  app.put(
    '/me/push-token',
    { schema: doc({ tag, summary: 'Registar o token de notificações deste telemóvel', body: pushTokenSchema }) },
    async (req, reply) => {
      await push.register(req.uid, pushTokenSchema.parse(req.body));
      return reply.status(204).send();
    },
  );

  const tokenBody = z.object({ token: z.string().min(1).max(4096) });
  app.delete(
    '/me/push-token',
    { schema: doc({ tag, summary: 'Deixar de receber notificações neste telemóvel (ao terminar sessão)', body: tokenBody }) },
    async (req, reply) => {
      await push.unregister(req.uid, tokenBody.parse(req.body).token);
      return reply.status(204).send();
    },
  );
}

/** Sem sessão: responder ou marcar como lida a partir da notificação (com o token que ela traz). */
export async function pushPublicRoutes(app: FastifyInstance, push: PushService, chat: ChatService) {
  app.post(
    '/push/reply',
    { config: rateLimits.relaxed, schema: doc({ tag, summary: 'Responder a partir da notificação', body: replySchema }) },
    async (req) => {
      const input = replySchema.parse(req.body);
      const { userId, conversationId } = await push.replies.verify(input.token);
      const message = await chat.send(userId, conversationId, sendSchema.parse({ id: input.id, kind: 'text', body: input.body }));
      await chat.markRead(userId, conversationId);
      return message;
    },
  );

  app.post(
    '/push/read',
    { config: rateLimits.relaxed, schema: doc({ tag, summary: 'Marcar como lida a partir da notificação', body: readSchema }) },
    async (req, reply) => {
      const { userId, conversationId } = await push.replies.verify(readSchema.parse(req.body).token);
      await chat.markRead(userId, conversationId);
      return reply.status(204).send();
    },
  );
}
