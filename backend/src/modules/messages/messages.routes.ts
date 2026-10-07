import type { FastifyInstance } from 'fastify';

import { idParams } from '../../core/validation.js';
import { messageSchema } from './messages.model.js';
import type { MessagesService } from './messages.service.js';

export async function messagesRoutes(app: FastifyInstance, messages: MessagesService) {
  app.put('/messages/:id', (req) => {
    const { id } = idParams.parse(req.params);
    return messages.save(req.uid, messageSchema.parse({ ...(req.body as object), id }));
  });

  app.delete('/messages/:id', async (req, reply) => {
    await messages.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
