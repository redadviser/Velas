import { fileURLToPath } from 'node:url';

import { loadDotEnv, loadMailConfig } from '../config/env.js';
import { createMailer } from './mailer.js';

/**
 * Envia um email de teste com as definições SMTP do .env:
 *   npm run mail:test -- destinatario@exemplo.com
 */
async function main() {
  loadDotEnv();
  const to = process.argv[2];
  if (!to) throw new Error('Indica o destinatário: npm run mail:test -- destinatario@exemplo.com');
  const config = loadMailConfig();
  if (!config.smtp) throw new Error('SMTP_HOST está vazio no .env.');
  const { host, port, protocol, user } = config.smtp;
  console.log(`A enviar por ${host}:${port} (${protocol}) como ${user || 'sem autenticação'}…`);
  await createMailer(config, console)({
    to,
    subject: 'Velas — teste de email',
    text: 'Se recebeste este email, o envio está a funcionar.',
    html: '<p>Se recebeste este email, o envio está a funcionar.</p>',
  });
  console.log(`Enviado para ${to}.`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((e: Error) => {
    console.error(`Falhou: ${e.message}`);
    process.exitCode = 1;
  });
}
