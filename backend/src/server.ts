import { constants } from 'node:fs';
import { access, mkdir } from 'node:fs/promises';

import { buildApp } from './app.js';
import { loadConfig, loadDotEnv } from './config/env.js';
import type { Deps } from './container.js';
import { createPool, ensureDatabase } from './core/database.js';
import { createMailer, type Mailer } from './core/mailer.js';
import { migrate } from './core/migrations.js';
import { PhotoStorage } from './core/storage.js';
import { googleVerifier } from './modules/auth/google.js';
import { AccessTokens } from './modules/auth/tokens.js';

async function main() {
  loadDotEnv();
  const config = loadConfig();
  const db = createPool(config.database);

  // O mailer usa o logger da app (para escrever os emails quando não há SMTP),
  // por isso só é criado depois dela.
  let mailer: Mailer = async () => {};

  const deps: Deps = {
    config,
    db,
    storage: new PhotoStorage(config.uploadDir, config.publicUrl, config.jwtSecret),
    tokens: new AccessTokens(config.jwtSecret),
    mail: (m) => mailer(m),
    verifyGoogle: googleVerifier(config.googleClientIds),
  };

  const app = await buildApp(deps, { logger: { level: process.env.LOG_LEVEL ?? 'info' } });
  mailer = createMailer(config.mail, app.log);

  // Cria a base de dados (se faltar) e as tabelas antes de aceitar pedidos.
  if (process.env.MIGRATE_ON_START !== 'false') {
    await ensureDatabase(config.database, (msg) => app.log.info(msg));
    await migrate(db, (msg) => app.log.info(msg));
  }
  // As fotografias precisam de uma pasta gravável e persistente (volume no CapRover).
  try {
    await mkdir(config.uploadDir, { recursive: true });
    await access(config.uploadDir, constants.W_OK);
  } catch {
    app.log.error(`UPLOAD_DIR (${config.uploadDir}) não é gravável: o envio de fotografias vai falhar.`);
  }
  if (config.googleClientIds.length === 0) app.log.warn('GOOGLE_CLIENT_IDS vazio: o login com Google está desativado.');

  await app.listen({ port: config.port, host: config.host });

  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.once(signal, async () => {
      await app.close();
      await db.end();
      process.exit(0);
    });
  }
}

// Erros de arranque (variáveis em falta, BD inacessível): uma linha clara no
// log e código 1, para o CapRover/Docker voltar a tentar.
main().catch((e: Error) => {
  console.error(`Arranque falhou: ${e.message}`);
  process.exit(1);
});
