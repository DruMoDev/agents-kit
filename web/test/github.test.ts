import { beforeEach, describe, expect, it, vi } from "vitest";
import { fetchRepos, GitHubError, resetRepoCache, REPOS_CACHE_KEY, type Repo } from "../src/lib/github";
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

function fakeKV() {
  const data = new Map<string, string>();
  const puts: { key: string; value: string; options?: { expirationTtl?: number } }[] = [];
  return {
    data,
    puts,
    async get(key: string) {
      return data.get(key) ?? null;
    },
    async put(key: string, value: string, options?: { expirationTtl?: number }) {
      puts.push({ key, value, options });
      data.set(key, value);
    },
  };
}

beforeEach(() => resetRepoCache());

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
    const repos = await fetchRepos(env, { fetch: fetchMock, kv: null });
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
    const repos = await fetchRepos(env, { fetch: fetchMock, kv: null });
    expect(repos.map((r) => r.name)).toEqual(["uno", "dos"]);
    expect(JSON.parse(String((fetchMock.mock.calls[1] as unknown as [string, RequestInit])[1].body)).variables).toEqual({ after: "CUR1" });
  });

  it("cachea la lista en KV (cache:repos:v1, 300 s) y en memoria del isolate", async () => {
    const kv = fakeKV();
    const fetchMock = vi.fn(async () => Response.json(page([node("app-a", { changelog: CHANGELOG })])));
    const first = await fetchRepos(env, { fetch: fetchMock, kv });
    const second = await fetchRepos(env, { fetch: fetchMock, kv });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(second).toEqual(first);
    expect(REPOS_CACHE_KEY).toBe("cache:repos:v1");
    expect(kv.puts).toHaveLength(1);
    expect(kv.puts[0].key).toBe("cache:repos:v1");
    expect(kv.puts[0].options).toEqual({ expirationTtl: 300 });
    expect(JSON.parse(kv.puts[0].value)).toEqual(first);
  });

  it("otro isolate (memoria vacía) lee la lista de KV sin consultar GitHub", async () => {
    const kv = fakeKV();
    const fetchMock = vi.fn(async () => Response.json(page([node("app-a", { changelog: CHANGELOG })])));
    const first = await fetchRepos(env, { fetch: fetchMock, kv });
    resetRepoCache();
    const get = vi.spyOn(kv, "get");
    expect(await fetchRepos(env, { fetch: fetchMock, kv })).toEqual(first);
    expect(get).toHaveBeenCalledWith("cache:repos:v1");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("la memoria del isolate caduca antes que KV y entonces se relee KV", async () => {
    const kv = fakeKV();
    let t = 1_000_000;
    const now = () => t;
    const fetchMock = vi.fn(async () => Response.json(page([node("app-a")])));
    await fetchRepos(env, { fetch: fetchMock, kv, now });
    const get = vi.spyOn(kv, "get");
    t += 10_000;
    await fetchRepos(env, { fetch: fetchMock, kv, now });
    expect(get).not.toHaveBeenCalled();
    t += 60_000;
    await fetchRepos(env, { fetch: fetchMock, kv, now });
    expect(get).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("usa el KV SEEN del entorno por defecto", async () => {
    const kv = fakeKV();
    const fetchMock = vi.fn(async () => Response.json(page([node("app-a")])));
    await fetchRepos({ ...env, SEEN: kv }, { fetch: fetchMock });
    expect(kv.data.has("cache:repos:v1")).toBe(true);
  });

  it("refresh (?refrescar=1) salta memoria y KV, consulta GitHub y reescribe ambas", async () => {
    const kv = fakeKV();
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(Response.json(page([node("viejo")])))
      .mockResolvedValueOnce(Response.json(page([node("nuevo")])));
    await fetchRepos(env, { fetch: fetchMock, kv });
    const fresh = await fetchRepos(env, { fetch: fetchMock, kv, refresh: true });
    expect(fresh.map((r) => r.name)).toEqual(["nuevo"]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(JSON.parse(kv.data.get("cache:repos:v1")!).map((r: Repo) => r.name)).toEqual(["nuevo"]);
    // memoria también actualizada: la siguiente carga normal no vuelve a GitHub
    expect((await fetchRepos(env, { fetch: fetchMock, kv })).map((r) => r.name)).toEqual(["nuevo"]);
    resetRepoCache();
    expect((await fetchRepos(env, { fetch: fetchMock, kv })).map((r) => r.name)).toEqual(["nuevo"]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("KV caído o con basura: consulta GitHub y no rompe", async () => {
    const fetchMock = vi.fn(async () => Response.json(page([node("app-a")])));
    const broken = {
      get: async () => {
        throw new Error("KV GET failed");
      },
      put: async () => {
        throw new Error("KV PUT failed: 429");
      },
    };
    expect((await fetchRepos(env, { fetch: fetchMock, kv: broken })).map((r) => r.name)).toEqual(["app-a"]);
    resetRepoCache();
    const junk = fakeKV();
    junk.data.set("cache:repos:v1", "{no json");
    expect((await fetchRepos(env, { fetch: fetchMock, kv: junk })).map((r) => r.name)).toEqual(["app-a"]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("errores GraphQL parciales con data: conserva los repos resueltos y omite los fallidos", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const fetchMock = vi.fn(async () =>
      Response.json({
        ...page([node("app-a", { changelog: CHANGELOG }), null, node("app-b")]),
        errors: [{ message: "Something went wrong while executing your query.", path: ["viewer", "repositories", "nodes", 1] }],
      }),
    );
    const repos = await fetchRepos(env, { fetch: fetchMock, kv: null });
    expect(repos.map((r) => r.name)).toEqual(["app-a", "app-b"]);
    expect(warn).toHaveBeenCalled();
    expect(String(warn.mock.calls[0])).not.toContain("ghp_secreto");
    warn.mockRestore();
  });

  it("token sin permisos: GitHubError en español sin el token", async () => {
    const err = await fetchRepos(env, { fetch: async () => new Response("Bad credentials ghp_secreto", { status: 401 }), kv: null }).catch((e) => e);
    expect(err).toBeInstanceOf(GitHubError);
    expect(err.message).toMatch(/token/i);
    expect(err.message).not.toContain("ghp_secreto");
  });

  it("errores GraphQL y red caída: GitHubError", async () => {
    const e1 = await fetchRepos(env, {
      fetch: async () => Response.json({ errors: [{ message: "Resource not accessible by personal access token" }] }),
      kv: null,
    }).catch((e) => e);
    expect(e1).toBeInstanceOf(GitHubError);
    const e2 = await fetchRepos(env, {
      fetch: async () => {
        throw new TypeError("fetch failed");
      },
      kv: null,
    }).catch((e) => e);
    expect(e2).toBeInstanceOf(GitHubError);
    expect(e2.message).toContain("GitHub");
    const e3 = await fetchRepos(env, { fetch: async () => new Response("boom", { status: 502 }), kv: null }).catch((e) => e);
    expect(e3).toBeInstanceOf(GitHubError);
  });

  it("sin GITHUB_TOKEN: GitHubError claro sin llamar a la red", async () => {
    const fetchMock = vi.fn();
    const err = await fetchRepos({}, { fetch: fetchMock, kv: null }).catch((e) => e);
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
