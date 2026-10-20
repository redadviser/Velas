import type { FastifyInstance } from 'fastify';

import { rateLimits } from '../../core/auth-guard.js';
import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import { createCardSchema, sentQuery, tokenParams } from './cards.model.js';
import type { CardsService } from './cards.service.js';

const tag = 'Cartões de parabéns';

/** Rotas com sessão: criar, ver o estado, o mural, apagar e guardar um cartão recebido. */
export async function cardsRoutes(app: FastifyInstance, cards: CardsService) {
  app.post('/cards', { schema: doc({ tag, summary: 'Criar um cartão (link, ou no mural de um amigo com recipient_id)', body: createCardSchema }) }, async (req, reply) =>
    reply.status(201).send(await cards.create(req.uid, createCardSchema.parse(req.body))),
  );

  app.get('/cards/sent', { schema: doc({ tag, summary: 'Cartões enviados, com o estado', query: sentQuery }) }, (req) =>
    cards.sent(req.uid, sentQuery.parse(req.query).person_id),
  );

  app.get(
    '/cards/received',
    { schema: doc({ tag, summary: 'O meu mural: cartões recebidos' }) },
    (req) => cards.received(req.uid),
  );

  app.post(
    '/cards/received/seen',
    { schema: doc({ tag, summary: 'Marcar o mural como visto', description: 'Quem enviou os cartões fica a saber que foram vistos.' }) },
    async (req, reply) => {
      await cards.markSeen(req.uid);
      return reply.status(204).send();
    },
  );

  app.delete('/cards/:id', { schema: doc({ tag, summary: 'Apagar um cartão enviado', params: idParams }) }, async (req, reply) => {
    await cards.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.post(
    '/cards/:token/claim',
    {
      config: rateLimits.lookup,
      schema: doc({
        tag,
        summary: 'Guardar um cartão recebido',
        description: 'Fica amigo de quem enviou e a mensagem aparece na conversa privada entre os dois.',
        params: tokenParams,
      }),
    },
    (req) => cards.claim(req.uid, tokenParams.parse(req.params).token),
  );
}

/** Rotas públicas: quem tem o link vê o cartão, com ou sem conta. */
export async function cardsPublicRoutes(app: FastifyInstance, cards: CardsService) {
  app.get(
    '/cards/:token',
    { config: rateLimits.lookup, schema: doc({ tag, summary: 'Ver um cartão pelo link (sem sessão)', params: tokenParams }) },
    (req) => cards.preview(tokenParams.parse(req.params).token),
  );

  app.post(
    '/cards/:token/opened',
    { config: rateLimits.lookup, schema: doc({ tag, summary: 'Marcar o cartão como aberto (sem sessão)', params: tokenParams }) },
    async (req, reply) => {
      await cards.markOpened(tokenParams.parse(req.params).token);
      return reply.status(204).send();
    },
  );
}
