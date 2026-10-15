import { z } from 'zod';

import { id } from '../../core/validation.js';
import { giphyUrl } from '../gifs/gifs.service.js';

const dimension = z.number().int().min(1).max(10_000).nullish();
const giphy = z.string().max(500).regex(giphyUrl);

export const directSchema = z.object({ user_id: id });

export const messagesQuery = z.object({
  /** Mensagens anteriores a esta (paginação para trás). */
  before: id.optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

/**
 * Nova mensagem. O id vem da app, para reenviar sem duplicar.
 * - text: `body`
 * - image: `media_key` devolvido por POST /conversations/:id/uploads (+ `body` opcional como legenda)
 * - gif: `media_url` do GIPHY (GET /gifs)
 * - sticker: `sticker_id` de um sticker guardado, ou `media_url` de um sticker do GIPHY
 */
export const sendSchema = z.object({
  id,
  kind: z.enum(['text', 'image', 'gif', 'sticker']),
  body: z.string().max(4000).default(''),
  media_key: z.string().max(200).nullish(),
  media_url: giphy.nullish(),
  sticker_id: id.nullish(),
  width: dimension,
  height: dimension,
  reply_to: id.nullish(),
});
export type SendInput = z.infer<typeof sendSchema>;

/** Uma reação por pessoa; null retira a reação. */
export const reactionSchema = z.object({ emoji: z.string().trim().min(1).max(16).nullable() });

export const saveStickerSchema = z.union([
  z.object({ message_id: id }),
  z.object({ media_url: giphy, width: dimension, height: dimension }),
]);
export type SaveStickerInput = z.infer<typeof saveStickerSchema>;

export interface Reaction {
  emoji: string;
  user_id: string;
}

/** Mensagem no formato de ChatMessage.fromJson (app). */
export interface MessageJson {
  id: string;
  conversation_id: string;
  sender_id: string | null;
  sender_name: string | null;
  sender_photo_url: string | null;
  kind: 'text' | 'image' | 'gif' | 'sticker';
  body: string;
  /** URL assinado (imagens da API) ou do GIPHY. */
  media_url: string | null;
  width: number | null;
  height: number | null;
  reply: { id: string; sender_name: string | null; kind: string; body: string; deleted: boolean } | null;
  reactions: Reaction[];
  created_at: string;
  deleted: boolean;
}

export interface ConversationJson {
  id: string;
  kind: 'group' | 'direct';
  group_id: string | null;
  /** Título do grupo ou nome da outra pessoa. */
  title: string;
  celebrant_name: string | null;
  other_user: (Presence & { user_id: string; display_name: string; username: string | null; photo_url: string | null }) | null;
  last_message: Pick<MessageJson, 'id' | 'sender_id' | 'sender_name' | 'kind' | 'body' | 'created_at' | 'deleted'> | null;
  last_message_at: string | null;
  unread_count: number;
  /** Quem (além de mim) já viu a última mensagem. */
  seen_by: { user_id: string; display_name: string }[];
  created_at: string;
}

/** Online agora, ou quando foi visto por último. */
export interface Presence {
  online: boolean;
  last_seen_at: string | null;
}

export interface Participant extends Presence {
  user_id: string;
  display_name: string;
  username: string | null;
  photo_url: string | null;
  last_read_at: string | null;
}

export interface StickerJson {
  id: string;
  url: string;
  width: number | null;
  height: number | null;
  created_at: string;
}
