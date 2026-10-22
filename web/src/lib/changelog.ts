// Parser de CHANGELOG.md. Refleja la semántica de `scripts/kit-changelog.sh validar`
// (el contrato está en tests/fixtures/changelog/), pero nunca lanza: descarta solo lo malformado.

export const ENTRY_TYPES = ["Nuevo", "Mejora", "Arreglo", "Interno"] as const;
export type EntryType = (typeof ENTRY_TYPES)[number];

export interface Entry {
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
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];
  return d <= days;
}

function parseEntryLine(line: string, date: string): Entry | null {
  const m = ENTRY_LINE.exec(line);
  if (!m) return null;
  const rest = m[2];
  // el último " · [#" separa el título del enlace (el título puede contener " · ")
  const pos = rest.lastIndexOf(SEPARATOR);
  if (pos < 0) return null;
  const title = rest.slice(0, pos).trim();
  if (!title) return null;
  const tail = LINK_TAIL.exec(rest.slice(pos + SEPARATOR.length));
  if (!tail) return null;
  const pr = Number(tail[1]);
  if (pr !== Number(tail[3])) return null;
  return { type: m[1] as EntryType, title, pr, url: tail[2], date, body: "" };
}

export function parseChangelog(text: string): Day[] {
  const byDate = new Map<string, Entry[]>();
  let date: string | null = null; // fecha válida en curso (null = las entradas se descartan)
  let current: { entry: Entry; lines: string[] } | null = null;
  let inComment = false;
  let fence = "";

  const close = () => {
    if (!current) return;
    const lines = current.lines;
    while (lines.length && lines[0].trim() === "") lines.shift();
    while (lines.length && lines[lines.length - 1].trim() === "") lines.pop();
    current.entry.body = lines.join("\n");
    current = null;
  };

  for (const raw of String(text ?? "").split("\n")) {
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
      const m = DATE_LINE.exec(vis);
      date = m && validDate(Number(m[1]), Number(m[2]), Number(m[3])) ? `${m[1]}-${m[2]}-${m[3]}` : null;
      continue;
    }
    if (vis.startsWith("### ")) {
      close();
      const entry = date ? parseEntryLine(vis, date) : null;
      if (entry && date) {
        if (!byDate.has(date)) byDate.set(date, []);
        byDate.get(date)!.push(entry);
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
