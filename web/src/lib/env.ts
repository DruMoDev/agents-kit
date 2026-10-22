// Variables y bindings que usa la web. En el worker llegan de `import { env } from "cloudflare:workers"`.
import type { KVLike } from "./seen";

export interface WebEnv {
  /** Token fine-grained de solo lectura (secreto de Cloudflare). */
  GITHUB_TOKEN?: string;
  /** "fixtures" = datos de ejemplo de fixtures/repos.json (desarrollo y e2e). */
  DATA_SOURCE?: string;
  ACCESS_TEAM_DOMAIN?: string;
  ACCESS_AUD?: string;
  /** "1" = no exigir Access (solo desarrollo y e2e). */
  DEV_BYPASS_ACCESS?: string;
  SEEN?: KVLike;
}

export type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;
