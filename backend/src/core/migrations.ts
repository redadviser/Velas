import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

import { loadConfig, loadDotEnv } from '../config/env.js';
import { createPool, ensureDatabase, type Db } from './database.js';

const migrationsDir = fileURLToPath(new URL('../../migrations/', import.meta.url));

/** Chave do advisory lock: várias instâncias a arrancar ao mesmo tempo esperam umas pelas outras. */
const lockKey = 7_301_964;

/** Aplica, por ordem, os ficheiros de migrations/ que ainda não foram aplicados. */
export async function migrate(db: Db, log: (msg: string) => void = console.log): Promise<void> {
  const files = (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();
  const client = await db.connect();
  try {
    await client.query('select pg_advisory_lock($1)', [lockKey]);
    await client.query(`create table if not exists schema_migrations (
      name text primary key,
      applied_at timestamptz not null default now()
    )`);
    const done = new Set(
      (await client.query<{ name: string }>('select name from schema_migrations')).rows.map((r) => r.name),
    );

    for (const file of files) {
      if (done.has(file)) continue;
      const sql = await readFile(migrationsDir + file, 'utf8');
      try {
        await client.query('begin');
        await client.query(sql);
        await client.query('insert into schema_migrations (name) values ($1)', [file]);
        await client.query('commit');
        log(`✓ ${file}`);
      } catch (e) {
        await client.query('rollback');
        throw new Error(`Falhou a migração ${file}: ${(e as Error).message}`);
      }
    }
  } finally {
    await client.query('select pg_advisory_unlock($1)', [lockKey]).catch(() => {});
    client.release();
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  loadDotEnv();
  const config = loadConfig();
  const db = createPool(config.database);
  ensureDatabase(config.database)
    .then(() => migrate(db))
    .then(() => console.log(`Base de dados "${config.database.database}" pronta.`))
    .catch((e: Error) => {
      console.error(e.message);
      process.exitCode = 1;
    })
    .finally(() => db.end());
}
