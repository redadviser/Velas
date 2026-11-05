import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { rateLimits } from '../../core/auth-guard.js';
import { escapeHtml, htmlPage, jsString } from '../../core/html.js';
import { doc } from '../../core/openapi.js';
import { emailSchema } from '../../core/validation.js';
import type { AccountDeletionService } from './account-deletion.service.js';

const tag = 'Perfil';
const tokenSchema = z.string().regex(/^[A-Za-z0-9_-]{20,100}$/);
const requestBody = z.object({ email: emailSchema, website: z.string().optional() });
const confirmBody = z.object({ token: tokenSchema });
const pageQuery = z.object({ token: z.string().optional() });

/** Rotas públicas: pedir pela página web, a página do link do email e confirmar. */
export async function accountDeletionPublicRoutes(app: FastifyInstance, deletion: AccountDeletionService) {
  /** Responde sempre 204, para não revelar se o email tem conta. */
  app.post(
    '/account-deletion',
    {
      config: rateLimits.strict,
      schema: doc({ tag, summary: 'Pedir o apagamento da conta sem a app (envia o email de confirmação)', body: requestBody }),
    },
    async (req, reply) => {
      const { email, website } = requestBody.parse(req.body);
      if (!website) await deletion.requestByEmail(email, req.log);
      return reply.status(204).send();
    },
  );

  app.get(
    '/conta/apagar',
    { config: rateLimits.lookup, schema: doc({ tag: 'Páginas', summary: 'Página do link do email: confirmar a eliminação da conta', query: pageQuery }) },
    async (req, reply) => {
      const token = tokenSchema.safeParse(pageQuery.parse(req.query).token);
      const email = token.success ? await deletion.pending(token.data) : null;
      return reply
        .type('text/html; charset=utf-8')
        .header('cache-control', 'no-store')
        .send(email && token.success ? confirmPage(token.data, email) : expiredPage());
    },
  );

  // Só um POST apaga: os leitores de email que abrem os links sozinhos não apagam nada.
  app.post(
    '/account-deletion/confirm',
    { config: rateLimits.strict, schema: doc({ tag, summary: 'Confirmar a eliminação (apaga a conta e todos os dados)', body: confirmBody }) },
    async (req, reply) => {
      await deletion.confirm(confirmBody.parse(req.body).token);
      return reply.status(204).send();
    },
  );
}

function confirmPage(token: string, email: string): string {
  return htmlPage({
    title: 'Birthdayly — apagar a conta',
    body: `<div id="ask">
<h1>Apagar a conta?</h1>
<p>Vais apagar a conta <strong>${escapeHtml(email)}</strong> e todos os dados: o perfil, os aniversários, as ideias de presente, as mensagens, os cartões, as fotografias, as conversas privadas e os grupos que administras.</p>
<p>Não é possível recuperar.</p>
<p class="small">Se tens o Birthdayly+, cancela a subscrição na App Store ou no Google Play: apagar a conta não a cancela.</p>
<p class="small" id="error" hidden></p>
<button class="btn primary" id="confirm" type="button">Apagar a conta definitivamente</button>
<p class="small">Mudaste de ideias? Fecha esta página: a conta continua como está.</p>
</div>
<div id="done" hidden>
<h1>Conta apagada</h1>
<p>A tua conta e todos os dados foram apagados. Obrigado por teres usado a Birthdayly.</p>
</div>`,
    script: `
var btn = document.getElementById('confirm'), error = document.getElementById('error');
btn.onclick = function () {
  btn.disabled = true; error.hidden = true;
  fetch('/account-deletion/confirm', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ token: ${jsString(token)} })
  }).then(function (r) {
    if (r.ok) { document.getElementById('ask').hidden = true; document.getElementById('done').hidden = false; return; }
    error.textContent = r.status === 410 ? 'Este link expirou ou já foi usado. Pede outro na app ou em /legal/apagar-conta.'
      : 'Não foi possível apagar a conta. Tenta outra vez daqui a pouco.';
    error.hidden = false; btn.disabled = r.status === 410;
  }, function () { error.textContent = 'Sem ligação. Tenta outra vez.'; error.hidden = false; btn.disabled = false; });
};`,
  });
}

function expiredPage(): string {
  return htmlPage({
    title: 'Birthdayly — link expirado',
    body: `<h1>Link expirado</h1>
<p>Este link para apagar a conta expirou ou já foi usado.</p>
<a class="btn primary" href="/legal/apagar-conta">Pedir um link novo</a>`,
  });
}

/** O formulário da página /legal/apagar-conta (pedir o email sem a app). */
export function deletionRequestForm(): { body: string; script: string } {
  return {
    body: `<div class="panel">
<h2>Pedir a eliminação</h2>
<form id="del">
<p>Indique o email associado à conta. Enviaremos um link para confirmar a eliminação.</p>
<label class="small" for="del-email">Email</label>
<input class="field" id="del-email" name="email" type="email" placeholder="nome@exemplo.pt" autocomplete="email" maxlength="254" required>
<input class="trap" name="website" tabindex="-1" autocomplete="off" aria-hidden="true">
<p class="small" id="del-error" role="alert" hidden></p>
<button class="btn" id="del-send" type="submit">Enviar link de confirmação</button>
</form>
<p id="del-done" role="status" hidden>Se este email estiver associado a uma conta Birthdayly, enviámos um link para confirmar a eliminação. Verifique a caixa de entrada e a pasta de spam.</p>
</div>`,
    script: `
var del = document.getElementById('del'), delSend = document.getElementById('del-send'), delError = document.getElementById('del-error');
del.onsubmit = function (e) {
  e.preventDefault();
  var f = new FormData(del);
  delSend.disabled = true; delError.hidden = true;
  fetch('/account-deletion', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: f.get('email'), website: f.get('website') || undefined })
  }).then(function (r) {
    if (r.ok) { del.hidden = true; document.getElementById('del-done').hidden = false; return; }
    delError.textContent = r.status === 429 ? 'Demasiados pedidos. Tenta outra vez daqui a um minuto.' : 'Confirma o email e tenta outra vez.';
    delError.hidden = false; delSend.disabled = false;
  }, function () { delError.textContent = 'Sem ligação. Tenta outra vez.'; delError.hidden = false; delSend.disabled = false; });
};`,
  };
}
