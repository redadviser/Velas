import { existsSync } from 'node:fs';

import { defaultFees, defaultServiceFee, type FeeTable } from '../modules/payments/payments.model.js';

/** Pagamentos dentro da app (Stripe Connect). Sem STRIPE_SECRET_KEY ficam desligados. */
export interface PaymentsConfig {
  stripeSecretKey: string;
  /** Segredo do webhook (Stripe → Developers → Webhooks), para confirmar os pagamentos. */
  stripeWebhookSecret?: string;
  fees: FeeTable;
  /** Taxa de serviço da Birthdayly por pagamento, em euros (PAYMENTS_SERVICE_FEE; 0 desliga). */
  serviceFee: number;
}

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
  /** Swagger UI em /docs e especificação OpenAPI em /docs/json. */
  docs: boolean;
  /** Chave da API do GIPHY (pesquisa de GIFs e stickers no chat). Sem ela, a pesquisa fica desligada. */
  giphyApiKey?: string;
  payments?: PaymentsConfig;
  /** Para onde vão as denúncias de utilizadores (MODERATION_EMAIL). Sem ele ficam só na base de dados. */
  moderationEmail?: string;
  /** Responsável pelos dados e contacto de apoio, nas páginas legais e na app. */
  legal: { entity: string; email?: string };
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
    androidPackage: env.ANDROID_PACKAGE ?? 'com.velas.app',
    appStoreUrl: env.APP_STORE_URL?.trim() || undefined,
    playStoreUrl: env.PLAY_STORE_URL?.trim() || undefined,
    rateLimit: env.RATE_LIMIT !== 'false',
    docs: env.API_DOCS !== 'false',
    giphyApiKey: env.GIPHY_API_KEY?.trim() || undefined,
    payments: loadPaymentsConfig(env),
    moderationEmail: env.MODERATION_EMAIL?.trim() || undefined,
    legal: {
      entity: env.LEGAL_ENTITY?.trim() || 'Eupasoft',
      email: env.SUPPORT_EMAIL?.trim() || undefined,
    },
  };
}

export function loadPaymentsConfig(env: NodeJS.ProcessEnv = process.env): PaymentsConfig | undefined {
  const key = env.STRIPE_SECRET_KEY?.trim();
  if (!key) return undefined;
  let fees = defaultFees;
  if (env.STRIPE_FEES?.trim()) {
    try {
      fees = { ...defaultFees, ...(JSON.parse(env.STRIPE_FEES) as Partial<FeeTable>) };
    } catch {
      throw new Error('STRIPE_FEES tem de ser JSON, ex.: {"card":{"percent":1.5,"fixed":0.25}}');
    }
  }
  const serviceFee = env.PAYMENTS_SERVICE_FEE?.trim() ? Number(env.PAYMENTS_SERVICE_FEE) : defaultServiceFee;
  if (!Number.isFinite(serviceFee) || serviceFee < 0 || serviceFee > 5) {
    throw new Error('PAYMENTS_SERVICE_FEE tem de ser um valor em euros entre 0 e 5, ex.: 0.39');
  }
  return { stripeSecretKey: key, stripeWebhookSecret: env.STRIPE_WEBHOOK_SECRET?.trim() || undefined, fees, serviceFee };
}

export function loadMailConfig(env: NodeJS.ProcessEnv = process.env): MailConfig {
  const from = env.MAIL_FROM?.trim() || 'Birthdayly <no-reply@velas.app>';
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
