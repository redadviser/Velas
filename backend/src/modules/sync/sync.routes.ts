import type { FastifyInstance } from 'fastify';

import type { SyncService } from './sync.service.js';

export async function syncRoutes(app: FastifyInstance, sync: SyncService) {
  app.get('/data', (req) => sync.snapshot(req.uid));
}
