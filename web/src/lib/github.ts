// Repos con agents-kit y sus changelogs: una consulta GraphQL (paginada) cacheada 5 minutos
// en KV (clave cache:repos:v1) y, por delante, unos segundos en la memoria del isolate;
// o fixtures/repos.json con DATA_SOURCE=fixtures.
// No se usa la Cache API: no funciona en *.workers.dev ni detrás de Cloudflare Access.
import fixtureRepos from "../../fixtures/repos.json";
import { parseChangelog, type Day } from "./changelog";
import type { FetchLike, WebEnv } from "./env";

export interface Repo {
  name: string;
  url: string;
  isPrivate: boolean;
  days: Day[];
  lastDate: string | null;
}

/** Error de GitHub con mensaje en español apto para mostrar (nunca incluye el token). */
export class GitHubError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GitHubError";
  }
}

/** Lo mínimo de KVNamespace que usa la caché de la lista. */
export interface CacheKV {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

export interface FetchReposOptions {
  fetch?: FetchLike;
  /** null = sin KV; por defecto env.SEEN. */
  kv?: CacheKV | null;
  /** true = saltar las cachés y reescribirlas (?refrescar=1). */
  refresh?: boolean;
  /** Reloj en ms (tests). */
  now?: () => number;
}

const GRAPHQL_URL = "https://api.github.com/graphql";
export const REPOS_CACHE_KEY = "cache:repos:v1";
const KV_TTL_S = 300;
const MEMORY_TTL_MS = 30_000;
const MAX_PAGES = 20;

let memory: { repos: Repo[]; expires: number } | null = null;

/** Vacía la caché en memoria del isolate (tests). */
export function resetRepoCache(): void {
  memory = null;
}

const QUERY = `query($after: String) {
  viewer {
    repositories(first: 100, after: $after, ownerAffiliations: OWNER, isArchived: false, orderBy: {field: PUSHED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        name
        url
        isPrivate
        pushedAt
        marker: object(expression: "HEAD:.agents-kit.json") { __typename }
        changelog: object(expression: "HEAD:CHANGELOG.md") { ... on Blob { text } }
      }
    }
  }
}`;

interface RepoNode {
  name: string;
  url: string;
  isPrivate: boolean;
  pushedAt?: string | null;
  marker: { __typename: string } | null;
  changelog: { text?: string | null } | null;
}

interface GraphQLPage {
  data?: { viewer?: { repositories?: { pageInfo: { hasNextPage: boolean; endCursor: string | null }; nodes: (RepoNode | null)[] } } };
  errors?: { message?: string; type?: string; path?: (string | number)[] }[];
}

function toRepo(node: RepoNode): Repo {
  let days: Day[] = [];
  try {
    days = parseChangelog(node.changelog?.text ?? "");
  } catch {
    days = [];
  }
  return { name: node.name, url: node.url, isPrivate: node.isPrivate, days, lastDate: days[0]?.date ?? null };
}

async function queryPage(token: string, after: string | null, doFetch: FetchLike): Promise<GraphQLPage> {
  let res: Response;
  try {
    res = await doFetch(GRAPHQL_URL, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
        "user-agent": "agents-kit-changelogs",
      },
      body: JSON.stringify({ query: QUERY, variables: { after } }),
    });
  } catch {
    throw new GitHubError("No se pudo conectar con GitHub. Inténtalo de nuevo en unos minutos.");
  }
  if (res.status === 401 || res.status === 403) {
    throw new GitHubError("GitHub rechazó el token: no es válido, ha caducado o no tiene permisos de lectura.");
  }
  if (!res.ok) throw new GitHubError(`GitHub respondió con un error (${res.status}). Inténtalo de nuevo en unos minutos.`);
  let body: GraphQLPage;
  try {
    body = (await res.json()) as GraphQLPage;
  } catch {
    throw new GitHubError("GitHub devolvió una respuesta ilegible.");
  }
  if (!body.data?.viewer?.repositories) {
    throw new GitHubError("GitHub no devolvió los repositorios: revisa que el token tenga permiso de lectura de contenidos y metadatos.");
  }
  // errores parciales: los repos que fallan llegan como null y se omiten; el resto se muestra
  if (body.errors?.length) {
    const detail = body.errors.map((e) => `${(e.path ?? []).join(".") || "?"}: ${e.message ?? e.type ?? "error"}`).join("; ");
    console.warn(`GitHub devolvió ${body.errors.length} error(es) parciales; se omiten esos repos. ${detail}`);
  }
  return body;
}

async function queryRepos(token: string, doFetch: FetchLike): Promise<Repo[]> {
  const repos: Repo[] = [];
  let after: string | null = null;
  for (let i = 0; i < MAX_PAGES; i++) {
    const page = await queryPage(token, after, doFetch);
    const { pageInfo, nodes } = page.data!.viewer!.repositories!;
    for (const node of nodes) if (node?.marker) repos.push(toRepo(node));
    if (!pageInfo.hasNextPage || !pageInfo.endCursor) break;
    after = pageInfo.endCursor;
  }
  return repos;
}

function isRepoList(v: unknown): v is Repo[] {
  return Array.isArray(v) && v.every((r) => r && typeof r.name === "string" && Array.isArray(r.days));
}

export async function fetchRepos(env: WebEnv, opts: FetchReposOptions = {}): Promise<Repo[]> {
  if (env.DATA_SOURCE === "fixtures") return structuredClone(fixtureRepos as Repo[]);
  const token = env.GITHUB_TOKEN?.trim();
  if (!token) throw new GitHubError("Falta el token de GitHub (secreto GITHUB_TOKEN).");

  const now = opts.now ?? Date.now;
  const kv = opts.kv === undefined ? env.SEEN ?? null : opts.kv;

  if (!opts.refresh) {
    if (memory && memory.expires > now()) return structuredClone(memory.repos);
    if (kv) {
      try {
        const raw = await kv.get(REPOS_CACHE_KEY);
        const cached: unknown = raw ? JSON.parse(raw) : null;
        if (isRepoList(cached)) {
          memory = { repos: cached, expires: now() + MEMORY_TTL_MS };
          return structuredClone(cached);
        }
      } catch {
        // KV caído o con basura: se consulta GitHub
      }
    }
  }

  const repos = await queryRepos(token, opts.fetch ?? fetch);
  memory = { repos, expires: now() + MEMORY_TTL_MS };
  if (kv) {
    try {
      await kv.put(REPOS_CACHE_KEY, JSON.stringify(repos), { expirationTtl: KV_TTL_S });
    } catch {
      // límite de escritura o KV caído: la memoria basta hasta la próxima
    }
  }
  return structuredClone(repos);
}
