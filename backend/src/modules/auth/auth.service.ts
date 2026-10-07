import type { FastifyBaseLogger } from 'fastify';

import type { Config } from '../../config/env.js';
import { tx, type Db, type Tx } from '../../core/database.js';
import { HttpError, unauthorized } from '../../core/errors.js';
import type { Mailer } from '../../core/mailer.js';
import { hashPassword, verifyPassword } from '../../core/passwords.js';
import type { UsersService } from '../users/users.service.js';
import type { Session, SignupInput } from './auth.model.js';
import type { GoogleVerifier } from './google.js';
import { AccessTokens, hashToken, randomToken, refreshTtlDays, resetTtlMinutes } from './tokens.js';

export class AuthService {
  constructor(
    private readonly db: Db,
    private readonly users: UsersService,
    private readonly tokens: AccessTokens,
    private readonly mail: Mailer,
    private readonly verifyGoogle: GoogleVerifier,
    private readonly config: Config,
  ) {}

  /** Nova sessão: access token curto + refresh token (só o hash é guardado). */
  private async issueSession(c: Tx, userId: string): Promise<Session> {
    const refresh = randomToken();
    await c.query(
      `insert into refresh_tokens (user_id, token_hash, expires_at) values ($1, $2, now() + make_interval(days => $3))`,
      [userId, hashToken(refresh), refreshTtlDays],
    );
    return {
      access_token: await this.tokens.sign(userId),
      refresh_token: refresh,
      expires_in: AccessTokens.ttlSeconds,
      user: await this.users.profileIn(c, userId),
    };
  }

  async signup(input: SignupInput): Promise<Session> {
    const passwordHash = await hashPassword(input.password);
    return tx(this.db, null, async (c) => {
      const taken = await c.query('select 1 from users where lower(email) = $1', [input.email]);
      if (taken.rowCount) throw new HttpError(409, 'email_taken');
      const userId = await this.users.createIn(c, {
        email: input.email,
        passwordHash,
        name: input.name,
        username: input.username,
        phone: input.phone,
      });
      return this.issueSession(c, userId);
    });
  }

  /** Username e telemóvel ainda livres (antes do registo). */
  async checkAvailability(username: string, phone: string | null): Promise<{ username_taken: boolean; phone_taken: boolean }> {
    const { rows } = await this.db.query('select signup_check($1, $2) as r', [
      username.trim().replace(/^@/, '').toLowerCase(),
      phone || null,
    ]);
    return rows[0].r;
  }

  /** [identifier] é o email ou o username. */
  async login(identifier: string, password: string): Promise<Session> {
    const byEmail = identifier.includes('@') && !identifier.startsWith('@');
    const { rows } = await this.db.query<{ id: string; password_hash: string | null; google_sub: string | null }>(
      byEmail
        ? 'select id, password_hash, google_sub from users where lower(email) = lower($1)'
        : 'select u.id, u.password_hash, u.google_sub from users u join profiles p on p.id = u.id where p.username = $1',
      [byEmail ? identifier : identifier.replace(/^@/, '').toLowerCase()],
    );
    const user = rows[0];
    const ok = await verifyPassword(password, user?.password_hash);
    if (user && !user.password_hash && user.google_sub) throw unauthorized('google_account');
    if (!user || !ok) throw unauthorized('invalid_credentials');
    return tx(this.db, null, (c) => this.issueSession(c, user.id));
  }

  /**
   * Entrar com Google. Liga à conta existente com o mesmo email (verificado
   * pelo Google) ou cria uma conta nova com username sugerido.
   */
  async google(idToken: string): Promise<Session> {
    const g = await this.verifyGoogle(idToken);
    const email = g.email.trim().toLowerCase();
    return tx(this.db, null, async (c) => {
      const bySub = await c.query<{ id: string }>('select id from users where google_sub = $1', [g.sub]);
      let userId = bySub.rows[0]?.id;
      if (!userId) {
        const byEmail = await c.query<{ id: string }>('select id from users where lower(email) = $1', [email]);
        userId = byEmail.rows[0]?.id;
        if (userId) {
          // Só se liga a uma conta existente se o Google garantir que o email é da pessoa.
          if (!g.emailVerified) throw new HttpError(409, 'email_taken');
          await c.query('update users set google_sub = $2, email_verified = true where id = $1', [userId, g.sub]);
        } else {
          userId = await this.users.createIn(c, {
            email,
            passwordHash: null,
            googleSub: g.sub,
            emailVerified: g.emailVerified,
            name: g.name,
            username: await this.users.suggestUsernameIn(c, email),
          });
        }
      }
      return this.issueSession(c, userId);
    });
  }

  /** Renova a sessão. O refresh token é rodado: o antigo deixa de funcionar. */
  refresh(refreshToken: string): Promise<Session> {
    return tx(this.db, null, async (c) => {
      const { rows } = await c.query<{ user_id: string }>(
        'delete from refresh_tokens where token_hash = $1 and expires_at > now() returning user_id',
        [hashToken(refreshToken)],
      );
      if (!rows[0]) throw unauthorized('invalid_refresh_token');
      return this.issueSession(c, rows[0].user_id);
    });
  }

  async logout(refreshToken: string): Promise<void> {
    await this.db.query('delete from refresh_tokens where token_hash = $1', [hashToken(refreshToken)]);
  }

  /** Envia o link de recuperação se o email tiver conta (sem revelar se tem). */
  async forgotPassword(email: string, log: FastifyBaseLogger): Promise<void> {
    const { rows } = await this.db.query<{ id: string }>('select id from users where lower(email) = $1', [email]);
    const user = rows[0];
    if (!user) return;
    const token = randomToken();
    await this.db.query(
      `insert into password_resets (token_hash, user_id, expires_at) values ($1, $2, now() + make_interval(mins => $3))`,
      [hashToken(token), user.id, resetTtlMinutes],
    );
    const link = `${this.config.publicUrl}/auth/reset?token=${token}`;
    await this.mail({
      to: email,
      subject: 'Velas — nova palavra-passe',
      text: `Recebemos um pedido para alterar a tua palavra-passe.\n\nAbre este link no telemóvel onde tens a app Velas (válido durante ${resetTtlMinutes} minutos):\n${link}\n\nSe não foste tu, ignora este email.`,
      html: `<p>Recebemos um pedido para alterar a tua palavra-passe.</p><p><a href="${link}">Definir nova palavra-passe</a></p><p>Abre o link no telemóvel onde tens a app Velas. É válido durante ${resetTtlMinutes} minutos.</p><p>Se não foste tu, ignora este email.</p>`,
    }).catch((e) => log.error(e, 'falhou o envio do email de recuperação'));
  }

  /** Link que abre a app com o token de recuperação. */
  appRecoveryLink(token: string): string {
    return `${this.config.appScheme}://auth-callback?type=recovery&token=${token}`;
  }

  /** Troca o token do email por uma sessão (a app pede de seguida a nova palavra-passe). */
  recover(token: string): Promise<Session> {
    return tx(this.db, null, async (c) => {
      const { rows } = await c.query<{ user_id: string }>(
        `update password_resets set used_at = now()
         where token_hash = $1 and used_at is null and expires_at > now()
         returning user_id`,
        [hashToken(token)],
      );
      if (!rows[0]) throw new HttpError(400, 'invalid_reset_token');
      await c.query('update users set email_verified = true where id = $1', [rows[0].user_id]);
      return this.issueSession(c, rows[0].user_id);
    });
  }
}
