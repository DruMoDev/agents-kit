// Verificación del JWT de Cloudflare Access (cabecera Cf-Access-Jwt-Assertion) con WebCrypto.
// RS256, firma contra el JWKS del equipo, `aud` = ACCESS_AUD, `iss` = https://<equipo>, `exp` y `nbf`.
import type { FetchLike, WebEnv } from "./env";

const JWKS_TTL_MS = 60 * 60 * 1000;

interface Jwk extends JsonWebKey {
  kid?: string;
}

const JWKS_MIN_REFRESH_MS = 60 * 1000;

const jwksCache = new Map<string, { keys: Jwk[]; fetched: number }>();

/** Solo para tests. */
export function resetJwksCache(): void {
  jwksCache.clear();
}

function text(status: number, body: string): Response {
  return new Response(body, { status, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
}

const forbidden = () => text(403, "Acceso denegado");

function b64urlDecode(s: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]*$/.test(s)) throw new Error("base64url inválido");
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

const decodeJson = (s: string) => JSON.parse(new TextDecoder().decode(b64urlDecode(s)));

async function loadKeys(domain: string, doFetch: FetchLike, force: boolean): Promise<Jwk[]> {
  const cached = jwksCache.get(domain);
  const age = cached ? Date.now() - cached.fetched : Infinity;
  // un kid desconocido fuerza la recarga, pero como mucho una vez por minuto
  if (cached && (age < JWKS_MIN_REFRESH_MS || (!force && age < JWKS_TTL_MS))) return cached.keys;
  const res = await doFetch(`https://${domain}/cdn-cgi/access/certs`);
  if (!res.ok) throw new Error(`JWKS ${res.status}`);
  const body = (await res.json()) as { keys?: Jwk[] };
  const keys = Array.isArray(body.keys) ? body.keys : [];
  jwksCache.set(domain, { keys, fetched: Date.now() });
  return keys;
}

function normalizeDomain(d: string): string {
  return d.trim().replace(/^https?:\/\//i, "").replace(/\/+$/, "");
}

/** null = la petición pasa; si no, la respuesta que hay que devolver (403 o 503). */
export async function verifyAccess(
  request: Request,
  env: WebEnv,
  deps: { fetch?: FetchLike; now?: () => number } = {},
): Promise<Response | null> {
  if (env.DEV_BYPASS_ACCESS === "1") return null;
  const domain = normalizeDomain(env.ACCESS_TEAM_DOMAIN ?? "");
  const aud = (env.ACCESS_AUD ?? "").trim();
  if (!domain || !aud) return text(503, "Access sin configurar");

  const jwt = request.headers.get("Cf-Access-Jwt-Assertion");
  if (!jwt) return forbidden();

  try {
    const parts = jwt.split(".");
    if (parts.length !== 3) return forbidden();
    const [h, p, s] = parts;
    const header = decodeJson(h) as { alg?: string; kid?: string };
    const payload = decodeJson(p) as { aud?: string | string[]; iss?: string; exp?: number; nbf?: number };
    if (header.alg !== "RS256" || !header.kid) return forbidden();

    const now = Math.floor((deps.now ?? Date.now)() / 1000);
    if (typeof payload.exp !== "number" || payload.exp <= now) return forbidden();
    if (typeof payload.nbf === "number" && payload.nbf > now) return forbidden();
    const auds = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
    if (!auds.includes(aud)) return forbidden();
    if (payload.iss !== `https://${domain}`) return forbidden();

    const doFetch = deps.fetch ?? fetch;
    let jwk = (await loadKeys(domain, doFetch, false)).find((k) => k.kid === header.kid);
    // clave rotada: se recarga el JWKS una vez
    if (!jwk) jwk = (await loadKeys(domain, doFetch, true)).find((k) => k.kid === header.kid);
    if (!jwk || jwk.kty !== "RSA") return forbidden();

    const { kid: _kid, alg: _alg, use: _use, key_ops: _ops, ...material } = jwk as Jwk & { use?: string };
    const key = await crypto.subtle.importKey(
      "jwk",
      { ...material, ext: true },
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const ok = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      key,
      b64urlDecode(s),
      new TextEncoder().encode(`${h}.${p}`),
    );
    return ok ? null : forbidden();
  } catch {
    return forbidden();
  }
}
