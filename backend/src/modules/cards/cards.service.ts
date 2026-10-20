import { randomBytes } from 'node:crypto';

import { tx, type Db, type Tx } from '../../core/database.js';
import { HttpError } from '../../core/errors.js';
import type { RealtimeHub } from '../../core/realtime.js';
import type { PhotoStorage } from '../../core/storage.js';
import { sendSchema } from '../chat/chat.model.js';
import type { ChatService } from '../chat/chat.service.js';
import type { CardPreview, ClaimResult, CreateCardInput, ReceivedCard, SentCard } from './cards.model.js';

const sentColumns = 'id, token, person_id, recipient_name, body, via, created_at, opened_at, claimed_at';

/**
 * Cartões de parabéns: um link que mostra a mensagem a quem o recebe, com ou
 * sem a app, ou uma publicação direta no mural de um amigo. Ao chegar ao
 * mural, as duas pessoas ficam amigas e a mensagem abre a conversa privada
 * entre elas (ver migrations/011_greeting_cards.sql).
 *
 * As mudanças (cartão aberto, guardado, publicado) avisam quem enviou e quem
 * recebeu com o evento `{ type: 'cards' }`.
 */
export class CardsService {
  constructor(
    private readonly db: Db,
    private readonly storage: PhotoStorage,
    private readonly chat: ChatService,
    private readonly hub: RealtimeHub,
  ) {}

  /** Reenviar o mesmo id devolve o cartão já criado. Com `recipient_id`, publica no mural desse amigo. */
  async create(userId: string, input: CreateCardInput): Promise<SentCard> {
    const recipientId = input.recipient_id ?? null;
    if (recipientId) {
      const { rows } = await this.db.query<{ ok: boolean }>('select are_friends($1, $2) as ok', [userId, recipientId]);
      if (!rows[0]?.ok) throw new HttpError(403, 'not_friends');
    }
    const token = randomBytes(16).toString('base64url');
    const { rows } = await this.db.query<SentCard>(
      `insert into greeting_cards (id, token, sender_id, person_id, recipient_name, body, via, recipient_id, claimed_at)
       values ($1, $2, $3, $4, $5, $6, $7, $8, case when $8::uuid is null then null else now() end)
       on conflict (id) do nothing
       returning ${sentColumns}`,
      [input.id, token, userId, input.person_id, input.recipient_name, input.body, recipientId ? 'wall' : 'link', recipientId],
    );
    if (rows[0]) {
      if (recipientId) {
        await this.linkPerson(this.db, userId, input.person_id, recipientId);
        await this.deliver({ id: rows[0].id, sender_id: userId, body: rows[0].body }, recipientId);
        this.hub.send([userId, recipientId], { type: 'cards' });
      }
      return rows[0];
    }
    const existing = await this.db.query<SentCard>(
      `select ${sentColumns} from greeting_cards where id = $1 and sender_id = $2`,
      [input.id, userId],
    );
    if (!existing.rows[0]) throw new HttpError(409, 'conflict');
    return existing.rows[0];
  }

  /** Cartões enviados (de uma pessoa, se dada), mais recentes primeiro. */
  async sent(userId: string, personId?: string): Promise<SentCard[]> {
    const { rows } = await this.db.query<SentCard>(
      `select ${sentColumns} from greeting_cards
       where sender_id = $1 and ($2::uuid is null or person_id = $2)
       order by created_at desc`,
      [userId, personId ?? null],
    );
    return rows;
  }

  /** O mural: cartões recebidos, mais recentes primeiro. */
  async received(userId: string): Promise<ReceivedCard[]> {
    const { rows } = await this.db.query<{
      id: string;
      body: string;
      via: 'link' | 'wall';
      created_at: string;
      received_at: string;
      seen: boolean;
      sender_id: string;
      display_name: string;
      username: string | null;
      photo_path: string | null;
    }>(
      `select c.id, c.body, c.via, c.created_at, c.claimed_at as received_at, c.opened_at is not null as seen,
              p.id as sender_id, p.display_name, p.username, p.photo_path
       from greeting_cards c join profiles p on p.id = c.sender_id
       where c.recipient_id = $1
       order by c.claimed_at desc`,
      [userId],
    );
    return rows.map(({ sender_id, display_name, username, photo_path, ...card }) => ({
      ...card,
      sender: { user_id: sender_id, display_name, username, photo_url: this.storage.urlOf(photo_path) },
    }));
  }

  /** Abriu o mural: os cartões passam a vistos e quem os enviou fica a saber. */
  async markSeen(userId: string): Promise<void> {
    const { rows } = await this.db.query<{ sender_id: string }>(
      `update greeting_cards set opened_at = now()
       where recipient_id = $1 and opened_at is null
       returning sender_id`,
      [userId],
    );
    if (rows.length) this.hub.send([userId, ...new Set(rows.map((r) => r.sender_id))], { type: 'cards' });
  }

