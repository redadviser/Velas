import { tx, type Db, type Tx } from '../../core/database.js';
import { notFound } from '../../core/errors.js';
import { hashPassword } from '../../core/passwords.js';
import type { PhotoStorage } from '../../core/storage.js';
import { defaultCategories, profileColumns, type NewUser, type Profile, type ProfilePatch } from './users.model.js';

export class UsersService {
  constructor(
    private readonly db: Db,
    private readonly storage: PhotoStorage,
  ) {}

  // Dentro de uma transação de outro módulo (ex.: autenticação) -------------

  async profileIn(c: Tx, userId: string): Promise<Profile> {
    const { rows } = await c.query<Profile>(
      `select p.id, u.email, p.display_name, p.username, p.phone, p.notifications_enabled,
              p.reminder_hour, p.reminder_minute, p.default_reminder_days, p.payment_methods,
              u.password_hash is not null as has_password, u.google_sub is not null as google_linked
       from profiles p join users u on u.id = p.id
       where p.id = $1`,
      [userId],
    );
    if (!rows[0]) throw notFound();
    return rows[0];
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

  update(userId: string, patch: ProfilePatch): Promise<Profile> {
    const sets: string[] = [];
    const values: unknown[] = [userId];
    for (const col of profileColumns) {
      if (patch[col] === undefined) continue;
      values.push(col === 'payment_methods' ? JSON.stringify(patch[col]) : patch[col]);
      sets.push(`${col} = $${values.length}`);
    }
    return tx(this.db, userId, async (c) => {
      if (sets.length) await c.query(`update profiles set ${sets.join(', ')} where id = $1`, values);
      return this.profileIn(c, userId);
    });
  }

  /** Definir ou alterar a palavra-passe (também em contas criadas com o Google). */
  async setPassword(userId: string, password: string): Promise<void> {
    await this.db.query('update users set password_hash = $2 where id = $1', [userId, await hashPassword(password)]);
  }

  /** Direito ao apagamento (RGPD): conta, dados e fotografias. */
  async deleteAccount(userId: string): Promise<void> {
    await tx(this.db, userId, async (c) => {
      // Primeiro os grupos de que é administrador (levam os membros consigo);
      // assim o trigger "o administrador não pode sair" não bloqueia.
      await c.query('delete from gift_groups where created_by = $1', [userId]);
      await c.query('delete from users where id = $1', [userId]);
    });
    await this.storage.removeUser(userId);
  }
}
