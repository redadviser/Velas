import type { FastifyInstance } from 'fastify';

import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import { friendRequestSchema, respondFriendSchema, userParams } from './friends.model.js';
import type { FriendsService } from './friends.service.js';

export async function friendsRoutes(app: FastifyInstance, friends: FriendsService) {
  const tag = 'Amigos';

  app.get('/friends', { schema: doc({ tag, summary: 'Amigos e pedidos de amizade pendentes' }) }, (req) => friends.list(req.uid));

  app.post(
    '/friends/requests',
    { schema: doc({ tag, summary: 'Pedir amizade (procura a conta com POST /users/find)', body: friendRequestSchema }) },
    async (req) => ({ result: await friends.request(req.uid, friendRequestSchema.parse(req.body).user_id) }),
  );

  app.post(
    '/friends/requests/:id/respond',
    { schema: doc({ tag, summary: 'Aceitar ou recusar um pedido de amizade', params: idParams, body: respondFriendSchema }) },
    async (req, reply) => {
      await friends.respond(req.uid, idParams.parse(req.params).id, respondFriendSchema.parse(req.body).accept);
      return reply.status(204).send();
    },
  );

  app.delete(
    '/friends/:userId',
    { schema: doc({ tag, summary: 'Remover um amigo ou cancelar um pedido', params: userParams }) },
    async (req, reply) => {
      await friends.remove(req.uid, userParams.parse(req.params).userId);
      return reply.status(204).send();
    },
  );
}
