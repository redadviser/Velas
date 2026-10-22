import { randomBytes } from 'node:crypto';

import { tx, type Db, type Tx } from '../../core/database.js';
import { HttpError, notFound } from '../../core/errors.js';
import type { RealtimeHub } from '../../core/realtime.js';
import {
  maxAnswers,
  maxAnswersPerHour,
  minElapsedMs,
  type AnswerInput,
  type BirthdayRequest,
  type PendingAnswer,
  type RequestOwner,
} from './birthday-requests.model.js';

const newToken = () => randomBytes(16).toString('base64url');

const requestColumns = `r.token, r.enabled, r.expires_at, r.enabled and r.expires_at > now() as open,
  (select count(*)::int from birthday_answers a where a.user_id = r.user_id and a.status = 'accepted') as answers,
  (select count(*)::int from birthday_answers a where a.user_id = r.user_id and a.status = 'pending') as pending`;

/**
 * Pedir aniversários por link: quem abre o link deixa o nome e a data, que
 * ficam pendentes até o dono os aceitar (ver migrations/013 e 017). Contra o
 * spam: uma resposta por telemóvel, no máximo 30 por hora em cada link, um
 * campo escondido para robôs, links que expiram e que se podem desligar.
 */
export class BirthdayRequestsService {
  constructor(
    private readonly db: Db,
    private readonly hub: RealtimeHub,
  ) {}

  private async requestIn(c: Db | Tx, userId: string): Promise<BirthdayRequest> {
    const { rows } = await c.query<BirthdayRequest>(`select ${requestColumns} from birthday_requests r where r.user_id = $1`, [
      userId,
    ]);
    return rows[0]!;
  }

  /** O link do utilizador (criado na primeira vez). */
  async mine(userId: string): Promise<BirthdayRequest> {
    await this.db.query(
      'insert into birthday_requests (user_id, token) values ($1, $2) on conflict (user_id) do nothing',
      [userId, newToken()],
    );
    return this.requestIn(this.db, userId);
  }

  /** Um link novo, ligado e válido por mais 30 dias: o antigo deixa de funcionar. */
  async reset(userId: string): Promise<BirthdayRequest> {
    await this.db.query(
      `insert into birthday_requests (user_id, token) values ($1, $2)
       on conflict (user_id) do update set token = excluded.token, enabled = true, expires_at = now() + interval '30 days'`,
      [userId, newToken()],
    );
    return this.requestIn(this.db, userId);
  }

  /** Desligar (ninguém responde) ou voltar a ligar (por mais 30 dias). */
  async setEnabled(userId: string, enabled: boolean): Promise<BirthdayRequest> {
    await this.mine(userId);
    await this.db.query(
      `update birthday_requests set enabled = $2,
              expires_at = case when $2 then greatest(expires_at, now() + interval '30 days') else expires_at end
       where user_id = $1`,
      [userId, enabled],
    );
    return this.requestIn(this.db, userId);
  }

  async owner(token: string): Promise<RequestOwner | null> {
    const { rows } = await this.db.query<RequestOwner>(
      `select p.id as user_id, coalesce(nullif(p.display_name, ''), p.username, 'Alguém') as name,
              r.enabled and r.expires_at > now() as open
       from birthday_requests r join profiles p on p.id = r.user_id
       where r.token = $1`,
      [token],
    );
    return rows[0] ?? null;
  }

  /**
   * Guarda a resposta como pendente. Robôs (campo escondido ou envio rápido
   * demais) e quem já está na lista recebem a mesma resposta, sem que nada
   * fique guardado. Uma segunda resposta do mesmo telemóvel substitui a primeira.
   */
  async answer(token: string, a: AnswerInput): Promise<void> {
    if (a.website || (a.elapsed_ms !== undefined && a.elapsed_ms < minElapsedMs)) return;
    const ownerId = await tx(this.db, null, async (c) => {
      const { rows } = await c.query<{ user_id: string; open: boolean }>(
        `select user_id, enabled and expires_at > now() as open from birthday_requests where token = $1 for update`,
        [token],
      );
      const request = rows[0];
      if (!request) throw new HttpError(404, 'request_not_found');
      if (!request.open) throw new HttpError(410, 'request_closed');
      const counts = await c.query<{ hour: number; total: number }>(
        `select count(*) filter (where created_at > now() - interval '1 hour')::int as hour, count(*)::int as total
         from birthday_answers where user_id = $1`,
        [request.user_id],
      );
      if (counts.rows[0]!.hour >= maxAnswersPerHour || counts.rows[0]!.total >= maxAnswers) {
        throw new HttpError(429, 'request_busy');
      }
      const known = await c.query(
        `select 1 from people
         where user_id = $1 and lower(trim(name)) = lower($2) and birth_day = $3 and birth_month = $4`,
        [request.user_id, a.name, a.day, a.month],
      );
      if (known.rowCount) return null;
      await c.query(
        `insert into birthday_answers (user_id, name, birth_day, birth_month, birth_year, device)
         values ($1, $2, $3, $4, $5, $6)
         on conflict (user_id, device) where status = 'pending' do update set
           name = excluded.name, birth_day = excluded.birth_day, birth_month = excluded.birth_month,
           birth_year = excluded.birth_year, created_at = now()`,
        [request.user_id, a.name, a.day, a.month, a.year ?? null, a.device],
      );
      return request.user_id;
    });
    // A app de quem pediu mostra logo que há respostas por confirmar.
    if (ownerId) this.hub.send([ownerId], { type: 'data' });
  }

  async pending(userId: string): Promise<PendingAnswer[]> {
    const { rows } = await this.db.query<PendingAnswer>(
      `select id, name, birth_day, birth_month, birth_year, created_at from birthday_answers
       where user_id = $1 and status = 'pending' order by created_at`,
      [userId],
    );
    return rows;
  }

  /** Aceitar uma resposta (ou todas, sem [answerId]): entra na lista, sem repetir quem lá está. */
  async accept(userId: string, answerId?: string): Promise<number> {
    const added = await tx(this.db, userId, async (c) => {
      const { rows } = await c.query<{ id: string; name: string; birth_day: number; birth_month: number; birth_year: number | null }>(
        `update birthday_answers set status = 'accepted'
         where user_id = $1 and status = 'pending' and ($2::uuid is null or id = $2)
         returning id, name, birth_day, birth_month, birth_year`,
        [userId, answerId ?? null],
      );
      if (answerId && !rows.length) throw notFound();
      let n = 0;
      for (const a of rows) {
        const r = await c.query(
          `insert into people (user_id, name, birth_day, birth_month, birth_year)
           select $1, $2, $3, $4, $5
           where not exists (
             select 1 from people
             where user_id = $1 and lower(trim(name)) = lower($2) and birth_day = $3 and birth_month = $4
           )`,
          [userId, a.name, a.birth_day, a.birth_month, a.birth_year],
        );
        n += r.rowCount ?? 0;
      }
      return n;
    });
    this.hub.send([userId], { type: 'data' });
    return added;
  }

  async ignore(userId: string, answerId?: string): Promise<void> {
    await this.db.query(
      `update birthday_answers set status = 'ignored'
       where user_id = $1 and status = 'pending' and ($2::uuid is null or id = $2)`,
      [userId, answerId ?? null],
    );
  }
}
