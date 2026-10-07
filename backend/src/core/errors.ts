import type { FastifyError, FastifyReply, FastifyRequest } from 'fastify';
import { ZodError } from 'zod';

/**
 * Erro com um código estável que a app traduz para português
 * (ver ui/lib/core/utils/errors.dart).
 */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message?: string,
  ) {
    super(message ?? code);
  }
}

export const notFound = () => new HttpError(404, 'not_found');
export const unauthorized = (code = 'unauthorized') => new HttpError(401, code);

const uniqueCodes: Record<string, string> = {
  users_email_key: 'email_taken',
  profiles_username_key: 'username_taken',
  profiles_phone_key: 'phone_taken',
};

interface PgError {
  code?: string;
  constraint?: string;
  message: string;
}

function isPgError(e: unknown): e is PgError {
  return typeof e === 'object' && e !== null && typeof (e as PgError).code === 'string' && /^[0-9A-Z]{5}$/.test((e as PgError).code!);
}

/** Converte erros do Postgres (incluindo os `raise exception` das funções). */
function fromPg(e: PgError): HttpError | null {
  switch (e.code) {
    case '42501':
      return new HttpError(403, 'forbidden', e.message);
    case 'P0002': // invalid_code, invitation_not_found
      return new HttpError(404, e.message);
    case 'P0001': // group_closed
      return new HttpError(409, e.message);
    case '23505':
      return new HttpError(409, uniqueCodes[e.constraint ?? ''] ?? 'conflict');
    case '23514':
    case '22001':
    case '22003':
      return new HttpError(422, 'invalid_value', e.message);
    case '23503':
      return new HttpError(422, 'invalid_reference');
    case '22P02':
      return new HttpError(400, 'bad_request');
    default:
      return null;
  }
}

export function errorHandler(error: FastifyError | Error, req: FastifyRequest, reply: FastifyReply) {
  // Erros do próprio Fastify (JSON inválido, corpo grande demais, limite de pedidos).
  const status = (error as FastifyError).statusCode;
  let http: HttpError | null = null;
  if (error instanceof HttpError) http = error;
  else if (error instanceof ZodError) {
    http = new HttpError(400, 'validation_error', error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; '));
  } else if (typeof status === 'number' && status < 500) {
    http = new HttpError(status, status === 429 ? 'rate_limited' : status === 413 ? 'too_large' : 'bad_request', error.message);
  } else if (isPgError(error)) http = fromPg(error);

  if (!http) {
    req.log.error(error);
    return reply.status(500).send({ error: 'internal_error', message: 'Erro interno.' });
  }
  return reply.status(http.status).send({ error: http.code, message: http.message });
}
