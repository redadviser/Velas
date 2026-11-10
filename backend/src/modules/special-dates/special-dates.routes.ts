import type { FastifyInstance } from 'fastify';

import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import { specialDateSchema } from './special-dates.model.js';
import type { SpecialDatesService } from './special-dates.service.js';

export async function specialDatesRoutes(app: FastifyInstance, dates: SpecialDatesService) {
  const tag = 'Datas especiais';

  app.put(
    '/special-dates/:id',
    {
      schema: doc({ tag, summary: 'Criar ou atualizar uma data especial', params: idParams, body: specialDateSchema.omit({ id: true }) }),
    },
    (req) => {
      const { id } = idParams.parse(req.params);
      return dates.save(req.uid, specialDateSchema.parse({ ...(req.body as object), id }));
    },
  );

  app.delete('/special-dates/:id', { schema: doc({ tag, summary: 'Apagar uma data especial', params: idParams }) }, async (req, reply) => {
    await dates.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
