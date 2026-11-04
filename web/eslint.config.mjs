// eslint.config.mjs
import js from "@eslint/js";
import astro from "eslint-plugin-astro";
import { defineConfig } from "eslint/config";
import globals from "globals";
import tseslint from "typescript-eslint";

// KIT_LINT_RAPIDO=1: el lint de cada edición (hook de después de editar), sin información de tipos.
const rapido = process.env.KIT_LINT_RAPIDO === "1";

export default defineConfig(
  { ignores: ["dist/", ".astro/", ".wrangler/", "coverage/", "node_modules/", "playwright-report/", "test-results/"] },
  {
    // Nada de directivas en el código: las excepciones van aquí, con su porqué.
    linterOptions: { noInlineConfig: true, reportUnusedDisableDirectives: "error" },
  },
  js.configs.recommended,
  tseslint.configs.strictTypeChecked,
  astro.configs.recommended,
  {
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname, extraFileExtensions: [".astro"] },
    },
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/ban-ts-comment": [
        "error",
        { "ts-expect-error": "allow-with-description", "ts-ignore": true, "ts-nocheck": true, minimumDescriptionLength: 10 },
      ],
    },
  },
  // astro-eslint-parser no admite projectService: en los .astro, el project de su tsconfig (el mismo resultado, sin el aviso).
  { files: ["**/*.astro"], languageOptions: { parserOptions: { projectService: false, project: true } } },
  // Ficheros JS de configuración: sin reglas con tipos, con los globales de Node (process...).
  {
    files: ["**/*.{js,mjs,cjs}"],
    extends: [tseslint.configs.disableTypeChecked],
    languageOptions: { globals: globals.node },
  },
  rapido ? tseslint.configs.disableTypeChecked : {},
);
