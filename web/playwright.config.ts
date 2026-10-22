import { defineConfig, devices } from "@playwright/test";

// e2e contra el build (`astro build` + `astro preview`: workerd, KV local, CSP de verdad)
// con datos de fixtures/repos.json y sin Access.
// El estado de KV vive en .wrangler/e2e-state y se borra al arrancar el servidor:
// cada ejecución empieza con todo "sin ver". Nunca toca la red.
const PORT = 4329;

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: "list",
  use: {
    baseURL: `http://localhost:${PORT}`,
    ...devices["Desktop Chrome"],
  },
  webServer: {
    command: `node e2e/serve.mjs ${PORT}`,
    url: `http://localhost:${PORT}/`,
    reuseExistingServer: false,
    timeout: 120_000,
    stdout: "pipe",
    stderr: "pipe",
  },
});
