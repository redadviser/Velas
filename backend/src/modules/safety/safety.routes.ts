import type { FastifyInstance } from 'fastify';

import { rateLimits } from '../../core/auth-guard.js';
import { doc } from '../../core/openapi.js';
import { reportSchema, userParams } from './safety.model.js';
import type { SafetyService } from './safety.service.js';

const tag = 'Segurança';

/** Bloquear e denunciar utilizadores. */
export async function safetyRoutes(app: FastifyInstance, safety: SafetyService) {
  app.get('/blocks', { schema: doc({ tag, summary: 'Utilizadores que bloqueei' }) }, (req) => safety.blocked(req.uid));

  app.post(
    '/users/:id/block',
    {
      schema: doc({
        tag,
        summary: 'Bloquear um utilizador',
        description: 'Deixam de ser amigos; não pode pedir amizade nem escrever em privado; as mensagens dele nos grupos deixam de aparecer.',
        params: userParams,
      }),
    },
    async (req, reply) => {
      await safety.block(req.uid, userParams.parse(req.params).id);
      return reply.status(204).send();
    },
  );

  app.delete('/users/:id/block', { schema: doc({ tag, summary: 'Desbloquear', params: userParams }) }, async (req, reply) => {
    await safety.unblock(req.uid, userParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.post(
    '/users/:id/report',
    {
      config: rateLimits.lookup,
      schema: doc({ tag, summary: 'Denunciar um utilizador (ou uma mensagem dele)', params: userParams, body: reportSchema }),
    },
    async (req, reply) => {
      await safety.report(req.uid, userParams.parse(req.params).id, reportSchema.parse(req.body));
      return reply.status(204).send();
    },
  );
}
