import { describe, expect, it } from "vitest";
import { getSeen, markSeen, unseenCount, type KVLike } from "../src/lib/seen";
import type { Repo } from "../src/lib/github";

function fakeKV(initial: Record<string, string> = {}) {
  const data = new Map(Object.entries(initial));
  const kv: KVLike & { data: Map<string, string> } = {
    data,
    async get(key: string) {
      return data.has(key) ? data.get(key)! : null;
    },
    async put(key: string, value: string) {
      data.set(key, value);
    },
  };
  return kv;
}

const repo: Repo = {
  name: "demo",
  url: "https://github.com/dru/demo",
  isPrivate: true,
  lastDate: "2026-10-18",
  days: [
    {
      date: "2026-10-18",
      entries: [
        { type: "Nuevo", title: "A", pr: 3, url: "u", date: "2026-10-18", body: "" },
        { type: "Mejora", title: "B", pr: 2, url: "u", date: "2026-10-18", body: "" },
      ],
    },
    { date: "2026-10-01", entries: [{ type: "Arreglo", title: "C", pr: 1, url: "u", date: "2026-10-01", body: "" }] },
  ],
};

describe("seen", () => {
  it("la primera vez no hay nada visto", async () => {
    expect([...(await getSeen(fakeKV(), "demo"))]).toEqual([]);
  });

  it("lee seen:<repo> con forma {ids: [...]} e ignora JSON roto", async () => {
    const kv = fakeKV({ "seen:demo": '{"ids":[1,2]}', "seen:roto": "{no json", "seen:raro": '{"ids":["x",3]}' });
    expect([...(await getSeen(kv, "demo"))].sort()).toEqual([1, 2]);
    expect([...(await getSeen(kv, "roto"))]).toEqual([]);
    expect([...(await getSeen(kv, "raro"))]).toEqual([3]);
  });

  it("markSeen une sin borrar lo que ya había", async () => {
    const kv = fakeKV({ "seen:demo": '{"ids":[1,7]}' });
    await markSeen(kv, "demo", [3, 1]);
    expect(JSON.parse(kv.data.get("seen:demo")!).ids.sort((a: number, b: number) => a - b)).toEqual([1, 3, 7]);
    await markSeen(kv, "demo", []);
    expect(JSON.parse(kv.data.get("seen:demo")!).ids.sort((a: number, b: number) => a - b)).toEqual([1, 3, 7]);
  });

  it("markSeen ignora ids que no son enteros positivos", async () => {
    const kv = fakeKV();
    await markSeen(kv, "demo", [5, -1, 1.5, Number.NaN] as number[]);
    expect(JSON.parse(kv.data.get("seen:demo")!).ids).toEqual([5]);
  });

  it("unseenCount cuenta las entradas cuyo PR no está visto", () => {
    expect(unseenCount(repo, new Set())).toBe(3);
    expect(unseenCount(repo, new Set([3, 1, 99]))).toBe(1);
    expect(unseenCount({ ...repo, days: [] }, new Set())).toBe(0);
  });
});
