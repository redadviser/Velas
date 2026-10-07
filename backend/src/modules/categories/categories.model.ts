import { z } from 'zod';

import { id } from '../../core/validation.js';

export const categorySchema = z.object({
  id,
  name: z.string().trim().min(1).max(40),
  /** Índice da cor na paleta da app. */
  color: z.number().int().min(0).max(50),
  sort: z.number().int().min(0).max(10_000),
});
export type CategoryInput = z.infer<typeof categorySchema>;

export interface CategoryRow extends CategoryInput {
  user_id: string;
  created_at: Date;
}
