import type { FastifyInstance } from 'fastify';

import type { Config } from '../../config/env.js';
import { docPage, escapeHtml } from '../../core/html.js';
import { doc } from '../../core/openapi.js';
import { deletionRequestForm } from '../users/account-deletion.routes.js';
import {
  deleteAccountDoc,
  minimumAge,
  termsOfUse,
  termsVersion,
  type LegalContact,
  type LegalDoc,
} from './legal.content.js';

/**
 * Páginas públicas dos Termos e de como apagar a conta. As lojas pedem estes
 * URLs, e a app abre-os a partir do Perfil. A Política de Privacidade é a da
 * empresa: /legal/privacidade só reencaminha para ela (links antigos).
 */
export async function legalRoutes(app: FastifyInstance, config: Config) {
  const contact: LegalContact = config.legal;
  const pages: [string, string, (c: LegalContact) => LegalDoc, LegalExtra?][] = [
    ['/legal/termos', 'Termos de Utilização', termsOfUse],
    // Com o formulário para pedir o apagamento sem a app.
    ['/legal/apagar-conta', 'Eliminar a conta', deleteAccountDoc, deletionRequestForm()],
  ];
  for (const [path, summary, build, extra] of pages) {
    app.get(path, { schema: doc({ tag: 'Páginas', summary }) }, (_req, reply) =>
      reply.type('text/html; charset=utf-8').header('cache-control', 'public, max-age=3600').send(legalPage(build(contact), contact, extra)),
    );
  }

  app.get('/legal/privacidade', { schema: doc({ tag: 'Páginas', summary: 'Política de Privacidade (reencaminha para a da empresa)' }) }, (_req, reply) =>
    reply.redirect(contact.privacyUrl, 301),
  );

  app.get('/legal/info', { schema: doc({ tag: 'Sistema', summary: 'Versão dos termos, idade mínima e contacto de apoio' }) }, () => ({
    terms_version: termsVersion,
    minimum_age: minimumAge,
    entity: contact.entity,
    support_email: contact.email ?? null,
    privacy_url: contact.privacyUrl,
    terms_url: `${config.publicUrl}/legal/termos`,
  }));
}

/** HTML e script a acrescentar no fim da página (já escapados). */
type LegalExtra = { body: string; script: string };

const months = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

/** "2026-11-05" → "5 de novembro de 2026". */
function longDate(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return `${d} de ${months[m! - 1]} de ${y}`;
}

export function legalPage(d: LegalDoc, c: LegalContact, extra?: LegalExtra): string {
  const section = (s: LegalDoc['sections'][number], i: number) =>
    `<section id="s${i + 1}"><h2>${escapeHtml(s.title)}</h2>` +
    (s.paragraphs ?? []).map((p) => `<p>${escapeHtml(p)}</p>`).join('') +
    (s.steps?.length ? `<ol class="steps">${s.steps.map((b) => `<li>${escapeHtml(b)}</li>`).join('')}</ol>` : '') +
    '</section>';
  const links = [
    ['/legal/termos', 'Termos de Utilização'],
    [c.privacyUrl, 'Política de Privacidade'],
    ['/legal/apagar-conta', 'Eliminar a conta'],
    ...(c.email ? [[`mailto:${c.email}`, c.email]] : []),
  ];
  return docPage({
    title: `${d.title} · Birthdayly`,
    heading: d.title,
    meta: d.updated ? `Versão de ${longDate(d.updated)}` : undefined,
    numbered: d.numbered,
    toc: d.sections.map((s) => s.title),
    body: (d.intro ? `<p class="lead">${escapeHtml(d.intro)}</p>` : '') + d.sections.map(section).join('') + (extra?.body ?? ''),
    footer:
      `<nav>${links.map(([href, label]) => `<a href="${escapeHtml(href!)}">${escapeHtml(label!)}</a>`).join('')}</nav>` +
      `<div>© ${new Date().getFullYear()} ${escapeHtml(c.entity)}${c.address ? ` · ${escapeHtml(c.address)}` : ''}</div>`,
    script: extra?.script,
  });
}
