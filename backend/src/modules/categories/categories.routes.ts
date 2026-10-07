import type { FastifyInstance } from 'fastify';

import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import { categorySchema } from './categories.model.js';
import type { CategoriesService } from './categories.service.js';

export async function categoriesRoutes(app: FastifyInstance, categories: CategoriesService) {
  const tag = 'Categorias';

  app.put(
    '/categories/:id',
    { schema: doc({ tag, summary: 'Criar ou atualizar uma categoria', params: idParams, body: categorySchema.omit({ id: true }) }) },
    (req) => {
      const { id } = idParams.parse(req.params);
      return categories.save(req.uid, categorySchema.parse({ ...(req.body as object), id }));
    },
  );

  app.delete('/categories/:id', { schema: doc({ tag, summary: 'Apagar uma categoria', params: idParams }) }, async (req, reply) => {
    await categories.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
