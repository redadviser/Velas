import type { FastifyInstance } from 'fastify';

import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import { wishSchema } from './wishlist.model.js';
import type { WishlistService } from './wishlist.service.js';

export async function wishlistRoutes(app: FastifyInstance, wishlist: WishlistService) {
  const tag = 'Lista de desejos';

  app.get('/me/wishlist', { schema: doc({ tag, summary: 'A minha lista de desejos' }) }, (req) => wishlist.mine(req.uid));

  app.put(
    '/me/wishlist/:id',
    { schema: doc({ tag, summary: 'Criar ou atualizar um desejo', params: idParams, body: wishSchema.omit({ id: true }) }) },
    (req) => {
      const { id } = idParams.parse(req.params);
      return wishlist.save(req.uid, wishSchema.parse({ ...(req.body as object), id }));
    },
  );

  app.delete('/me/wishlist/:id', { schema: doc({ tag, summary: 'Apagar um desejo', params: idParams }) }, async (req, reply) => {
    await wishlist.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.get(
    '/friends/:id/wishlist',
    { schema: doc({ tag, summary: 'Gostos e lista de desejos de um amigo', params: idParams }) },
    (req) => wishlist.ofFriend(req.uid, idParams.parse(req.params).id),
  );
}
