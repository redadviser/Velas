import type { FastifyInstance } from 'fastify';

import { idParams } from '../../core/validation.js';
import {
  confirmedSchema,
  groupSchema,
  memberInfoSchema,
  paidSchema,
  purchasedSchema,
  saveGroupSchema,
} from './groups.model.js';
import type { GroupsService } from './groups.service.js';

export async function groupsRoutes(app: FastifyInstance, groups: GroupsService) {
  app.get('/groups', (req) => groups.list(req.uid));

  app.put('/groups/:id', (req) => {
    const { id } = idParams.parse(req.params);
    const body = saveGroupSchema.parse(req.body);
    return groups.save(req.uid, groupSchema.parse({ ...(body.group as object), id }), body.new_members);
  });

  app.delete('/groups/:id', async (req, reply) => {
    await groups.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.post('/groups/:id/purchased', async (req, reply) => {
    const { id } = idParams.parse(req.params);
    await groups.setPurchased(req.uid, id, purchasedSchema.parse(req.body).purchased);
    return reply.status(204).send();
  });

  app.get('/groups/:id/payee', (req) => groups.payee(req.uid, idParams.parse(req.params).id));

  app.patch('/group-members/:id', async (req, reply) => {
    const { id } = idParams.parse(req.params);
    await groups.updateMember(req.uid, id, memberInfoSchema.parse(req.body));
    return reply.status(204).send();
  });

  app.post('/group-members/:id/paid', async (req, reply) => {
    const { id } = idParams.parse(req.params);
    await groups.setPaid(req.uid, id, paidSchema.parse(req.body).method);
    return reply.status(204).send();
  });

  app.post('/group-members/:id/confirmed', async (req, reply) => {
    const { id } = idParams.parse(req.params);
    await groups.setConfirmed(req.uid, id, confirmedSchema.parse(req.body).confirmed);
    return reply.status(204).send();
  });

  app.delete('/group-members/:id', async (req, reply) => {
    await groups.removeMember(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
