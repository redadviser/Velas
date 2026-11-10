import type { FastifyInstance } from 'fastify';

import { doc } from '../../core/openapi.js';
import { idParams } from '../../core/validation.js';
import { guestSchema, joinPartySchema, partySchema, rsvpSchema, taskParams, taskSchema } from './parties.model.js';
import type { PartiesService } from './parties.service.js';

export async function partiesRoutes(app: FastifyInstance, parties: PartiesService) {
  const tag = 'Festas surpresa';

  app.get('/parties', { schema: doc({ tag, summary: 'Festas que criei ou para as quais fui convidado' }) }, (req) =>
    parties.list(req.uid),
  );

  app.put(
    '/parties/:id',
    { schema: doc({ tag, summary: 'Criar ou atualizar uma festa (só quem a criou)', params: idParams, body: partySchema.omit({ id: true }) }) },
    (req) => {
      const { id } = idParams.parse(req.params);
      return parties.save(req.uid, partySchema.parse({ ...(req.body as object), id }));
    },
  );

  app.delete('/parties/:id', { schema: doc({ tag, summary: 'Apagar uma festa', params: idParams }) }, async (req, reply) => {
    await parties.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.post('/parties/join', { schema: doc({ tag, summary: 'Entrar com o código de convite', body: joinPartySchema }) }, (req) =>
    parties.join(req.uid, joinPartySchema.parse(req.body).code),
  );

  app.put(
    '/parties/:id/rsvp',
    { schema: doc({ tag, summary: 'Responder se vou', params: idParams, body: rsvpSchema }) },
    (req) => parties.rsvp(req.uid, idParams.parse(req.params).id, rsvpSchema.parse(req.body).rsvp),
  );

  app.post(
    '/parties/:id/guests',
    { schema: doc({ tag, summary: 'Acrescentar um convidado sem conta', params: idParams, body: guestSchema }) },
    (req) => {
      const g = guestSchema.parse(req.body);
      return parties.addGuest(req.uid, idParams.parse(req.params).id, g.name, g.id);
    },
  );

  app.delete('/party-guests/:id', { schema: doc({ tag, summary: 'Tirar um convidado ou sair da festa', params: idParams }) }, async (req, reply) => {
    await parties.removeGuest(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.put(
    '/parties/:id/tasks/:taskId',
    { schema: doc({ tag, summary: 'Criar ou atualizar uma tarefa', params: taskParams, body: taskSchema }) },
    (req) => {
      const { id, taskId } = taskParams.parse(req.params);
      return parties.saveTask(req.uid, id, taskId, taskSchema.parse(req.body));
    },
  );

  app.delete('/parties/:id/tasks/:taskId', { schema: doc({ tag, summary: 'Apagar uma tarefa', params: taskParams }) }, async (req, reply) => {
    const { id, taskId } = taskParams.parse(req.params);
    await parties.removeTask(req.uid, id, taskId);
    return reply.status(204).send();
  });
}
