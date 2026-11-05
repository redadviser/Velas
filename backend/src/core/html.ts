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
  '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,400;9..144,600&family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap">';

/** O "b-vela" do ícone da app (ui/assets/branding/app_icon.svg). */
const appMark =
  '<svg viewBox="0 0 100 100" width="20" height="20" aria-hidden="true">' +
  '<path d="M33 11C38.5 18 40 22 40 25.5A7 7 0 0 1 26 25.5C26 22 27.5 18 33 11Z" fill="#FFF3D6"/>' +
  '<path d="M33 18.5C35.6 22 36.3 24 36.3 25.6A3.3 3.3 0 0 1 29.7 25.6C29.7 24 30.4 22 33 18.5Z" fill="#F4A25C"/>' +
  '<rect x="32" y="33" width="2" height="4" rx="1" fill="#fff"/><rect x="27" y="37" width="12" height="48" rx="4" fill="#fff"/>' +
  '<circle cx="54" cy="66" r="15" fill="none" stroke="#fff" stroke-width="12"/></svg>';

/** Cores da app (claro/escuro), letras, cabeçalho e rodapé: comum a todas as páginas. */
const baseCss = `:root{--bg:#fcf8f5;--fg:#281c1a;--text:#3d2f2c;--card:#fff;--muted:#7a6a65;--border:#ece5e1;--primary:#f05560;--primary-hover:#e04450;
--on-primary:#fff;--accent:#f8eaf3;--shadow:0 1px 2px rgba(40,28,26,.04),0 6px 24px rgba(40,28,26,.06);
--serif:Fraunces,Georgia,"Times New Roman",serif;--sans:"Plus Jakarta Sans",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
@media (prefers-color-scheme:dark){:root{--bg:#191210;--fg:#f4ede8;--text:#e3d8d3;--card:#211816;--muted:#a3948e;--border:#3a2f2c;
--primary:#fa686a;--primary-hover:#ff7d7f;--on-primary:#1a0d0b;--accent:#3e2d38;--shadow:none}}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;min-height:100vh;display:flex;flex-direction:column;background:var(--bg);color:var(--text);font:400 16px/1.6 var(--sans);-webkit-font-smoothing:antialiased}
a{color:var(--primary)}
.wrap{width:100%;max-width:720px;margin:0 auto;padding:0 20px}
.top{background:var(--card);border-bottom:1px solid var(--border)}
.bar{height:60px;display:flex;align-items:center}
.brand{display:inline-flex;align-items:center;gap:10px;color:var(--fg);font:600 19px/1 var(--serif);letter-spacing:-.01em}
.brand i{width:30px;height:30px;border-radius:9px;display:grid;place-items:center;background:linear-gradient(135deg,#f05560,#e662a8 55%,#ab8be3)}
.foot{padding-top:20px;padding-bottom:32px;border-top:1px solid var(--border);color:var(--muted);font-size:13px}
.foot nav{display:flex;flex-wrap:wrap;gap:6px 18px;margin-bottom:6px}
.foot a{color:var(--muted);text-decoration:none}.foot a:hover{color:var(--fg);text-decoration:underline}
[hidden]{display:none!important}
.trap{position:absolute;left:-9999px;width:1px;height:1px;opacity:0}
.field{display:block;width:100%;margin-top:6px;padding:12px 14px;min-height:48px;border-radius:12px;border:1px solid var(--border);background:var(--card);color:var(--fg);font:400 16px/1.4 var(--sans)}
.field:focus{outline:2px solid var(--primary);outline-offset:-1px;border-color:transparent}
.btn{display:block;width:100%;min-height:48px;margin-top:12px;padding:13px 18px;border-radius:12px;border:1px solid var(--border);background:var(--card);color:var(--fg);font:600 15px/1.3 var(--sans);text-align:center;text-decoration:none;cursor:pointer}
.btn.primary{background:var(--primary);border-color:var(--primary);color:var(--on-primary)}
.btn.primary:hover{background:var(--primary-hover);border-color:var(--primary-hover)}
.btn:disabled{opacity:.55;cursor:default}`;

/** Cabeçalho com a marca e rodapé, iguais em todas as páginas. */
function shell(o: { title: string; head?: string; css: string; main: string; footer: string; script?: string }): string {
  return `<!doctype html>
<html lang="pt-PT"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>${escapeHtml(o.title)}</title>${o.head ?? ''}
${fontsLink}
<style>
${baseCss}
${o.css}
</style></head><body>
<header class="top"><div class="wrap bar"><span class="brand"><i>${appMark}</i>Birthdayly</span></div></header>
${o.main}
<footer class="wrap foot">${o.footer}</footer>${o.script ? `<script>${o.script}</script>` : ''}</body></html>`;
}

const year = () => new Date().getFullYear();

/**
 * Página de uma ação aberta a partir de um link (convites, cartões, pedidos de
 * aniversário, recuperação da palavra-passe): um cartão ao centro. [body],
 * [mark] e [script] já têm de vir escapados.
 */
