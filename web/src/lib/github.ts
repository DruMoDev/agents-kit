// Repos con agents-kit y sus changelogs: una consulta GraphQL (paginada) cacheada 5 minutos,
// o fixtures/repos.json con DATA_SOURCE=fixtures.
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

/** Lo mínimo de la Cache API que se usa (caches.default en Workers). */
export interface CacheLike {
  match(key: Request | string): Promise<Response | undefined>;
  put(key: Request | string, res: Response): Promise<void>;
}

export interface FetchReposOptions {
  fetch?: FetchLike;
  /** null = sin caché; por defecto caches.default si existe. */
  cache?: CacheLike | null;
  /** true = saltar la caché (?refrescar=1). */
  refresh?: boolean;
}

const GRAPHQL_URL = "https://api.github.com/graphql";
const CACHE_KEY = "https://agents-kit-changelogs.internal/repos/v1";
const CACHE_TTL_S = 300;
const MAX_PAGES = 20;

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
  errors?: { message?: string; type?: string }[];
}

function defaultCache(): CacheLike | null {
  const c = (globalThis as { caches?: { default?: CacheLike } }).caches;
  return c?.default ?? null;
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
  if (body.errors?.length || !body.data?.viewer?.repositories) {
    throw new GitHubError("GitHub no devolvió los repositorios: revisa que el token tenga permiso de lectura de contenidos y metadatos.");
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

export async function fetchRepos(env: WebEnv, opts: FetchReposOptions = {}): Promise<Repo[]> {
  if (env.DATA_SOURCE === "fixtures") return structuredClone(fixtureRepos as Repo[]);
  const token = env.GITHUB_TOKEN?.trim();
  if (!token) throw new GitHubError("Falta el token de GitHub (secreto GITHUB_TOKEN).");

  const cache = opts.cache === undefined ? defaultCache() : opts.cache;
  if (cache && !opts.refresh) {
    try {
      const hit = await cache.match(CACHE_KEY);
      if (hit) return (await hit.json()) as Repo[];
    } catch {
      // caché ilegible: se consulta GitHub
    }
  }

  const repos = await queryRepos(token, opts.fetch ?? fetch);
  if (cache) {
    try {
      await cache.put(
        CACHE_KEY,
        new Response(JSON.stringify(repos), {
          headers: { "content-type": "application/json", "cache-control": `max-age=${CACHE_TTL_S}` },
        }),
      );
    } catch {
      // sin caché no pasa nada
    }
  }
  return repos;
}
