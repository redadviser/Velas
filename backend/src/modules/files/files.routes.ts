import type { FastifyInstance } from 'fastify';

import { mediaType, type PhotoStorage } from '../../core/storage.js';

/** Fotografias, por URL assinado e temporário (público, sem sessão). */
export async function filesRoutes(app: FastifyInstance, storage: PhotoStorage) {
  // Fora da documentação: só funciona com o URL assinado devolvido em photo_url.
  app.get('/files/*', { schema: { hide: true } }, async (req, reply) => {
    const key = (req.params as { '*': string })['*'];
    const { exp, sig } = req.query as { exp?: string; sig?: string };
    if (!storage.verify(key, exp, sig)) return reply.status(403).send({ error: 'forbidden' });
    const data = await storage.read(key);
    if (!data) return reply.status(404).send({ error: 'not_found' });
    reply
      .type(mediaType(data)?.mime ?? 'application/octet-stream')
      .header('cache-control', 'private, max-age=86400')
      .header('accept-ranges', 'bytes');
    // Os leitores de vídeo e áudio (o do iPhone sobretudo) pedem o ficheiro aos bocados.
    const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range ?? '');
    if (range && (range[1] || range[2])) {
      const size = data.length;
      const start = range[1] ? Number(range[1]) : Math.max(0, size - Number(range[2]));
      const end = range[1] && range[2] ? Math.min(Number(range[2]), size - 1) : size - 1;
      if (start >= size || start > end) {
        return reply.status(416).header('content-range', `bytes */${size}`).send();
      }
      return reply
        .status(206)
        .header('content-range', `bytes ${start}-${end}/${size}`)
        .send(data.subarray(start, end + 1));
    }
    return reply.send(data);
  });
}
