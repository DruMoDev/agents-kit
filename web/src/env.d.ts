// Tipos mínimos del módulo del runtime de Workers (sin depender de @cloudflare/workers-types).
declare module "cloudflare:workers" {
  export const env: Record<string, unknown>;
}
