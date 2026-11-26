import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from 'jose';

import { HttpError } from '../../core/errors.js';

export interface AppleIdentity {
  sub: string;
  /** Pode faltar (a Apple só garante o email no primeiro login) ou ser um endereço de reencaminhamento. */
  email: string | null;
  emailVerified: boolean;
}

export interface AppleAuth {
  verify(identityToken: string): Promise<AppleIdentity>;
  /** Troca o authorization code pelo refresh token, guardado para o revogar ao apagar a conta. Null sem chave configurada. */
  refreshToken(authorizationCode: string): Promise<string | null>;
  revoke(refreshToken: string): Promise<void>;
}

export interface AppleConfig {
  /** Bundle ID da app iOS (audiência do identity token e client_id na API da Apple). */
  clientId: string;
  /** Chave "Sign in with Apple" (.p8) para o client secret; sem ela não há troca nem revogação de tokens. */
  teamId?: string;
  keyId?: string;
  privateKey?: string;
}

const issuer = 'https://appleid.apple.com';

/**
 * Entrar com a Apple: valida o identity token (chaves públicas da Apple,
 * emissor, validade e audiência = bundle ID) e fala com a API REST da Apple
 * para obter e revogar o refresh token (obrigatório ao apagar a conta).
 */
export function appleAuth(config: AppleConfig, http: typeof fetch = fetch): AppleAuth {
  const jwks = createRemoteJWKSet(new URL(`${issuer}/auth/keys`));
  const canCallApi = Boolean(config.teamId && config.keyId && config.privateKey);

  async function clientSecret(): Promise<string> {
    const key = await importPKCS8(config.privateKey!.replace(/\\n/g, '\n'), 'ES256');
    return new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: config.keyId! })
      .setIssuer(config.teamId!)
      .setSubject(config.clientId)
      .setAudience(issuer)
      .setIssuedAt()
      .setExpirationTime('5m')
      .sign(key);
  }

  async function post(path: string, params: Record<string, string>): Promise<Response> {
    const body = new URLSearchParams({ client_id: config.clientId, client_secret: await clientSecret(), ...params });
    return http(`${issuer}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body,
    });
  }

  return {
    async verify(identityToken) {
      try {
        const { payload } = await jwtVerify(identityToken, jwks, { issuer, audience: config.clientId });
        if (!payload.sub) throw new Error('missing sub');
        return {
          sub: payload.sub,
          email: typeof payload.email === 'string' ? payload.email : null,
          emailVerified: payload.email_verified === true || payload.email_verified === 'true',
        };
      } catch {
        throw new HttpError(401, 'invalid_apple_token');
      }
    },
    async refreshToken(authorizationCode) {
      if (!canCallApi) return null;
      const res = await post('/auth/token', { code: authorizationCode, grant_type: 'authorization_code' });
      if (!res.ok) throw new HttpError(401, 'invalid_apple_token');
      const data = (await res.json()) as { refresh_token?: string };
      return data.refresh_token ?? null;
    },
    async revoke(refreshToken) {
      if (!canCallApi) return;
      const res = await post('/auth/revoke', { token: refreshToken, token_type_hint: 'refresh_token' });
      if (!res.ok) throw new Error(`Apple revoke falhou: ${res.status}`);
    },
  };
}
