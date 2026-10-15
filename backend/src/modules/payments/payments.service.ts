import type { Config } from '../../config/env.js';
import { tx, type Db } from '../../core/database.js';
import { HttpError, notFound } from '../../core/errors.js';
import type { RealtimeHub } from '../../core/realtime.js';
import type { GatewayEvent, GatewayStatus, InAppMethod, PaymentsGateway } from './gateway.js';
import {
  defaultFees,
  mbwayPhone,
  withFee,
  type CheckoutInput,
  type FeeTable,
  type PaymentJson,
  type PayoutStatus,
} from './payments.model.js';

interface PaymentRow {
  id: string;
  method: InAppMethod;
  amount: number;
  fee: number;
  status: PaymentJson['status'];
  error: string | null;
  stripe_payment_intent: string | null;
  stripe_checkout_session: string | null;
  payer_id: string | null;
}

/** paid_method de group_members para cada método da Stripe. */
const paidMethod: Record<InAppMethod, string> = { card: 'card', paypal: 'paypal', mb_way: 'mbway' };

/**
 * Pagamentos dentro da app com Stripe Connect. O dinheiro vai para a conta
 * Stripe de quem compra a prenda (destination charge); a comissão é somada a
 * quem paga. Um pagamento concluído marca a parte como paga e confirmada.
 */
export class PaymentsService {
  constructor(
    private readonly db: Db,
    private readonly config: Config,
    private readonly gateway?: PaymentsGateway,
    private readonly hub?: RealtimeHub,
  ) {}

  get enabled(): boolean {
    return Boolean(this.gateway);
  }

  get fees(): FeeTable {
    return this.config.payments?.fees ?? defaultFees;
  }

  private requireGateway(): PaymentsGateway {
    if (!this.gateway) throw new HttpError(503, 'payments_unavailable');
    return this.gateway;
  }

  // Quem recebe -------------------------------------------------------------

  async payoutStatus(userId: string): Promise<PayoutStatus> {
    const { rows } = await this.db.query<{ stripe_account_id: string | null; payouts_enabled: boolean; mbway_pay_phone: string | null }>(
      'select stripe_account_id, payouts_enabled, mbway_pay_phone from profiles where id = $1',
      [userId],
    );
    const p = rows[0];
    if (!p) throw notFound();
    return {
      enabled: this.enabled,
      connected: Boolean(p.stripe_account_id),
      ready: this.enabled && p.payouts_enabled,
      mbway_pay_phone: p.mbway_pay_phone,
    };
  }

  /** Link para ligar (ou continuar a ligar) a conta Stripe de quem recebe. */
  async startOnboarding(userId: string): Promise<{ url: string }> {
    const gateway = this.requireGateway();
    const { rows } = await this.db.query<{ stripe_account_id: string | null; email: string }>(
      'select p.stripe_account_id, u.email from profiles p join users u on u.id = p.id where p.id = $1',
      [userId],
    );
    if (!rows[0]) throw notFound();
    let account = rows[0].stripe_account_id;
    if (!account) {
      account = (await gateway.createAccount({ email: rows[0].email, userId })).id;
      await this.db.query('update profiles set stripe_account_id = $2 where id = $1', [userId, account]);
    }
    const base = this.config.publicUrl;
    const url = await gateway.onboardingLink(account, {
      returnUrl: `${base}/stripe/return`,
      refreshUrl: `${base}/stripe/refresh`,
    });
    return { url };
  }

  /** Depois de voltar da Stripe: a conta já pode receber? */
  async refreshPayouts(userId: string): Promise<PayoutStatus> {
    const { rows } = await this.db.query<{ stripe_account_id: string | null }>(
      'select stripe_account_id from profiles where id = $1',
      [userId],
    );
    const account = rows[0]?.stripe_account_id;
    if (account && this.gateway) {
      const ready = await this.gateway.accountReady(account);
      await this.db.query('update profiles set payouts_enabled = $2 where id = $1', [userId, ready]);
    }
    return this.payoutStatus(userId);
  }

  // Quem paga ---------------------------------------------------------------

