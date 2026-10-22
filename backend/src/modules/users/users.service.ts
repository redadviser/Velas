import { tx, type Db, type Tx } from '../../core/database.js';
import { HttpError, notFound } from '../../core/errors.js';
import { hashPassword } from '../../core/passwords.js';
import { imageType, type PhotoStorage } from '../../core/storage.js';
import { acceptTermsIn } from '../auth/auth.service.js';
import { defaultCategories, profileColumns, type NewUser, type Profile, type ProfilePatch } from './users.model.js';

export class UsersService {
  constructor(
    private readonly db: Db,
    private readonly storage: PhotoStorage,
  ) {}

  /** Chamado depois de mudar o perfil (ex.: o chat volta a anunciar a presença). */
  onUpdated?: (userId: string, patch: ProfilePatch) => Promise<void>;

  // Dentro de uma transação de outro módulo (ex.: autenticação) -------------

  async profileIn(c: Tx, userId: string): Promise<Profile> {
    const { rows } = await c.query<Omit<Profile, 'photo_url'> & { photo_path: string | null }>(
      `select p.id, u.email, p.display_name, p.username, p.phone, p.notifications_enabled,
              p.reminder_hour, p.reminder_minute, p.default_reminder_days, p.payment_methods,
              u.password_hash is not null as has_password, u.google_sub is not null as google_linked,
              p.photo_path, p.show_presence, p.read_receipts, p.typing_indicator,
              p.message_notifications, p.message_previews, p.mbway_pay_phone,
              coalesce(p.plus_until > now(), false) as plus, p.plus_until,
              not p.plus_trial_used as plus_trial_available, p.weekly_digest, u.terms_version
       from profiles p join users u on u.id = p.id
       where p.id = $1`,
      [userId],
    );
    if (!rows[0]) throw notFound();
    const { photo_path, ...profile } = rows[0];
    return { ...profile, photo_url: this.storage.urlOf(photo_path) };
  }

  /** Cria a conta, o perfil e as categorias por defeito. Devolve o id. */
  async createIn(c: Tx, u: NewUser): Promise<string> {
    const { rows } = await c.query<{ id: string }>(
      `insert into users (email, password_hash, google_sub, email_verified) values ($1, $2, $3, $4) returning id`,
      [u.email, u.passwordHash, u.googleSub ?? null, u.emailVerified ?? false],
    );
    const userId = rows[0]!.id;
    await c.query(`insert into profiles (id, display_name, username, phone) values ($1, $2, $3, $4)`, [
      userId,
      u.name.trim() || u.email.split('@')[0],
      u.username,
      u.phone || null,
    ]);
    for (const cat of defaultCategories) {
      await c.query('insert into categories (user_id, name, color, sort) values ($1, $2, $3, $4)', [
        userId,
        cat.name,
        cat.color,
        cat.sort,
      ]);
    }
    return userId;
  }