export function htmlPage({
  title,
  body,
  script = '',
  preview,
  mark = '',
}: {
  title: string;
  body: string;
  script?: string;
  preview?: LinkPreview;
  /** Imagem do topo do cartão (ex.: a fotografia de quem envia), já escapada. */
  mark?: string;
}): string {
  return shell({
    title,
    head: preview ? `\n${previewTags(title, preview)}` : '',
    css: `main{flex:1;display:grid;place-items:center;padding:32px 16px}
.card{width:100%;max-width:440px;background:var(--card);border:1px solid var(--border);border-radius:16px;box-shadow:var(--shadow);padding:32px 28px;text-align:center}
@media (max-width:420px){.card{padding:28px 20px}}
.mark{display:block;width:64px;height:64px;margin:0 auto 18px;border-radius:50%;object-fit:cover}
h1{margin:0 0 10px;color:var(--fg);font:600 26px/1.25 var(--serif);letter-spacing:-.01em}
p{margin:0 0 12px;color:var(--muted)}
.small{margin-top:18px;font-size:14px}
.code{margin:18px 0 6px;padding:14px;border-radius:12px;background:var(--accent);color:var(--fg);font:600 24px/1.2 ui-monospace,Menlo,monospace;letter-spacing:3px}
.quote{margin:20px 0 8px;padding:20px 22px;border-radius:12px;background:var(--accent);color:var(--fg);text-align:left;white-space:pre-wrap;overflow-wrap:anywhere;font:400 18px/1.6 var(--serif)}
.from{text-align:right;font-style:italic}
.fields{display:flex;gap:12px}.fields .field{flex:1}
form .field{margin-top:12px}
.media{display:block;width:100%;margin:20px 0 0;border-radius:12px;background:var(--accent)}
audio.media{background:none}`,
    main: `<main><div class="card">
${mark}
${body}
</div></main>`,
    footer: `<nav><a href="/legal/termos">Termos de Utilização</a><a href="/legal/apagar-conta">Eliminar a conta</a></nav><div>© ${year()} Birthdayly</div>`,
    script,
  });
}

/**
 * Página de documento (Termos, eliminar a conta): o texto numa coluna de
 * leitura, com índice e cláusulas numeradas quando [numbered]. [body], [footer]
 * e [script] já têm de vir escapados.
 */
export function docPage({
  title,
  heading,
  meta,
  toc,
  numbered = false,
  body,
  footer,
  script = '',
}: {
  title: string;
  heading: string;
  meta?: string;
  /** Títulos das secções, para o índice (só com [numbered]). */
  toc?: string[];
  numbered?: boolean;
  body: string;
  footer: string;
  script?: string;
}): string {
  const index = numbered && toc?.length
    ? `<nav class="toc" aria-label="Índice"><p>Índice</p><ol>${toc.map((t, i) => `<li><a href="#s${i + 1}">${escapeHtml(t)}</a></li>`).join('')}</ol></nav>`
    : '';
  return shell({
    title,
    css: `main.wrap{flex:1;padding-top:44px;padding-bottom:56px}
@media (max-width:600px){main.wrap{padding-top:28px}.numbered section p{padding-left:38px}}
h1{margin:0;color:var(--fg);font:600 34px/1.2 var(--serif);letter-spacing:-.015em}
@media (max-width:600px){h1{font-size:28px}}
.meta{margin:8px 0 0;color:var(--muted);font-size:14px}
.lead{margin:20px 0 0;font-size:17px;color:var(--text)}
.toc{margin:28px 0 8px;padding:16px 20px;background:var(--card);border:1px solid var(--border);border-radius:12px}
.toc p{margin:0 0 8px;color:var(--muted);font-size:13px;font-weight:600}
.toc ol{margin:0;padding-left:22px;columns:2;column-gap:32px;font-size:15px}
@media (max-width:600px){.toc ol{columns:1}}
.toc li{break-inside:avoid;padding:3px 0}.toc li::marker{color:var(--muted)}
.toc a{color:var(--text);text-decoration:none}.toc a:hover{color:var(--primary);text-decoration:underline}
section{margin-top:32px;scroll-margin-top:16px}
h2{margin:0 0 10px;color:var(--fg);font:600 18px/1.4 var(--sans)}
section p{margin:0 0 10px}
ol.steps{margin:0 0 10px;padding-left:22px}ol.steps li{margin-bottom:6px;padding-left:4px}
.numbered{counter-reset:sec}
.numbered section{counter-increment:sec;counter-reset:par}
.numbered h2::before{content:counter(sec) ". "}
.numbered section p{counter-increment:par;position:relative;padding-left:44px}
.numbered section p::before{content:counter(sec) "." counter(par) ".";position:absolute;left:0;color:var(--muted);font-variant-numeric:tabular-nums}
.panel{margin-top:36px;padding:24px;background:var(--card);border:1px solid var(--border);border-radius:16px;box-shadow:var(--shadow)}
.panel h2{margin-bottom:4px}.panel p{color:var(--muted);margin:0 0 14px}
.panel label{display:block;margin-top:4px;color:var(--fg);font-size:14px;font-weight:600}
.panel .btn{width:auto;display:inline-block;padding:13px 22px;background:var(--primary);border-color:var(--primary);color:var(--on-primary)}
.small{font-size:14px;color:var(--muted)}`,
    main: `<main class="wrap"><article${numbered ? ' class="numbered"' : ''}>
<h1>${escapeHtml(heading)}</h1>${meta ? `\n<p class="meta">${escapeHtml(meta)}</p>` : ''}
${index}
${body}
</article></main>`,
    footer,
    script,
  });
}

/** Texto como literal JavaScript, seguro dentro de <script>. */
export function jsString(s: string): string {
  return JSON.stringify(s).replace(/</g, '\\u003c');
}

