import type { FastifyInstance } from 'fastify';

import { rateLimits } from '../../core/auth-guard.js';
import { HttpError } from '../../core/errors.js';
import { doc } from '../../core/openapi.js';
import type { AdaptyConfig } from './adapty.js';
import type { SubscriptionsService } from './subscriptions.service.js';

const tag = 'Birthdayly+';

/** Com sessão: depois de comprar ou restaurar na app, o servidor confirma com o Adapty. */
export async function subscriptionsRoutes(app: FastifyInstance, subscriptions: SubscriptionsService) {
  app.post(
    '/me/plus/sync',
    {
      config: rateLimits.relaxed,
      schema: doc({ tag, summary: 'Confirmar o Birthdayly+ comprado na loja (depois de comprar ou restaurar)' }),
    },
    (req) => subscriptions.sync(req.uid),
  );
}

/** Público: webhook do Adapty (Adapty → Integrations → Webhook). */
export async function subscriptionsPublicRoutes(
  app: FastifyInstance,
  subscriptions: SubscriptionsService,
  config?: AdaptyConfig,
) {
  app.post('/adapty/webhook', { schema: { hide: true } }, async (req) => {
    // Com ADAPTY_WEBHOOK_AUTH, só aceita pedidos com esse Authorization. Mesmo sem ele, um
    // pedido falso não dá o plano a ninguém: o estado vem sempre da API do Adapty.
    if (config?.webhookAuth && req.headers.authorization !== config.webhookAuth) throw new HttpError(401, 'unauthorized');
    if (subscriptions.enabled) await subscriptions.webhook(req.body);
    return {};
  });
}
