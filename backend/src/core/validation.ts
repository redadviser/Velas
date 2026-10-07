import { z } from 'zod';

// Validações partilhadas pelos módulos.

export const id = z.guid();
export const idParams = z.object({ id });

export const usernameSchema = z
  .string()
  .trim()
  .transform((s) => s.replace(/^@/, '').toLowerCase())
  .pipe(z.string().regex(/^[a-z0-9._]{3,20}$/).refine((s) => !/^[._]|[._]$/.test(s), 'invalid username'));

export const phoneSchema = z.string().regex(/^\+[1-9][0-9]{7,14}$/);
export const emailSchema = z.string().trim().toLowerCase().pipe(z.email().max(254));
export const passwordSchema = z.string().min(8).max(128);
export const timestampSchema = z.iso.datetime({ offset: true }).nullish();
export const moneySchema = z.number().min(0).max(1_000_000).nullish();

/** Dados de pagamento (MB WAY, IBAN, ...): objeto pequeno de texto/booleanos. */
export const paymentSchema = z
  .record(z.string().max(40), z.union([z.string().max(120), z.boolean()]))
  .refine((o) => Object.keys(o).length <= 12, 'too many fields');

export type PaymentMethods = z.infer<typeof paymentSchema>;
