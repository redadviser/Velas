import { z } from 'zod';

import { id } from '../../core/validation.js';

export const userParams = z.object({ id });

export const reportReasons = ['spam', 'harassment', 'inappropriate', 'impersonation', 'underage', 'other'] as const;

export const reportSchema = z.object({
  reason: z.enum(reportReasons),
  details: z.string().trim().max(500).default(''),
  /** A mensagem de onde partiu a denúncia (opcional). */
  message_id: id.optional(),
  /** Bloquear logo também. */
  block: z.boolean().default(false),
});
export type ReportInput = z.infer<typeof reportSchema>;

export interface BlockedUser {
  user_id: string;
  display_name: string;
  username: string | null;
  photo_url: string | null;
  blocked_at: string;
}
