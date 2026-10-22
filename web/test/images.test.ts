import { describe, expect, it, vi } from "vitest";
import { fetchImage, imageAllowed } from "../src/lib/images";
import type { Repo } from "../src/lib/github";

const repo: Repo = { name: "demo", url: "https://github.com/dru/demo", isPrivate: true, days: [], lastDate: null };

describe("imageAllowed", () => {
  it.each(["docs/changelog/12-login.png", "docs/changelog/a.JPG", "docs/changelog/b.jpeg", "docs/changelog/c.gif", "docs/changelog/sub/d.webp"])(
    "acepta %s",
    (p) => expect(imageAllowed(p)).toBe(true),
  );
  it.each([
    "../x.png",
    "docs/x.png",
    "docs/changelog/a.svg",
    "https://example.com/docs/changelog/a.png",
    "/docs/changelog/a.png",
    "docs/changelog/../../secreto.png",
    "docs/changelog//a.png",
    "docs/changelog/a.png?x=1",
    "docs\\changelog\\a.png",
    "docs/changelog/.png",
    "",
  ])("rechaza %s", (p) => expect(imageAllowed(p)).toBe(false));
});

describe("fetchImage", () => {
  it("pide la API de contenidos en crudo con el token y cachea un día", async () => {
    const fetchMock = vi.fn(async () => new Response(new Uint8Array([1, 2, 3]), { status: 200, headers: { "set-cookie": "x" } }));
    const res = await fetchImage({ GITHUB_TOKEN: "tok" }, repo, "docs/changelog/12-login.png", { fetch: fetchMock });
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/png");
    expect(res.headers.get("cache-control")).toBe("private, max-age=86400");
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    expect(res.headers.get("set-cookie")).toBeNull();
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://api.github.com/repos/dru/demo/contents/docs/changelog/12-login.png");
    const h = new Headers(init.headers);
    expect(h.get("accept")).toBe("application/vnd.github.raw");
    expect(h.get("authorization")).toBe("Bearer tok");
  });

  it("ruta no permitida: 404 sin llamar a GitHub", async () => {
    const fetchMock = vi.fn();
    const res = await fetchImage({ GITHUB_TOKEN: "tok" }, repo, "../x.png", { fetch: fetchMock });
    expect(res.status).toBe(404);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("GitHub responde 404 o falla: 404 sin filtrar el token", async () => {
    const res = await fetchImage({ GITHUB_TOKEN: "tok" }, repo, "docs/changelog/x.png", {
      fetch: async () => new Response("Not Found tok", { status: 404 }),
    });
    expect(res.status).toBe(404);
    expect(await res.text()).not.toContain("tok");
    const res2 = await fetchImage({ GITHUB_TOKEN: "tok" }, repo, "docs/changelog/x.png", {
      fetch: async () => {
        throw new Error("red caída");
      },
    });
    expect(res2.status).toBe(502);
  });

  it("modo fixtures: devuelve una imagen de ejemplo sin tocar la red", async () => {
    const fetchMock = vi.fn();
    const res = await fetchImage({ DATA_SOURCE: "fixtures" }, repo, "docs/changelog/12-login.png", { fetch: fetchMock });
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/png");
    const bytes = new Uint8Array(await res.arrayBuffer());
    expect([...bytes.slice(0, 8)]).toEqual([137, 80, 78, 71, 13, 10, 26, 10]);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
