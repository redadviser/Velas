import type { FastifyInstance } from 'fastify';

import { imageType, type PhotoStorage } from '../../core/storage.js';

/** Fotografias, por URL assinado e temporário (público, sem sessão). */
export async function filesRoutes(app: FastifyInstance, storage: PhotoStorage) {
  // Fora da documentação: só funciona com o URL assinado devolvido em photo_url.
  app.get('/files/*', { schema: { hide: true } }, async (req, reply) => {
    const key = (req.params as { '*': string })['*'];
    const { exp, sig } = req.query as { exp?: string; sig?: string };
    if (!storage.verify(key, exp, sig)) return reply.status(403).send({ error: 'forbidden' });
    const data = await storage.read(key);
    if (!data) return reply.status(404).send({ error: 'not_found' });
    return reply
      .type(imageType(data)?.mime ?? 'application/octet-stream')
      .header('cache-control', 'private, max-age=86400')
      .send(data);
  });
}
