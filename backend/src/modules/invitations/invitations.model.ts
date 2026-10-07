import { z } from 'zod';

/** Procurar uma conta por email, telemóvel (E.164) ou username. */
export const findUserSchema = z.object({ identifier: z.string().trim().min(3).max(254) });
export const inviteSchema = z.object({ user_id: z.guid() });
export const respondSchema = z.object({ accept: z.boolean() });
export const codeParams = z.object({ code: z.string().trim().min(4).max(20) });
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