  /** Começa o pagamento da parte de [memberId] (tem de ser a minha). */
  async checkout(userId: string, memberId: string, input: CheckoutInput): Promise<PaymentJson> {
    const gateway = this.requireGateway();

    const ctx = await tx(this.db, userId, async (c) => {
      const { rows } = await c.query<{
        group_id: string;
        title: string;
        target_amount: number;
        split_mode: 'equal' | 'custom';
        purchased_at: string | null;
        confirmed_at: string | null;
        buyer_id: string | null;
      }>(
        `select g.id as group_id, g.title, g.target_amount, g.split_mode, g.purchased_at, m.confirmed_at,
                group_buyer_user(g.id) as buyer_id
         from group_members m join gift_groups g on g.id = m.group_id
         where m.id = $1 and m.user_id = $2`,
        [memberId, userId],
      );
      const g = rows[0];
      if (!g) throw notFound();
      if (g.purchased_at) throw new HttpError(409, 'group_closed');
      if (g.confirmed_at) throw new HttpError(409, 'already_paid');
      if (!g.buyer_id || g.buyer_id === userId) throw new HttpError(409, 'is_buyer');

      // A parte calcula-se aqui (igual à app: GiftGroup.shares), nunca a partir do pedido.
      const { rows: members } = await c.query<{ id: string; custom_amount: number | null }>(
        'select id, custom_amount from group_members where group_id = $1 order by created_at, id',
        [g.group_id],
      );
      let shareCents: number;
      if (g.split_mode === 'custom') {
        shareCents = Math.round((members.find((m) => m.id === memberId)?.custom_amount ?? 0) * 100);
      } else {
        const cents = Math.round(g.target_amount * 100);
        const i = members.findIndex((m) => m.id === memberId);
        shareCents = Math.floor(cents / members.length) + (i < cents % members.length ? 1 : 0);
      }
      if (shareCents < 50) throw new HttpError(422, 'amount_too_small');

      const { rows: buyer } = await c.query<{ stripe_account_id: string | null; payouts_enabled: boolean }>(
        'select stripe_account_id, payouts_enabled from profiles where id = $1',
        [g.buyer_id],
      );
      if (!buyer[0]?.stripe_account_id || !buyer[0].payouts_enabled) throw new HttpError(409, 'payee_not_ready');

      const { rows: me } = await c.query<{ email: string; mbway_pay_phone: string | null }>(
        'select u.email, p.mbway_pay_phone from users u join profiles p on p.id = u.id where u.id = $1',
        [userId],
      );
      return { ...g, shareCents, destination: buyer[0].stripe_account_id, email: me[0]!.email, savedPhone: me[0]!.mbway_pay_phone };
    });

    let phone: string | null = null;
    if (input.method === 'mb_way') {
      phone = input.phone ? mbwayPhone(input.phone) : ctx.savedPhone;
      if (!phone) throw new HttpError(422, 'invalid_phone');
      if (input.save_phone) await this.db.query('update profiles set mbway_pay_phone = $2 where id = $1', [userId, phone]);
    }

    const { totalCents, feeCents } = withFee(ctx.shareCents, this.fees[input.method]);
    const { rows } = await this.db.query<{ id: string }>(
      `insert into payments (group_id, member_id, payer_id, payee_id, method, amount, fee)
       values ($1, $2, $3, $4, $5, $6, $7) returning id`,
      [ctx.group_id, memberId, userId, ctx.buyer_id, input.method, ctx.shareCents / 100, feeCents / 100],
    );
    const paymentId = rows[0]!.id;
    const metadata = { payment_id: paymentId, group_id: ctx.group_id, member_id: memberId };

    try {
      if (input.method === 'mb_way') {
        const r = await gateway.startMbWay({
          amountCents: totalCents,
          transferCents: ctx.shareCents,
          destination: ctx.destination,
          phone: phone!,
          description: ctx.title,
          metadata,
        });
        await this.db.query('update payments set stripe_payment_intent = $2 where id = $1', [paymentId, r.paymentIntentId]);
        if (r.status !== 'pending') await this.finalize(paymentId, r.status, r.error);
      } else {
        const base = this.config.publicUrl;
        const r = await gateway.createCheckout({
          method: input.method,
          amountCents: totalCents,
          transferCents: ctx.shareCents,
          destination: ctx.destination,
          title: ctx.title,
          email: ctx.email,
          locale: input.locale,
          successUrl: `${base}/pay/done`,
          cancelUrl: `${base}/pay/cancel`,
          metadata,
        });
        await this.db.query('update payments set stripe_checkout_session = $2 where id = $1', [paymentId, r.sessionId]);
        return { ...(await this.paymentJson(paymentId)), checkout_url: r.url };
      }
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      await this.finalize(paymentId, 'failed', message);
      throw new HttpError(502, 'payment_failed', message);
    }
    return this.paymentJson(paymentId);
  }

