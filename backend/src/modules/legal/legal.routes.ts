import type { FastifyInstance } from 'fastify';

import type { Config } from '../../config/env.js';
import { escapeHtml, htmlPage } from '../../core/html.js';
import { doc } from '../../core/openapi.js';
import {
  deleteAccountDoc,
  minimumAge,
  privacyPolicy,
  termsOfUse,
  termsVersion,
  type LegalContact,
  type LegalDoc,
} from './legal.content.js';

/**
 * Páginas públicas da Política de Privacidade, dos Termos e de como apagar a
 * conta. As lojas pedem estes URLs, e a app abre-os a partir do Perfil.
 */
export async function legalRoutes(app: FastifyInstance, config: Config) {
  const contact: LegalContact = { entity: config.legal.entity, email: config.legal.email };
  const pages: [string, string, (c: LegalContact) => LegalDoc][] = [
    ['/legal/privacidade', 'Política de Privacidade', privacyPolicy],
    ['/legal/termos', 'Termos de Utilização', termsOfUse],
    ['/legal/apagar-conta', 'Apagar a conta', deleteAccountDoc],
  ];
  for (const [path, summary, build] of pages) {
    app.get(path, { schema: doc({ tag: 'Páginas', summary }) }, (_req, reply) =>
      reply.type('text/html; charset=utf-8').header('cache-control', 'public, max-age=3600').send(legalPage(build(contact))),
    );
  }

  app.get('/legal/info', { schema: doc({ tag: 'Sistema', summary: 'Versão dos termos, idade mínima e contacto de apoio' }) }, () => ({
    terms_version: termsVersion,
    minimum_age: minimumAge,
    entity: contact.entity,
    support_email: contact.email ?? null,
    privacy_url: `${config.publicUrl}/legal/privacidade`,
    terms_url: `${config.publicUrl}/legal/termos`,
  }));
}

export function legalPage(d: LegalDoc): string {
  const section = (s: LegalDoc['sections'][number]) =>
    `<h2>${escapeHtml(s.title)}</h2>` +
    (s.paragraphs ?? []).map((p) => `<p>${escapeHtml(p)}</p>`).join('') +
    (s.bullets?.length ? `<ul>${s.bullets.map((b) => `<li>${escapeHtml(b)}</li>`).join('')}</ul>` : '');
  return htmlPage({
    title: `Birthdayly — ${d.title}`,
    body: `<div class="doc"><h1>${escapeHtml(d.title)}</h1><p class="lead">${escapeHtml(d.intro)}</p>${d.sections.map(section).join('')}</div>`,
  });
}
