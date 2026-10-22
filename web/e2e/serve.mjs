// Arranca `astro dev` para los e2e: KV local en un directorio propio que se borra antes,
// DATA_SOURCE=fixtures y DEV_BYPASS_ACCESS=1 (llegan al worker por CLOUDFLARE_INCLUDE_PROCESS_ENV).
import { rmSync } from "node:fs";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const port = process.argv[2] ?? "4329";
const root = fileURLToPath(new URL("..", import.meta.url));
const stateDir = fileURLToPath(new URL("../.wrangler/e2e-state", import.meta.url));
rmSync(stateDir, { recursive: true, force: true });

const env = { ...process.env };
delete env.GITHUB_TOKEN; // los e2e nunca usan un token real
Object.assign(env, {
  CLOUDFLARE_INCLUDE_PROCESS_ENV: "true",
  DATA_SOURCE: "fixtures",
  DEV_BYPASS_ACCESS: "1",
  WEB_PERSIST_DIR: stateDir,
});

// --ignore-lock: primer plano siempre (Astro pasa a segundo plano si detecta un agente)
const child = spawn("npx", ["astro", "dev", "--port", port, "--host", "localhost", "--ignore-lock"], { cwd: root, env, stdio: "inherit" });
const stop = () => child.kill("SIGTERM");
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
child.on("exit", (code) => process.exit(code ?? 0));
