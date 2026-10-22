import { describe, expect, it } from "vitest";
import { handleSeen } from "../src/lib/seen-api";
import type { KVLike } from "../src/lib/seen";
import type { Repo } from "../src/lib/github";
import { GitHubError } from "../src/lib/github";

function fakeKV() {
  const data = new Map<string, string>();
  const kv: KVLike & { data: Map<string, string> } = {
    data,
    async get(k) {
      return data.get(k) ?? null;
    },
    async put(k, v) {
      data.set(k, v);
    },
  };
  return kv;
}

const repos: Repo[] = [{ name: "demo", url: "https://github.com/dru/demo", isPrivate: true, lastDate: null, days: [] }];
const load = async () => repos;

const post = (body: unknown, type = "application/json") =>
  new Request("https://x/api/seen", {
    method: "POST",
    headers: { "content-type": type },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

describe("POST /api/seen", () => {
  it("marca y responde 204", async () => {
    const kv = fakeKV();
    const res = await handleSeen(post({ repo: "demo", prs: [3, 1] }), kv, load);
    expect(res.status).toBe(204);
    expect(kv.data.get("seen:demo")).toBe('{"ids":[1,3]}');
  });

  it("repo inexistente: 404 y no escribe", async () => {
    const kv = fakeKV();
    const res = await handleSeen(post({ repo: "otro", prs: [1] }), kv, load);
    expect(res.status).toBe(404);
    expect(kv.data.size).toBe(0);
  });

  it("cuerpo inválido: 400", async () => {
    const kv = fakeKV();
    for (const body of ["no json", { repo: "demo" }, { repo: "demo", prs: "1" }, { repo: 3, prs: [1] }, { repo: "demo", prs: [1.5] }, { repo: "demo", prs: [0] }]) {
      expect((await handleSeen(post(body), kv, load)).status).toBe(400);
    }
    expect(kv.data.size).toBe(0);
  });

  it("demasiados ids: 400", async () => {
    const prs = Array.from({ length: 1001 }, (_, i) => i + 1);
    expect((await handleSeen(post({ repo: "demo", prs }), fakeKV(), load)).status).toBe(400);
  });

  it("sin KV: 503", async () => {
    expect((await handleSeen(post({ repo: "demo", prs: [1] }), undefined, load)).status).toBe(503);
  });

  it("GitHub caído: 502 con mensaje en español", async () => {
    const res = await handleSeen(post({ repo: "demo", prs: [1] }), fakeKV(), async () => {
      throw new GitHubError("No se pudo conectar con GitHub.");
    });
    expect(res.status).toBe(502);
    expect(await res.text()).toContain("No se pudo conectar");
  });
});
