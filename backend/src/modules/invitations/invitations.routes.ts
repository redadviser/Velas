import type { FastifyInstance } from 'fastify';

import { rateLimits } from '../../core/auth-guard.js';
import { idParams } from '../../core/validation.js';
import { codeParams, findUserSchema, inviteSchema, joinSchema, respondSchema } from './invitations.model.js';
import type { InvitationsService } from './invitations.service.js';

export async function invitationsRoutes(app: FastifyInstance, invitations: InvitationsService) {
  app.post('/users/find', { config: rateLimits.lookup }, async (req) => ({
    user: await invitations.findUser(req.uid, findUserSchema.parse(req.body).identifier),
  }));

  app.post('/groups/:id/invitations', async (req) => {
    const { id } = idParams.parse(req.params);
    return { result: await invitations.invite(req.uid, id, inviteSchema.parse(req.body).user_id) };
  });

  app.delete('/invitations/:id', async (req, reply) => {
    await invitations.cancel(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.get('/invitations', (req) => invitations.mine(req.uid));

  app.post('/invitations/:id/respond', async (req) => {
    const { id } = idParams.parse(req.params);
    return { group_id: await invitations.respond(req.uid, id, respondSchema.parse(req.body).accept) };
  });

  // Links de convite.
  app.get('/invite-codes/:code', (req) => invitations.preview(req.uid, codeParams.parse(req.params).code));

  app.post('/invite-codes/:code/join', async (req) => {
    const { code } = codeParams.parse(req.params);
    return { group_id: await invitations.join(req.uid, code, joinSchema.parse(req.body ?? {}).display_name) };
  });
}
