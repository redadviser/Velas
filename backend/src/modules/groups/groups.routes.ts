import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import {
  confirmedSchema,
  groupSchema,
  memberInfoSchema,
  newMemberSchema,
  paidSchema,
  purchasedSchema,
  saveGroupSchema,
} from './groups.model.js';
import type { GroupsService } from './groups.service.js';

/** Corpo de PUT /groups/:id como a documentação o mostra (o grupo é validado à parte, com o id do URL). */
const saveGroupDoc = z.object({
  group: groupSchema.omit({ id: true }),
  new_members: z.array(newMemberSchema).max(100).default([]),
});

export async function groupsRoutes(app: FastifyInstance, groups: GroupsService) {
  const tag = 'Prendas em grupo';

  app.get('/groups', { schema: doc({ tag, summary: 'Grupos em que participo, com membros e convites' }) }, (req) =>
    groups.list(req.uid),
  );

  app.put(
    '/groups/:id',
    { schema: doc({ tag, summary: 'Criar ou atualizar um grupo (só o administrador)', params: idParams, body: saveGroupDoc }) },
    (req) => {
      const { id } = idParams.parse(req.params);
      const body = saveGroupSchema.parse(req.body);
      return groups.save(req.uid, groupSchema.parse({ ...(body.group as object), id }), body.new_members);
    },
  );

  app.delete('/groups/:id', { schema: doc({ tag, summary: 'Apagar um grupo', params: idParams }) }, async (req, reply) => {
    await groups.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.post(
    '/groups/:id/purchased',
    { schema: doc({ tag, summary: 'Marcar a prenda como comprada', params: idParams, body: purchasedSchema }) },
    async (req, reply) => {
      const { id } = idParams.parse(req.params);
      await groups.setPurchased(req.uid, id, purchasedSchema.parse(req.body).purchased);
      return reply.status(204).send();
    },
  );

  app.get('/groups/:id/payee', { schema: doc({ tag, summary: 'A quem pagar (dados de pagamento do comprador)', params: idParams }) }, (req) =>
    groups.payee(req.uid, idParams.parse(req.params).id),
  );

  app.patch(
    '/group-members/:id',
    { schema: doc({ tag, summary: 'Alterar um participante', params: idParams, body: memberInfoSchema }) },
    async (req, reply) => {
      const { id } = idParams.parse(req.params);
      await groups.updateMember(req.uid, id, memberInfoSchema.parse(req.body));
      return reply.status(204).send();
    },
  );

  app.post(
    '/group-members/:id/paid',
    { schema: doc({ tag, summary: 'Marcar como pago (method null = por pagar)', params: idParams, body: paidSchema }) },
    async (req, reply) => {
      const { id } = idParams.parse(req.params);
      await groups.setPaid(req.uid, id, paidSchema.parse(req.body).method);
      return reply.status(204).send();
    },
  );

  app.post(
    '/group-members/:id/confirmed',
    { schema: doc({ tag, summary: 'Confirmar a receção do pagamento', params: idParams, body: confirmedSchema }) },
    async (req, reply) => {
      const { id } = idParams.parse(req.params);
      await groups.setConfirmed(req.uid, id, confirmedSchema.parse(req.body).confirmed);
      return reply.status(204).send();
    },
  );

  app.delete('/group-members/:id', { schema: doc({ tag, summary: 'Remover um participante', params: idParams }) }, async (req, reply) => {
    await groups.removeMember(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
