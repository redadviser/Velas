import type { FastifyInstance } from 'fastify';

import { rateLimits } from '../../core/auth-guard.js';
import { escapeHtml, htmlPage, jsString } from '../../core/html.js';
import { doc } from '../../core/openapi.js';
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
  const tag = 'Autenticação';

  app.post(
    '/auth/signup',
    { config: strict, schema: doc({ tag, summary: 'Criar conta (devolve a sessão)', body: signupSchema }) },
    async (req, reply) => reply.status(201).send(await auth.signup(signupSchema.parse(req.body))),
  );

  app.post(
    '/auth/signup-check',
    {
      config: relaxed,
      schema: doc({ tag, summary: 'Verificar se o username e o telemóvel estão livres', body: signupCheckSchema }),
    },
    (req) => {
      const body = signupCheckSchema.parse(req.body);
      return auth.checkAvailability(body.username, body.phone ?? null);
    },
  );

  app.post(
    '/auth/login',
    { config: strict, schema: doc({ tag, summary: 'Entrar com email/username e palavra-passe', body: loginSchema }) },
    (req) => {
      const body = loginSchema.parse(req.body);
      return auth.login(body.identifier, body.password);
    },
  );

  app.post(
    '/auth/google',
    { config: strict, schema: doc({ tag, summary: 'Entrar com o ID token do Google', body: googleSchema }) },
    (req) => auth.google(googleSchema.parse(req.body).id_token),
  );

  app.post(
    '/auth/refresh',
    { config: relaxed, schema: doc({ tag, summary: 'Renovar a sessão com o refresh token', body: refreshSchema }) },
    (req) => auth.refresh(refreshSchema.parse(req.body).refresh_token),
  );

  app.post(
    '/auth/logout',
    { schema: doc({ tag, summary: 'Terminar a sessão (revoga o refresh token)', body: logoutSchema }) },
    async (req, reply) => {
      await auth.logout(logoutSchema.parse(req.body).refresh_token);
      return reply.status(204).send();
    },
  );

  /** Responde sempre 204, para não revelar se o email tem conta. */
  app.post(
    '/auth/password/forgot',
    { config: strict, schema: doc({ tag, summary: 'Enviar email de recuperação da palavra-passe', body: forgotSchema }) },
    async (req, reply) => {
      await auth.forgotPassword(forgotSchema.parse(req.body).email, req.log);
      return reply.status(204).send();
    },
  );

  /** Página aberta a partir do email: passa o token para a app. */
  app.get(
    '/auth/reset',
    { schema: doc({ tag: 'Páginas', summary: 'Página do link de recuperação (abre a app)', query: resetQuerySchema }) },
    async (req, reply) => {
      const { token } = resetQuerySchema.parse(req.query);
      return reply.type('text/html; charset=utf-8').send(resetPage(auth.appRecoveryLink(token)));
    },
  );

  app.post(
    '/auth/password/recover',
    { config: strict, schema: doc({ tag, summary: 'Entrar com o token do email de recuperação', body: recoverSchema }) },
    (req) => auth.recover(recoverSchema.parse(req.body).token),
  );
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
