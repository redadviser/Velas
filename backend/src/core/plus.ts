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

/** Aniversários guardados no plano Grátis (a app tem o mesmo número em plus.dart). */
export const FREE_PEOPLE_LIMIT = 20;

/**
 * Antes de guardar [adding] aniversários novos: sem o plano, acima do limite
 * responde 402 people_limit. Conta os criados (profiles.people_created), por
 * isso apagar não liberta espaço. Quem já passou do limite mantém os que tem.
 */
export async function requirePeopleRoom(c: Db | Tx, userId: string, adding = 1): Promise<void> {
  if (adding <= 0) return;
  const { rows } = await c.query<{ n: number }>('select people_created as n from profiles where id = $1', [userId]);
  if ((rows[0]?.n ?? 0) + adding <= FREE_PEOPLE_LIMIT) return;
  if (!(await hasPlus(c, userId))) throw new HttpError(402, 'people_limit');
}
