import type { FastifyInstance } from 'fastify';

import type { Config } from '../../config/env.js';
import { rateLimits } from '../../core/auth-guard.js';
import { escapeHtml, htmlPage, jsString } from '../../core/html.js';
import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import { checkoutSchema } from './payments.model.js';
import type { PaymentsService } from './payments.service.js';

const tag = 'Pagamentos';

/** Rotas com sessão: ligar a conta Stripe de quem recebe e pagar a parte. */
export async function paymentsRoutes(app: FastifyInstance, payments: PaymentsService) {
  app.get('/me/payouts', { schema: doc({ tag, summary: 'Receber pagamentos na app: estado da conta Stripe' }) }, (req) =>
    payments.payoutStatus(req.uid),
  );

  app.post(
    '/me/payouts/onboarding',
    { schema: doc({ tag, summary: 'Link para ligar (ou continuar a ligar) a conta Stripe de quem recebe' }) },
    (req) => payments.startOnboarding(req.uid),
  );

  app.post(
    '/me/payouts/refresh',
    { schema: doc({ tag, summary: 'Voltar a ver se a conta Stripe já pode receber' }) },
    (req) => payments.refreshPayouts(req.uid),
  );

  app.post(
    '/group-members/:id/checkout',
    {
      config: rateLimits.relaxed,
      schema: doc({
        tag,
        summary: 'Pagar a minha parte: cartão/PayPal (devolve checkout_url) ou MB WAY (pedido para o telemóvel)',
        params: idParams,
        body: checkoutSchema,
      }),
    },
    (req) => payments.checkout(req.uid, idParams.parse(req.params).id, checkoutSchema.parse(req.body)),
  );

  app.get('/payments/:id', { schema: doc({ tag, summary: 'Estado de um pagamento meu', params: idParams }) }, (req) =>
    payments.status(req.uid, idParams.parse(req.params).id),
  );
}

/** Rotas públicas: webhook da Stripe e páginas para voltar à app. */
export async function paymentsPublicRoutes(app: FastifyInstance, payments: PaymentsService, config: Config) {
  // O webhook precisa do corpo em bruto para validar a assinatura.
  await app.register(async (scope) => {
    scope.addContentTypeParser('application/json', { parseAs: 'buffer' }, (_req, body, done) => done(null, body));
    scope.post('/stripe/webhook', { schema: { hide: true } }, async (req, reply) => {
      const signature = req.headers['stripe-signature'];
      if (typeof signature !== 'string' || !Buffer.isBuffer(req.body)) return reply.status(400).send({ error: 'bad_request' });
      await payments.webhook(req.body, signature);
      return { received: true };
    });
  });

  const back = (title: string, text: string) => {
    const appLink = `${config.appScheme}://app/payments`;
    return htmlPage({
      title: `Birthdayly — ${title}`,
      body: `<h1>${escapeHtml(title)}</h1><p>${escapeHtml(text)}</p>
<a class="btn primary" href="${escapeHtml(appLink)}">Voltar à app</a>`,
      script: `setTimeout(function(){location.href=${jsString(appLink)}},400)`,
    });
  };
  const page = (title: string, text: string) => async (_req: unknown, reply: { type: (t: string) => { send: (b: string) => unknown } }) =>
    reply.type('text/html; charset=utf-8').send(back(title, text));

  app.get('/pay/done', { schema: { hide: true } }, page('Pagamento concluído', 'Já podes voltar à app: a tua parte fica marcada como paga.'));
  app.get('/pay/cancel', { schema: { hide: true } }, page('Pagamento cancelado', 'Não foi cobrado nada. Volta à app para escolher outra forma de pagar.'));
  app.get('/stripe/return', { schema: { hide: true } }, page('Conta ligada', 'Volta à app para começares a receber os pagamentos dos teus amigos.'));
  app.get('/stripe/refresh', { schema: { hide: true } }, page('O link expirou', 'Volta à app e toca outra vez em "Receber pagamentos na app".'));
}
