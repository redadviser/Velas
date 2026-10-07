import type { FastifyInstance } from 'fastify';

import { doc } from '../../core/openapi.js';
import type { SyncService } from './sync.service.js';

export async function syncRoutes(app: FastifyInstance, sync: SyncService) {
  app.get(
    '/data',
    { schema: doc({ tag: 'Sincronização', summary: 'Todos os dados do utilizador (categorias, pessoas, presentes, mensagens)' }) },
    (req) => sync.snapshot(req.uid),
  );
}
