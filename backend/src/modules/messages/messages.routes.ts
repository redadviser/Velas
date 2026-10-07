import type { FastifyInstance } from 'fastify';

import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import { messageSchema } from './messages.model.js';
import type { MessagesService } from './messages.service.js';

export async function messagesRoutes(app: FastifyInstance, messages: MessagesService) {
  const tag = 'Mensagens';

  app.put(
    '/messages/:id',
    { schema: doc({ tag, summary: 'Criar ou atualizar uma mensagem', params: idParams, body: messageSchema.omit({ id: true }) }) },
    (req) => {
      const { id } = idParams.parse(req.params);
      return messages.save(req.uid, messageSchema.parse({ ...(req.body as object), id }));
    },
  );

  app.delete('/messages/:id', { schema: doc({ tag, summary: 'Apagar uma mensagem', params: idParams }) }, async (req, reply) => {
    await messages.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
