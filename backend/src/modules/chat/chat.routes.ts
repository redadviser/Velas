import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { HttpError } from '../../core/errors.js';
import { doc } from '../../core/openapi.js';
import { PhotoStorage } from '../../core/storage.js';
import { idParams } from '../../core/validation.js';
import { directSchema, messagesQuery, reactionSchema, saveStickerSchema, sendSchema } from './chat.model.js';
import type { ChatService } from './chat.service.js';
import type { StickersService } from './stickers.service.js';

const imageTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
const binaryBody = { consumes: imageTypes, body: { type: 'string', format: 'binary' } };
const sizeQuery = z.object({
  width: z.coerce.number().int().min(1).max(10_000).optional(),
  height: z.coerce.number().int().min(1).max(10_000).optional(),
});

function bytes(body: unknown): Buffer {
  if (!Buffer.isBuffer(body)) throw new HttpError(415, 'unsupported_media_type');
  return body;
}

export async function chatRoutes(app: FastifyInstance, chat: ChatService, stickers: StickersService) {
  const tag = 'Conversas';

  app.get('/conversations', { schema: doc({ tag, summary: 'Conversas (grupos e privadas), com não lidas' }) }, (req) =>
    chat.list(req.uid),
  );

  app.get('/conversations/:id', { schema: doc({ tag, summary: 'Uma conversa e quem participa', params: idParams }) }, (req) =>
    chat.get(req.uid, idParams.parse(req.params).id),
  );

  app.post(
    '/conversations/direct',
    { schema: doc({ tag, summary: 'Abrir a conversa privada com um amigo', body: directSchema }) },
    (req) => chat.openDirect(req.uid, directSchema.parse(req.body).user_id),
  );

  app.post('/conversations/:id/read', { schema: doc({ tag, summary: 'Marcar como lida', params: idParams }) }, async (req, reply) => {
    await chat.markRead(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.get(
    '/conversations/:id/messages',
    { schema: doc({ tag, summary: 'Mensagens (mais recentes primeiro)', params: idParams, query: messagesQuery }) },
    (req) => {
      const { before, limit } = messagesQuery.parse(req.query);
      return chat.messages(req.uid, idParams.parse(req.params).id, before, limit);
    },
  );

  app.post(
    '/conversations/:id/messages',
    { schema: doc({ tag, summary: 'Enviar uma mensagem', params: idParams, body: sendSchema }) },
    (req) => chat.send(req.uid, idParams.parse(req.params).id, sendSchema.parse(req.body)),
  );

  app.post(
    '/conversations/:id/uploads',
    {
      bodyLimit: PhotoStorage.chatMaxBytes,
      schema: { ...doc({ tag, summary: 'Enviar uma imagem (bytes no corpo) para depois a usar numa mensagem', params: idParams }), ...binaryBody },
    },
    (req) => chat.upload(req.uid, idParams.parse(req.params).id, bytes(req.body)),
  );

  app.delete('/chat-messages/:id', { schema: doc({ tag, summary: 'Apagar uma mensagem minha', params: idParams }) }, async (req, reply) => {
    await chat.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });

  app.put(
    '/chat-messages/:id/reaction',
    { schema: doc({ tag, summary: 'Reagir com um emoji (null retira)', params: idParams, body: reactionSchema }) },
    (req) => chat.react(req.uid, idParams.parse(req.params).id, reactionSchema.parse(req.body).emoji),
  );

  // Stickers ----------------------------------------------------------------

  app.get('/stickers', { schema: doc({ tag, summary: 'Os meus stickers' }) }, (req) => stickers.list(req.uid));

  app.post(
    '/stickers',
    { schema: doc({ tag, summary: 'Guardar um sticker (de uma mensagem ou do GIPHY)', body: saveStickerSchema }) },
    (req) => stickers.save(req.uid, saveStickerSchema.parse(req.body)),
  );

  app.post(
    '/stickers/upload',
    {
      bodyLimit: PhotoStorage.chatMaxBytes,
      schema: { ...doc({ tag, summary: 'Criar um sticker a partir de uma imagem (bytes no corpo)', query: sizeQuery }), ...binaryBody },
    },
    (req) => {
      const { width, height } = sizeQuery.parse(req.query);
      return stickers.upload(req.uid, bytes(req.body), width ?? null, height ?? null);
    },
  );

  app.delete('/stickers/:id', { schema: doc({ tag, summary: 'Apagar um sticker', params: idParams }) }, async (req, reply) => {
    await stickers.remove(req.uid, idParams.parse(req.params).id);
    return reply.status(204).send();
  });
}
