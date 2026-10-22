// Construye la web y arranca `astro preview` (el worker del build en workerd, con la CSP real)
// para los e2e: KV local en un directorio propio que se borra antes, DATA_SOURCE=fixtures y
// DEV_BYPASS_ACCESS=1 (llegan al worker por CLOUDFLARE_INCLUDE_PROCESS_ENV; el bypass solo vale en localhost).
import { rmSync } from "node:fs";
import { spawn, spawnSync } from "node:child_process";
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

const build = spawnSync("npx", ["astro", "build"], { cwd: root, env, stdio: "inherit" });
if (build.status !== 0) process.exit(build.status ?? 1);

// --ignore-lock: primer plano siempre (Astro pasa a segundo plano si detecta un agente)
const child = spawn("npx", ["astro", "preview", "--port", port, "--host", "localhost", "--ignore-lock"], { cwd: root, env, stdio: "inherit" });
const stop = () => child.kill("SIGTERM");
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
child.on("exit", (code) => process.exit(code ?? 0));
