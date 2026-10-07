import { z } from 'zod';

import { id, moneySchema, timestampSchema } from '../../core/validation.js';

/** Ideia de presente para uma pessoa. */
export const giftSchema = z.object({
  id,
  person_id: id,
  title: z.string().trim().min(1).max(200),
  price: moneySchema,
  link: z.string().max(2000).default(''),
  notes: z.string().max(2000).default(''),
  purchased: z.boolean().default(false),
  created_at: timestampSchema,
});
export type GiftInput = z.infer<typeof giftSchema>;

export interface GiftRow {
  id: string;
  user_id: string;
  person_id: string;
  title: string;
  price: number | null;
  link: string;
  notes: string;
  purchased: boolean;
  created_at: Date;
  updated_at: Date;
}
