/** Escapa texto para HTML (conteúdo e atributos). */
export function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

/** Pré-visualização do link nas apps de mensagens (Open Graph). */
export interface LinkPreview {
  description: string;
  /** URL absoluto da imagem (1200×630). */
  image: string;
}

function previewTags(title: string, p: LinkPreview): string {
  const tag = (property: string, content: string) => `<meta property="${property}" content="${escapeHtml(content)}">`;
  return [
    tag('og:type', 'website'),
    tag('og:site_name', 'Birthdayly'),
    tag('og:title', title),
    tag('og:description', p.description),
    tag('og:image', p.image),
    tag('og:image:width', '1200'),
    tag('og:image:height', '630'),
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="description" content="${escapeHtml(p.description)}">`,
  ].join('\n');
}

/** O "b-vela" do ícone da app (ui/assets/branding/app_icon.svg), sobre o gradiente do .mark. */
const appMark =
  '<svg viewBox="0 0 100 100" width="44" height="44">' +
  '<path d="M33 11C38.5 18 40 22 40 25.5A7 7 0 0 1 26 25.5C26 22 27.5 18 33 11Z" fill="#FFF3D6"/>' +
  '<path d="M33 18.5C35.6 22 36.3 24 36.3 25.6A3.3 3.3 0 0 1 29.7 25.6C29.7 24 30.4 22 33 18.5Z" fill="#F4A25C"/>' +
  '<rect x="32" y="33" width="2" height="4" rx="1" fill="#fff"/><rect x="27" y="37" width="12" height="48" rx="4" fill="#fff"/>' +
  '<circle cx="54" cy="66" r="15" fill="none" stroke="#fff" stroke-width="12"/></svg>';

/**
 * Página simples com o aspeto da app (cores Birthdayly, claro/escuro). Usada nas
 * páginas abertas a partir de links: convites e recuperação de palavra-passe.
 * [body] e [script] já têm de vir escapados.
 */
export function htmlPage({
  title,
  body,
  script = '',
  preview,
  mark = `<div class="mark" aria-hidden="true">${appMark}</div>`,
}: {
  title: string;
  body: string;
  script?: string;
  preview?: LinkPreview;
  /** Imagem do topo (por omissão o bolo), já escapada. */
  mark?: string;
}): string {
  return `<!doctype html>
<html lang="pt-PT"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>${escapeHtml(title)}</title>${preview ? `\n${previewTags(title, preview)}` : ''}
<style>
:root{--bg:#fcf8f5;--fg:#281c1a;--card:#fff;--muted:#746560;--border:#e9e3df;--primary:#f05560;--on-primary:#fffbf7;--accent:#f8eaf3}
@media (prefers-color-scheme:dark){:root{--bg:#191210;--fg:#f4ede8;--card:#241c19;--muted:#a99b94;--border:#ffffff1a;--primary:#fa686a;--on-primary:#150a08;--accent:#3e2d38}}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px 16px;background:var(--bg);color:var(--fg);font-family:system-ui,-apple-system,"Segoe UI",sans-serif;line-height:1.5}
main{width:100%;max-width:420px;background:var(--card);border:1px solid var(--border);border-radius:24px;padding:28px 24px;text-align:center}
.mark{width:56px;height:56px;margin:0 auto 16px;border-radius:18px;display:grid;place-items:center;font-size:28px;background:linear-gradient(135deg,#f05560,#e662a8 55%,#ab8be3)}
img.mark{display:block;object-fit:cover;border-radius:50%}
h1{font-family:Georgia,"Times New Roman",serif;font-weight:600;font-size:26px;margin:0 0 8px}
p{margin:0 0 12px;color:var(--muted)}
.btn{display:block;width:100%;margin-top:12px;padding:14px 18px;border-radius:14px;border:1px solid var(--border);background:transparent;color:var(--fg);font:inherit;font-weight:600;text-decoration:none;cursor:pointer}
.btn.primary{background:var(--primary);border-color:var(--primary);color:var(--on-primary)}
.code{margin:16px 0 4px;padding:14px;border-radius:14px;background:var(--accent);font:600 24px/1.2 ui-monospace,Menlo,monospace;letter-spacing:3px}
.small{font-size:14px;margin-top:20px}
.quote{margin:20px 0 8px;padding:20px;border-radius:18px;background:var(--accent);color:var(--fg);text-align:left;white-space:pre-wrap;overflow-wrap:anywhere;font:400 18px/1.55 Georgia,"Times New Roman",serif}
.from{text-align:right;font-style:italic}
.field{display:block;width:100%;margin-top:12px;padding:14px;border-radius:14px;border:1px solid var(--border);background:var(--bg);color:var(--fg);font:inherit;font-size:16px}
.fields{display:flex;gap:12px}.fields .field{flex:1}
.media{display:block;width:100%;margin:20px 0 0;border-radius:18px;background:var(--accent)}
audio.media{background:none}
[hidden]{display:none!important}
</style></head><body><main>
${mark}
${body}
</main>${script ? `<script>${script}</script>` : ''}</body></html>`;
}

/** Texto como literal JavaScript, seguro dentro de <script>. */
export function jsString(s: string): string {
  return JSON.stringify(s).replace(/</g, '\\u003c');
}
