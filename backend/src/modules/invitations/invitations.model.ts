import { z } from 'zod';

/** Procurar uma conta por email, telemóvel (E.164) ou username. */
export const findUserSchema = z.object({ identifier: z.string().trim().min(3).max(254) });
export const inviteSchema = z.object({ user_id: z.guid() });
export const respondSchema = z.object({ accept: z.boolean() });
/** Código de convite como a pessoa o escreve ("k7p2 qx9m", "K7P2-QX9M"): só letras e números, em maiúsculas. */
export const inviteCodeSchema = z
  .string()
  .max(40)
  .transform((s) => s.replace(/[^A-Za-z0-9]/g, '').toUpperCase())
  .pipe(z.string().min(4).max(20));
export const codeParams = z.object({ code: inviteCodeSchema });

/** "K7P2QX9M" → "K7P2 QX9M" (os códigos antigos, de outro tamanho, ficam como estão). */
export const formatInviteCode = (code: string) => (code.length === 8 ? `${code.slice(0, 4)} ${code.slice(4)}` : code);
export const joinSchema = z.object({ display_name: z.string().max(80).default('') });

export interface FoundUser {
  user_id: string;
  display_name: string;
  username: string | null;
}

export type InviteResult = 'invited' | 'already_invited' | 'already_member' | 'group_closed' | 'not_found';

/** Convite recebido, com o mínimo para decidir (my_invitations()). */
export interface InvitationPreview {
  id: string;
  group_id: string;
  title: string;
  celebrant_name: string;
  inviter_name: string | null;
  member_count: number;
  created_at: string;
}

/** O que se vê de um grupo ao abrir um link de convite (group_preview()). */
export interface GroupPreview {
  id: string;
  title: string;
  celebrant_name: string;
  admin_name: string | null;
  member_count: number;
  already_member: boolean;
  closed: boolean;
}
