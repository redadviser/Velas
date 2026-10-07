import type { FastifyInstance } from 'fastify';

import type { AccessTokens } from '../modules/auth/tokens.js';
import { unauthorized } from './errors.js';

declare module 'fastify' {
  interface FastifyRequest {
    /** Utilizador autenticado (só nas rotas protegidas). */
    uid: string;
  }
}

/** Exige `Authorization: Bearer <access token>` em todas as rotas do [scope]. */
export function requireAuth(scope: FastifyInstance, tokens: AccessTokens) {
  scope.decorateRequest('uid', '');
  scope.addHook('onRequest', async (req) => {
    const header = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7) : null;
    const uid = token ? await tokens.verify(token) : null;
    if (!uid) throw unauthorized();
    req.uid = uid;
  });
}

/** Limites por IP (ver @fastify/rate-limit). */
export const rateLimits = {
  /** Rotas que aceitam palavras-passe ou enviam emails. */
  strict: { rateLimit: { max: 10, timeWindow: '1 minute' } },
  relaxed: { rateLimit: { max: 60, timeWindow: '1 minute' } },
  /** Procura de contas (evita enumerar utilizadores). */
  lookup: { rateLimit: { max: 30, timeWindow: '1 minute' } },
};
