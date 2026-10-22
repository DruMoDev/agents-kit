// Capturas de los changelogs, servidas desde GitHub solo para repos descubiertos y rutas permitidas.
import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { fetchRepos, GitHubError } from "../../../lib/github";
import { fetchImage, imageAllowed } from "../../../lib/images";
import type { WebEnv } from "../../../lib/env";

const plain = (status: number, body: string) =>
  new Response(body, { status, headers: { "content-type": "text/plain; charset=utf-8" } });

export const GET: APIRoute = async ({ params }) => {
  const e = env as unknown as WebEnv;
  const path = params.path ?? "";
  if (!imageAllowed(path)) return plain(404, "Imagen no encontrada");
  let repos;
  try {
    repos = await fetchRepos(e);
  } catch (err) {
    if (err instanceof GitHubError) return plain(502, err.message);
    throw err;
  }
  const repo = repos.find((r) => r.name === params.repo);
  if (!repo) return plain(404, "Imagen no encontrada");
  return fetchImage(e, repo, path);
};
