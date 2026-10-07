import type { FastifyInstance } from 'fastify';

import { rateLimits } from '../../core/auth-guard.js';
import { escapeHtml, htmlPage, jsString } from '../../core/html.js';
import {
  forgotSchema,
  googleSchema,
  loginSchema,
  logoutSchema,
  recoverSchema,
  refreshSchema,
  resetQuerySchema,
  signupCheckSchema,
  signupSchema,
} from './auth.model.js';
import type { AuthService } from './auth.service.js';

/** Rotas públicas (sem sessão). */
export async function authRoutes(app: FastifyInstance, auth: AuthService) {
  const { strict, relaxed } = rateLimits;

  app.post('/auth/signup', { config: strict }, async (req, reply) =>
    reply.status(201).send(await auth.signup(signupSchema.parse(req.body))),
  );

  app.post('/auth/signup-check', { config: relaxed }, (req) => {
    const body = signupCheckSchema.parse(req.body);
    return auth.checkAvailability(body.username, body.phone ?? null);
  });

  app.post('/auth/login', { config: strict }, (req) => {
    const body = loginSchema.parse(req.body);
    return auth.login(body.identifier, body.password);
  });

  app.post('/auth/google', { config: strict }, (req) => auth.google(googleSchema.parse(req.body).id_token));

  app.post('/auth/refresh', { config: relaxed }, (req) => auth.refresh(refreshSchema.parse(req.body).refresh_token));

  app.post('/auth/logout', async (req, reply) => {
    await auth.logout(logoutSchema.parse(req.body).refresh_token);
    return reply.status(204).send();
  });

  /** Responde sempre 204, para não revelar se o email tem conta. */
  app.post('/auth/password/forgot', { config: strict }, async (req, reply) => {
    await auth.forgotPassword(forgotSchema.parse(req.body).email, req.log);
    return reply.status(204).send();
  });

  /** Página aberta a partir do email: passa o token para a app. */
  app.get('/auth/reset', async (req, reply) => {
    const { token } = resetQuerySchema.parse(req.query);
    return reply.type('text/html; charset=utf-8').send(resetPage(auth.appRecoveryLink(token)));
  });

  app.post('/auth/password/recover', { config: strict }, (req) => auth.recover(recoverSchema.parse(req.body).token));
}

function resetPage(appLink: string): string {
  const link = escapeHtml(appLink);
  return htmlPage({
    title: 'Velas — nova palavra-passe',
    body: `<h1>Nova palavra-passe</h1><p>A abrir a app Velas…</p>
<a class="btn primary" href="${link}">Abrir a app</a>
<p class="small">Abre este link no telemóvel onde tens a app instalada.</p>`,
    script: `location.href=${jsString(appLink)}`,
  });
}
