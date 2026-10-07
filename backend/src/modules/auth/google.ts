import { createRemoteJWKSet, jwtVerify } from 'jose';

import { HttpError } from '../../core/errors.js';

export interface GoogleIdentity {
  sub: string;
  email: string;
  emailVerified: boolean;
  name: string;
}

export type GoogleVerifier = (idToken: string) => Promise<GoogleIdentity>;

/**
 * Valida o ID token devolvido pelo Google Sign-In na app: assinatura (chaves
 * públicas do Google), emissor, validade e audiência (um dos client IDs do
 * projeto: iOS, Android ou Web).
 */
export function googleVerifier(clientIds: string[]): GoogleVerifier {
  const jwks = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));
  return async (idToken) => {
    if (clientIds.length === 0) throw new HttpError(503, 'google_not_configured');
    try {
      const { payload } = await jwtVerify(idToken, jwks, {
        issuer: ['https://accounts.google.com', 'accounts.google.com'],
        audience: clientIds,
      });
      if (!payload.sub || typeof payload.email !== 'string') throw new Error('missing claims');
      return {
        sub: payload.sub,
        email: payload.email,
        emailVerified: payload.email_verified === true || payload.email_verified === 'true',
        name: typeof payload.name === 'string' ? payload.name : '',
      };
    } catch {
      throw new HttpError(401, 'invalid_google_token');
    }
  };
}
