import { z } from 'zod';

import { id, moneySchema, timestampSchema } from '../../core/validation.js';

/** Chaves de gostos (a app traduz e liga-as às sugestões de prendas). */
export const interestsSchema = z.array(z.string().regex(/^[a-z][a-z_]{1,30}$/)).max(30);

/** Algo que o utilizador gostava de receber. */
export const wishSchema = z.object({
  id,
  title: z.string().trim().min(1).max(200),
  price: moneySchema,
  link: z.string().max(2000).default(''),
  notes: z.string().max(2000).default(''),
  created_at: timestampSchema,
});
export type WishInput = z.infer<typeof wishSchema>;

export interface WishRow {
  id: string;
  title: string;
  price: number | null;
  link: string;
  notes: string;
  created_at: Date;
}

/** O que um amigo vê: os gostos e a lista de desejos. */
export interface FriendWishlist {
  interests: string[];
  items: WishRow[];
}
