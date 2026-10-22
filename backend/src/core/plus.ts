import type { Db, Tx } from './database.js';
import { HttpError } from './errors.js';

/** A conta tem o Birthdayly+ ativo (ver migrations/016_plus.sql)? */
export async function hasPlus(c: Db | Tx, userId: string): Promise<boolean> {
  const { rows } = await c.query<{ ok: boolean }>('select has_plus($1) as ok', [userId]);
  return rows[0]?.ok ?? false;
}

/** Funcionalidade do Birthdayly+: sem o plano responde 402 plus_required (a app mostra os planos). */
export async function requirePlus(c: Db | Tx, userId: string): Promise<void> {
  if (!(await hasPlus(c, userId))) throw new HttpError(402, 'plus_required');
}
