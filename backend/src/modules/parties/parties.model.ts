import { z } from 'zod';

import { id } from '../../core/validation.js';

export const rsvpValues = ['pending', 'yes', 'maybe', 'no'] as const;

export const partySchema = z.object({
  id,
  title: z.string().trim().min(1).max(120),
  celebrant_name: z.string().trim().min(1).max(120),
  person_id: id.nullish(),
  starts_at: z.iso.datetime({ offset: true }).nullish(),
  place: z.string().trim().max(200).default(''),
  notes: z.string().max(2000).default(''),
});
export type PartyInput = z.infer<typeof partySchema>;

export const joinPartySchema = z.object({ code: z.string().trim().min(4).max(20) });
export const rsvpSchema = z.object({ rsvp: z.enum(rsvpValues) });
export const guestSchema = z.object({ id: id.optional(), name: z.string().trim().min(1).max(80) });
export const taskSchema = z.object({
  title: z.string().trim().min(1).max(200),
  assignee_id: id.nullish(),
  done: z.boolean().default(false),
});
export type TaskInput = z.infer<typeof taskSchema>;
export const taskParams = z.object({ id, taskId: id });

export interface PartyGuest {
  id: string;
  user_id: string | null;
  display_name: string;
  username: string | null;
  rsvp: (typeof rsvpValues)[number];
  created_at: string;
}

export interface PartyTask {
  id: string;
  title: string;
  assignee_id: string | null;
  done: boolean;
  created_at: string;
}

export interface PartyJson {
  id: string;
  created_by: string;
  title: string;
  celebrant_name: string;
  /** Só para quem criou (é uma pessoa da lista dele). */
  person_id: string | null;
  starts_at: Date | null;
  place: string;
  notes: string;
  invite_code: string;
  created_at: Date;
  updated_at: Date;
  guests: PartyGuest[];
  tasks: PartyTask[];
}
