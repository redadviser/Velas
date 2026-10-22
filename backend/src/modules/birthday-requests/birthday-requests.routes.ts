import type { FastifyInstance } from 'fastify';

import type { Config } from '../../config/env.js';
import { rateLimits } from '../../core/auth-guard.js';
import { escapeHtml, htmlPage, jsString, type LinkPreview } from '../../core/html.js';
import { doc } from '../../core/openapi.js';
import { answerParams, answerSchema, requestPatchSchema, requestTokenParams } from './birthday-requests.model.js';
import type { BirthdayRequestsService } from './birthday-requests.service.js';

const tag = 'Pedidos de aniversário';

/** Rotas com sessão: o meu link, ligar/desligar/trocar e as respostas por confirmar. */
export async function birthdayRequestsRoutes(app: FastifyInstance, requests: BirthdayRequestsService) {
  app.get('/birthday-request', { schema: doc({ tag, summary: 'O meu link para pedir aniversários' }) }, (req) =>
    requests.mine(req.uid),
  );
  app.post(
    '/birthday-request/reset',
    { schema: doc({ tag, summary: 'Trocar de link (o antigo deixa de funcionar; o novo vale 30 dias)' }) },
    (req) => requests.reset(req.uid),
  );
  app.patch(
    '/birthday-request',
    { schema: doc({ tag, summary: 'Desligar ou voltar a ligar o link', body: requestPatchSchema }) },
    (req) => requests.setEnabled(req.uid, requestPatchSchema.parse(req.body).enabled),
  );

  app.get('/birthday-request/answers', { schema: doc({ tag, summary: 'Respostas por confirmar' }) }, (req) =>
    requests.pending(req.uid),
  );
  app.post(
    '/birthday-request/answers/accept',
    { schema: doc({ tag, summary: 'Aceitar todas as respostas (entram na lista de aniversários)' }) },
    async (req) => ({ added: await requests.accept(req.uid) }),
  );
  app.post(
    '/birthday-request/answers/:id/accept',
    { schema: doc({ tag, summary: 'Aceitar uma resposta', params: answerParams }) },
    async (req) => ({ added: await requests.accept(req.uid, answerParams.parse(req.params).id) }),
  );
  app.post(
    '/birthday-request/answers/ignore',
    { schema: doc({ tag, summary: 'Ignorar todas as respostas por confirmar' }) },
    async (req, reply) => {
      await requests.ignore(req.uid);
      return reply.status(204).send();
    },
  );
  app.post(
    '/birthday-request/answers/:id/ignore',
    { schema: doc({ tag, summary: 'Ignorar uma resposta', params: answerParams }) },
    async (req, reply) => {
      await requests.ignore(req.uid, answerParams.parse(req.params).id);
      return reply.status(204).send();
    },
  );
}

/** Rotas públicas: a página do link e a resposta (sem conta). */
export async function birthdayRequestsPublicRoutes(app: FastifyInstance, requests: BirthdayRequestsService, config: Config) {
  app.post(
    '/birthday-requests/:token/answers',
    {
      config: rateLimits.lookup,
      schema: doc({ tag, summary: 'Deixar o meu aniversário (sem sessão)', params: requestTokenParams, body: answerSchema }),
    },
    async (req, reply) => {
      await requests.answer(requestTokenParams.parse(req.params).token, answerSchema.parse(req.body));
      return reply.status(201).send({ ok: true });
    },
  );

  const schema = doc({ tag: 'Páginas', summary: 'Página do link para deixar o aniversário', params: requestTokenParams });
  app.get('/b/:token', { schema }, async (req, reply) => {
    reply.type('text/html; charset=utf-8').header('cache-control', 'no-store');
    const parsed = requestTokenParams.safeParse(req.params);
    const owner = parsed.success ? await requests.owner(parsed.data.token) : null;
    if (owner && !owner.open) {
      return reply.status(410).send(
        htmlPage({
          title: 'Birthdayly — link fechado',
          body: '<h1>Este link já não aceita respostas</h1><p>Pede um novo a quem to enviou.</p>',
        }),
      );
    }
    if (!parsed.success || !owner) {
      return reply.status(404).send(
        htmlPage({
          title: 'Birthdayly — link inválido',
          body: '<h1>Link inválido</h1><p>Este link já não funciona. Pede um novo a quem to enviou.</p>',
        }),
      );
    }
    const preview: LinkPreview = {
      description: 'Deixa a tua data em 10 segundos. Não precisas de instalar nada.',
      image: `${req.protocol}://${req.host}/og/invite.jpg`,
    };
    return reply.send(requestPage(parsed.data.token, owner.name, config, preview));
  });
}

