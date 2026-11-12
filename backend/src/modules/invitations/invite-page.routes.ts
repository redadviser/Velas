import { readFileSync } from 'node:fs';

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';

import type { Config } from '../../config/env.js';
import { escapeHtml, htmlPage, jsString, type LinkPreview } from '../../core/html.js';
import { doc } from '../../core/openapi.js';
import { codeParams, formatInviteCode } from './invitations.model.js';

/** Códigos de convite: letras e números (gift_groups.invite_code). */
const codePattern = /^[A-Za-z0-9]{4,20}$/;

/** Imagem da pré-visualização do link (WhatsApp, iMessage, ...), 1200×630. */
const previewImage = readFileSync(new URL('../../../public/og-invite.jpg', import.meta.url));

/** O que cada link convida: prenda em grupo (`/g/`) ou festa surpresa (`/f/`). */
export type InviteKind = 'group' | 'party';

const copy = {
  group: {
    path: 'join',
    title: 'Convite para uma prenda em grupo na Birthdayly',
    heading: 'Foste convidado para uma prenda em grupo',
    lead: 'Abre o convite na app Birthdayly para veres a prenda e a tua parte.',
    preview: 'Abre na app Birthdayly para entrares no grupo e veres a tua parte.',
  },
  party: {
    path: 'party',
    title: 'Convite para uma festa surpresa na Birthdayly',
    heading: 'Foste convidado para uma festa surpresa',
    lead: 'Abre o convite na app Birthdayly para veres a data, o sítio e o que falta tratar. Não digas nada a quem faz anos.',
    preview: 'Abre na app Birthdayly para veres a festa e responderes se vais.',
  },
} as const;

/**
 * Páginas abertas pelos links de convite partilhados (`/g/CODIGO` e
 * `/f/CODIGO`). Tentam abrir a app; quem ainda não a tem vê onde a descarregar
 * e o código para usar depois. Públicas e sem consultar a base de dados (não
 * revelam nada sobre o grupo ou a festa). Funcionam em qualquer domínio
 * apontado para a API (ex.: um domínio curto só para convites).
 */
export async function invitePageRoutes(app: FastifyInstance, config: Config) {
  app.get('/og/invite.jpg', { schema: { hide: true } }, (_req, reply) =>
    reply.type('image/jpeg').header('cache-control', 'public, max-age=604800').send(previewImage),
  );

  const page = (kind: InviteKind) => async (req: FastifyRequest, reply: FastifyReply) => {
    const raw = (req.params as { code: string }).code;
    reply.type('text/html; charset=utf-8').header('cache-control', 'no-store');
    if (!codePattern.test(raw)) {
      return reply.status(404).send(
        htmlPage({
          title: 'Birthdayly: convite inválido',
          body: '<h1>Convite inválido</h1><p>Este link não é válido. Pede um novo a quem te convidou.</p>',
        }),
      );
    }
    const code = raw.toUpperCase();
    const preview: LinkPreview = {
      description: `Código ${formatInviteCode(code)} · ${copy[kind].preview}`,
      image: `${req.protocol}://${req.host}/og/invite.jpg`,
    };
    return reply.send(invitePage(code, config, preview, kind));
  };
  const summary = (what: string) => doc({ tag: 'Páginas', summary: `Página do link de convite ${what} (abre a app)`, params: codeParams });
  app.get('/g/:code', { schema: summary('para um grupo') }, page('group'));
  app.get('/f/:code', { schema: summary('para uma festa') }, page('party'));
}

export function invitePage(code: string, config: Config, preview?: LinkPreview, kind: InviteKind = 'group'): string {
  const text = copy[kind];
  const appLink = `${config.appScheme}://app/${text.path}/${code}`;
  // No Android, o intent abre a app ou, se não estiver instalada, a Play Store.
  const fallback = config.playStoreUrl ? `S.browser_fallback_url=${encodeURIComponent(config.playStoreUrl)};` : '';
  const androidLink = `intent://app/${text.path}/${code}#Intent;scheme=${config.appScheme};package=${config.androidPackage};${fallback}end`;

  const store = (url: string | undefined, label: string, id: string) =>
    url ? `<a class="btn" id="${id}" href="${escapeHtml(url)}">${label}</a>` : '';

  return htmlPage({
    title: text.title,
    preview,
    body: `<h1>${escapeHtml(text.heading)}</h1>
<p>${escapeHtml(text.lead)}</p>
<a class="btn primary" id="open" href="${escapeHtml(appLink)}">Abrir na app</a>
${store(config.appStoreUrl, 'Descarregar para iPhone', 'ios')}
${store(config.playStoreUrl, 'Descarregar para Android', 'android')}
<div class="code" id="code">${escapeHtml(formatInviteCode(code))}</div>
<button class="btn" id="copy" type="button">Copiar código</button>
<p class="small">Depois de instalares a app, volta a este link e toca em <b>Abrir na app</b>, ou usa o código em <b>+ → Um grupo de prenda → Tenho um código</b>.</p>`,
    script: `
var ua = navigator.userAgent, android = /Android/i.test(ua), ios = /iPhone|iPad|iPod/i.test(ua);
var hide = function (id) { var e = document.getElementById(id); if (e) e.style.display = 'none'; };
if (android) { hide('ios'); document.getElementById('open').href = ${jsString(androidLink)}; location.href = ${jsString(androidLink)}; }
if (ios) hide('android');
document.getElementById('copy').onclick = function () {
  var b = this;
  navigator.clipboard.writeText(${jsString(code)}).then(function () { b.textContent = 'Código copiado'; });
};`,
  });
}
