import type { FastifyInstance } from 'fastify';

import { rateLimits } from '../../core/auth-guard.js';
import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import { codeParams, findUserSchema, inviteSchema, joinSchema, respondSchema } from './invitations.model.js';
import type { InvitationsService } from './invitations.service.js';

export async function invitationsRoutes(app: FastifyInstance, invitations: InvitationsService) {
  const tag = 'Convites';

  app.post(
    '/users/find',
    {
      config: rateLimits.lookup,
      schema: doc({ tag, summary: 'Procurar uma conta por email, telemóvel ou username', body: findUserSchema }),
    },
    async (req) => ({
      user: await invitations.findUser(req.uid, findUserSchema.parse(req.body).identifier),
    }),
  );

  app.post(
    '/groups/:id/invitations',
    { schema: doc({ tag, summary: 'Convidar uma conta para o grupo', params: idParams, body: inviteSchema }) },
    async (req) => {
      const { id } = idParams.parse(req.params);
      return { result: await invitations.invite(req.uid, id, inviteSchema.parse(req.body).user_id) };
    },
  );

  app.delete('/invitations/:id', { schema: doc({ tag, summary: 'Cancelar um convite', params: idParams }) }, async (req, reply) => {
    await invitations.cancel(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.get('/invitations', { schema: doc({ tag, summary: 'Convites recebidos' }) }, (req) => invitations.mine(req.uid));

  app.post(
    '/invitations/:id/respond',
    { schema: doc({ tag, summary: 'Aceitar ou recusar um convite', params: idParams, body: respondSchema }) },
    async (req) => {
      const { id } = idParams.parse(req.params);
      return { group_id: await invitations.respond(req.uid, id, respondSchema.parse(req.body).accept) };
    },
  );

  // Links de convite.
  app.get(
    '/invite-codes/:code',
    { schema: doc({ tag, summary: 'Ver o grupo de um código de convite', params: codeParams }) },
    (req) => invitations.preview(req.uid, codeParams.parse(req.params).code),
  );

  app.post(
    '/invite-codes/:code/join',
    { schema: doc({ tag, summary: 'Entrar num grupo com um código de convite', params: codeParams, body: joinSchema }) },
    async (req) => {
      const { code } = codeParams.parse(req.params);
      return { group_id: await invitations.join(req.uid, code, joinSchema.parse(req.body ?? {}).display_name) };
    },
  );
}
