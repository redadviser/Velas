import { z } from 'zod';

import { paymentSchema, phoneSchema, usernameSchema } from '../../core/validation.js';

/** Perfil no formato que a app lê (UserProfile.fromJson). */
export interface Profile {
  id: string;
  email: string;
  display_name: string;
  username: string | null;
  phone: string | null;
  notifications_enabled: boolean;
  reminder_hour: number;
  reminder_minute: number;
  default_reminder_days: number[];
  payment_methods: Record<string, unknown>;
  has_password: boolean;
  google_linked: boolean;
}

/** Dados para criar uma conta (registo ou primeira entrada com Google). */
export interface NewUser {
  email: string;
  passwordHash: string | null;
  googleSub?: string;
  emailVerified?: boolean;
  name: string;
  username: string | null;
  phone?: string | null;
}

/** Categorias criadas em todas as contas novas. */
export const defaultCategories = [
  { name: 'Família', color: 0, sort: 0 },
  { name: 'Amigos', color: 1, sort: 1 },
  { name: 'Trabalho', color: 4, sort: 2 },
] as const;

export const profilePatchSchema = z
  .object({
    display_name: z.string().trim().min(1).max(80),
    username: usernameSchema.nullable(),
    phone: phoneSchema.nullable(),
    notifications_enabled: z.boolean(),
    reminder_hour: z.number().int().min(0).max(23),
    reminder_minute: z.number().int().min(0).max(59),
    default_reminder_days: z.array(z.number().int().min(0).max(60)).max(10),
    payment_methods: paymentSchema,
  })
  .partial();

export type ProfilePatch = z.infer<typeof profilePatchSchema>;

/** Colunas de `profiles` que o próprio utilizador pode alterar. */
export const profileColumns = Object.keys(profilePatchSchema.shape) as (keyof ProfilePatch)[];
