import type { FastifyInstance } from 'fastify';

import { HttpError } from '../../core/errors.js';
import { PhotoStorage } from '../../core/storage.js';
import { idParams } from '../../core/validation.js';
import { importSchema, personSchema } from './people.model.js';
import type { PeopleService } from './people.service.js';

export async function peopleRoutes(app: FastifyInstance, people: PeopleService) {
  // Fotografias enviadas em bruto (o tipo real é verificado pelos bytes).
  app.addContentTypeParser(
    ['image/jpeg', 'image/png', 'image/webp', 'application/octet-stream'],
    { parseAs: 'buffer', bodyLimit: PhotoStorage.maxBytes },
    (_req, body, done) => done(null, body),
  );

  app.put('/people/:id', (req) => {
    const { id } = idParams.parse(req.params);
    return people.save(req.uid, personSchema.parse({ ...(req.body as object), id }));
  });

  app.post('/people/import', async (req) => ({
    people: await people.importMany(req.uid, importSchema.parse(req.body).people),
  }));

  app.delete('/people/:id', async (req, reply) => {
    await people.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.put('/people/:id/photo', (req) => {
    const { id } = idParams.parse(req.params);
    if (!Buffer.isBuffer(req.body)) throw new HttpError(415, 'unsupported_media_type');
    return people.setPhoto(req.uid, id, req.body);
  });

  app.delete('/people/:id/photo', async (req, reply) => {
    await people.removePhoto(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
