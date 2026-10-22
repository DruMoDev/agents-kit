import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { fetchRepos } from "../../lib/github";
import { handleSeen } from "../../lib/seen-api";
import type { WebEnv } from "../../lib/env";

export const POST: APIRoute = ({ request }) => {
  const e = env as unknown as WebEnv;
  return handleSeen(request, e.SEEN, () => fetchRepos(e));
};

export const ALL: APIRoute = () =>
  new Response("Método no permitido", { status: 405, headers: { allow: "POST", "content-type": "text/plain; charset=utf-8" } });
