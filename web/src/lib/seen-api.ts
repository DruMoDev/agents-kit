// POST /api/seen {repo, prs: number[]} => 204. El repo debe ser uno de los descubiertos.
// Si KV no deja escribir (límite de 1/s por clave) => 503 con Retry-After.
import { GitHubError, type Repo } from "./github";
import { markSeen, type KVLike } from "./seen";

const MAX_IDS = 1000;

function text(status: number, body: string): Response {
  return new Response(body, { status, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
}

export async function handleSeen(request: Request, kv: KVLike | undefined, loadRepos: () => Promise<Repo[]>): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return text(400, "Cuerpo JSON inválido");
  }
  const { repo, prs } = (body ?? {}) as { repo?: unknown; prs?: unknown };
  const validPrs =
    Array.isArray(prs) && prs.length <= MAX_IDS && prs.every((n) => typeof n === "number" && Number.isInteger(n) && n > 0);
  if (typeof repo !== "string" || !repo || !validPrs) return text(400, "Se espera {repo, prs: [números de PR]}");
  if (!kv) return text(503, "Falta el almacén SEEN");

  let repos: Repo[];
  try {
    repos = await loadRepos();
  } catch (err) {
    if (err instanceof GitHubError) return text(502, err.message);
    throw err;
  }
  if (!repos.some((r) => r.name === repo)) return text(404, "Esa app no existe");

  try {
    await markSeen(kv, repo, prs as number[]);
  } catch {
    // KV limita a 1 escritura por segundo y clave (429) o puede fallar: el cliente reintenta
    return new Response("No se pudo guardar ahora mismo. Inténtalo de nuevo en unos segundos.", {
      status: 503,
      headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store", "retry-after": "1" },
    });
  }
  return new Response(null, { status: 204, headers: { "cache-control": "no-store" } });
}
