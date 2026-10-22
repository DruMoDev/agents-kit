// Markdown mínimo y propio para la versión extendida de las entradas.
// Todo el texto se escapa; solo se generan las etiquetas de abajo:
// párrafos, listas con guion, bloques de código (``` o ~~~), `código`, **negrita**,
// enlaces http(s) e imágenes (relativas por imgUrl, o https directas).

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

const HTTP_URL = /^https?:\/\/[^\s"'<>`]+$/i;
const HTTPS_URL = /^https:\/\/[^\s"'<>`]+$/i;
const RELATIVE_PATH = /^(?![a-z][a-z0-9+.-]*:)(?!\/\/)[^\s"'<>`\\]+$/i;

// código | imagen | enlace | negrita
const INLINE = /`([^`]+)`|!\[([^\]]*)\]\(([^)\s]*)(?:\s+"[^"]*")?\)|\[([^\]]+)\]\(([^)\s]*)(?:\s+"[^"]*")?\)|\*\*(.+?)\*\*/g;

function renderInline(text: string, imgUrl: (path: string) => string, allowLinks = true): string {
  let out = "";
  let last = 0;
  for (const m of text.matchAll(INLINE)) {
    const [whole, code, alt, src, label, href, bold] = m;
    const start = m.index ?? 0;
    out += escapeHtml(text.slice(last, start));
    last = start + whole.length;
    if (code !== undefined) {
      out += `<code>${escapeHtml(code)}</code>`;
    } else if (src !== undefined) {
      let url: string | null = null;
      if (HTTPS_URL.test(src)) url = src;
      else if (RELATIVE_PATH.test(src)) url = imgUrl(src.replace(/^\.\//, ""));
      out += url
        ? `<img src="${escapeHtml(url)}" alt="${escapeHtml(alt ?? "")}" loading="lazy">`
        : escapeHtml(whole);
    } else if (label !== undefined) {
      out +=
        allowLinks && HTTP_URL.test(href ?? "")
          ? `<a href="${escapeHtml(href!)}" rel="noopener noreferrer" target="_blank">${renderInline(label, imgUrl, false)}</a>`
          : escapeHtml(whole);
    } else if (bold !== undefined) {
      out += `<strong>${renderInline(bold, imgUrl, allowLinks)}</strong>`;
    }
  }
  return out + escapeHtml(text.slice(last));
}

export function renderMarkdown(body: string, imgUrl: (path: string) => string): string {
  const lines = String(body ?? "").replace(/\r\n?/g, "\n").split("\n");
  const blocks: string[] = [];
  let para: string[] = [];
  let list: string[] = [];

  const flush = () => {
    if (para.length) blocks.push(`<p>${renderInline(para.join("\n"), imgUrl)}</p>`);
    if (list.length) blocks.push(`<ul>${list.map((li) => `<li>${renderInline(li, imgUrl)}</li>`).join("")}</ul>`);
    para = [];
    list = [];
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const fence = /^(```|~~~)\s*([\w+-]*)/.exec(line);
    if (fence) {
      flush();
      const code: string[] = [];
      i++;
      while (i < lines.length && !lines[i].startsWith(fence[1])) code.push(lines[i++]);
      const lang = fence[2] ? ` class="language-${escapeHtml(fence[2])}"` : "";
      blocks.push(`<pre><code${lang}>${escapeHtml(code.join("\n"))}</code></pre>`);
      continue;
    }
    if (line.trim() === "") {
      flush();
      continue;
    }
    const item = /^\s*[-*] (.*)$/.exec(line);
    if (item) {
      if (para.length) flush();
      list.push(item[1]);
      continue;
    }
    if (list.length) flush();
    para.push(line);
  }
  flush();
  return blocks.join("\n");
}
