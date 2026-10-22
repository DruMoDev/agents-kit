// Estado "visto" por entrada en KV: clave `seen:<repo>`, valor `{"ids": [números de PR]}`.
import type { Repo } from "./github";

/** Lo mínimo de KVNamespace que se usa (permite fakes en los tests). */
export interface KVLike {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

const key = (repo: string) => `seen:${repo}`;
const isPr = (n: unknown): n is number => typeof n === "number" && Number.isInteger(n) && n > 0;

export async function getSeen(kv: KVLike, repo: string): Promise<Set<number>> {
  const raw = await kv.get(key(repo));
  if (!raw) return new Set();
  try {
    const ids = (JSON.parse(raw) as { ids?: unknown })?.ids;
    return new Set(Array.isArray(ids) ? ids.filter(isPr) : []);
  } catch {
    return new Set();
  }
}

/** Añade `prs` a lo ya visto (leer, unir, escribir): nunca borra ids. */
export async function markSeen(kv: KVLike, repo: string, prs: number[]): Promise<void> {
  const seen = await getSeen(kv, repo);
  const before = seen.size;
  for (const pr of prs) if (isPr(pr)) seen.add(pr);
  if (seen.size === before && before > 0) return;
  await kv.put(key(repo), JSON.stringify({ ids: [...seen].sort((a, b) => a - b) }));
}

export function unseenCount(repo: Repo, seen: Set<number>): number {
  let n = 0;
  for (const day of repo.days) for (const e of day.entries) if (!seen.has(e.pr)) n++;
  return n;
}
