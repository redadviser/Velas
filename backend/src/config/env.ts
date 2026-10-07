import { existsSync } from 'node:fs';

/** Ligação ao servidor PostgreSQL. */
export interface DatabaseConfig {
  host: string;
  port: number;
  /** Nome da base de dados (é criada se ainda não existir). */
  database: string;
  user: string;
  password: string;
  /** Liga com TLS (a maioria dos Postgres geridos exige). */
  ssl: boolean;
}

/** Servidor de email (recuperação de palavra-passe). */
export interface SmtpConfig {
  host: string;
  port: number;
  /** ssl = TLS desde o início (465); starttls = passa a TLS depois de ligar (587); none = sem TLS (só testes locais). */
  protocol: 'ssl' | 'starttls' | 'none';
  user: string;
  password: string;
}

export interface MailConfig {
  /** Sem servidor (SMTP_HOST vazio) os emails são escritos no log. */
  smtp?: SmtpConfig;
  from: string;
}

export interface Config {
  port: number;
  host: string;
  database: DatabaseConfig;
  /** Segredo HMAC dos access tokens e dos URLs das fotografias. */
  jwtSecret: string;
  /** Endereço público da API, usado nos links de email e das fotografias. */
  publicUrl: string;
  /** Client IDs OAuth aceites como audiência do ID token Google (iOS, Android, Web). */
  googleClientIds: string[];
  uploadDir: string;
  mail: MailConfig;
  /** Esquema de URL da app (abre a app a partir dos links de email e de convite). */
  appScheme: string;
  /** ID da app Android (applicationId), para abrir a app ou a Play Store a partir de um link. */
  androidPackage: string;
  /** Links das lojas, mostrados na página de convite a quem ainda não tem a app. */
  appStoreUrl?: string;
  playStoreUrl?: string;
  /** Limites de pedidos por IP nas rotas de autenticação (desligar só em testes). */
  rateLimit: boolean;
}

function required(env: NodeJS.ProcessEnv, key: string): string {
  const v = env[key]?.trim();
  if (!v) throw new Error(`Falta a variável de ambiente ${key} (ver .env.example).`);
  return v;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const port = Number(env.PORT ?? 3000);
  const jwtSecret = required(env, 'JWT_SECRET');
  if (jwtSecret.length < 32) throw new Error('JWT_SECRET tem de ter pelo menos 32 caracteres.');
  return {
    port,
    host: env.HOST ?? '0.0.0.0',
    database: {
      host: required(env, 'DB_HOST'),
      port: Number(env.DB_PORT ?? 5432),
      database: required(env, 'DB_NAME'),
      user: required(env, 'DB_USER'),
      // Sem trim: a palavra-passe pode ter espaços.
      password: env.DB_PASSWORD ?? '',
      ssl: env.DB_SSL === 'true',
    },
    jwtSecret,
    publicUrl: (env.PUBLIC_URL ?? `http://localhost:${port}`).replace(/\/+$/, ''),
    googleClientIds: (env.GOOGLE_CLIENT_IDS ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
    uploadDir: env.UPLOAD_DIR ?? './uploads',
    mail: loadMailConfig(env),
    appScheme: env.APP_SCHEME ?? 'com.eupasoft.velas',
    androidPackage: env.ANDROID_PACKAGE ?? 'com.eupasoft.aniversarios',
    appStoreUrl: env.APP_STORE_URL?.trim() || undefined,
    playStoreUrl: env.PLAY_STORE_URL?.trim() || undefined,
    rateLimit: env.RATE_LIMIT !== 'false',
  };
}

export function loadMailConfig(env: NodeJS.ProcessEnv = process.env): MailConfig {
  const from = env.MAIL_FROM?.trim() || 'Velas <no-reply@velas.app>';
  const host = env.SMTP_HOST?.trim();
  if (!host) return { from };
  const port = Number(env.SMTP_PORT || 465);
  const protocol = (env.SMTP_PROTOCOL?.trim().toLowerCase() || (port === 465 ? 'ssl' : 'starttls')) as SmtpConfig['protocol'];
  if (!['ssl', 'starttls', 'none'].includes(protocol)) {
    throw new Error('SMTP_PROTOCOL tem de ser ssl, starttls ou none.');
  }
  return {
    from,
    smtp: {
      host,
      port,
      protocol,
      user: env.SMTP_USER?.trim() ?? '',
      // Sem trim: a palavra-passe pode ter espaços.
      password: env.SMTP_PASSWORD ?? '',
    },
  };
}

/** Carrega o ficheiro .env, se existir (Node 22+). */
export function loadDotEnv(path = '.env'): void {
  if (existsSync(path)) process.loadEnvFile(path);
}
