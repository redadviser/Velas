import { z } from 'zod';

export const friendRequestSchema = z.object({ user_id: z.guid() });
export const respondFriendSchema = z.object({ accept: z.boolean() });
export const userParams = z.object({ userId: z.guid() });

/** Outra conta, com o mínimo para a reconhecer. */
export interface FriendUser {
  user_id: string;
  display_name: string;
  username: string | null;
  photo_url: string | null;
}

export interface Friend extends FriendUser {
  since: string;
}

export interface FriendRequest extends FriendUser {
  id: string;
  created_at: string;
}

export interface FriendsList {
  friends: Friend[];
  /** Pedidos que me fizeram (aceitar ou recusar). */
  incoming: FriendRequest[];
  /** Pedidos que fiz e ainda não tiveram resposta. */
  outgoing: FriendRequest[];
}

/** sent: pedido enviado; accepted: a outra pessoa já me tinha pedido, ficamos amigos. */
export type FriendRequestResult = 'sent' | 'accepted' | 'already_friends' | 'already_sent' | 'not_found' | 'self';
