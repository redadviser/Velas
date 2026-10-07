import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { doc } from '../../core/openapi.js';
import { passwordSchema } from '../../core/validation.js';
import { profilePatchSchema } from './users.model.js';
import type { UsersService } from './users.service.js';

const passwordBody = z.object({ password: passwordSchema });

/** Perfil e conta do utilizador autenticado. */
export async function usersRoutes(app: FastifyInstance, users: UsersService) {
  const tag = 'Perfil';

  app.get('/me', { schema: doc({ tag, summary: 'Perfil do utilizador' }) }, (req) => users.profile(req.uid));

  app.patch('/me', { schema: doc({ tag, summary: 'Alterar o perfil (só os campos enviados)', body: profilePatchSchema }) }, (req) =>
    users.update(req.uid, profilePatchSchema.parse(req.body)),
  );

  app.put('/me/password', { schema: doc({ tag, summary: 'Definir uma nova palavra-passe', body: passwordBody }) }, async (req, reply) => {
    const { password } = passwordBody.parse(req.body);
    await users.setPassword(req.uid, password);
    return reply.status(204).send();
  });

  app.delete('/me', { schema: doc({ tag, summary: 'Apagar a conta e todos os dados' }) }, async (req, reply) => {
    await users.deleteAccount(req.uid);
    return reply.status(204).send();
  });
}
