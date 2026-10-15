import { readFileSync } from 'node:fs';

import type { FastifyInstance } from 'fastify';

import type { Config } from '../../config/env.js';
import { escapeHtml, htmlPage, jsString, type LinkPreview } from '../../core/html.js';
import { doc } from '../../core/openapi.js';
import { codeParams, formatInviteCode } from './invitations.model.js';

/** Códigos de convite: letras e números (gift_groups.invite_code). */
const codePattern = /^[A-Za-z0-9]{4,20}$/;

/** Imagem da pré-visualização do link (WhatsApp, iMessage, ...), 1200×630. */
const previewImage = readFileSync(new URL('../../../public/og-invite.jpg', import.meta.url));

/**
 * Página aberta pelo link de convite partilhado (`/g/CODIGO`). Tenta abrir a
 * app; quem ainda não a tem vê onde a descarregar e o código para usar depois.
 * Pública e sem consultar a base de dados (não revela nada sobre o grupo).
 * Funciona em qualquer domínio apontado para a API (ex.: um domínio curto só
 * para convites).
 */
export async function invitePageRoutes(app: FastifyInstance, config: Config) {
  app.get('/og/invite.jpg', { schema: { hide: true } }, (_req, reply) =>
    reply.type('image/jpeg').header('cache-control', 'public, max-age=604800').send(previewImage),
  );

  const schema = doc({ tag: 'Páginas', summary: 'Página do link de convite (abre a app)', params: codeParams });
  app.get('/g/:code', { schema }, async (req, reply) => {
    const raw = (req.params as { code: string }).code;
    reply.type('text/html; charset=utf-8').header('cache-control', 'no-store');
    if (!codePattern.test(raw)) {
      return reply.status(404).send(
        htmlPage({
          title: 'Birthdayly — convite inválido',
          body: '<h1>Convite inválido</h1><p>Este link não é válido. Pede um novo a quem te convidou.</p>',
        }),
      );
    }
    const code = raw.toUpperCase();
    const preview: LinkPreview = {
      description: `Código ${formatInviteCode(code)} · Abre na app Birthdayly para entrares no grupo e veres a tua parte.`,
      image: `${req.protocol}://${req.host}/og/invite.jpg`,
    };
    return reply.send(invitePage(code, config, preview));
  });
}

export function invitePage(code: string, config: Config, preview?: LinkPreview): string {
  const appLink = `${config.appScheme}://app/join/${code}`;
  // No Android, o intent abre a app ou, se não estiver instalada, a Play Store.
  const fallback = config.playStoreUrl ? `S.browser_fallback_url=${encodeURIComponent(config.playStoreUrl)};` : '';
  const androidLink = `intent://app/join/${code}#Intent;scheme=${config.appScheme};package=${config.androidPackage};${fallback}end`;

  const store = (url: string | undefined, label: string, id: string) =>
    url ? `<a class="btn" id="${id}" href="${escapeHtml(url)}">${label}</a>` : '';

  return htmlPage({
    title: 'Convite para uma prenda em grupo na Birthdayly',
    preview,
    body: `<h1>Foste convidado para uma prenda em grupo</h1>
<p>Abre o convite na app Birthdayly para veres a prenda e a tua parte.</p>
<a class="btn primary" id="open" href="${escapeHtml(appLink)}">Abrir na app</a>
${store(config.appStoreUrl, 'Descarregar para iPhone', 'ios')}
${store(config.playStoreUrl, 'Descarregar para Android', 'android')}
<div class="code" id="code">${escapeHtml(formatInviteCode(code))}</div>
<button class="btn" id="copy" type="button">Copiar código</button>
<p class="small">Depois de instalares a app, abre <b>Presentes → Em grupo → Tenho um código</b> e usa este código.</p>`,
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
