import { z } from 'zod';

import { emailSchema, passwordSchema, phoneSchema, usernameSchema } from '../../core/validation.js';
import type { Profile } from '../users/users.model.js';

/** Resposta de todas as rotas que iniciam sessão. */
export interface Session {
  access_token: string;
  refresh_token: string;
  /** Validade do access token, em segundos. */
  expires_in: number;
  user: Profile;
}

export const signupSchema = z.object({
  name: z.string().trim().min(1).max(80),
  username: usernameSchema,
  email: emailSchema,
  password: passwordSchema,
  phone: z.union([phoneSchema, z.literal('')]).optional(),
});
export type SignupInput = z.infer<typeof signupSchema>;

export const signupCheckSchema = z.object({ username: z.string().max(40), phone: z.string().max(20).nullish() });

export const loginSchema = z.object({
  /** Email ou username (com ou sem @). */
  identifier: z.string().trim().min(1).max(254),
  password: z.string().min(1).max(128),
});

export const googleSchema = z.object({ id_token: z.string().min(20).max(4096) });
export const refreshSchema = z.object({ refresh_token: z.string().min(20).max(200) });
export const logoutSchema = z.object({ refresh_token: z.string().max(200) });
export const forgotSchema = z.object({ email: emailSchema });
export const resetQuerySchema = z.object({ token: z.string().regex(/^[A-Za-z0-9_-]{20,100}$/) });
export const recoverSchema = z.object({ token: z.string().min(20).max(200) });
