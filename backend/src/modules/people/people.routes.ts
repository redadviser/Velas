import type { FastifyInstance } from 'fastify';

import { HttpError } from '../../core/errors.js';
import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import { importSchema, personSchema } from './people.model.js';
import type { PeopleService } from './people.service.js';

const photoTypes = ['image/jpeg', 'image/png', 'image/webp'];

export async function peopleRoutes(app: FastifyInstance, people: PeopleService) {
  const tag = 'Pessoas';

  app.put(
    '/people/:id',
    { schema: doc({ tag, summary: 'Criar ou atualizar uma pessoa', params: idParams, body: personSchema.omit({ id: true }) }) },
    (req) => {
      const { id } = idParams.parse(req.params);
      return people.save(req.uid, personSchema.parse({ ...(req.body as object), id }));
    },
  );

  app.post(
    '/people/import',
    { schema: doc({ tag, summary: 'Importar contactos (até 2000 pessoas)', body: importSchema }) },
    async (req) => ({
      people: await people.importMany(req.uid, importSchema.parse(req.body).people),
    }),
  );

  app.get(
    '/people/:id/history',
    {
      schema: doc({
        tag,
        summary: 'Histórico da pessoa por ano (cartões, prendas e prendas em grupo)',
        description: 'No plano Grátis só o ano atual; os outros anos vêm em locked_years.',
        params: idParams,
      }),
    },
    (req) => people.history(req.uid, idParams.parse(req.params).id),
  );

  app.delete('/people/:id', { schema: doc({ tag, summary: 'Apagar uma pessoa', params: idParams }) }, async (req, reply) => {
    await people.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.put(
    '/people/:id/photo',
    {
      schema: {
        ...doc({ tag, summary: 'Enviar a fotografia (bytes da imagem no corpo)', params: idParams }),
        consumes: photoTypes,
        body: { type: 'string', format: 'binary' },
      },
    },
    (req) => {
      const { id } = idParams.parse(req.params);
      if (!Buffer.isBuffer(req.body)) throw new HttpError(415, 'unsupported_media_type');
      return people.setPhoto(req.uid, id, req.body);
    },
  );

  app.delete('/people/:id/photo', { schema: doc({ tag, summary: 'Remover a fotografia', params: idParams }) }, async (req, reply) => {
    await people.removePhoto(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
