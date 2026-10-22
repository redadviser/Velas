import type { Config } from '../../config/env.js';
import { tx, type Db } from '../../core/database.js';
import { HttpError, notFound } from '../../core/errors.js';
import type { Mailer } from '../../core/mailer.js';
import type { RealtimeHub } from '../../core/realtime.js';
import type { PhotoStorage } from '../../core/storage.js';
import type { BlockedUser, ReportInput } from './safety.model.js';

const reasonLabels: Record<ReportInput['reason'], string> = {
  spam: 'Spam ou publicidade',
  harassment: 'Assédio ou ameaças',
  inappropriate: 'Conteúdo impróprio',
  impersonation: 'Perfil falso ou a fazer-se passar por outra pessoa',
  underage: 'Menor de idade',
  other: 'Outro',
};

/** Bloquear e denunciar utilizadores (ver migrations/018_safety.sql). */
export class SafetyService {
  constructor(
    private readonly db: Db,
    private readonly storage: PhotoStorage,
    private readonly hub: RealtimeHub,
    private readonly mail: Mailer,
    private readonly config: Config,
  ) {}

  /** Bloquear: deixam de ser amigos e deixa de se ver o que o outro escreve. */
  async block(userId: string, otherId: string): Promise<void> {
    if (otherId === userId) throw new HttpError(422, 'invalid_value', 'self');
    await tx(this.db, userId, async (c) => {
      if (!(await c.query('select 1 from profiles where id = $1', [otherId])).rowCount) throw notFound();
      await c.query('insert into user_blocks (blocker_id, blocked_id) values ($1, $2) on conflict do nothing', [userId, otherId]);
      await c.query(
        `delete from friendships
         where least(requester_id, addressee_id) = least($1::uuid, $2::uuid)
           and greatest(requester_id, addressee_id) = greatest($1::uuid, $2::uuid)`,
        [userId, otherId],
      );
    });
    // As duas apps atualizam os amigos e as conversas.
    this.hub.send([userId, otherId], { type: 'friends' });
    this.hub.send([userId, otherId], { type: 'conversations' });
  }

  async unblock(userId: string, otherId: string): Promise<void> {
    await this.db.query('delete from user_blocks where blocker_id = $1 and blocked_id = $2', [userId, otherId]);
    this.hub.send([userId], { type: 'conversations' });
  }

  async blocked(userId: string): Promise<BlockedUser[]> {
    const { rows } = await this.db.query<Omit<BlockedUser, 'photo_url'> & { photo_path: string | null }>(
      `select p.id as user_id, p.display_name, p.username, p.photo_path, b.created_at as blocked_at
       from user_blocks b join profiles p on p.id = b.blocked_id
       where b.blocker_id = $1 order by b.created_at desc`,
      [userId],
    );
    return rows.map(({ photo_path, ...u }) => ({ ...u, photo_url: this.storage.urlOf(photo_path) }));
  }

  /**
   * Regista a denúncia (com a mensagem, se partiu de uma) e avisa a equipa por
   * email. Com `block`, bloqueia logo também.
   */
  async report(userId: string, otherId: string, input: ReportInput): Promise<void> {
    if (otherId === userId) throw new HttpError(422, 'invalid_value', 'self');
    const { reporter, reported, message } = await tx(this.db, userId, async (c) => {
      const people = await c.query<{ id: string; display_name: string; username: string | null }>(
        'select id, display_name, username from profiles where id = any($1::uuid[])',
        [[userId, otherId]],
      );
      const reported = people.rows.find((p) => p.id === otherId);
      if (!reported) throw notFound();
      // Só se aceita uma mensagem do denunciado numa conversa a que quem denuncia tem acesso.
      let message: string | null = null;
      if (input.message_id) {
        const m = await c.query<{ body: string; kind: string }>(
          `select body, kind from chat_messages
           where id = $1 and sender_id = $2 and can_chat(conversation_id)`,
          [input.message_id, otherId],
        );
        if (!m.rows[0]) throw notFound();
        message = m.rows[0].kind === 'text' ? m.rows[0].body : `[${m.rows[0].kind}] ${m.rows[0].body}`.trim();
      }
      await c.query(
        `insert into user_reports (reporter_id, reported_id, reason, details, message_id, message_body)
         values ($1, $2, $3, $4, $5, $6)`,
        [userId, otherId, input.reason, input.details, input.message_id ?? null, message],
      );
      return { reporter: people.rows.find((p) => p.id === userId)!, reported, message };
    });
    if (input.block) await this.block(userId, otherId);

    const to = this.config.moderationEmail;
    if (!to) return;
    const who = (p: { id: string; display_name: string; username: string | null }) =>
      `${p.display_name}${p.username ? ` (@${p.username})` : ''} — ${p.id}`;
    const lines = [
      `Motivo: ${reasonLabels[input.reason]}`,
      `Denunciado: ${who(reported)}`,
      `Por: ${who(reporter)}`,
      input.details ? `Detalhes: ${input.details}` : null,
      message !== null ? `Mensagem: ${message}` : null,
      input.block ? 'Quem denunciou também bloqueou.' : null,
    ].filter((l): l is string => l !== null);
    await this.mail({
      to,
      subject: `Denúncia na Birthdayly: ${reasonLabels[input.reason]}`,
      text: lines.join('\n'),
      html: lines.map((l) => `<p>${l.replace(/[&<>]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[ch]!)}</p>`).join(''),
    }).catch(() => {});
  }
}
