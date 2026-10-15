import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { rateLimits } from '../../core/auth-guard.js';
import { doc } from '../../core/openapi.js';
import type { GifsService } from './gifs.service.js';

const gifQuery = z.object({
  q: z.string().max(100).default(''),
  type: z.enum(['gifs', 'stickers']).default('gifs'),
  offset: z.coerce.number().int().min(0).max(4999).default(0),
});

export async function gifsRoutes(app: FastifyInstance, gifs: GifsService) {
  app.get(
    '/gifs',
    {
      config: rateLimits.relaxed,
      schema: doc({
        tag: 'Conversas',
        summary: 'Pesquisar GIFs ou stickers no GIPHY (sem q: os mais populares)',
        description: 'Precisa de GIPHY_API_KEY no servidor; sem ela responde 503 gifs_unavailable.',
        query: gifQuery,
      }),
    },
    (req) => {
      const { q, type, offset } = gifQuery.parse(req.query);
      return gifs.search(type, q, offset);
    },
  );
}
