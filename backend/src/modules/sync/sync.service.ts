import { tx, type Db } from '../../core/database.js';
import type { CategoriesService } from '../categories/categories.service.js';
import type { GiftsService } from '../gifts/gifts.service.js';
import type { MessagesService } from '../messages/messages.service.js';
import type { PeopleService } from '../people/people.service.js';
import type { Snapshot } from './sync.model.js';

/** Carregamento inicial da app: tudo num só pedido e numa só transação. */
export class SyncService {
  constructor(
    private readonly db: Db,
    private readonly categories: CategoriesService,
    private readonly people: PeopleService,
    private readonly gifts: GiftsService,
    private readonly messages: MessagesService,
  ) {}

  snapshot(userId: string): Promise<Snapshot> {
    return tx(this.db, userId, async (c) => ({
      categories: await this.categories.listIn(c, userId),
      people: await this.people.listIn(c, userId),
      gift_ideas: await this.gifts.listIn(c, userId),
      messages: await this.messages.listIn(c, userId),
    }));
  }
}
