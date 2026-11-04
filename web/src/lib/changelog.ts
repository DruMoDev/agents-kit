// Parser de CHANGELOG.md. Refleja la semántica de `scripts/kit-changelog.sh validar`
// (el contrato está en tests/fixtures/changelog/), pero nunca lanza: descarta solo lo malformado.

export const ENTRY_TYPES = ["Nuevo", "Mejora", "Arreglo", "Interno"] as const;
export type EntryType = (typeof ENTRY_TYPES)[number];

interface Entry {
  type: EntryType;
  title: string;
  pr: number;
  url: string;
  date: string;
  /** Markdown de la versión extendida (puede estar vacío). */
  body: string;
}

export interface Day {
  date: string;
  entries: Entry[];
}

const DATE_LINE = /^## (\d{4})-(\d{2})-(\d{2})$/;
const ENTRY_LINE = /^### (Nuevo|Mejora|Arreglo|Interno): (.*)$/;
const LINK_TAIL = /^(\d+)\]\((https:\/\/github\.com\/[^/ ()]+\/[^/ ()]+\/pull\/(\d+))\)$/;
const SEPARATOR = " · [#";

function validDate(y: number, m: number, d: number): boolean {
  if (m < 1 || m > 12 || d < 1) return false;
  const leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1] ?? 0;
  return d <= days;
}

function parseEntryLine(line: string, date: string): Entry | null {
  const [, type, rest] = ENTRY_LINE.exec(line) ?? [];
  if (type === undefined || rest === undefined) return null;
  // el último " · [#" separa el título del enlace (el título puede contener " · ")
  const pos = rest.lastIndexOf(SEPARATOR);
  if (pos < 0) return null;
  const title = rest.slice(0, pos).trim();
  if (!title) return null;
  const [, prText, url, prInUrl] = LINK_TAIL.exec(rest.slice(pos + SEPARATOR.length)) ?? [];
  if (prText === undefined || url === undefined || prInUrl === undefined) return null;
  const pr = Number(prText);
  if (pr !== Number(prInUrl)) return null;
  return { type: type as EntryType, title, pr, url, date, body: "" };
}

export function parseChangelog(text: string | null | undefined): Day[] {
  const byDate = new Map<string, Entry[]>();
  let date: string | null = null; // fecha válida en curso (null = las entradas se descartan)
  let current: { entry: Entry; lines: string[] } | null = null;
  let inComment = false;
  let fence = "";

  const close = () => {
    if (!current) return;
    const lines = current.lines;
    while (lines[0]?.trim() === "") lines.shift();
    while (lines.at(-1)?.trim() === "") lines.pop();
    current.entry.body = lines.join("\n");
    current = null;
  };

  for (const raw of (text ?? "").split("\n")) {
    const line = raw.replace(/\r$/, "");

    // bloques de código: nada de dentro cuenta como fecha, entrada o comentario
    if (!inComment) {
      if (fence) {
        if (line.startsWith(fence)) fence = "";
        current?.lines.push(line.replace(/\s+$/, ""));
        continue;
      }
      if (line.startsWith("```") || line.startsWith("~~~")) {
        fence = line.slice(0, 3);
        current?.lines.push(line.replace(/\s+$/, ""));
        continue;
      }
    }

    // quitar comentarios HTML (también de varias líneas)
    let vis = "";
    let rest = line;
    while (rest !== "") {
      if (inComment) {
        const p = rest.indexOf("-->");
        if (p < 0) break;
        rest = rest.slice(p + 3);
        inComment = false;
      } else {
        const p = rest.indexOf("<!--");
        if (p < 0) {
          vis += rest;
          break;
        }
        vis += rest.slice(0, p);
        rest = rest.slice(p + 4);
        inComment = true;
      }
    }
    vis = vis.replace(/\s+$/, "");

    if (vis.startsWith("## ")) {
      close();
      const [, y, mo, d] = DATE_LINE.exec(vis) ?? [];
      date = y && mo && d && validDate(Number(y), Number(mo), Number(d)) ? `${y}-${mo}-${d}` : null;
      continue;
    }
    if (vis.startsWith("### ")) {
      close();
      const entry = date ? parseEntryLine(vis, date) : null;
      if (entry && date) {
        let list = byDate.get(date);
        if (!list) {
          list = [];
          byDate.set(date, list);
        }
        list.push(entry);
        current = { entry, lines: [] };
      }
      continue;
    }
    // una línea que era solo comentario no deja rastro en el cuerpo
    if (vis === "" && line.trim() !== "") continue;
    current?.lines.push(vis);
  }
  close();

  return [...byDate.entries()]
    .sort(([a], [b]) => (a < b ? 1 : a > b ? -1 : 0))
    .map(([d, entries]) => ({ date: d, entries }));
}
