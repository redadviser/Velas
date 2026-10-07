import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyServerOptions } from 'fastify';

import { createServices, type Deps } from './container.js';
import { requireAuth } from './core/auth-guard.js';
import { errorHandler } from './core/errors.js';
import { doc, documentBearerAuth, registerDocs } from './core/openapi.js';
import { authRoutes } from './modules/auth/auth.routes.js';
import { categoriesRoutes } from './modules/categories/categories.routes.js';
import { filesRoutes } from './modules/files/files.routes.js';
import { giftsRoutes } from './modules/gifts/gifts.routes.js';
import { groupsRoutes } from './modules/groups/groups.routes.js';
import { invitePageRoutes } from './modules/invitations/invite-page.routes.js';
import { invitationsRoutes } from './modules/invitations/invitations.routes.js';
import { messagesRoutes } from './modules/messages/messages.routes.js';
import { peopleRoutes } from './modules/people/people.routes.js';
import { syncRoutes } from './modules/sync/sync.routes.js';
import { usersRoutes } from './modules/users/users.routes.js';

export async function buildApp(deps: Deps, options: FastifyServerOptions = {}) {
  const services = createServices(deps);
  const app = Fastify({ trustProxy: true, ...options });
  app.setErrorHandler(errorHandler);
  await app.register(rateLimit, { global: false, enableDraftSpec: true, allowList: () => !deps.config.rateLimit });
  // Quem valida os pedidos é o Zod; os schemas das rotas são só documentação (ver core/openapi.ts).
  app.setValidatorCompiler(() => (value) => ({ value }));
  if (deps.config.docs) await registerDocs(app);

  app.get('/health', { schema: doc({ tag: 'Sistema', summary: 'Estado da API e da base de dados' }) }, async () => {
    await deps.db.query('select 1');
    return { ok: true };
  });

  // Rotas públicas.
  await authRoutes(app, services.auth);
  await filesRoutes(app, deps.storage);
  await invitePageRoutes(app, deps.config);

  // Rotas que exigem sessão.
  await app.register(async (scope) => {
    requireAuth(scope, deps.tokens);
    documentBearerAuth(scope);
    await usersRoutes(scope, services.users);
    await syncRoutes(scope, services.sync);
    await peopleRoutes(scope, services.people);
    await categoriesRoutes(scope, services.categories);
    await giftsRoutes(scope, services.gifts);
    await messagesRoutes(scope, services.messages);
    await groupsRoutes(scope, services.groups);
    await invitationsRoutes(scope, services.invitations);
  });

  return app;
}
