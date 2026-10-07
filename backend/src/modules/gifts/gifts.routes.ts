import type { FastifyInstance } from 'fastify';

import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import { giftSchema } from './gifts.model.js';
import type { GiftsService } from './gifts.service.js';

export async function giftsRoutes(app: FastifyInstance, gifts: GiftsService) {
  const tag = 'Ideias de presente';

  app.put(
    '/gift-ideas/:id',
    { schema: doc({ tag, summary: 'Criar ou atualizar uma ideia de presente', params: idParams, body: giftSchema.omit({ id: true }) }) },
    (req) => {
      const { id } = idParams.parse(req.params);
      return gifts.save(req.uid, giftSchema.parse({ ...(req.body as object), id }));
    },
  );

  app.delete('/gift-ideas/:id', { schema: doc({ tag, summary: 'Apagar uma ideia de presente', params: idParams }) }, async (req, reply) => {
    await gifts.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
