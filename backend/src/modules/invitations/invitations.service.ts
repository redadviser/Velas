import { tx, type Db } from '../../core/database.js';
import type { PhotoStorage } from '../../core/storage.js';
import type { FoundUser, GroupPreview, InvitationPreview, InviteResult } from './invitations.model.js';

/**
 * Convites para grupos: por conta (email, telemóvel ou username) ou por
 * link com código. A lógica está nas funções SQL de migrations/002_gift_groups.sql.
 */
export class InvitationsService {
  constructor(
    private readonly db: Db,
    private readonly storage: PhotoStorage,
  ) {}

  /** Com a fotografia, para confirmar que é a pessoa certa. */
  async findUser(userId: string, identifier: string): Promise<FoundUser | null> {
    const { rows } = await tx(this.db, userId, (c) =>
      c.query<FoundUser & { photo_path: string | null }>(
        'select f.*, p.photo_path from find_user($1) f join profiles p on p.id = f.user_id',
        [identifier],
      ),
    );
    if (!rows[0]) return null;
    const { photo_path, ...user } = rows[0];
    return { ...user, photo_url: this.storage.urlOf(photo_path) };
  }

  /** Só o administrador convida. */
  async invite(userId: string, groupId: string, inviteeId: string): Promise<InviteResult> {
    const { rows } = await tx(this.db, userId, (c) =>
      c.query('select invite_to_group($1, $2) as result', [groupId, inviteeId]),
    );
    return rows[0].result;
  }

  /** Cancelar um convite (administrador). */
  async cancel(userId: string, invitationId: string): Promise<void> {
    await tx(this.db, userId, (c) =>
      c.query('delete from group_invitations where id = $1 and is_group_admin(group_id)', [invitationId]),
    );
  }

  async mine(userId: string): Promise<InvitationPreview[]> {
    const { rows } = await tx(this.db, userId, (c) => c.query('select my_invitations() as list'));
    return rows[0].list;
  }

  /** Aceita ou recusa. Ao aceitar devolve o id do grupo. */
  async respond(userId: string, invitationId: string, accept: boolean): Promise<string | null> {
    const { rows } = await tx(this.db, userId, (c) =>
      c.query('select respond_invitation($1, $2) as group_id', [invitationId, accept]),
    );
    return rows[0].group_id;
  }

  async preview(userId: string, code: string): Promise<GroupPreview> {
    const { rows } = await tx(this.db, userId, (c) => c.query('select group_preview($1) as preview', [code]));
    return rows[0].preview;
  }

  /** Entra no grupo a partir do link. Devolve o id do grupo. */
  async join(userId: string, code: string, displayName: string): Promise<string> {
    const { rows } = await tx(this.db, userId, (c) =>
      c.query('select join_gift_group($1, $2) as group_id', [code, displayName]),
    );
    return rows[0].group_id;
  }
}
