// Ayudas de presentación: fechas en español, orden de las apps y filtro por tipo.
import { ENTRY_TYPES, type Day, type EntryType } from "./changelog";
import type { Repo } from "./github";

const MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
const SHORT = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"];

function parts(iso: string): [number, number, number] | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso ?? "");
  if (!m) return null;
  const month = Number(m[2]);
  if (month < 1 || month > 12) return null;
  return [Number(m[1]), month, Number(m[3])];
}

/** "2026-10-20" => "20 de octubre de 2026" */
export function formatDate(iso: string): string {
  const p = parts(iso);
  return p ? `${p[2]} de ${MONTHS[p[1] - 1]} de ${p[0]}` : iso;
}

/** "2026-10-05" => "5 oct 2026" */
export function formatShortDate(iso: string): string {
  const p = parts(iso);
  return p ? `${p[2]} ${SHORT[p[1] - 1]} ${p[0]}` : iso;
}

export interface AppItem {
  repo: Repo;
  unseen: number;
}

/** Primero las apps con más cambios sin ver; luego por fecha del último cambio; sin cambios al final. */
export function sortApps<T extends AppItem>(items: T[]): T[] {
  return [...items].sort((a, b) => {
    if (b.unseen !== a.unseen) return b.unseen - a.unseen;
    const da = a.repo.lastDate ?? "";
    const db = b.repo.lastDate ?? "";
    if (da !== db) return da < db ? 1 : -1;
    return a.repo.name.localeCompare(b.repo.name);
  });
}

export function parseTypeFilter(value: string | null): EntryType | null {
  return value && (ENTRY_TYPES as readonly string[]).includes(value) ? (value as EntryType) : null;
}

export function filterDays(days: Day[], type: EntryType | null): Day[] {
  if (!type) return days;
  return days.map((d) => ({ ...d, entries: d.entries.filter((e) => e.type === type) })).filter((d) => d.entries.length > 0);
}

export function countLabel(n: number, one: string, many: string): string {
  return `${n} ${n === 1 ? one : many}`;
}

/** Color y descripción de cada tipo (las clases CSS usan el slug). */
export const TYPE_META: Record<EntryType, { slug: string; hint: string }> = {
  Nuevo: { slug: "nuevo", hint: "Algo que antes no existía" },
  Mejora: { slug: "mejora", hint: "Algo que ya existía, ahora mejor" },
  Arreglo: { slug: "arreglo", hint: "Algo que fallaba y ya funciona" },
  Interno: { slug: "interno", hint: "Cambios por dentro, sin efecto visible" },
};

/** La URL actual sin `refrescar` (ruta + query), para redirigir tras refrescar. */
export function withoutRefresh(url: URL): string {
  const params = new URLSearchParams(url.search);
  params.delete("refrescar");
  const qs = params.toString();
  return url.pathname + (qs ? `?${qs}` : "");
}
