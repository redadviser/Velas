/** Assinaturas do Birthdayly+ vendidas pelas lojas, através do Adapty. */
export interface AdaptyConfig {
  /** Chave secreta da app (Adapty → App settings → General → Secret key). */
  secretKey: string;
  /** Valor do cabeçalho Authorization que o Adapty envia nos webhooks (escolhido no dashboard). */
  webhookAuth?: string;
  /** O nível de acesso que dá o Birthdayly+ (Adapty → Access levels). */
  accessLevel: string;
}

/** ADAPTY_SECRET_KEY (sem ela, as compras ficam desligadas), ADAPTY_WEBHOOK_AUTH, ADAPTY_ACCESS_LEVEL. */
export function loadAdaptyConfig(env: NodeJS.ProcessEnv = process.env): AdaptyConfig | undefined {
  const secretKey = env.ADAPTY_SECRET_KEY?.trim();
  if (!secretKey) return undefined;
  return {
    secretKey,
    webhookAuth: env.ADAPTY_WEBHOOK_AUTH?.trim() || undefined,
    accessLevel: env.ADAPTY_ACCESS_LEVEL?.trim() || 'premium',
  };
}

/** Sem fim (compra vitalícia). */
export const lifetime = new Date('9999-12-31T00:00:00Z');

/** Quem diz até quando um utilizador tem o plano na loja (o Adapty; nos testes, um falso). */
export interface AdaptyClient {
  /** Até quando tem o nível de acesso (pode ser passado), ou null se nunca o teve / não é cliente. */
  accessUntil(customerUserId: string): Promise<Date | null>;
}

interface AccessLevel {
  access_level_id: string;
  starts_at: string | null;
  expires_at: string | null;
}

/** API de servidor v2 do Adapty: GET /profile/ pelo customer_user_id (o id do utilizador na Birthdayly). */
export class AdaptyApi implements AdaptyClient {
  constructor(
    private readonly config: AdaptyConfig,
    private readonly http: typeof fetch = fetch,
  ) {}

  async accessUntil(customerUserId: string): Promise<Date | null> {
    const res = await this.http('https://api.adapty.io/api/v2/server-side-api/profile/', {
      headers: { authorization: `Api-Key ${this.config.secretKey}`, 'adapty-customer-user-id': customerUserId },
    });
    // Ainda não comprou nada (o perfil só existe depois de a app o identificar).
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`Adapty: perfil não disponível (${res.status})`);
    const body = (await res.json()) as { data?: { access_levels?: AccessLevel[] | null } };
    const level = body.data?.access_levels?.find((a) => a.access_level_id === this.config.accessLevel);
    if (!level) return null;
    // Ainda não começou (ex.: oferta futura): por agora não dá acesso.
    if (level.starts_at && new Date(level.starts_at) > new Date()) return null;
    return level.expires_at ? new Date(level.expires_at) : lifetime;
  }
}
