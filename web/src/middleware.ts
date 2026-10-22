// Toda petición pasa por Cloudflare Access (verifyAccess). Las páginas no se guardan en caché.
import { defineMiddleware } from "astro:middleware";
import { env } from "cloudflare:workers";
import { verifyAccess } from "./lib/access";
import type { WebEnv } from "./lib/env";

export const onRequest = defineMiddleware(async (context, next) => {
  const denied = await verifyAccess(context.request, env as unknown as WebEnv);
  if (denied) return denied;

  const res = await next();
  const headers = new Headers(res.headers);
  headers.set("x-content-type-options", "nosniff");
  headers.set("referrer-policy", "no-referrer");
  // las páginas traen la CSP de Astro (security.csp en astro.config.mjs, con hashes);
  // lo que no es HTML no carga nada; en `astro dev` (sin CSP de Astro) solo frame-ancestors
  if (!headers.has("content-security-policy")) {
    const isHtml = (headers.get("content-type") ?? "").includes("text/html");
    headers.set("content-security-policy", isHtml ? "frame-ancestors 'none'" : "default-src 'none'; frame-ancestors 'none'");
  }
  // las imágenes traen su propia caché privada; lo demás nunca se guarda
  if (!context.url.pathname.startsWith("/img/")) headers.set("cache-control", "no-store");
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
});
