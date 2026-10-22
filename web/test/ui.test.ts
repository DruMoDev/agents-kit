import { describe, expect, it } from "vitest";
import { formatDate, formatShortDate, sortApps, filterDays, parseTypeFilter, countLabel, withoutRefresh } from "../src/lib/ui";
import type { Repo } from "../src/lib/github";

const repo = (name: string, lastDate: string | null, prs: number[] = []): Repo => ({
  name,
  url: `https://github.com/dru/${name}`,
  isPrivate: true,
  lastDate,
  days: lastDate ? [{ date: lastDate, entries: prs.map((pr) => ({ type: "Nuevo", title: `t${pr}`, pr, url: "u", date: lastDate, body: "" })) }] : [],
});

describe("formatDate", () => {
  it("fecha larga en español", () => {
    expect(formatDate("2026-10-20")).toBe("20 de octubre de 2026");
    expect(formatDate("2026-01-01")).toBe("1 de enero de 2026");
  });
  it("fecha corta", () => {
    expect(formatShortDate("2026-10-05")).toBe("5 oct 2026");
  });
  it("valor raro: se devuelve tal cual", () => {
    expect(formatDate("ayer")).toBe("ayer");
    expect(formatShortDate("")).toBe("");
  });
});

describe("sortApps", () => {
  it("primero las que tienen novedades (más primero), luego por fecha, las vacías al final", () => {
    const items = [
      { repo: repo("a", "2026-10-01", [1]), unseen: 0 },
      { repo: repo("b", null), unseen: 0 },
      { repo: repo("c", "2026-09-01", [1, 2]), unseen: 2 },
      { repo: repo("d", "2026-10-10", [1]), unseen: 1 },
      { repo: repo("e", "2026-10-15", [1]), unseen: 0 },
      { repo: repo("f", "2026-10-20", [1]), unseen: 1 },
    ];
    expect(sortApps(items).map((i) => i.repo.name)).toEqual(["c", "f", "d", "e", "a", "b"]);
  });
});

describe("filtro por tipo", () => {
  it("acepta solo tipos válidos", () => {
    expect(parseTypeFilter("Mejora")).toBe("Mejora");
    expect(parseTypeFilter("mejora")).toBe(null);
    expect(parseTypeFilter(null)).toBe(null);
    expect(parseTypeFilter("<b>")).toBe(null);
  });
  it("filterDays quita días vacíos", () => {
    const days = [
      { date: "2026-10-02", entries: [{ type: "Nuevo" as const, title: "x", pr: 2, url: "u", date: "2026-10-02", body: "" }] },
      { date: "2026-10-01", entries: [{ type: "Arreglo" as const, title: "y", pr: 1, url: "u", date: "2026-10-01", body: "" }] },
    ];
    expect(filterDays(days, "Arreglo").map((d) => d.date)).toEqual(["2026-10-01"]);
    expect(filterDays(days, null)).toHaveLength(2);
  });
});

describe("countLabel", () => {
  it("singular y plural", () => {
    expect(countLabel(1, "cambio", "cambios")).toBe("1 cambio");
    expect(countLabel(0, "cambio", "cambios")).toBe("0 cambios");
    expect(countLabel(3, "cambio", "cambios")).toBe("3 cambios");
  });
});

describe("withoutRefresh", () => {
  it("quita refrescar y conserva el resto de parámetros", () => {
    expect(withoutRefresh(new URL("http://x/?refrescar=1"))).toBe("/");
    expect(withoutRefresh(new URL("http://x/app/recetario?refrescar=1&tipo=Arreglo"))).toBe("/app/recetario?tipo=Arreglo");
    expect(withoutRefresh(new URL("http://x/app/a%20b?tipo=Nuevo&refrescar=1"))).toBe("/app/a%20b?tipo=Nuevo");
  });
});
