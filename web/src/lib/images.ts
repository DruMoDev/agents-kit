// Imágenes de los changelogs: el worker las sirve desde GitHub (los repos pueden ser privados).
// Solo rutas relativas bajo docs/changelog/ con extensión de imagen rasterizada; nunca una URL arbitraria.
import type { FetchLike, WebEnv } from "./env";
import type { Repo } from "./github";

const TYPES: Record<string, string> = {
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
};

// segmentos de letras, números, punto, guion y guion bajo; el nombre del fichero no puede empezar por punto
const ALLOWED = /^docs\/changelog\/(?:[\p{L}\p{N}_-][\p{L}\p{N}._-]*\/)*[\p{L}\p{N}_-][\p{L}\p{N}._-]*\.(png|jpe?g|gif|webp)$/iu;

export function imageAllowed(path: string): boolean {
  if (typeof path !== "string" || !ALLOWED.test(path)) return false;
  return !path.split("/").some((seg) => seg === "" || seg === "." || seg === "..");
}

// PNG 320x180 gris liso para DATA_SOURCE=fixtures (sin red)
const PLACEHOLDER_PNG =
  "iVBORw0KGgoAAAANSUhEUgAAAUAAAAC0CAIAAABqhmJGAAABlElEQVR42u3TMQkAAAzEwPevsEO3GqmOh4NTEEhmDygVCcDAgIEBA4OBAQMDBgYMDAYGDAwYGAwMGBgwMGBgMDBgYMDAgIHBwICBAQODgQEDAwYGDAwGBgwMGBgwMBgYMDBgYDAwYGDAwICBwcCAgQEDg4FVAAMDBgYMDAYGDAwYGDAwGBgwMGBgMDBgYMDAgIHBwICBAQMDBgYDAwYGDAwGBgwMGBgwMBgYMDBgYMDAYGDAwICBwcCAgQEDAwYGAwMGBgwMBgYMDBgYMDAYGDAwYGDAwGBgwMCAgcHAgIEBAwMGBgMDBgYMDBgYDAwYGDAwGBgwMGBgwMBgYMDAgIEBA4OBAQMDBgYDAwYGDAwYGAwMGBgwMBgYMDBgYMDAYGDAwICBAQODgQEDAwYGAwMGBgwMGBgMDBgYMDBgYDAwYGDAwGBgwMCAgQEDg4EBAwMGBgOrAAYGDAwYGAwMGBgwMGBgMDBgYMDAYGDAwICBAQODgQEDAwYGDAwGBgwMGBgMDBgYMDBgYDAwYGDAwICBodsD3RvZGw+C744AAAAASUVORK5CYII=";

function notFound(): Response {
  return new Response("Imagen no encontrada", { status: 404, headers: { "content-type": "text/plain; charset=utf-8" } });
}

function ownerAndName(repo: Repo): [string, string] | null {
  const m = /^https:\/\/github\.com\/([^/]+)\/([^/]+?)\/?$/.exec(repo.url);
  return m ? [m[1], m[2]] : null;
}

export async function fetchImage(
  env: WebEnv,
  repo: Repo,
  path: string,
  deps: { fetch?: FetchLike } = {},
): Promise<Response> {
  if (!imageAllowed(path)) return notFound();
  const ext = path.slice(path.lastIndexOf(".") + 1).toLowerCase();
  const headers = { "content-type": TYPES[ext], "cache-control": "public, max-age=86400" };

  if (env.DATA_SOURCE === "fixtures") {
    const bytes = Uint8Array.from(atob(PLACEHOLDER_PNG), (c) => c.charCodeAt(0));
    return new Response(bytes, { status: 200, headers: { ...headers, "content-type": "image/png" } });
  }

  const slug = ownerAndName(repo);
  if (!slug || !env.GITHUB_TOKEN) return notFound();
  const url =
    `https://api.github.com/repos/${encodeURIComponent(slug[0])}/${encodeURIComponent(slug[1])}/contents/` +
    path.split("/").map(encodeURIComponent).join("/");
  const doFetch = deps.fetch ?? fetch;
  let res: Response;
  try {
    res = await doFetch(url, {
      headers: {
        accept: "application/vnd.github.raw",
        authorization: `Bearer ${env.GITHUB_TOKEN}`,
        "user-agent": "agents-kit-changelogs",
        "x-github-api-version": "2022-11-28",
      },
    });
  } catch {
    return new Response("No se pudo conectar con GitHub", { status: 502, headers: { "content-type": "text/plain; charset=utf-8" } });
  }
  if (!res.ok) return notFound();
  return new Response(res.body, { status: 200, headers });
}
