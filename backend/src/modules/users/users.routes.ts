import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { passwordSchema } from '../../core/validation.js';
import { profilePatchSchema } from './users.model.js';
import type { UsersService } from './users.service.js';

/** Perfil e conta do utilizador autenticado. */
export async function usersRoutes(app: FastifyInstance, users: UsersService) {
  app.get('/me', (req) => users.profile(req.uid));

  app.patch('/me', (req) => users.update(req.uid, profilePatchSchema.parse(req.body)));

  app.put('/me/password', async (req, reply) => {
    const { password } = z.object({ password: passwordSchema }).parse(req.body);
    await users.setPassword(req.uid, password);
    return reply.status(204).send();
  });

  app.delete('/me', async (req, reply) => {
    await users.deleteAccount(req.uid);
    return reply.status(204).send();
  });
}
