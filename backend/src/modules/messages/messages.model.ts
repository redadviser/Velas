import { z } from 'zod';

import { id } from '../../core/validation.js';

/** Mensagem de parabéns preparada para uma pessoa. */
export const messageSchema = z.object({
  id,
  person_id: id,
  body: z.string().min(1).max(1000),
  tone: z.string().max(40).default(''),
});
export type MessageInput = z.infer<typeof messageSchema>;

export interface MessageRow extends MessageInput {
  user_id: string;
  updated_at: Date;
}
