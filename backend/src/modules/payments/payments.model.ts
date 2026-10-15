import { z } from 'zod';

import type { InAppMethod } from './gateway.js';

export const inAppMethods = ['card', 'paypal', 'mb_way', 'sepa_debit', 'revolut_pay'] as const;

/** Comissão da Stripe por método: percentagem + valor fixo (em euros). */
export type FeeTable = Record<InAppMethod, { percent: number; fixed: number }>;

/**
 * Valores por omissão (cartões europeus ~1,5% + 0,25 €). Confirma no painel da
 * Stripe os da tua conta e ajusta com STRIPE_FEES, ex.:
 * {"card":{"percent":1.5,"fixed":0.25},"mb_way":{"percent":1.5,"fixed":0.25},"paypal":{"percent":3.4,"fixed":0.35}}
 */
export const defaultFees: FeeTable = {
  card: { percent: 1.5, fixed: 0.25 },
  mb_way: { percent: 1.5, fixed: 0.25 },
  paypal: { percent: 3.4, fixed: 0.35 },
  sepa_debit: { percent: 0, fixed: 0.35 },
  revolut_pay: { percent: 1.5, fixed: 0.25 },
};

/**
 * A comissão é somada a quem paga, para quem compra a prenda receber a parte
 * inteira: total = (parte + fixo) / (1 − percentagem), arredondado ao cêntimo acima.
 */
export function withFee(shareCents: number, fee: { percent: number; fixed: number }) {
  const totalCents = Math.ceil((shareCents + Math.round(fee.fixed * 100)) / (1 - fee.percent / 100));
  return { totalCents, feeCents: totalCents - shareCents };
}

/** Telemóvel para o MB WAY em E.164 (9 dígitos portugueses ganham o +351). */
export function mbwayPhone(input: string): string | null {
  const d = input.replace(/[\s\-()]/g, '');
  if (/^9[1236]\d{7}$/.test(d)) return `+351${d}`;
  if (/^00351\d{9}$/.test(d)) return `+${d.slice(2)}`;
  return /^\+[1-9]\d{7,14}$/.test(d) ? d : null;
}

export const checkoutSchema = z.object({
  method: z.enum(inAppMethods),
  /** Só MB WAY: o número para onde vai o pedido (sem ele usa o guardado). */
  phone: z.string().max(20).nullish(),
  /** Só MB WAY: guardar o número para próximos pagamentos. */
  save_phone: z.boolean().default(false),
  /** Língua da página de pagamento (pt, en, es, fr). */
  locale: z.enum(['pt', 'en', 'es', 'fr']).optional(),
});
export type CheckoutInput = z.infer<typeof checkoutSchema>;

export interface PaymentJson {
  id: string;
  method: InAppMethod;
  /** A parte, a comissão e o total, em euros. */
  amount: number;
  fee: number;
  total: number;
  /** processing: transferência autorizada, à espera de chegar (a parte já conta como paga). */
  status: 'pending' | 'processing' | 'succeeded' | 'failed' | 'canceled';
  error: string | null;
  /** Cartão / PayPal: página de pagamento a abrir. */
  checkout_url: string | null;
}

export interface PayoutStatus {
  /** A Birthdayly tem pagamentos na app ligados (STRIPE_SECRET_KEY). */
  enabled: boolean;
  /** Já começou a ligar a conta Stripe. */
  connected: boolean;
  /** Pode receber (onboarding concluído). */
  ready: boolean;
  /** Número MB WAY guardado para pagar. */
  mbway_pay_phone: string | null;
}
