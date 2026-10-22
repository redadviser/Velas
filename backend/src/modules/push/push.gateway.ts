import { SignJWT, importPKCS8 } from 'jose';

export type PushPlatform = 'android' | 'ios';

/** Uma notificação. No Android vai só como dados (a app desenha-a, com "Responder"). */
export interface PushMessage {
  title: string;
  body: string;
  /** Lido pela app: `type` (chat, scheduled_sent, scheduled_failed) e o resto do contexto. */
  data: Record<string, string>;
  /** iOS: categoria (botões) e agrupamento por conversa. */
  category?: string;
  threadId?: string;
}

/** Quem entrega as notificações (Firebase Cloud Messaging; nos testes, uma falsa). */
export interface PushSender {
  /** `unregistered`: o token já não vale (app desinstalada) e deve ser apagado. */
  send(token: string, platform: PushPlatform, message: PushMessage): Promise<'ok' | 'unregistered'>;
}

/** Conta de serviço do Firebase (Definições do projeto → Contas de serviço → Gerar chave). */
export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

/** FIREBASE_SERVICE_ACCOUNT: o JSON da conta de serviço, tal como vem ou em base64. Sem ele, não há push. */
export function loadServiceAccount(env: NodeJS.ProcessEnv = process.env): ServiceAccount | undefined {
  const raw = env.FIREBASE_SERVICE_ACCOUNT?.trim();
  if (!raw) return undefined;
  const text = raw.startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8');
  let json: Partial<ServiceAccount>;
  try {
    json = JSON.parse(text) as Partial<ServiceAccount>;
  } catch {
    throw new Error('FIREBASE_SERVICE_ACCOUNT tem de ser o JSON da conta de serviço (ou esse JSON em base64).');
  }
  if (!json.project_id || !json.client_email || !json.private_key) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT incompleto: faltam project_id, client_email ou private_key.');
  }
  return { project_id: json.project_id, client_email: json.client_email, private_key: json.private_key };
}

/** Envio pela API HTTP v1 do FCM, com um access token OAuth da conta de serviço (renovado a cada hora). */
export class FcmSender implements PushSender {
  private token?: { value: string; expires: number };

  constructor(
    private readonly account: ServiceAccount,
    private readonly http: typeof fetch = fetch,
  ) {}

  private async accessToken(): Promise<string> {
    if (this.token && this.token.expires > Date.now() + 60_000) return this.token.value;
    const key = await importPKCS8(this.account.private_key, 'RS256');
    const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuer(this.account.client_email)
      .setAudience('https://oauth2.googleapis.com/token')
      .setIssuedAt()
      .setExpirationTime('1h')
      .sign(key);
    const res = await this.http('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    });
    if (!res.ok) throw new Error(`FCM: não foi possível obter o access token (${res.status})`);
    const json = (await res.json()) as { access_token: string; expires_in: number };
    this.token = { value: json.access_token, expires: Date.now() + json.expires_in * 1000 };
    return json.access_token;
  }

  async send(token: string, platform: PushPlatform, m: PushMessage): Promise<'ok' | 'unregistered'> {
    const message =
      platform === 'android'
        ? // Só dados e prioridade alta: a app mostra a notificação com "Responder" mesmo fechada.
          { token, data: { ...m.data, title: m.title, body: m.body }, android: { priority: 'HIGH' } }
        : {
            token,
            notification: { title: m.title, body: m.body },
            data: m.data,
            apns: {
              payload: {
                aps: { sound: 'default', ...(m.category ? { category: m.category } : {}), ...(m.threadId ? { 'thread-id': m.threadId } : {}) },
              },
            },
          };
    const res = await this.http(`https://fcm.googleapis.com/v1/projects/${this.account.project_id}/messages:send`, {
      method: 'POST',
      headers: { authorization: `Bearer ${await this.accessToken()}`, 'content-type': 'application/json' },
      body: JSON.stringify({ message }),
    });
    if (res.ok) return 'ok';
    const error = ((await res.json().catch(() => ({}))) as { error?: { status?: string; details?: { errorCode?: string }[] } }).error;
    const code = error?.details?.find((d) => d.errorCode)?.errorCode ?? error?.status;
    // INVALID_ARGUMENT pode ser da mensagem, não do token: aí não se apaga nada.
    if (res.status === 404 || code === 'UNREGISTERED') return 'unregistered';
    throw new Error(`FCM: envio falhou (${res.status} ${code ?? ''})`);
  }
}
