import { describe, expect, it, vi } from "vitest";
import { fetchRepos, GitHubError, type Repo } from "../src/lib/github";
import fixtureRepos from "../fixtures/repos.json";

const CHANGELOG = [
  "# Changelog",
  "",
  "## 2026-10-18",
  "",
  "### Nuevo: Login · [#12](https://github.com/dru/app-a/pull/12)",
  "Texto.",
  "",
  "## 2026-10-01",
  "",
  "### Arreglo: Algo · [#3](https://github.com/dru/app-a/pull/3)",
].join("\n");

function node(name: string, opts: { marker?: boolean; changelog?: string | null; isPrivate?: boolean } = {}) {
  return {
    name,
    url: `https://github.com/dru/${name}`,
    isPrivate: opts.isPrivate ?? true,
    pushedAt: "2026-10-20T10:00:00Z",
    marker: opts.marker === false ? null : { __typename: "Blob" },
    changelog: opts.changelog === undefined ? null : opts.changelog === null ? null : { text: opts.changelog },
  };
}

function page(nodes: unknown[], hasNextPage = false, endCursor: string | null = null) {
  return { data: { viewer: { repositories: { pageInfo: { hasNextPage, endCursor }, nodes } } } };
}

function memoryCache() {
  const store = new Map<string, Response>();
  return {
    store,
    async match(key: Request | string) {
      const k = typeof key === "string" ? key : key.url;
      return store.get(k)?.clone();
    },
    async put(key: Request | string, res: Response) {
      store.set(typeof key === "string" ? key : key.url, res.clone());
    },
  };
}

const env = { GITHUB_TOKEN: "ghp_secreto" };

describe("fetchRepos (GraphQL)", () => {
  it("mapea la respuesta y filtra los repos sin marcador", async () => {
    const fetchMock = vi.fn(async () =>
      Response.json(
        page([
          node("app-a", { changelog: CHANGELOG }),
          node("sin-kit", { marker: false, changelog: CHANGELOG }),
          node("app-b", { changelog: null, isPrivate: false }),
          node("app-c", { changelog: "### Novedad: roto" }),
        ]),
      ),
    );
    const repos = await fetchRepos(env, { fetch: fetchMock, cache: null });
    expect(repos.map((r) => r.name)).toEqual(["app-a", "app-b", "app-c"]);
    const a = repos[0];
    expect(a.url).toBe("https://github.com/dru/app-a");
    expect(a.isPrivate).toBe(true);
    expect(a.lastDate).toBe("2026-10-18");
    expect(a.days.map((d) => d.entries.map((e) => e.pr))).toEqual([[12], [3]]);
    expect(repos[1]).toEqual({ name: "app-b", url: "https://github.com/dru/app-b", isPrivate: false, days: [], lastDate: null });
    expect(repos[2].days).toEqual([]);

    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://api.github.com/graphql");
    expect(new Headers(init.headers).get("authorization")).toBe("Bearer ghp_secreto");
    const body = JSON.parse(String(init.body));
    expect(body.query).toContain("ownerAffiliations: OWNER");
    expect(body.query).toContain("isArchived: false");
    expect(body.query).toContain('HEAD:.agents-kit.json');
    expect(body.query).toContain('HEAD:CHANGELOG.md');
    expect(body.variables).toEqual({ after: null });
  });

  it("pagina con pageInfo cuando hay más de 100 repos", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(Response.json(page([node("uno", { changelog: CHANGELOG })], true, "CUR1")))
      .mockResolvedValueOnce(Response.json(page([node("dos")], false, null)));
    const repos = await fetchRepos(env, { fetch: fetchMock, cache: null });
    expect(repos.map((r) => r.name)).toEqual(["uno", "dos"]);
    expect(JSON.parse(String((fetchMock.mock.calls[1] as unknown as [string, RequestInit])[1].body)).variables).toEqual({ after: "CUR1" });
  });

  it("cachea la respuesta y ?refrescar=1 (refresh) la salta", async () => {
    const cache = memoryCache();
    const fetchMock = vi.fn(async () => Response.json(page([node("app-a", { changelog: CHANGELOG })])));
    await fetchRepos(env, { fetch: fetchMock, cache });
    await fetchRepos(env, { fetch: fetchMock, cache });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const cached = [...cache.store.values()][0];
    expect(cached.headers.get("cache-control")).toBe("max-age=300");
    await fetchRepos(env, { fetch: fetchMock, cache, refresh: true });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("token sin permisos: GitHubError en español sin el token", async () => {
    const err = await fetchRepos(env, { fetch: async () => new Response("Bad credentials ghp_secreto", { status: 401 }), cache: null }).catch((e) => e);
    expect(err).toBeInstanceOf(GitHubError);
    expect(err.message).toMatch(/token/i);
    expect(err.message).not.toContain("ghp_secreto");
  });

  it("errores GraphQL y red caída: GitHubError", async () => {
    const e1 = await fetchRepos(env, {
      fetch: async () => Response.json({ errors: [{ message: "Resource not accessible by personal access token" }] }),
      cache: null,
    }).catch((e) => e);
    expect(e1).toBeInstanceOf(GitHubError);
    const e2 = await fetchRepos(env, {
      fetch: async () => {
        throw new TypeError("fetch failed");
      },
      cache: null,
    }).catch((e) => e);
    expect(e2).toBeInstanceOf(GitHubError);
    expect(e2.message).toContain("GitHub");
    const e3 = await fetchRepos(env, { fetch: async () => new Response("boom", { status: 502 }), cache: null }).catch((e) => e);
    expect(e3).toBeInstanceOf(GitHubError);
  });

  it("sin GITHUB_TOKEN: GitHubError claro sin llamar a la red", async () => {
    const fetchMock = vi.fn();
    const err = await fetchRepos({}, { fetch: fetchMock, cache: null }).catch((e) => e);
    expect(err).toBeInstanceOf(GitHubError);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("fetchRepos (fixtures)", () => {
  it("DATA_SOURCE=fixtures devuelve fixtures/repos.json sin tocar la red", async () => {
    const fetchMock = vi.fn();
    const repos = await fetchRepos({ DATA_SOURCE: "fixtures" }, { fetch: fetchMock });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(repos).toEqual(fixtureRepos);
  });

  it("fixtures/repos.json: 3 apps con la forma Repo (varias entradas con imagen, una entrada, sin changelog)", () => {
    const repos = fixtureRepos as Repo[];
    expect(repos).toHaveLength(3);
    const counts = repos.map((r) => r.days.flatMap((d) => d.entries).length);
    expect(counts[0]).toBeGreaterThan(2);
    expect(new Set(repos[0].days.flatMap((d) => d.entries.map((e) => e.type))).size).toBeGreaterThan(2);
    expect(repos[0].days.length).toBeGreaterThan(1);
    expect(repos[0].days.some((d) => d.entries.some((e) => e.body.includes("](docs/changelog/")))).toBe(true);
    expect(counts[1]).toBe(1);
    expect(counts[2]).toBe(0);
    expect(repos[2].lastDate).toBeNull();
    for (const r of repos) {
      expect(r.lastDate).toBe(r.days[0]?.date ?? null);
      for (const d of r.days) for (const e of d.entries) {
        expect(e.date).toBe(d.date);
        expect(e.url).toBe(`${r.url}/pull/${e.pr}`);
      }
      // las fechas, de más reciente a más antigua
      const dates = r.days.map((d) => d.date);
      expect([...dates].sort().reverse()).toEqual(dates);
    }
  });
});
