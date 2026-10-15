import { randomUUID } from 'node:crypto';

import { tx, type Db } from '../../core/database.js';
import { HttpError, notFound } from '../../core/errors.js';
import { imageType, type PhotoStorage } from '../../core/storage.js';
import type { SaveStickerInput, StickerJson } from './chat.model.js';

interface StickerRow {
  id: string;
  media_key: string | null;
  media_url: string | null;
  width: number | null;
  height: number | null;
  created_at: string;
}

/**
 * Stickers guardados por cada pessoa: a partir de uma imagem/GIF/sticker de
 * uma conversa, de um sticker do GIPHY ou de uma imagem da galeria. As
 * imagens são copiadas para a pasta do utilizador, por isso continuam
 * disponíveis mesmo que a mensagem original seja apagada.
 */
export class StickersService {
  constructor(
    private readonly db: Db,
    private readonly storage: PhotoStorage,
  ) {}

  static readonly maxPerUser = 300;

  private json(r: StickerRow): StickerJson {
    return {
      id: r.id,
      url: r.media_key ? this.storage.signedUrl(r.media_key) : r.media_url!,
      width: r.width,
      height: r.height,
      created_at: r.created_at,
    };
  }

  async list(userId: string): Promise<StickerJson[]> {
    const { rows } = await this.db.query<StickerRow>(
      'select id, media_key, media_url, width, height, created_at from stickers where user_id = $1 order by created_at desc',
      [userId],
    );
    return rows.map((r) => this.json(r));
  }

  private async insert(userId: string, s: Omit<StickerRow, 'id' | 'created_at'>): Promise<StickerJson> {
    return tx(this.db, userId, async (c) => {
      const { rows: count } = await c.query<{ n: number }>('select count(*)::int as n from stickers where user_id = $1', [userId]);
      if (count[0]!.n >= StickersService.maxPerUser) throw new HttpError(409, 'too_many_stickers');
      if (s.media_url) {
        const same = await c.query<StickerRow>(
          'select id, media_key, media_url, width, height, created_at from stickers where user_id = $1 and media_url = $2',
          [userId, s.media_url],
        );
        if (same.rows[0]) return this.json(same.rows[0]);
      }
      const { rows } = await c.query<StickerRow>(
        `insert into stickers (user_id, media_key, media_url, width, height) values ($1, $2, $3, $4, $5)
         returning id, media_key, media_url, width, height, created_at`,
        [userId, s.media_key, s.media_url, s.width, s.height],
      );
      return this.json(rows[0]!);
    });
  }

  private copyKey(userId: string, from: string) {
    return `${userId}/sticker-${randomUUID()}.${from.split('.').pop()}`;
  }

  async save(userId: string, input: SaveStickerInput): Promise<StickerJson> {
    if ('media_url' in input) {
      return this.insert(userId, { media_key: null, media_url: input.media_url, width: input.width ?? null, height: input.height ?? null });
    }
    const { rows } = await tx(this.db, userId, (c) =>
      c.query<{ media_key: string | null; media_url: string | null; width: number | null; height: number | null }>(
        `select media_key, media_url, width, height from chat_messages
         where id = $1 and deleted_at is null and kind <> 'text' and can_chat(conversation_id)`,
        [input.message_id],
      ),
    );
    const m = rows[0];
    if (!m) throw notFound();
    if (!m.media_key) return this.insert(userId, { media_key: null, media_url: m.media_url, width: m.width, height: m.height });

    const key = this.copyKey(userId, m.media_key);
    if (!(await this.storage.copy(m.media_key, key))) throw notFound();
    try {
      return await this.insert(userId, { media_key: key, media_url: null, width: m.width, height: m.height });
    } catch (e) {
      await this.storage.remove(key);
      throw e;
    }
  }

  /** Imagem da galeria (bytes no corpo). */
  async upload(userId: string, data: Buffer, width: number | null, height: number | null): Promise<StickerJson> {
    const type = imageType(data);
    if (!type) throw new HttpError(415, 'unsupported_media_type');
    const key = `${userId}/sticker-${randomUUID()}.${type.ext}`;
    await this.storage.put(key, data);
    try {
      return await this.insert(userId, { media_key: key, media_url: null, width, height });
    } catch (e) {
      await this.storage.remove(key);
      throw e;
    }
  }

  async remove(userId: string, stickerId: string): Promise<void> {
    const { rows } = await this.db.query<{ media_key: string | null }>(
      'delete from stickers where id = $1 and user_id = $2 returning media_key',
      [stickerId, userId],
    );
    if (rows[0]?.media_key) await this.storage.remove(rows[0].media_key);
  }
}
