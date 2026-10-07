import type { FastifyInstance } from 'fastify';

import { idParams } from '../../core/validation.js';
import { giftSchema } from './gifts.model.js';
import type { GiftsService } from './gifts.service.js';

export async function giftsRoutes(app: FastifyInstance, gifts: GiftsService) {
  app.put('/gift-ideas/:id', (req) => {
    const { id } = idParams.parse(req.params);
    return gifts.save(req.uid, giftSchema.parse({ ...(req.body as object), id }));
  });

  app.delete('/gift-ideas/:id', async (req, reply) => {
    await gifts.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
