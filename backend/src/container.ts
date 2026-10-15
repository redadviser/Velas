import type { Config } from './config/env.js';
import type { Db } from './core/database.js';
import type { Mailer } from './core/mailer.js';
import { RealtimeHub } from './core/realtime.js';
import type { PhotoStorage } from './core/storage.js';
import { AuthService } from './modules/auth/auth.service.js';
import type { GoogleVerifier } from './modules/auth/google.js';
import type { AccessTokens } from './modules/auth/tokens.js';
import { CategoriesService } from './modules/categories/categories.service.js';
import { ChatService } from './modules/chat/chat.service.js';
import { StickersService } from './modules/chat/stickers.service.js';
import { FriendsService } from './modules/friends/friends.service.js';
import { GifsService } from './modules/gifs/gifs.service.js';
import { GiftsService } from './modules/gifts/gifts.service.js';
import { GroupsService } from './modules/groups/groups.service.js';
import { InvitationsService } from './modules/invitations/invitations.service.js';
import { MessagesService } from './modules/messages/messages.service.js';
import { PeopleService } from './modules/people/people.service.js';
import { SyncService } from './modules/sync/sync.service.js';
import { UsersService } from './modules/users/users.service.js';

/** Infraestrutura partilhada (substituível nos testes). */
export interface Deps {
  config: Config;
  db: Db;
  storage: PhotoStorage;
  tokens: AccessTokens;
  mail: Mailer;
  verifyGoogle: GoogleVerifier;
  /** Pedidos HTTP a serviços externos (GIPHY); substituído nos testes. */
  fetch?: typeof fetch;
}

export type Services = ReturnType<typeof createServices>;

/** Cria os serviços de todos os módulos com as suas dependências. */
export function createServices(deps: Deps) {
  const { db, storage } = deps;
  const users = new UsersService(db, storage);
  const categories = new CategoriesService(db);
  const people = new PeopleService(db, storage);
  const gifts = new GiftsService(db);
  const messages = new MessagesService(db);
  const hub = new RealtimeHub();
  return {
    hub,
    auth: new AuthService(db, users, deps.tokens, deps.mail, deps.verifyGoogle, deps.config),
    users,
    categories,
    people,
    gifts,
    messages,
    sync: new SyncService(db, categories, people, gifts, messages),
    groups: new GroupsService(db, storage),
    invitations: new InvitationsService(db, storage),
    friends: new FriendsService(db, hub, storage),
    chat: new ChatService(db, storage, hub),
    stickers: new StickersService(db, storage),
    gifs: new GifsService(deps.config.giphyApiKey, deps.fetch),
  };
}
