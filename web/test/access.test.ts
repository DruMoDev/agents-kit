import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { resetJwksCache, verifyAccess } from "../src/lib/access";

const TEAM = "dru.cloudflareaccess.com";
const AUD = "aud-correcta";
let keys: CryptoKeyPair;
let otherKeys: CryptoKeyPair;
let jwks: { keys: JsonWebKey[] };

const b64url = (data: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data as ArrayBuffer);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function sign(payload: Record<string, unknown>, opts: { kid?: string; alg?: string; key?: CryptoKey } = {}) {
  const header = { alg: opts.alg ?? "RS256", kid: opts.kid ?? "k1", typ: "JWT" };
  const input = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", opts.key ?? keys.privateKey, new TextEncoder().encode(input));
  return `${input}.${b64url(sig)}`;
}

const now = () => Math.floor(Date.now() / 1000);
const goodPayload = () => ({ aud: [AUD], iss: `https://${TEAM}`, exp: now() + 600, iat: now() - 10, email: "dru@example.com" });
const env = { ACCESS_TEAM_DOMAIN: TEAM, ACCESS_AUD: AUD };
const req = (jwt?: string) =>
  new Request("https://changelogs.example.com/", { headers: jwt ? { "Cf-Access-Jwt-Assertion": jwt } : {} });

function jwksFetch() {
  return vi.fn(async (url: string | URL | Request) => {
    expect(String(url)).toBe(`https://${TEAM}/cdn-cgi/access/certs`);
    return Response.json(jwks);
  });
}

beforeAll(async () => {
  const params = { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" };
  keys = (await crypto.subtle.generateKey(params, true, ["sign", "verify"])) as CryptoKeyPair;
  otherKeys = (await crypto.subtle.generateKey(params, true, ["sign", "verify"])) as CryptoKeyPair;
  const jwk = (await crypto.subtle.exportKey("jwk", keys.publicKey)) as JsonWebKey;
  jwks = { keys: [{ ...jwk, kid: "k1", alg: "RS256", use: "sig" } as JsonWebKey] };
});

beforeEach(() => resetJwksCache());

describe("verifyAccess", () => {
  it("JWT válido: pasa (null)", async () => {
    const f = jwksFetch();
    expect(await verifyAccess(req(await sign(goodPayload())), env, { fetch: f })).toBeNull();
    expect(f).toHaveBeenCalledTimes(1);
  });

  it("acepta aud como cadena y un dominio con https:// y barra final", async () => {
    const jwt = await sign({ ...goodPayload(), aud: AUD });
    expect(await verifyAccess(req(jwt), { ACCESS_TEAM_DOMAIN: `https://${TEAM}/`, ACCESS_AUD: AUD }, { fetch: jwksFetch() })).toBeNull();
  });

  it("cachea el JWKS entre peticiones", async () => {
    const f = jwksFetch();
    await verifyAccess(req(await sign(goodPayload())), env, { fetch: f });
    await verifyAccess(req(await sign(goodPayload())), env, { fetch: f });
    expect(f).toHaveBeenCalledTimes(1);
  });

  const forbidden: [string, () => Promise<string | undefined>][] = [
    ["sin cabecera", async () => undefined],
    ["aud errónea", async () => sign({ ...goodPayload(), aud: ["otra"] })],
    ["expirado", async () => sign({ ...goodPayload(), exp: now() - 60 })],
    ["sin exp", async () => sign({ ...goodPayload(), exp: undefined })],
    ["nbf en el futuro", async () => sign({ ...goodPayload(), nbf: now() + 600 })],
    ["emisor distinto", async () => sign({ ...goodPayload(), iss: "https://otro.cloudflareaccess.com" })],
    ["firmado con otra clave", async () => sign(goodPayload(), { key: otherKeys.privateKey })],
    ["kid desconocido", async () => sign(goodPayload(), { kid: "nope" })],
    ["alg none", async () => sign(goodPayload(), { alg: "none" })],
    ["basura", async () => "no.es.unjwt"],
    ["firma manipulada", async () => (await sign(goodPayload())).replace(/\.[^.]+$/, ".AAAA")],
  ];
  it.each(forbidden)("%s: 403", async (_name, make) => {
    const res = await verifyAccess(req(await make()), env, { fetch: jwksFetch() });
    expect(res?.status).toBe(403);
  });

  it("sin configuración: 503 'Access sin configurar'", async () => {
    const res = await verifyAccess(req(await sign(goodPayload())), { ACCESS_TEAM_DOMAIN: "", ACCESS_AUD: AUD });
    expect(res?.status).toBe(503);
    expect(await res!.text()).toContain("Access sin configurar");
    expect((await verifyAccess(req(), {}))?.status).toBe(503);
  });

  it("DEV_BYPASS_ACCESS=1: pasa sin cabecera y sin configuración", async () => {
    expect(await verifyAccess(req(), { DEV_BYPASS_ACCESS: "1" })).toBeNull();
    expect(await verifyAccess(req(), { ...env, DEV_BYPASS_ACCESS: "1" })).toBeNull();
    expect((await verifyAccess(req(), { DEV_BYPASS_ACCESS: "0" }))?.status).toBe(503);
  });

  it("JWKS inalcanzable: 403 sin lanzar", async () => {
    const res = await verifyAccess(req(await sign(goodPayload())), env, {
      fetch: async () => {
        throw new Error("red caída");
      },
    });
    expect(res?.status).toBe(403);
  });
});
