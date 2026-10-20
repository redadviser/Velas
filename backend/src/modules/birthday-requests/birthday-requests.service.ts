import { randomBytes } from 'node:crypto';

import { tx, type Db } from '../../core/database.js';
import { HttpError } from '../../core/errors.js';
import type { RealtimeHub } from '../../core/realtime.js';
import { maxAnswers, type AnswerInput, type BirthdayRequest, type RequestOwner } from './birthday-requests.model.js';

const newToken = () => randomBytes(16).toString('base64url');

/**
 * Pedir aniversários por link: quem abre o link deixa o nome e a data, e o
 * aniversário entra na lista de quem pediu (ver migrations/013_birthday_requests.sql).
 */
export class BirthdayRequestsService {
  constructor(
    private readonly db: Db,
    private readonly hub: RealtimeHub,
  ) {}

  /** O link do utilizador (criado na primeira vez). */
  async mine(userId: string): Promise<BirthdayRequest> {
    await this.db.query(
      'insert into birthday_requests (user_id, token) values ($1, $2) on conflict (user_id) do nothing',
      [userId, newToken()],
    );
    const { rows } = await this.db.query<BirthdayRequest>(
      'select token, answers from birthday_requests where user_id = $1',
      [userId],
    );
    return rows[0]!;
  }

  /** Um link novo: o antigo deixa de funcionar (ex.: foi partilhado onde não devia). */
  async reset(userId: string): Promise<BirthdayRequest> {
    const { rows } = await this.db.query<BirthdayRequest>(
      `insert into birthday_requests (user_id, token) values ($1, $2)
       on conflict (user_id) do update set token = excluded.token
       returning token, answers`,
      [userId, newToken()],
    );
    return rows[0]!;
  }

  async owner(token: string): Promise<RequestOwner | null> {
    const { rows } = await this.db.query<RequestOwner>(
      `select p.id as user_id, coalesce(nullif(p.display_name, ''), p.username, 'Alguém') as name
       from birthday_requests r join profiles p on p.id = r.user_id
       where r.token = $1`,
      [token],
    );
    return rows[0] ?? null;
  }

  /**
   * Acrescenta o aniversário à lista de quem pediu. Se já lá estiver alguém
   * com o mesmo nome e a mesma data, não repete (e responde da mesma forma).
   */
  async answer(token: string, a: AnswerInput): Promise<void> {
    const ownerId = await tx(this.db, null, async (c) => {
      const { rows } = await c.query<{ user_id: string; answers: number }>(
        'select user_id, answers from birthday_requests where token = $1 for update',
        [token],
      );
      const request = rows[0];
      if (!request) throw new HttpError(404, 'request_not_found');
      if (request.answers >= maxAnswers) throw new HttpError(429, 'request_full');
      const exists = await c.query(
        `select 1 from people
         where user_id = $1 and lower(trim(name)) = lower($2) and birth_day = $3 and birth_month = $4`,
        [request.user_id, a.name, a.day, a.month],
      );
      if (exists.rowCount) return null;
      await c.query(
        `insert into people (user_id, name, birth_day, birth_month, birth_year)
         values ($1, $2, $3, $4, $5)`,
        [request.user_id, a.name, a.day, a.month, a.year ?? null],
      );
      await c.query('update birthday_requests set answers = answers + 1 where user_id = $1', [request.user_id]);
      return request.user_id;
    });
    // A app de quem pediu volta a carregar os dados (o aniversário aparece sozinho).
    if (ownerId) this.hub.send([ownerId], { type: 'data' });
  }
}
