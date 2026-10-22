// @ts-check
import { defineConfig } from "astro/config";
import cloudflare from "@astrojs/cloudflare";

// Sin sesiones ni servicio de imágenes de Cloudflare: así el adaptador no añade
// los bindings SESSION ni IMAGES (y wrangler no los aprovisiona al desplegar).
// WEB_PERSIST_DIR (solo e2e): KV local en un directorio aparte que se borra en cada ejecución.
const persistDir = process.env.WEB_PERSIST_DIR;

export default defineConfig({
  output: "server",
  session: false,
  devToolbar: { enabled: false },
  adapter: cloudflare({
    imageService: "passthrough",
    ...(persistDir ? { persistState: { path: persistDir } } : {}),
  }),
});
