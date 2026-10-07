// PostgreSQL em memória (PGlite) com a parte da interface do pg.Pool que a API
// usa: query(), connect() e release(). Só para testes.
import { PGlite } from '@electric-sql/pglite';

import type { Db } from '../src/core/database.js';

const NUMERIC = 1700;
const DATE = 1082;

export async function createTestDb(): Promise<{ db: Db; close: () => Promise<void> }> {
  // Os mesmos formatos que src/core/database.ts configura no driver pg.
  const pglite = await PGlite.create({
    parsers: { [NUMERIC]: (v: string) => Number.parseFloat(v), [DATE]: (v: string) => v },
  });

  const query = async (text: string, params?: unknown[]) => {
    if (params?.length) {
      const r = await pglite.query(text, params);
      return { rows: r.rows, rowCount: r.rows.length || r.affectedRows || 0 };
    }
    // Sem parâmetros pode haver várias instruções (migrações).
    const results = await pglite.exec(text);
    const last = results.at(-1);
    return { rows: last?.rows ?? [], rowCount: last?.rows.length || last?.affectedRows || 0 };
  };

  // Uma só ligação: as transações dos testes correm uma de cada vez.
  let lock = Promise.resolve();
  const connect = async () => {
    let release!: () => void;
    const previous = lock;
    lock = new Promise<void>((r) => (release = r));
    await previous;
    return { query, release };
  };

  return { db: { query, connect } as unknown as Db, close: () => pglite.close() };
}
