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

/** As letras da app: Fraunces nos títulos, Plus Jakarta Sans no texto. */
const fontsLink =
  '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' +
  '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600&family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap">';

/** As cores da app (claro/escuro) e as letras, comuns a todas as páginas. */
const baseCss = `:root{--bg:#fcf8f5;--fg:#281c1a;--card:#fff;--muted:#746560;--border:#e9e3df;--primary:#f05560;--on-primary:#fffbf7;--accent:#f8eaf3;
--serif:Fraunces,Georgia,"Times New Roman",serif;--sans:"Plus Jakarta Sans",system-ui,-apple-system,"Segoe UI",sans-serif}
@media (prefers-color-scheme:dark){:root{--bg:#191210;--fg:#f4ede8;--card:#241c19;--muted:#a99b94;--border:#ffffff1a;--primary:#fa686a;--on-primary:#150a08;--accent:#3e2d38}}
*{box-sizing:border-box}`;

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
${fontsLink}
<style>
${baseCss}
body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px 16px;background:var(--bg);color:var(--fg);font-family:var(--sans);line-height:1.5}
main{width:100%;max-width:420px;background:var(--card);border:1px solid var(--border);border-radius:24px;padding:28px 24px;text-align:center}
.mark{width:56px;height:56px;margin:0 auto 16px;border-radius:18px;display:grid;place-items:center;font-size:28px;background:linear-gradient(135deg,#f05560,#e662a8 55%,#ab8be3)}
img.mark{display:block;object-fit:cover;border-radius:50%}
h1{font-family:var(--serif);font-weight:600;font-size:26px;margin:0 0 8px}
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
.trap{position:absolute;left:-9999px;width:1px;height:1px;opacity:0}
</style></head><body><main>
${mark}
${body}
</main>${script ? `<script>${script}</script>` : ''}</body></html>`;
}

/** Texto como literal JavaScript, seguro dentro de <script>. */
export function jsString(s: string): string {
  return JSON.stringify(s).replace(/</g, '\\u003c');
}

/**
 * Página de documento (Termos, apagar a conta): cabeçalho com a marca, o texto
 * numa coluna de leitura e um rodapé com os links legais. [body], [footer] e
 * [script] já têm de vir escapados.
 */
export function docPage({
  title,
  eyebrow,
  heading,
  meta,
  body,
  footer,
  script = '',
}: {
  title: string;
  eyebrow: string;
  heading: string;
  meta?: string;
  body: string;
  footer: string;
  script?: string;
}): string {
  const smallMark = appMark.replace('width="44" height="44"', 'width="22" height="22"');
  return `<!doctype html>
<html lang="pt-PT"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)}</title>
${fontsLink}
<style>
${baseCss}
body{margin:0;background:var(--bg);color:var(--fg);font:400 16px/1.7 var(--sans);-webkit-font-smoothing:antialiased}
a{color:var(--primary);text-underline-offset:3px}
.top{border-bottom:1px solid var(--border);background:var(--card)}
.bar,.page,.foot{max-width:760px;margin:0 auto;padding:0 24px}
.bar{height:64px;display:flex;align-items:center}
.brand{display:flex;align-items:center;gap:10px;color:var(--fg);text-decoration:none;font:600 20px/1 var(--serif)}
.brand span{width:32px;height:32px;border-radius:10px;display:grid;place-items:center;background:linear-gradient(135deg,#f05560,#e662a8 55%,#ab8be3)}
.page{padding-top:48px;padding-bottom:56px}
.eyebrow{margin:0 0 8px;color:var(--primary);font-size:13px;font-weight:700;letter-spacing:.08em;text-transform:uppercase}
h1{margin:0;font:600 40px/1.15 var(--serif);letter-spacing:-.01em}
.meta{margin:12px 0 0;color:var(--muted);font-size:14px}
.lead{margin:24px 0 0;font-size:18px;color:var(--fg)}
section{margin-top:36px;padding-top:28px;border-top:1px solid var(--border)}
h2{margin:0 0 12px;font:700 18px/1.4 var(--sans)}
p{margin:0 0 14px}
section p,section li{color:var(--fg)}
ul,ol{margin:0 0 14px;padding-left:22px}li{margin-bottom:8px}
.panel{margin-top:36px;padding:24px;border:1px solid var(--border);border-radius:20px;background:var(--card)}
.panel h2{margin-bottom:6px}.panel p{color:var(--muted)}
.field{display:block;width:100%;margin-top:8px;padding:13px 14px;border-radius:14px;border:1px solid var(--border);background:var(--bg);color:var(--fg);font:inherit}
.btn{display:inline-block;margin-top:14px;padding:13px 22px;border:0;border-radius:14px;background:var(--primary);color:var(--on-primary);font:600 16px/1 var(--sans);cursor:pointer}
.btn:disabled{opacity:.6}
.small{font-size:14px;color:var(--muted)}
.trap{position:absolute;left:-9999px;width:1px;height:1px;opacity:0}
[hidden]{display:none!important}
.foot{padding-top:24px;padding-bottom:40px;border-top:1px solid var(--border);color:var(--muted);font-size:14px}
.foot nav{display:flex;flex-wrap:wrap;gap:8px 20px;margin-bottom:10px}.foot a{color:var(--muted);text-decoration:none}.foot a:hover{color:var(--fg)}
@media (max-width:520px){h1{font-size:32px}.page{padding-top:32px}}
</style></head><body>
<header class="top"><div class="bar"><a class="brand" href="/legal/termos"><span aria-hidden="true">${smallMark}</span>Birthdayly</a></div></header>
<main class="page">
<p class="eyebrow">${escapeHtml(eyebrow)}</p>
<h1>${escapeHtml(heading)}</h1>${meta ? `\n<p class="meta">${escapeHtml(meta)}</p>` : ''}
${body}
</main>
<footer class="foot">${footer}</footer>${script ? `<script>${script}</script>` : ''}</body></html>`;
}
