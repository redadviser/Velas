import Stripe from 'stripe';

export type InAppMethod = 'card' | 'paypal' | 'mb_way';

/** Estado de um pagamento do lado da Stripe, já traduzido. */
export type GatewayStatus = 'pending' | 'succeeded' | 'failed' | 'canceled';

export interface GatewayEvent {
  type: string;
  /** O objeto do evento (PaymentIntent, Checkout Session ou Account). */
  object: { id: string; metadata?: Record<string, string> | null } & Record<string, unknown>;
}

/**
 * O que a API precisa de um serviço de pagamentos. A implementação real é a
 * Stripe ([StripeGateway]); os testes usam uma falsa.
 */
export interface PaymentsGateway {
  /** Conta de quem recebe (o comprador da prenda), com onboarding pela Stripe. */
  createAccount(p: { email: string; userId: string }): Promise<{ id: string }>;
  onboardingLink(accountId: string, urls: { returnUrl: string; refreshUrl: string }): Promise<string>;
  /** Pode receber transferências? */
  accountReady(accountId: string): Promise<boolean>;

  /** MB WAY: envia o pedido para o telemóvel de quem paga (aprova na app MB WAY). */
  startMbWay(p: {
    amountCents: number;
    transferCents: number;
    destination: string;
    phone: string;
    description: string;
    metadata: Record<string, string>;
  }): Promise<{ paymentIntentId: string; status: GatewayStatus; error?: string }>;

  /** Cartão ou PayPal: página de pagamento segura da Stripe (Checkout). */
  createCheckout(p: {
    method: 'card' | 'paypal';
    amountCents: number;
    transferCents: number;
    destination: string;
    title: string;
    email?: string;
    locale?: string;
    successUrl: string;
    cancelUrl: string;
    metadata: Record<string, string>;
  }): Promise<{ sessionId: string; url: string }>;

  paymentIntentStatus(id: string): Promise<{ status: GatewayStatus; error?: string }>;
  checkoutStatus(id: string): Promise<{ status: GatewayStatus; paymentIntentId?: string }>;

  /** Valida a assinatura do webhook e devolve o evento. */
  parseWebhook(raw: Buffer, signature: string): GatewayEvent;
}

function fromIntent(pi: Stripe.PaymentIntent): { status: GatewayStatus; error?: string } {
  const error = pi.last_payment_error?.code ?? pi.last_payment_error?.message ?? undefined;
  switch (pi.status) {
    case 'succeeded':
      return { status: 'succeeded' };
    case 'canceled':
      return { status: 'canceled', error };
    case 'requires_payment_method':
      // Depois de uma tentativa (ex.: MB WAY recusado ou expirado) volta a este estado.
      return error ? { status: 'failed', error } : { status: 'pending' };
    default:
      return { status: 'pending' };
  }
}

export class StripeGateway implements PaymentsGateway {
  private readonly stripe: Stripe;

  constructor(
    secretKey: string,
    private readonly webhookSecret?: string,
  ) {
    this.stripe = new Stripe(secretKey);
  }

  async createAccount(p: { email: string; userId: string }) {
    // Equivalente a uma conta Express (ver docs.stripe.com/connect/migrate-to-controller-properties):
    // a Stripe trata da identificação e o recetor tem o painel Express.
    const account = await this.stripe.accounts.create({
      country: 'PT',
      email: p.email,
      business_type: 'individual',
      controller: {
        stripe_dashboard: { type: 'express' },
        fees: { payer: 'application' },
        losses: { payments: 'application' },
      },
      capabilities: { transfers: { requested: true } },
      business_profile: { product_description: 'Recebe a parte dos amigos nas prendas em grupo (Birthdayly).' },
      metadata: { user_id: p.userId },
    });
    return { id: account.id };
  }

  async onboardingLink(accountId: string, urls: { returnUrl: string; refreshUrl: string }) {
    const link = await this.stripe.accountLinks.create({
      account: accountId,
      return_url: urls.returnUrl,
      refresh_url: urls.refreshUrl,
      type: 'account_onboarding',
    });
    return link.url;
  }

  async accountReady(accountId: string) {
    const a = await this.stripe.accounts.retrieve(accountId);
    return a.capabilities?.transfers === 'active';
  }

  async startMbWay(p: Parameters<PaymentsGateway['startMbWay']>[0]) {
    const pi = await this.stripe.paymentIntents.create({
      amount: p.amountCents,
      currency: 'eur',
      payment_method_types: ['mb_way'],
      payment_method_data: { type: 'mb_way', billing_details: { phone: p.phone } },
      confirm: true,
      description: p.description,
      transfer_data: { destination: p.destination, amount: p.transferCents },
      metadata: p.metadata,
    });
    return { paymentIntentId: pi.id, ...fromIntent(pi) };
  }

  async createCheckout(p: Parameters<PaymentsGateway['createCheckout']>[0]) {
    const session = await this.stripe.checkout.sessions.create({
      mode: 'payment',
      payment_method_types: [p.method],
      line_items: [
        {
          quantity: 1,
          price_data: { currency: 'eur', unit_amount: p.amountCents, product_data: { name: p.title } },
        },
      ],
      payment_intent_data: {
        transfer_data: { destination: p.destination, amount: p.transferCents },
        metadata: p.metadata,
      },
      customer_email: p.email,
      locale: (p.locale as Stripe.Checkout.SessionCreateParams.Locale | undefined) ?? 'auto',
      success_url: p.successUrl,
      cancel_url: p.cancelUrl,
      metadata: p.metadata,
    });
    return { sessionId: session.id, url: session.url! };
  }

  async paymentIntentStatus(id: string) {
    return fromIntent(await this.stripe.paymentIntents.retrieve(id));
  }

  async checkoutStatus(id: string) {
    const s = await this.stripe.checkout.sessions.retrieve(id);
    const paymentIntentId = typeof s.payment_intent === 'string' ? s.payment_intent : s.payment_intent?.id;
    if (s.status === 'complete' && s.payment_status === 'paid') return { status: 'succeeded' as const, paymentIntentId };
    if (s.status === 'expired') return { status: 'canceled' as const, paymentIntentId };
    return { status: 'pending' as const, paymentIntentId };
  }

  parseWebhook(raw: Buffer, signature: string): GatewayEvent {
    if (!this.webhookSecret) throw new Error('STRIPE_WEBHOOK_SECRET em falta');
    const event = this.stripe.webhooks.constructEvent(raw, signature, this.webhookSecret);
    return { type: event.type, object: event.data.object as unknown as GatewayEvent['object'] };
  }
}
