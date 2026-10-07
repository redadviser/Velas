/** Escapa texto para HTML (conteúdo e atributos). */
export function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

/**
 * Página simples com o aspeto da app (cores Velas, claro/escuro). Usada nas
 * páginas abertas a partir de links: convites e recuperação de palavra-passe.
 * [body] e [script] já têm de vir escapados.
 */
export function htmlPage({ title, body, script = '' }: { title: string; body: string; script?: string }): string {
  return `<!doctype html>
<html lang="pt-PT"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>${escapeHtml(title)}</title>
<style>
:root{--bg:#fcf8f5;--fg:#281c1a;--card:#fff;--muted:#746560;--border:#e9e3df;--primary:#f05560;--on-primary:#fffbf7;--accent:#f8eaf3}
@media (prefers-color-scheme:dark){:root{--bg:#191210;--fg:#f4ede8;--card:#241c19;--muted:#a99b94;--border:#ffffff1a;--primary:#fa686a;--on-primary:#150a08;--accent:#3e2d38}}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px 16px;background:var(--bg);color:var(--fg);font-family:system-ui,-apple-system,"Segoe UI",sans-serif;line-height:1.5}
main{width:100%;max-width:420px;background:var(--card);border:1px solid var(--border);border-radius:24px;padding:28px 24px;text-align:center}
.mark{width:56px;height:56px;margin:0 auto 16px;border-radius:18px;display:grid;place-items:center;font-size:28px;background:linear-gradient(135deg,#f05560,#ab8be3)}
h1{font-family:Georgia,"Times New Roman",serif;font-weight:600;font-size:26px;margin:0 0 8px}
p{margin:0 0 12px;color:var(--muted)}
.btn{display:block;width:100%;margin-top:12px;padding:14px 18px;border-radius:14px;border:1px solid var(--border);background:transparent;color:var(--fg);font:inherit;font-weight:600;text-decoration:none;cursor:pointer}
.btn.primary{background:var(--primary);border-color:var(--primary);color:var(--on-primary)}
.code{margin:16px 0 4px;padding:14px;border-radius:14px;background:var(--accent);font:600 24px/1.2 ui-monospace,Menlo,monospace;letter-spacing:3px}
.small{font-size:14px;margin-top:20px}
</style></head><body><main>
<div class="mark" aria-hidden="true">🎂</div>
${body}
</main>${script ? `<script>${script}</script>` : ''}</body></html>`;
}

/** Texto como literal JavaScript, seguro dentro de <script>. */
export function jsString(s: string): string {
  return JSON.stringify(s).replace(/</g, '\\u003c');
}
