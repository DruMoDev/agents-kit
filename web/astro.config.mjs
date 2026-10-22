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
  // el markdown de los changelogs lo renderiza src/lib/markdown.ts; sin Shiki (estilos en línea, chocan con la CSP)
  markdown: { syntaxHighlight: false },
  // CSP en cabecera (solo en build: `astro dev` no la aplica). Astro añade script-src y
  // style-src 'self' con el hash de cada script y estilo en línea que genera.
  security: {
    csp: {
      directives: [
        "default-src 'self'",
        "img-src 'self' https: data:",
        "font-src 'self'",
        "connect-src 'self'",
        "object-src 'none'",
        "base-uri 'none'",
        "form-action 'self'",
        "frame-ancestors 'none'",
      ],
    },
  },
  adapter: cloudflare({
    imageService: "passthrough",
    ...(persistDir ? { persistState: { path: persistDir } } : {}),
  }),
});
