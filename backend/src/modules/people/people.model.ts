import { z } from 'zod';

import { id, moneySchema, timestampSchema } from '../../core/validation.js';

export const personSchema = z.object({
  id,
  name: z.string().trim().min(1).max(120),
  birth_day: z.number().int().min(1).max(31),
  birth_month: z.number().int().min(1).max(12),
  birth_year: z.number().int().min(1900).max(2100).nullish(),
  relation: z.string().max(80).default(''),
  category_id: id.nullish(),
  notes: z.string().max(2000).default(''),
  gift_budget: moneySchema,
  reminder_days: z.array(z.number().int().min(0).max(60)).max(10).nullish(),
  created_at: timestampSchema,
});
export type PersonInput = z.infer<typeof personSchema>;

/** Importação de contactos: até 2000 pessoas por pedido. */
export const importSchema = z.object({ people: z.array(personSchema).min(1).max(2000) });

export interface PersonRow {
  id: string;
  user_id: string;
  name: string;
  birth_day: number;
  birth_month: number;
  birth_year: number | null;
  relation: string;
  category_id: string | null;
  photo_path: string | null;
  notes: string;
  gift_budget: number | null;
  reminder_days: number[] | null;
  created_at: Date;
  updated_at: Date;
}

/** Pessoa como a app a lê: com o URL assinado da fotografia. */
export type PersonJson = PersonRow & { photo_url: string | null };

export interface PhotoJson {
  photo_path: string;
  photo_url: string;
}
