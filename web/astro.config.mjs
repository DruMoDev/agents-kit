// @ts-check
import { defineConfig } from "astro/config";
import cloudflare from "@astrojs/cloudflare";

// Sin sesiones ni servicio de imágenes de Cloudflare: así el adaptador no añade
// los bindings SESSION ni IMAGES (y wrangler no los aprovisiona al desplegar).
export default defineConfig({
  output: "server",
  session: false,
  adapter: cloudflare({ imageService: "passthrough" }),
});
