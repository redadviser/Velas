import swagger from '@fastify/swagger';
import swaggerUi from '@fastify/swagger-ui';
import type { FastifyInstance, FastifySchema } from 'fastify';
import { z } from 'zod';

/**
 * Documentação OpenAPI + Swagger UI (em /docs).
 *
 * Os schemas das rotas servem só para documentar: quem valida é o Zod, dentro
 * de cada handler. Por isso o validador do Fastify é desligado e as rotas não
 * declaram schemas de resposta (que filtrariam os campos devolvidos).
 */
export async function registerDocs(app: FastifyInstance) {
  app.setValidatorCompiler(() => (value) => ({ value }));

  await app.register(swagger, {
    openapi: {
      openapi: '3.0.3',
      info: {
        title: 'API Velas',
        version: '1.0.0',
        description:
          'API da app Velas (aniversários).\n\n' +
          'As rotas com cadeado exigem sessão: faz login em **POST /auth/login** (ou /auth/signup), ' +
          'copia o `access_token` e cola-o em **Authorize**.\n\n' +
          'Os erros têm sempre o formato `{ "error": "<código>", "message": "<detalhe>" }`.',
      },
      components: {
        securitySchemes: { bearerAuth: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' } },
      },
      tags: [
        { name: 'Sistema' },
        { name: 'Autenticação', description: 'Registo, login e sessões (públicas)' },
        { name: 'Perfil', description: 'Conta do utilizador autenticado' },
        { name: 'Sincronização' },
        { name: 'Pessoas' },
        { name: 'Categorias' },
        { name: 'Ideias de presente' },
        { name: 'Mensagens' },
        { name: 'Prendas em grupo' },
        { name: 'Convites' },
        { name: 'Páginas', description: 'Páginas HTML e ficheiros abertos a partir de links' },
      ],
    },
  });

  await app.register(swaggerUi, {
    routePrefix: '/docs',
    uiConfig: { persistAuthorization: true, docExpansion: 'list', tryItOutEnabled: true },
  });
}

/** Marca as rotas do [scope] como protegidas por `Authorization: Bearer`. */
export function documentBearerAuth(scope: FastifyInstance) {
  scope.addHook('onRoute', (route) => {
    route.schema = { ...route.schema, security: [{ bearerAuth: [] }] };
  });
}

function jsonSchema(schema: z.ZodType) {
  const { $schema: _, ...rest } = z.toJSONSchema(schema, { io: 'input', target: 'openapi-3.0', unrepresentable: 'any' });
  return rest;
}

interface RouteDoc {
  tag: string;
  summary: string;
  description?: string;
  body?: z.ZodType;
  params?: z.ZodType;
  query?: z.ZodType;
}

/** Schema (só de documentação) de uma rota, a partir dos schemas Zod que a validam. */
export function doc(d: RouteDoc): FastifySchema {
  return {
    tags: [d.tag],
    summary: d.summary,
    ...(d.description && { description: d.description }),
    ...(d.body && { body: jsonSchema(d.body) }),
    ...(d.params && { params: jsonSchema(d.params) }),
    ...(d.query && { querystring: jsonSchema(d.query) }),
  };
}
