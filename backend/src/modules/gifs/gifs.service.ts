import { HttpError } from '../../core/errors.js';

export type GifKind = 'gifs' | 'stickers';

export interface Gif {
  id: string;
  /** Versão a mostrar na conversa (~200 px de largura). */
  url: string;
  /** Versão mais leve para a grelha de escolha. */
  preview_url: string;
  width: number;
  height: number;
}

export interface GifPage {
  results: Gif[];
  next_offset: number | null;
}

/** Só se aceitam GIFs e stickers servidos pelo GIPHY (nunca URLs arbitrários). */
export const giphyUrl = /^https:\/\/(media\d*|i)\.giphy\.com\/[\w./-]+$/;

interface GiphyImage {
  url?: string;
  width?: string;
  height?: string;
}

interface GiphyResponse {
  data?: { id: string; images?: Record<string, GiphyImage | undefined> }[];
  pagination?: { total_count?: number; count?: number; offset?: number };
}

/**
 * Pesquisa de GIFs e stickers no GIPHY. A app pede através da API para a
 * chave não ir dentro da app. Sem GIPHY_API_KEY responde 503 (gifs_unavailable).
 */
export class GifsService {
  constructor(
    private readonly apiKey: string | undefined,
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  static readonly pageSize = 24;

  get enabled() {
    return Boolean(this.apiKey);
  }

  async search(kind: GifKind, query: string, offset: number): Promise<GifPage> {
    if (!this.apiKey) throw new HttpError(503, 'gifs_unavailable');
    const q = query.trim();
    const params = new URLSearchParams({
      api_key: this.apiKey,
      limit: String(GifsService.pageSize),
      offset: String(offset),
      rating: 'pg-13',
      bundle: 'messaging_non_clips',
    });
    if (q) {
      params.set('q', q);
      params.set('lang', 'pt');
    }
    const url = `https://api.giphy.com/v1/${kind}/${q ? 'search' : 'trending'}?${params}`;

    let body: GiphyResponse;
    try {
      const res = await this.fetcher(url, { signal: AbortSignal.timeout(8000) });
      if (!res.ok) throw new Error(`GIPHY ${res.status}`);
      body = (await res.json()) as GiphyResponse;
    } catch {
      throw new HttpError(502, 'gifs_unavailable');
    }

    const results: Gif[] = [];
    for (const g of body.data ?? []) {
      const main = g.images?.fixed_width;
      const preview = g.images?.fixed_width_small ?? main;
      const width = Number(main?.width);
      const height = Number(main?.height);
      if (!main?.url || !preview?.url || !giphyUrl.test(main.url) || !(width > 0) || !(height > 0)) continue;
      results.push({ id: g.id, url: main.url, preview_url: preview.url, width, height });
    }
    const p = body.pagination ?? {};
    const next = (p.offset ?? offset) + (p.count ?? results.length);
    return { results, next_offset: p.total_count !== undefined && next < p.total_count && results.length > 0 ? next : null };
  }
}