  private async paymentJson(paymentId: string): Promise<PaymentJson> {
    const { rows } = await this.db.query<PaymentRow>('select * from payments where id = $1', [paymentId]);
    const p = rows[0];
    if (!p) throw notFound();
    return {
      id: p.id,
      method: p.method,
      amount: p.amount,
      fee: p.fee,
      total: Math.round((p.amount + p.fee) * 100) / 100,
      status: p.status,
      error: p.error,
      checkout_url: null,
    };
  }

  /** Estado do pagamento (quem paga). Se ainda está pendente, pergunta à Stripe. */
  async status(userId: string, paymentId: string): Promise<PaymentJson> {
    const { rows } = await this.db.query<PaymentRow>('select * from payments where id = $1 and payer_id = $2', [paymentId, userId]);
    const p = rows[0];
    if (!p) throw notFound();
    if (p.status === 'pending' && this.gateway) {
      const r = p.stripe_payment_intent
        ? await this.gateway.paymentIntentStatus(p.stripe_payment_intent)
        : p.stripe_checkout_session
          ? await this.gateway.checkoutStatus(p.stripe_checkout_session)
          : null;
      if (r && r.status !== 'pending') await this.finalize(p.id, r.status, 'error' in r ? r.error : undefined);
    }
    return this.paymentJson(paymentId);
  }

  /**
   * Fecha o pagamento (uma só vez). Concluído: a parte fica paga e confirmada.
   * Corre sem utilizador (os triggers de permissões não se aplicam: é a Stripe a confirmar).
   */
  private async finalize(paymentId: string, status: Exclude<GatewayStatus, 'pending'>, error?: string): Promise<void> {
    const { rows } = await this.db.query<{ member_id: string | null; method: InAppMethod; group_id: string }>(
      `update payments set status = $2, error = $3 where id = $1 and status = 'pending'
       returning member_id, method, group_id`,
      [paymentId, status, error ?? null],
    );
    const p = rows[0];
    if (!p || status !== 'succeeded' || !p.member_id) return;
    await this.db.query(
      `update group_members set paid_at = coalesce(paid_at, now()), paid_method = $2, confirmed_at = coalesce(confirmed_at, now())
       where id = $1`,
      [p.member_id, paidMethod[p.method]],
    );
    // Os membros veem logo a parte paga (as apps recarregam os grupos).
    if (this.hub) {
      const { rows: users } = await this.db.query<{ id: string }>(
        `select user_id as id from group_members where group_id = $1 and user_id is not null
         union select created_by from gift_groups where id = $1`,
        [p.group_id],
      );
      this.hub.send(users.map((u) => u.id), { type: 'conversations' });
    }
  }

  // Webhook da Stripe -------------------------------------------------------

  async webhook(raw: Buffer, signature: string): Promise<void> {
    const gateway = this.requireGateway();
    let event: GatewayEvent;
    try {
      event = gateway.parseWebhook(raw, signature);
    } catch {
      throw new HttpError(400, 'invalid_signature');
    }
    const o = event.object;
    const paymentId = o.metadata?.payment_id;
    switch (event.type) {
      case 'payment_intent.succeeded':
        if (paymentId) await this.finalize(paymentId, 'succeeded');
        break;
      case 'payment_intent.payment_failed': {
        if (!paymentId) break;
        const err = (o.last_payment_error as { code?: string; message?: string } | null | undefined) ?? null;
        // Cartão recusado no Checkout: a pessoa ainda pode tentar outro cartão na mesma página.
        const session = await this.db.query('select 1 from payments where id = $1 and stripe_checkout_session is not null', [paymentId]);
        if (!session.rowCount) await this.finalize(paymentId, 'failed', err?.code ?? err?.message);
        break;
      }
      case 'payment_intent.canceled':
        if (paymentId) await this.finalize(paymentId, 'canceled');
        break;
      case 'checkout.session.completed':
        if (paymentId && o.payment_status === 'paid') await this.finalize(paymentId, 'succeeded');
        break;
      case 'checkout.session.async_payment_succeeded':
        if (paymentId) await this.finalize(paymentId, 'succeeded');
        break;
      case 'checkout.session.async_payment_failed':
        if (paymentId) await this.finalize(paymentId, 'failed');
        break;
      case 'checkout.session.expired':
        if (paymentId) await this.finalize(paymentId, 'canceled');
        break;
      case 'account.updated': {
        const caps = o.capabilities as { transfers?: string } | undefined;
        await this.db.query('update profiles set payouts_enabled = $2 where stripe_account_id = $1', [
          o.id,
          caps?.transfers === 'active',
        ]);
        break;
      }
    }
  }
}