  /** Username livre a partir do email (contas Google). Pode ser mudado no perfil. */
  async suggestUsernameIn(c: Tx, email: string): Promise<string | null> {
    let base = (email.split('@')[0] ?? '')
      .toLowerCase()
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9._]/g, '')
      .replace(/^[._]+|[._]+$/g, '')
      .slice(0, 15);
    if (base.length < 3) base = `velas${base}`;
    for (let i = 0; i < 12; i++) {
      const candidate = i === 0 ? base : `${base}${Math.floor(1000 + Math.random() * 9000)}`;
      const { rowCount } = await c.query('select 1 from profiles where username = $1', [candidate]);
      if (!rowCount) return candidate;
    }
    return null;
  }

  // Operações do próprio utilizador ----------------------------------------

  profile(userId: string): Promise<Profile> {
    return tx(this.db, userId, (c) => this.profileIn(c, userId));
  }

  async update(userId: string, patch: ProfilePatch): Promise<Profile> {
    const sets: string[] = [];
    const values: unknown[] = [userId];
    for (const col of profileColumns) {
      if (patch[col] === undefined) continue;
      values.push(col === 'payment_methods' ? JSON.stringify(patch[col]) : patch[col]);
      sets.push(`${col} = $${values.length}`);
    }
    const profile = await tx(this.db, userId, async (c) => {
      if (sets.length) await c.query(`update profiles set ${sets.join(', ')} where id = $1`, values);
      return this.profileIn(c, userId);
    });
    await this.onUpdated?.(userId, patch).catch(() => {});
    return profile;
  }

  /** Período experimental do Birthdayly+: 30 dias, uma vez por conta. */
  async startPlusTrial(userId: string): Promise<Profile> {
    return tx(this.db, userId, async (c) => {
      const { rowCount } = await c.query(
        `update profiles set plus_until = greatest(coalesce(plus_until, now()), now()) + interval '30 days',
                             plus_trial_used = true
         where id = $1 and not plus_trial_used`,
        [userId],
      );
      if (!rowCount) throw new HttpError(409, 'trial_used');
      return this.profileIn(c, userId);
    });
  }

  /** Fotografia de perfil (bytes da imagem). Substitui a anterior. */
  async setPhoto(userId: string, data: Buffer): Promise<Profile> {
    const type = imageType(data);
    if (!type) throw new HttpError(415, 'unsupported_media_type');
    const key = `${userId}/avatar-${Date.now()}.${type.ext}`;
    await this.storage.put(key, data);
    try {
      const { previous, profile } = await tx(this.db, userId, async (c) => {
        const { rows } = await c.query<{ photo_path: string | null }>(
          'select photo_path from profiles where id = $1 for update',
          [userId],
        );
        await c.query('update profiles set photo_path = $2 where id = $1', [userId, key]);
        return { previous: rows[0]?.photo_path, profile: await this.profileIn(c, userId) };
      });
      if (previous && previous !== key) await this.storage.remove(previous);
      return profile;
    } catch (e) {
      await this.storage.remove(key);
      throw e;
    }
  }

  async removePhoto(userId: string): Promise<Profile> {
    const { previous, profile } = await tx(this.db, userId, async (c) => {
      const { rows } = await c.query<{ photo_path: string | null }>(
        'select photo_path from profiles where id = $1 for update',
        [userId],
      );
      await c.query('update profiles set photo_path = null where id = $1', [userId]);
      return { previous: rows[0]?.photo_path, profile: await this.profileIn(c, userId) };
    });
    if (previous) await this.storage.remove(previous);
    return profile;
  }

  /** Definir ou alterar a palavra-passe (também em contas criadas com o Google). */
  async setPassword(userId: string, password: string): Promise<void> {
    await this.db.query('update users set password_hash = $2 where id = $1', [userId, await hashPassword(password)]);
  }

  /** Direito ao apagamento (RGPD): conta, dados e fotografias. */
  async deleteAccount(userId: string): Promise<void> {
    const conversations = await tx(this.db, userId, async (c) => {
      // Conversas que desaparecem com a conta: as privadas e as dos grupos que administra.
      const { rows } = await c.query<{ id: string }>(
        `select c.id from conversations c left join gift_groups g on g.id = c.group_id
         where $1 in (c.user_a, c.user_b) or g.created_by = $1
         union
         select id from gift_groups where created_by = $1`,
        [userId],
      );
      // Primeiro os grupos de que é administrador (levam os membros consigo);
      // assim o trigger "o administrador não pode sair" não bloqueia.
      await c.query('delete from gift_groups where created_by = $1', [userId]);
      await c.query('delete from users where id = $1', [userId]);
      return rows;
    });
    await this.storage.removeFolder(userId);
    for (const { id } of conversations) await this.storage.removeFolder(id);
  }

  /** Interesse no Birthdayly+ (ainda sem compra): o último plano escolhido conta. */
  async registerPlusInterest(userId: string, plan: 'monthly' | 'yearly'): Promise<void> {
    await this.db.query(
      `insert into plus_interest (user_id, plan) values ($1, $2)
       on conflict (user_id) do update set plan = excluded.plan`,
      [userId, plan],
    );
  }

  /** Aceitar a versão atual dos Termos e da Política de Privacidade. */
  async acceptTerms(userId: string): Promise<Profile> {
    return tx(this.db, userId, async (c) => {
      await acceptTermsIn(c, userId);
      return this.profileIn(c, userId);
    });
  }

  /**
   * Direito de acesso e portabilidade (RGPD): tudo o que a Birthdayly guarda
   * sobre a conta, num só documento JSON.
   */
  async exportData(userId: string): Promise<Record<string, unknown>> {
    return tx(this.db, userId, async (c) => {
      const q = async (sql: string) => (await c.query(sql, [userId])).rows;
      const urlOf = (rows: Record<string, unknown>[], key: string) =>
        rows.map(({ [key]: k, ...r }) => ({ ...r, ...(k ? { [key.replace(/_(key|path)$/, '_url')]: this.storage.urlOf(k as string) } : {}) }));
      const profile = await this.profileIn(c, userId);
      const account = (
        await q('select email, created_at, email_verified, google_sub is not null as google_linked, terms_version, terms_accepted_at from users where id = $1')
      )[0];
      return {
        exported_at: new Date().toISOString(),
        account,
        profile,
        categories: await q('select id, name, color, sort from categories where user_id = $1 order by sort'),
        people: urlOf(
          await q(`select id, name, birth_day, birth_month, birth_year, relation, category_id, notes, gift_budget,
                          reminder_days, reminder_hour, reminder_minute, linked_user_id, photo_path, created_at
                   from people where user_id = $1 order by name`),
          'photo_path',
        ),
        gift_ideas: await q(`select id, person_id, title, price, link, notes, purchased, purchased_at, created_at
                             from gift_ideas where user_id = $1 order by created_at`),
        messages: await q('select id, person_id, body, tone, updated_at from messages where user_id = $1'),
        cards_sent: urlOf(
          await q(`select id, person_id, recipient_name, body, via, media_kind, media_key, created_at, opened_at, claimed_at
                   from greeting_cards where sender_id = $1 order by created_at`),
          'media_key',
        ),
        cards_received: urlOf(
          await q(`select c.id, p.display_name as from_name, c.body, c.media_kind, c.media_key, c.claimed_at as received_at
                   from greeting_cards c join profiles p on p.id = c.sender_id where c.recipient_id = $1 order by c.claimed_at`),
          'media_key',
        ),
        wall_photos: urlOf(await q('select id, year, caption, media_key, created_at from wall_photos where user_id = $1'), 'media_key'),
        friends: await q(`select p.display_name, p.username, f.status, f.created_at
                          from friendships f join profiles p on p.id = case when f.requester_id = $1 then f.addressee_id else f.requester_id end
                          where $1 in (f.requester_id, f.addressee_id)`),
        gift_groups: await q(`select g.id, g.title, g.celebrant_name, g.target_amount, g.purchased_at, m.display_name as my_name,
                                     m.custom_amount as my_amount, m.paid_at as my_paid_at, g.created_by = $1 as admin
                              from gift_groups g join group_members m on m.group_id = g.id and m.user_id = $1
                              order by g.created_at`),
        chat_messages_sent: await q(`select id, conversation_id, kind, body, created_at from chat_messages
                                     where sender_id = $1 and deleted_at is null order by created_at`),
        payments: await q(`select id, group_id, method, amount, fee, service_fee, status, created_at
                           from payments where payer_id = $1 order by created_at`),
        birthday_request_answers: await q(`select name, birth_day, birth_month, birth_year, status, created_at
                                           from birthday_answers where user_id = $1 order by created_at`),
        blocked_users: await q(`select p.display_name, p.username, b.created_at from user_blocks b
                                join profiles p on p.id = b.blocked_id where b.blocker_id = $1`),
        reports_made: await q('select reason, details, created_at, status from user_reports where reporter_id = $1'),
      };
    });
  }
}
