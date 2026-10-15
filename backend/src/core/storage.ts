import { createHmac, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, rm, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';

/**
 * Fotografias em disco, servidas por URLs assinados e temporários (como os
 * de um bucket privado). Para usar S3/R2, basta outra implementação destes
 * métodos.
 */
export class PhotoStorage {
  constructor(
    private readonly root: string,
    private readonly publicUrl: string,
    private readonly secret: string,
  ) {}

  static readonly ttlSeconds = 60 * 60 * 24 * 7;
  static readonly maxBytes = 2 * 1024 * 1024;
  /** Imagens e GIFs enviados no chat. */
  static readonly chatMaxBytes = 8 * 1024 * 1024;

  /**
   * Caminhos sempre no formato <uuid>/<ficheiro>, sem `..`. A pasta é o
   * utilizador (fotografias, stickers) ou a conversa (imagens do chat).
   */
  private static readonly keyPattern = /^[0-9a-f-]{36}\/[A-Za-z0-9-]+\.(jpg|png|webp|gif)$/;

  /** Uma chave guardada noutro sítio (ex.: na BD) é deste armazenamento? */
  static isKey(key: string): boolean {
    return PhotoStorage.keyPattern.test(key);
  }

  private file(key: string): string {
    if (!PhotoStorage.keyPattern.test(key)) throw new Error('invalid storage key');
    return path.join(this.root, key);
  }

  async put(key: string, data: Buffer): Promise<void> {
    const file = this.file(key);
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, data);
  }

  async read(key: string): Promise<Buffer | null> {
    try {
      return await readFile(this.file(key));
    } catch {
      return null;
    }
  }

  async remove(key: string): Promise<void> {
    await unlink(this.file(key)).catch(() => {});
  }

  async copy(from: string, to: string): Promise<boolean> {
    const data = await this.read(from);
    if (!data) return false;
    await this.put(to, data);
    return true;
  }

  /** Apaga uma pasta inteira: as fotografias de um utilizador ou as imagens de uma conversa. */
  async removeFolder(id: string): Promise<void> {
    if (!/^[0-9a-f-]{36}$/.test(id)) return;
    await rm(path.join(this.root, id), { recursive: true, force: true });
  }

  private sign(key: string, exp: number): string {
    return createHmac('sha256', this.secret).update(`photo:${key}:${exp}`).digest('base64url');
  }

  /**
   * A validade termina sempre à meia-noite (UTC), para o mesmo ficheiro ter o
   * mesmo URL durante o dia e a app o poder guardar em cache.
   */
  signedUrl(key: string, now = Date.now()): string {
    const day = 60 * 60 * 24;
    const exp = Math.ceil((Math.floor(now / 1000) + PhotoStorage.ttlSeconds) / day) * day;
    return `${this.publicUrl}/files/${key}?exp=${exp}&sig=${this.sign(key, exp)}`;
  }

  verify(key: string, exp: string | undefined, sig: string | undefined): boolean {
    const e = Number(exp);
    if (!sig || !Number.isInteger(e) || e < Date.now() / 1000 || !PhotoStorage.keyPattern.test(key)) return false;
    const expected = Buffer.from(this.sign(key, e));
    const given = Buffer.from(sig);
    return expected.length === given.length && timingSafeEqual(expected, given);
  }
}

/** Tipo real da imagem pelos primeiros bytes (não se confia no Content-Type). */
export function imageType(data: Buffer): { ext: 'jpg' | 'png' | 'webp' | 'gif'; mime: string } | null {
  if (data.length > 3 && data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff) return { ext: 'jpg', mime: 'image/jpeg' };
  if (data.length > 8 && data.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return { ext: 'png', mime: 'image/png' };
  }
  if (data.length > 12 && data.toString('ascii', 0, 4) === 'RIFF' && data.toString('ascii', 8, 12) === 'WEBP') {
    return { ext: 'webp', mime: 'image/webp' };
  }
  if (data.length > 6 && ['GIF87a', 'GIF89a'].includes(data.toString('ascii', 0, 6))) return { ext: 'gif', mime: 'image/gif' };
  return null;
}
