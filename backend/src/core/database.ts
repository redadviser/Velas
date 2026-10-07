import pg from 'pg';

import type { DatabaseConfig } from '../config/env.js';

// numeric chega como string por omissão (para não perder precisão); aqui os
// valores são euros com 2 casas, por isso number é seguro e é o que a app espera.
pg.types.setTypeParser(pg.types.builtins.NUMERIC, (v) => Number.parseFloat(v));
// date como 'AAAA-MM-DD', sem conversão de fuso horário.
pg.types.setTypeParser(pg.types.builtins.DATE, (v) => v);

export type Db = pg.Pool;
export type Tx = pg.PoolClient;

const clientConfig = (c: DatabaseConfig, database = c.database): pg.ClientConfig => ({
  host: c.host,
  port: c.port,
  database,
  user: c.user,
  password: c.password,
  ssl: c.ssl ? { rejectUnauthorized: false } : undefined,
  connectionTimeoutMillis: 10_000,
});

export function createPool(c: DatabaseConfig): Db {
  return new pg.Pool({ ...clientConfig(c), max: 10 });
}

/**
 * Cria a base de dados se ainda não existir no servidor (ligando-se à base
 * `postgres`). O utilizador precisa da permissão CREATEDB; se não a tiver,
 * cria a base à mão e o resto (tabelas) é feito pelas migrações.
 */
export async function ensureDatabase(c: DatabaseConfig, log: (msg: string) => void = console.log): Promise<void> {
  const probe = new pg.Client(clientConfig(c));
  try {
    await probe.connect();
    return;
  } catch (e) {
    if ((e as { code?: string }).code !== '3D000') throw describeConnectionError(e, c); // 3D000 = não existe
  } finally {
    await probe.end().catch(() => {});
  }

  const admin = new pg.Client(clientConfig(c, 'postgres'));
  try {
    await admin.connect();
    await admin.query(`create database ${pg.escapeIdentifier(c.database)}`);
    log(`✓ base de dados "${c.database}" criada`);
  } catch (e) {
    if ((e as { code?: string }).code === '42501') {
      throw new Error(
        `A base de dados "${c.database}" não existe e o utilizador "${c.user}" não a pode criar. ` +
          `Cria-a no servidor (create database "${c.database}";) e volta a correr.`,
      );
    }
    if ((e as { code?: string }).code !== '42P04') throw describeConnectionError(e, c); // 42P04 = já existe
  } finally {
    await admin.end().catch(() => {});
  }
}

/** Mensagem clara para os erros de ligação mais comuns. */
function describeConnectionError(e: unknown, c: DatabaseConfig): Error {
  const err = e as { code?: string; message?: string };
  const where = `${c.user}@${c.host}:${c.port}/${c.database}`;
  const reason =
    err.code === '28P01'
      ? 'utilizador ou palavra-passe incorretos'
      : err.code === 'ECONNREFUSED'
        ? 'o servidor recusou a ligação (host/porta certos? o Postgres aceita ligações externas?)'
        : err.code === 'ENOTFOUND'
          ? 'host desconhecido'
          : (err.message ?? String(e));
  return new Error(`Não foi possível ligar a ${where}: ${reason}`);
}

/**
 * Executa [fn] numa transação. Com [uid], as funções SQL (app.uid()) e os
 * triggers sabem quem é o utilizador autenticado.
 */
export async function tx<T>(db: Db, uid: string | null, fn: (c: Tx) => Promise<T>): Promise<T> {
  const client = await db.connect();
  try {
    await client.query('begin');
    if (uid) await client.query(`select set_config('app.user_id', $1, true)`, [uid]);
    const result = await fn(client);
    await client.query('commit');
    return result;
  } catch (e) {
    await client.query('rollback').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}
