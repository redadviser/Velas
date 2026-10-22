import { z } from 'zod';

import { id } from '../../core/validation.js';

/** Cartão de parabéns criado a partir da mensagem preparada para uma pessoa. */
export const createCardSchema = z.object({
  id,
  person_id: id,
  /** Como quem envia trata a pessoa ("Ana", "Mãe"): aparece no cartão. */
  recipient_name: z.string().trim().min(1).max(120),
  body: z.string().trim().min(1).max(1000),
  /** Um amigo: o cartão vai diretamente para o mural dele, sem link. */
  recipient_id: id.optional(),
  /** Cartão especial (Birthdayly+): o media_key devolvido por POST /cards/media. */
  media_key: z.string().max(120).optional(),
});
export type CreateCardInput = z.infer<typeof createCardSchema>;

/** O token do link (/c/TOKEN): 16 bytes aleatórios em base64url. */
export const tokenParams = z.object({ token: z.string().regex(/^[A-Za-z0-9_-]{22}$/) });
export const sentQuery = z.object({ person_id: id.optional() });

/** O que quem enviou vê do cartão (com o estado: aberto, guardado na app). */
export interface SentCard {
  id: string;
  token: string;
  person_id: string | null;
  recipient_name: string;
  body: string;
  /** link: partilhado por link; wall: publicado no mural de um amigo. */
  via: 'link' | 'wall';
  created_at: string;
  opened_at: string | null;
  claimed_at: string | null;
  /** Cartão especial: fotografia, vídeo ou áudio (URL assinado). */
  media_kind: 'image' | 'video' | 'audio' | null;
  media_url: string | null;
}

/** Cartão no mural de quem o recebeu. */
export interface ReceivedCard {
  id: string;
  body: string;
  via: 'link' | 'wall';
  created_at: string;
  /** Quando chegou ao mural (guardado a partir do link ou publicado lá). */
  received_at: string;
  /** Já foi visto por quem o recebeu (os novos aparecem em destaque na app). */
  seen: boolean;
  media_kind: 'image' | 'video' | 'audio' | null;
  media_url: string | null;
  sender: { user_id: string; display_name: string; username: string | null; photo_url: string | null };
}

/** O que se vê do cartão com o link (público). */
export interface CardPreview {
  token: string;
  sender_id: string;
  sender_name: string;
  sender_photo_url: string | null;
  recipient_name: string;
  body: string;
  created_at: string;
  media_kind: 'image' | 'video' | 'audio' | null;
  media_url: string | null;
  claimed: boolean;
}

export interface ClaimResult {
  sender_id: string;
  /** Conversa privada com quem enviou, já com a mensagem do cartão. */
  conversation_id: string;
}

export const wallPhotoQuery = z.object({
  year: z.coerce.number().int().min(1900).max(2100),
  caption: z.string().max(200).default(''),
});

/** Fotografia no mural do próprio (Birthdayly+), num álbum por ano. */
export interface WallPhoto {
  id: string;
  year: number;
  caption: string;
  url: string;
  created_at: string;
}
