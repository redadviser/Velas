import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyServerOptions } from 'fastify';

import { createServices, type Deps } from './container.js';
import { requireAuth } from './core/auth-guard.js';
import { errorHandler } from './core/errors.js';
import { doc, documentBearerAuth, registerDocs } from './core/openapi.js';
import { realtimeRoutes } from './core/realtime.js';
import { PhotoStorage } from './core/storage.js';
import { authRoutes } from './modules/auth/auth.routes.js';
import { cardPageRoutes } from './modules/cards/card-page.routes.js';
import { cardsPublicRoutes, cardsRoutes } from './modules/cards/cards.routes.js';
import { categoriesRoutes } from './modules/categories/categories.routes.js';
import { chatRoutes } from './modules/chat/chat.routes.js';
import { filesRoutes } from './modules/files/files.routes.js';
import { friendsRoutes } from './modules/friends/friends.routes.js';
import { gifsRoutes } from './modules/gifs/gifs.routes.js';
import { paymentsPublicRoutes, paymentsRoutes } from './modules/payments/payments.routes.js';
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

  app.get(
    '/health',
    { schema: doc({ tag: 'Sistema', summary: 'Estado da API, da base de dados e do armazenamento de imagens' }) },
    async () => {
      const { rows } = await deps.db.query<{ name: string | null }>('select max(name) as name from schema_migrations');
      // storage: false = UPLOAD_DIR não é gravável (fotografias e imagens do chat falham).
      return { ok: true, schema: rows[0]?.name ?? null, storage: await deps.storage.writable() };
    },
  );

  // Rotas públicas.
  await authRoutes(app, services.auth);
  await filesRoutes(app, deps.storage);
  await invitePageRoutes(app, deps.config);
  await cardPageRoutes(app, services.cards, deps.config);
  await cardsPublicRoutes(app, services.cards);
  await paymentsPublicRoutes(app, services.payments, deps.config);
  // Tempo real: a autenticação é a primeira mensagem da ligação.
  await realtimeRoutes(app, services.hub, deps.tokens, {
    typing: (uid, cid) => services.chat.typing(uid, cid),
    presence: (uid, online) => services.chat.presence(uid, online),
  });

  // Rotas que exigem sessão.
  await app.register(async (scope) => {
    requireAuth(scope, deps.tokens);
    documentBearerAuth(scope);
    // Imagens enviadas em bruto (o tipo real é verificado pelos bytes). Cada
    // rota pode subir o limite com `bodyLimit` (ex.: imagens do chat).
    scope.addContentTypeParser(
      ['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'application/octet-stream'],
      { parseAs: 'buffer', bodyLimit: PhotoStorage.maxBytes },
      (_req, body, done) => done(null, body),
    );
    await usersRoutes(scope, services.users);
    await syncRoutes(scope, services.sync);
    await peopleRoutes(scope, services.people);
    await categoriesRoutes(scope, services.categories);
    await giftsRoutes(scope, services.gifts);
    await messagesRoutes(scope, services.messages);
    await cardsRoutes(scope, services.cards);
    await groupsRoutes(scope, services.groups);
    await invitationsRoutes(scope, services.invitations);
    await friendsRoutes(scope, services.friends);
    await chatRoutes(scope, services.chat, services.stickers);
    await gifsRoutes(scope, services.gifs);
    await paymentsRoutes(scope, services.payments);
  });

  return app;
}
