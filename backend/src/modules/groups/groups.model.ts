import { z } from 'zod';

import { id, paymentSchema } from '../../core/validation.js';

/** Prenda comprada a meias. O administrador é quem cria (created_by). */
export const groupSchema = z.object({
  id,
  title: z.string().trim().min(1).max(120),
  celebrant_name: z.string().trim().min(1).max(120),
  celebrant_day: z.number().int().min(1).max(31).nullish(),
  celebrant_month: z.number().int().min(1).max(12).nullish(),
  person_id: id.nullish(),
  gift_description: z.string().max(2000).default(''),
  gift_link: z.string().max(2000).default(''),
  target_amount: z.number().positive().max(100_000),
  split_mode: z.enum(['equal', 'custom']).default('equal'),
  /** Quem compra e recebe o dinheiro; null = o administrador. */
  buyer_member_id: id.nullish(),
  deadline: z.iso.date().nullish(),
});
export type GroupInput = z.infer<typeof groupSchema>;

/** Participante acrescentado pelo administrador (ele próprio ou alguém sem conta). */
export const newMemberSchema = z.object({
  id,
  user_id: id.nullish(),
  display_name: z.string().trim().min(1).max(80),
  custom_amount: z.number().min(0).max(100_000).nullish(),
  payment_methods: paymentSchema.default({}),
});
export type NewMemberInput = z.infer<typeof newMemberSchema>;

export const saveGroupSchema = z.object({
  group: z.unknown(),
  new_members: z.array(newMemberSchema).max(100).default([]),
});

export const memberInfoSchema = z.object({
  display_name: z.string().trim().min(1).max(80),
  custom_amount: z.number().min(0).max(100_000).nullable(),
  payment_methods: paymentSchema,
});
export type MemberInfo = z.infer<typeof memberInfoSchema>;

export const paymentMethods = ['mbway', 'transfer', 'revolut', 'paypal', 'cash'] as const;
export type PaymentMethod = (typeof paymentMethods)[number];

export const paidSchema = z.object({ method: z.enum(paymentMethods).nullable() });
export const confirmedSchema = z.object({ confirmed: z.boolean() });
export const purchasedSchema = z.object({ purchased: z.boolean() });

/**
 * Grupo com membros e convites embutidos, no formato de GiftGroup.fromJson
 * (as colunas de gift_groups + group_members + group_invitations).
 */
export type GroupJson = Record<string, unknown> & {
  id: string;
  created_by: string;
  group_members: Record<string, unknown>[];
  group_invitations: Record<string, unknown>[];
};