const months = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

export function requestPage(token: string, ownerName: string, config: Config, preview?: LinkPreview): string {
  const owner = escapeHtml(ownerName);
  const first = escapeHtml(ownerName.trim().split(/\s+/)[0] ?? ownerName);
  const store = (url: string | undefined, label: string, id: string) =>
    url ? `<a class="btn" id="${id}" href="${escapeHtml(url)}">${label}</a>` : '';
  const options = (from: number, to: number, label: (n: number) => string) =>
    Array.from({ length: to - from + 1 }, (_, i) => `<option value="${from + i}">${label(from + i)}</option>`).join('');

  return htmlPage({
    title: `${ownerName} quer saber quando fazes anos 🎂`,
    preview,
    body: `<div id="ask">
<p>${owner} está a juntar os aniversários de quem gosta</p>
<h1>Quando fazes anos?</h1>
<form id="form">
<input class="field" name="name" placeholder="O teu nome" autocomplete="name" maxlength="80" required>
<div class="fields">
<select class="field" name="day" aria-label="Dia" required><option value="">Dia</option>${options(1, 31, String)}</select>
<select class="field" name="month" aria-label="Mês" required><option value="">Mês</option>${options(1, 12, (m) => months[m - 1]!)}</select>
</div>
<input class="field" name="year" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" placeholder="Ano (opcional)">
<input class="trap" name="website" tabindex="-1" autocomplete="off" aria-hidden="true">
<p class="small" id="error" hidden></p>
<button class="btn primary" id="send" type="submit">Enviar</button>
</form>
<p class="small">Só ${first} vê a tua data.</p>
</div>
<div id="done" hidden>
<h1>Obrigado! 🎉</h1>
<p>${first} vai receber a tua data e já não se vai esquecer do teu aniversário.</p>
<p class="small">E tu? A Birthdayly lembra-te dos aniversários de quem gostas e ajuda a combinar as prendas em grupo.</p>
${store(config.appStoreUrl, 'Descarregar para iPhone', 'ios')}
${store(config.playStoreUrl, 'Descarregar para Android', 'android')}
</div>`,
    script: `
var ua = navigator.userAgent, hide = function (id) { var e = document.getElementById(id); if (e) e.style.display = 'none'; };
if (/Android/i.test(ua)) hide('ios');
if (/iPhone|iPad|iPod/i.test(ua)) hide('android');
var form = document.getElementById('form'), send = document.getElementById('send'), error = document.getElementById('error');
var opened = Date.now();
// Um identificador aleatório deste telemóvel: uma segunda resposta substitui a primeira.
var device = null;
try { device = localStorage.getItem('bd-device'); } catch (e) {}
if (!device) {
  device = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : String(Math.random()).slice(2) + String(Date.now());
  try { localStorage.setItem('bd-device', device); } catch (e) {}
}
form.onsubmit = function (e) {
  e.preventDefault();
  var f = new FormData(form), year = (f.get('year') || '').trim();
  send.disabled = true; error.hidden = true;
  fetch(${jsString(`/birthday-requests/${token}/answers`)}, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      name: f.get('name'), day: f.get('day'), month: f.get('month'), year: year ? Number(year) : null,
      device: device, website: f.get('website') || undefined, elapsed_ms: Date.now() - opened
    })
  }).then(function (r) {
    if (r.ok) { document.getElementById('ask').hidden = true; document.getElementById('done').hidden = false; return; }
    error.textContent = r.status === 400 ? 'Confirma a data: esse dia não existe nesse mês.'
      : r.status === 410 ? 'Este link já não aceita respostas.'
      : r.status === 429 ? 'Já há muitas respostas neste link. Tenta outra vez daqui a uma hora.'
      : 'Não foi possível enviar. Tenta outra vez daqui a pouco.';
    error.hidden = false; send.disabled = false;
  }, function () { error.textContent = 'Sem ligação. Tenta outra vez.'; error.hidden = false; send.disabled = false; });
};`,
  });
}
