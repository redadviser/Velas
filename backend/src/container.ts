import type { Config } from './config/env.js';
import type { Db } from './core/database.js';
import type { Mailer } from './core/mailer.js';
import { RealtimeHub } from './core/realtime.js';
import type { PhotoStorage } from './core/storage.js';
import { AuthService } from './modules/auth/auth.service.js';
import type { GoogleVerifier } from './modules/auth/google.js';
import type { AccessTokens } from './modules/auth/tokens.js';
import { BirthdayRequestsService } from './modules/birthday-requests/birthday-requests.service.js';
import { CardsService } from './modules/cards/cards.service.js';
import { CategoriesService } from './modules/categories/categories.service.js';
import { ChatService } from './modules/chat/chat.service.js';
import { StickersService } from './modules/chat/stickers.service.js';
import { FriendsService } from './modules/friends/friends.service.js';
import { GifsService } from './modules/gifs/gifs.service.js';
import type { PushSender } from './modules/push/push.gateway.js';
import { PushService, ReplyTokens } from './modules/push/push.service.js';
import { GiftsService } from './modules/gifts/gifts.service.js';
import { GroupsService } from './modules/groups/groups.service.js';
import { InvitationsService } from './modules/invitations/invitations.service.js';
import { MessagesService } from './modules/messages/messages.service.js';
import { PeopleService } from './modules/people/people.service.js';
import { SpecialDatesService } from './modules/special-dates/special-dates.service.js';
import { PartiesService } from './modules/parties/parties.service.js';
import { SafetyService } from './modules/safety/safety.service.js';
import type { AdaptyClient } from './modules/subscriptions/adapty.js';
import { SubscriptionsService } from './modules/subscriptions/subscriptions.service.js';
import { SyncService } from './modules/sync/sync.service.js';
import { AccountDeletionService } from './modules/users/account-deletion.service.js';
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
  /** Firebase Cloud Messaging (notificações push); sem ele não há push. Substituído nos testes. */
  push?: PushSender;
  /** Adapty (Birthdayly+ comprado nas lojas); sem ele as compras ficam desligadas. Substituído nos testes. */
  adapty?: AdaptyClient;
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
  const specialDates = new SpecialDatesService(db);
  const hub = new RealtimeHub();
  const chat = new ChatService(db, storage, hub);
  const groups = new GroupsService(db, storage, hub);
  const push = new PushService(db, deps.push, new ReplyTokens(deps.config.jwtSecret));
  push.isOnline = (userId) => hub.isOnline(userId);
  chat.onSent = (message, ids) => void push.chatMessage(message, ids).catch((e) => push.onError(e));
  const cards = new CardsService(db, storage, chat, hub);
  messages.scheduled = { cards, push, hub };
  // Mudar a privacidade da presença avisa logo quem a estava a ver.
  users.onUpdated = async (userId, patch) => {
    if (patch.show_presence !== undefined) await chat.announcePresence(userId);
  };
  return {
    hub,
    auth: new AuthService(db, users, deps.tokens, deps.mail, deps.verifyGoogle, deps.config),
    users,
    accountDeletion: new AccountDeletionService(db, users, deps.mail, deps.config),
    categories,
    people,
    gifts,
    messages,
    specialDates,
    parties: new PartiesService(db),
    sync: new SyncService(db, categories, people, gifts, messages, specialDates),
    groups,
    invitations: new InvitationsService(db, storage),
    friends: new FriendsService(db, hub, storage),
    chat,
    cards,
    birthdayRequests: new BirthdayRequestsService(db, hub),
    safety: new SafetyService(db, storage, hub, deps.mail, deps.config),
    stickers: new StickersService(db, storage),
    gifs: new GifsService(deps.config.giphyApiKey, deps.fetch),
    push,
    subscriptions: new SubscriptionsService(db, users, hub, deps.adapty),
  };
}
