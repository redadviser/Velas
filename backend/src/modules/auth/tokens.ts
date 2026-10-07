import { createHash, randomBytes } from 'node:crypto';

import { SignJWT, jwtVerify } from 'jose';

const audience = 'velas-app';

/** Access tokens JWT curtos (HS256). A sessão renova-se com o refresh token. */
export class AccessTokens {
  private readonly key: Uint8Array;

  constructor(secret: string) {
    this.key = new TextEncoder().encode(secret);
  }

  static readonly ttlSeconds = 15 * 60;

  sign(userId: string): Promise<string> {
    return new SignJWT({})
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(userId)
      .setAudience(audience)
      .setIssuedAt()
      .setExpirationTime(`${AccessTokens.ttlSeconds}s`)
      .sign(this.key);
  }

  /** Devolve o id do utilizador, ou null se o token for inválido ou tiver expirado. */
  async verify(token: string): Promise<string | null> {
    try {
      const { payload } = await jwtVerify(token, this.key, { algorithms: ['HS256'], audience });
      return payload.sub ?? null;
    } catch {
      return null;
    }
  }
}

export const refreshTtlDays = 60;
export const resetTtlMinutes = 60;

/** Token opaco aleatório (refresh, recuperação). Na base de dados guarda-se só o hash. */
export const randomToken = () => randomBytes(32).toString('base64url');
export const hashToken = (token: string) => createHash('sha256').update(token).digest('hex');
