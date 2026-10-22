import { z } from 'zod';

import { id } from '../../core/validation.js';

/** Mensagem de parabéns preparada para uma pessoa. */
export const messageSchema = z.object({
  id,
  person_id: id,
  body: z.string().min(1).max(1000),
  tone: z.string().max(40).default(''),
  /**
   * Agendar o envio (sem estes campos, ou a null, não está agendada):
   * `wall` publica no mural do amigo à hora marcada; `remind` avisa no
   * telemóvel para a enviar fora da app.
   */
  scheduled_at: z.iso.datetime({ offset: true }).nullish(),
  schedule_via: z.enum(['wall', 'remind']).nullish(),
  schedule_friend_id: id.nullish(),
  /** Cartão especial (Birthdayly+): o media_key devolvido por POST /cards/media. */
  schedule_media_key: z.string().max(120).nullish(),
});
export type MessageInput = z.infer<typeof messageSchema>;

export interface MessageRow {
  id: string;
  person_id: string;
  body: string;
  tone: string;
  user_id: string;
  updated_at: Date;
  scheduled_at: Date | null;
  schedule_via: 'wall' | 'remind' | null;
  schedule_friend_id: string | null;
  schedule_media_key: string | null;
  sent_at: Date | null;
  send_error: string | null;
}