  /** Apaga o cartão (o link deixa de funcionar e sai do mural). A mensagem fica na conversa. */
  async remove(userId: string, cardId: string): Promise<void> {
    const { rows } = await this.db.query<{ recipient_id: string | null }>(
      'delete from greeting_cards where id = $1 and sender_id = $2 returning recipient_id',
      [cardId, userId],
    );
    const recipient = rows[0]?.recipient_id;
    if (recipient) this.hub.send([recipient], { type: 'cards' });
  }

  async preview(token: string): Promise<CardPreview> {
    const { rows } = await this.db.query<Omit<CardPreview, 'sender_photo_url'> & { photo_path: string | null }>(
      `select c.token, c.sender_id, coalesce(nullif(p.display_name, ''), p.username, 'Alguém') as sender_name,
              p.photo_path, c.recipient_name, c.body, c.created_at, c.recipient_id is not null as claimed
       from greeting_cards c join profiles p on p.id = c.sender_id
       where c.token = $1`,
      [token],
    );
    if (!rows[0]) throw new HttpError(404, 'card_not_found');
    const { photo_path, ...card } = rows[0];
    return { ...card, sender_photo_url: this.storage.urlOf(photo_path) };
  }

  /** Marca a primeira abertura (pela página ou pela app de quem recebe). */
  async markOpened(token: string): Promise<void> {
    const { rows } = await this.db.query<{ sender_id: string }>(
      'update greeting_cards set opened_at = now() where token = $1 and opened_at is null returning sender_id',
      [token],
    );
    if (rows[0]) this.hub.send([rows[0].sender_id], { type: 'cards' });
  }

  /**
   * Guarda o cartão na conta de quem o recebeu: vai para o mural, fica amigo
   * de quem o enviou e a mensagem aparece na conversa privada entre os dois.
   * Pode repetir-se.
   */
  async claim(userId: string, token: string): Promise<ClaimResult> {
    const card = await tx(this.db, userId, async (c) => {
      const { rows } = await c.query<{
        id: string;
        sender_id: string;
        recipient_id: string | null;
        person_id: string | null;
        body: string;
      }>(
        'select id, sender_id, recipient_id, person_id, body from greeting_cards where token = $1 for update',
        [token],
      );
      const card = rows[0];
      if (!card) throw new HttpError(404, 'card_not_found');
      if (card.sender_id === userId) throw new HttpError(409, 'own_card');
      if (card.recipient_id && card.recipient_id !== userId) throw new HttpError(409, 'card_claimed');
      if (!card.recipient_id) {
        await c.query(
          `update greeting_cards set recipient_id = $2, claimed_at = now(), opened_at = coalesce(opened_at, now())
           where id = $1`,
          [card.id, userId],
        );
      }
      // Quem enviou escolheu esta pessoa e ela aceitou o cartão: ficam amigos.
      await c.query(
        `insert into friendships (requester_id, addressee_id, status, responded_at) values ($1, $2, 'accepted', now())
         on conflict ((least(requester_id, addressee_id)), (greatest(requester_id, addressee_id)))
         do update set status = 'accepted', responded_at = coalesce(friendships.responded_at, now())`,
        [card.sender_id, userId],
      );
      if (card.person_id) await this.linkPerson(c, card.sender_id, card.person_id, userId);
      return card;
    });
    this.hub.send([userId, card.sender_id], { type: 'friends' });
    const conversationId = await this.deliver(card, userId);
    this.hub.send([userId, card.sender_id], { type: 'cards' });
    return { sender_id: card.sender_id, conversation_id: conversationId };
  }

  /**
   * Liga o aniversário de onde partiu o cartão à conta de quem o recebeu, se
   * ainda não estiver ligado (nem esse amigo ligado a outro aniversário).
   */
  private async linkPerson(c: Db | Tx, senderId: string, personId: string, recipientId: string): Promise<void> {
    await c.query(
      `update people set linked_user_id = $3
       where id = $2 and user_id = $1 and linked_user_id is null
         and not exists (select 1 from people where user_id = $1 and linked_user_id = $3)`,
      [senderId, personId, recipientId],
    );
  }

  /**
   * Põe a mensagem na conversa privada entre os dois (já amigos), em nome de
   * quem escreveu o cartão. O id do cartão evita duplicá-la. Devolve a conversa.
   */
  private async deliver(card: { id: string; sender_id: string; body: string }, recipientId: string): Promise<string> {
    const conversation = await this.chat.openDirect(recipientId, card.sender_id);
    await this.chat.send(card.sender_id, conversation.id, sendSchema.parse({ id: card.id, kind: 'text', body: card.body }));
    return conversation.id;
  }
}
