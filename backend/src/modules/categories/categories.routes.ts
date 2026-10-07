import type { FastifyInstance } from 'fastify';

import { idParams } from '../../core/validation.js';
import { categorySchema } from './categories.model.js';
import type { CategoriesService } from './categories.service.js';

export async function categoriesRoutes(app: FastifyInstance, categories: CategoriesService) {
  app.put('/categories/:id', (req) => {
    const { id } = idParams.parse(req.params);
    return categories.save(req.uid, categorySchema.parse({ ...(req.body as object), id }));
  });

  app.delete('/categories/:id', async (req, reply) => {
    await categories.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
