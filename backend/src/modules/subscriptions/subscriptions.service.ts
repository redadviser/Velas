import type { Db } from '../../core/database.js';
import { HttpError } from '../../core/errors.js';
import type { RealtimeHub } from '../../core/realtime.js';
import type { Profile } from '../users/users.model.js';
import type { UsersService } from '../users/users.service.js';
import type { AdaptyClient } from './adapty.js';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Birthdayly+ vendido pelas lojas (Adapty). A fonte de verdade é sempre o
 * Adapty: os webhooks só avisam que algo mudou e a API pergunta o estado atual
 * (por isso a ordem em que os webhooks chegam não importa).
 */
export class SubscriptionsService {
  constructor(
    private readonly db: Db,
    private readonly users: UsersService,
    private readonly hub: RealtimeHub,
    private readonly adapty?: AdaptyClient,
  ) {}

  get enabled(): boolean {
    return Boolean(this.adapty);
  }

  /** Atualiza store_plus_until com o que o Adapty diz agora. Devolve false se o utilizador não existe. */
  private async refresh(userId: string): Promise<boolean> {
    if (!this.adapty) throw new HttpError(503, 'subscriptions_unavailable');
    const until = await this.adapty.accessUntil(userId);
    const { rowCount } = await this.db.query('update profiles set store_plus_until = $2 where id = $1', [userId, until]);
    return Boolean(rowCount);
  }

  /** Depois de comprar ou restaurar na app: o perfil já com o plano da loja. */
  async sync(userId: string): Promise<Profile> {
    await this.refresh(userId);
    return this.users.profile(userId);
  }

  /** Webhook do Adapty (renovação, expiração, reembolso…): volta a perguntar o estado desse utilizador. */
  async webhook(body: unknown): Promise<void> {
    const customer = (body as { customer_user_id?: unknown } | null)?.customer_user_id;
    // O pedido de verificação ({}) e os utilizadores anónimos não têm customer_user_id.
    if (typeof customer !== 'string' || !uuid.test(customer)) return;
    // O app recarrega o perfil (o plano pode ter mudado com a app aberta).
    if (await this.refresh(customer)) this.hub.send([customer], { type: 'data' });
  }
}
