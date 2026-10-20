import type { FastifyInstance } from 'fastify';

import type { Config } from '../../config/env.js';
import { HttpError } from '../../core/errors.js';
import { escapeHtml, htmlPage, jsString, type LinkPreview } from '../../core/html.js';
import { doc } from '../../core/openapi.js';
import { tokenParams, type CardPreview } from './cards.model.js';
import type { CardsService } from './cards.service.js';

/**
 * Página aberta pelo link do cartão (`/c/TOKEN`). Mostra logo a mensagem, com
 * ou sem a app, e convida a responder na app. Quem a instala a partir daqui
 * encontra o cartão ao abri-la:
 * - Android: o link da Play Store leva `referrer=card=TOKEN`, que a app lê na
 *   primeira abertura (Play Install Referrer);
 * - iPhone: os botões copiam o link do cartão, que a app procura na área de
 *   transferência na primeira abertura.
 * A pré-visualização do link (WhatsApp, iMessage) não mostra a mensagem.
 */
export async function cardPageRoutes(app: FastifyInstance, cards: CardsService, config: Config) {
  const schema = doc({ tag: 'Páginas', summary: 'Página do link de um cartão de parabéns', params: tokenParams });
  app.get('/c/:token', { schema }, async (req, reply) => {
    reply.type('text/html; charset=utf-8').header('cache-control', 'no-store');
    const parsed = tokenParams.safeParse(req.params);
    const card = parsed.success
      ? await cards.preview(parsed.data.token).catch((e) => {
          if (e instanceof HttpError && e.status === 404) return null;
          throw e;
        })
      : null;
    if (!card) {
      return reply.status(404).send(
        htmlPage({
          title: 'Birthdayly — cartão não encontrado',
          body: '<h1>Cartão não encontrado</h1><p>Este link não é válido ou o cartão foi apagado por quem o enviou.</p>',
        }),
      );
    }
    const preview: LinkPreview = {
      description: `Abre para leres o teu cartão de parabéns, ${card.recipient_name}.`,
      image: `${req.protocol}://${req.host}/og/invite.jpg`,
    };
    return reply.send(cardPage(card, config, preview));
  });
}

/** Link da Play Store com o cartão no referrer (lido pela app depois de instalada). */
export function playStoreLink(playStoreUrl: string, token: string): string {
  return `${playStoreUrl}${playStoreUrl.includes('?') ? '&' : '?'}referrer=${encodeURIComponent(`card=${token}`)}`;
}

export function cardPage(card: CardPreview, config: Config, preview?: LinkPreview): string {
  const sender = escapeHtml(card.sender_name);
  const appLink = `${config.appScheme}://app/card/${card.token}`;
  const playStore = config.playStoreUrl ? playStoreLink(config.playStoreUrl, card.token) : undefined;
  // No Android, o intent abre a app ou, se não estiver instalada, a Play Store (com o cartão).
  const fallback = playStore ? `S.browser_fallback_url=${encodeURIComponent(playStore)};` : '';
  const androidLink = `intent://app/card/${card.token}#Intent;scheme=${config.appScheme};package=${config.androidPackage};${fallback}end`;

  const store = (url: string | undefined, label: string, id: string) =>
    url ? `<a class="btn" id="${id}" href="${escapeHtml(url)}">${label}</a>` : '';
  const mark = card.sender_photo_url
    ? `<img class="mark" src="${escapeHtml(card.sender_photo_url)}" alt="">`
    : undefined;

  return htmlPage({
    title: `${card.sender_name} deixou-te uma mensagem de parabéns 🎂`,
    preview,
    mark,
    body: `<p>${sender} deixou-te uma mensagem</p>
<h1>Parabéns, ${escapeHtml(card.recipient_name)}! 🎉</h1>
<blockquote class="quote">${escapeHtml(card.body)}</blockquote>
<p class="from">— ${sender}</p>
<p class="small">Agradece a mensagem de ${sender} na Birthdayly: fica guardada e podem conversar.</p>
<a class="btn primary" id="open" href="${escapeHtml(appLink)}">Responder na app</a>
${store(config.appStoreUrl, 'Descarregar para iPhone', 'ios')}
${store(playStore, 'Descarregar para Android', 'android')}
<p class="small">Na Birthdayly ninguém se esquece de um aniversário. Nem do teu.</p>`,
    script: `
var ua = navigator.userAgent, android = /Android/i.test(ua), ios = /iPhone|iPad|iPod/i.test(ua);
var hide = function (id) { var e = document.getElementById(id); if (e) e.style.display = 'none'; };
try { fetch(${jsString(`/cards/${card.token}/opened`)}, { method: 'POST', keepalive: true }).catch(function () {}); } catch (e) {}
if (android) { hide('ios'); document.getElementById('open').href = ${jsString(androidLink)}; }
if (ios) {
  hide('android');
  var store = document.getElementById('ios');
  // Guarda o cartão para a app o abrir depois de instalada.
  var remember = function (then) {
    var go = function () { then(); };
    if (navigator.clipboard) navigator.clipboard.writeText(location.origin + ${jsString(`/c/${card.token}`)}).then(go, go); else go();
  };
  if (store) store.onclick = function (e) { e.preventDefault(); var url = this.href; remember(function () { location.href = url; }); };
  document.getElementById('open').onclick = function (e) {
    e.preventDefault();
    remember(function () {
      location.href = ${jsString(appLink)};
      // Sem a app, o iPhone fica nesta página: segue para a App Store.
      if (store) setTimeout(function () { if (!document.hidden) location.href = store.href; }, 1500);
    });
  };
}`,
  });
}
