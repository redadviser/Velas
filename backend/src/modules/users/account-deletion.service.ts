import type { FastifyBaseLogger } from 'fastify';

import type { Config } from '../../config/env.js';
import type { Db } from '../../core/database.js';
import { HttpError, notFound } from '../../core/errors.js';
import { escapeHtml } from '../../core/html.js';
import type { Mailer } from '../../core/mailer.js';
import { hashToken, randomToken } from '../auth/tokens.js';
import type { UsersService } from './users.service.js';

/** Quanto tempo vale o link do email. */
export const deletionTtlHours = 24;

/**
 * Apagar a conta em dois passos: o pedido envia um email com um link, e só
 * quando a pessoa abre o link e confirma é que a conta e os dados são apagados.
 */
export class AccountDeletionService {
  constructor(
    private readonly db: Db,
    private readonly users: UsersService,
    private readonly mail: Mailer,
    private readonly config: Config,
  ) {}

  /** Pedido feito na app: envia o email para o endereço da conta e devolve-o. */
  async request(userId: string): Promise<{ email: string }> {
    const { rows } = await this.db.query<{ email: string }>('select email from users where id = $1', [userId]);
    if (!rows[0]) throw notFound();
    try {
      await this.send(userId, rows[0].email);
    } catch {
      throw new HttpError(503, 'mail_failed');
    }
    return { email: rows[0].email };
  }

  /** Pedido feito na página web (sem a app): sem revelar se o email tem conta. */
  async requestByEmail(email: string, log: FastifyBaseLogger): Promise<void> {
    const { rows } = await this.db.query<{ id: string; email: string }>(
      'select id, email from users where lower(email) = $1',
      [email],
    );
    if (!rows[0]) return;
    await this.send(rows[0].id, rows[0].email).catch((e) => log.error(e, 'falhou o envio do email de eliminação da conta'));
  }

  /** O email da conta, se o link ainda vale (para a página de confirmação). */
  async pending(token: string): Promise<string | null> {
    const { rows } = await this.db.query<{ email: string }>(
      `select u.email from account_deletions d join users u on u.id = d.user_id
       where d.token_hash = $1 and d.expires_at > now()`,
      [hashToken(token)],
    );
    return rows[0]?.email ?? null;
  }

  /** Confirmado na página do link: apaga a conta e todos os dados. */
  async confirm(token: string): Promise<void> {
    const { rows } = await this.db.query<{ user_id: string }>(
      'delete from account_deletions where token_hash = $1 and expires_at > now() returning user_id',
      [hashToken(token)],
    );
    if (!rows[0]) throw new HttpError(410, 'invalid_deletion_token');
    await this.users.deleteAccount(rows[0].user_id);
  }

  private async send(userId: string, email: string): Promise<void> {
    const token = randomToken();
    await this.db.query(
      `insert into account_deletions (token_hash, user_id, expires_at)
       values ($1, $2, now() + make_interval(hours => $3))
       on conflict (user_id) do update set token_hash = excluded.token_hash, expires_at = excluded.expires_at, created_at = now()`,
      [hashToken(token), userId, deletionTtlHours],
    );
    const link = `${this.config.publicUrl}/conta/apagar?token=${token}`;
    const deleted =
      'o perfil, os aniversários, as ideias de presente, as mensagens, os cartões, as fotografias, as conversas privadas e os grupos que administras';
    const store =
      'Se tens o Birthdayly+, apagar a conta não cancela a subscrição: cancela-a na App Store ou no Google Play.';
    const help = this.config.legal.email ? ` Dúvidas? Escreve para ${this.config.legal.email}.` : '';
    await this.mail({
      to: email,
      subject: 'Birthdayly — confirmar a eliminação da conta',
      text:
        `Recebemos um pedido para apagar a tua conta da Birthdayly (${email}).\n\n` +
        `Para apagar a conta, abre este link e confirma (válido durante ${deletionTtlHours} horas):\n${link}\n\n` +
        `Ao confirmares, apagamos de forma definitiva ${deleted}. Não é possível recuperar.\n\n` +
        `${store}\n\n` +
        `Se não foste tu ou mudaste de ideias, ignora este email: a conta continua como está.${help}`,
      html:
        `<p>Recebemos um pedido para apagar a tua conta da Birthdayly (${escapeHtml(email)}).</p>` +
        `<p>Para apagar a conta, abre o link e confirma. É válido durante ${deletionTtlHours} horas.</p>` +
        `<p><a href="${escapeHtml(link)}">Confirmar a eliminação da conta</a></p>` +
        `<p>Ao confirmares, apagamos de forma definitiva ${deleted}. Não é possível recuperar.</p>` +
        `<p>${store}</p>` +
        `<p>Se não foste tu ou mudaste de ideias, ignora este email: a conta continua como está.${escapeHtml(help)}</p>`,
    });
  }
}
