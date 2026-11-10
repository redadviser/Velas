import { z } from 'zod';

import { id, timestampSchema } from '../../core/validation.js';

export const specialDateKinds = ['couple', 'wedding', 'family', 'memorial', 'other'] as const;

/** Data que se repete todos os anos (casamento, Dia da Mãe…), opcionalmente de uma pessoa. */
export const specialDateSchema = z.object({
  id,
  title: z.string().trim().min(1).max(120),
  kind: z.enum(specialDateKinds).default('other'),
  day: z.number().int().min(1).max(31),
  month: z.number().int().min(1).max(12),
  year: z.number().int().min(1900).max(2100).nullish(),
  person_id: id.nullish(),
  notes: z.string().max(2000).default(''),
  reminder_days: z.array(z.number().int().min(0).max(60)).max(10).nullish(),
  created_at: timestampSchema,
});
export type SpecialDateInput = z.infer<typeof specialDateSchema>;

export interface SpecialDateRow {
  id: string;
  user_id: string;
  title: string;
  kind: (typeof specialDateKinds)[number];
  day: number;
  month: number;
  year: number | null;
  person_id: string | null;
  notes: string;
  reminder_days: number[] | null;
  created_at: Date;
  updated_at: Date;
}
