import type { CategoryRow } from '../categories/categories.model.js';
import type { GiftRow } from '../gifts/gifts.model.js';
import type { MessageRow } from '../messages/messages.model.js';
import type { PersonJson } from '../people/people.model.js';

/** Todos os dados de um utilizador (AppData na app). */
export interface Snapshot {
  categories: CategoryRow[];
  people: PersonJson[];
  gift_ideas: GiftRow[];
  messages: MessageRow[];
}
