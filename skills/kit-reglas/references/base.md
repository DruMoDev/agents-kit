# La base obligatoria

Unos mínimos para todos los repos. Lo propio de cada proyecto va encima, con la escalera (`escalera.md`). Las versiones nunca salen de aquí ni de memoria: `npm view <paquete> version` y `npm view <paquete> peerDependencies` antes de instalar. Los ejemplos usan `npm`; con otro gestor, el equivalente (`pnpm`, `yarn`, `bun`).

## TypeScript: `tsconfig.json`

En `compilerOptions` del propio `tsconfig.json` (`kit-reglas.sh estado` no sigue `extends`):

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "verbatimModuleSyntax": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "tsBuildInfoFile": "node_modules/.cache/agents-kit/tsbuildinfo"
  }
}
```

Qué hace cada una, para explicárselo a Dru:
- `strict`: el paquete de comprobaciones estrictas (`null` y `undefined` explícitos, nada de `any` implícito...).
- `noUncheckedIndexedAccess`: `lista[i]` y `mapa[clave]` pueden ser `undefined`, y el código tiene que tratarlo.
- `exactOptionalPropertyTypes`: una propiedad opcional no acepta `undefined` escrito a mano si su tipo no lo dice.
- `verbatimModuleSyntax`: los imports de solo tipos se escriben `import type`, y el JS emitido es predecible.
- `noImplicitOverride`: sobrescribir un método de la clase padre exige `override`.
- `noFallthroughCasesInSwitch`: un `case` con código no puede caer en el siguiente sin `break` o `return`.
- `tsBuildInfoFile`: la caché de `tsc --incremental` (la usa `tsc-base.mjs`) fuera del árbol versionado.

Lo que más rompe en un repo empezado: `noUncheckedIndexedAccess` y `exactOptionalPropertyTypes`. Esa deuda se congela con `tsc-base.mjs generar`, no se apaga la opción. Si el repo es Astro, su `tsconfig` suele extender `astro/tsconfigs/strictest`: aun así escribe las seis opciones en el `tsconfig.json`.

## ESLint con `typescript-eslint`

Paquetes: `eslint`, `@eslint/js`, `typescript-eslint`, `globals` (y `typescript`, si falta). Un ejemplo de `eslint.config.mjs`:

```js
// eslint.config.mjs
import js from "@eslint/js";
import { defineConfig } from "eslint/config";
import globals from "globals";
import tseslint from "typescript-eslint";

// KIT_LINT_RAPIDO=1: el lint de cada edición (hook de después de editar), sin información de tipos.
const rapido = process.env.KIT_LINT_RAPIDO === "1";

export default defineConfig(
  { ignores: ["dist/", "build/", "coverage/", "node_modules/"] },
  {
    // Nada de directivas en el código: las excepciones van aquí, con su porqué.
    linterOptions: { noInlineConfig: true, reportUnusedDisableDirectives: "error" },
  },
  js.configs.recommended,
  tseslint.configs.strictTypeChecked,
  {
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
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
  // Ficheros JS de configuración: sin reglas con tipos, con los globales de Node (process...).
  {
    files: ["**/*.{js,mjs,cjs}"],
    extends: [tseslint.configs.disableTypeChecked],
    languageOptions: { globals: globals.node },
  },
  rapido ? tseslint.configs.disableTypeChecked : {},
);
```

- `strictTypeChecked`: el conjunto estricto con información de tipos (promesas sin esperar, comparaciones imposibles, `any` que se cuela...).
- `noInlineConfig: true`: ESLint ignora `/* eslint-disable */` y compañía (y avisa con un warning de cada una que encuentra: no tiene efecto). Una excepción va en la configuración, acotada con `files` y con un comentario que dice por qué.
- `reportUnusedDisableDirectives`: error por cada directiva que ya no suprime nada; cubre el día en que alguien quite `noInlineConfig` de un bloque de la configuración.
- `ban-ts-comment`: prohíbe `@ts-ignore` y `@ts-nocheck`; `@ts-expect-error` solo con una descripción.
- `defineConfig` es de `eslint/config`, en las versiones recientes de ESLint. Comprueba en la documentación de la versión que instales que existe y que los nombres siguen siendo estos.
- Si el repo tiene alias de imports (`@/`), añade `no-restricted-imports` contra las rutas relativas largas (ejemplo en `escalera.md`).
- Si el repo ya usa Biome u oxlint, se quedan (pueden ser el lint de cada edición), pero la base con tipos va en ESLint. Lo que ya cubre el otro linter no se duplica.

### Scripts de `package.json`

```json
{
  "scripts": {
    "lint": "eslint .",
    "typecheck": "KIT_TSC=tsc node .agents-kit/tsc-base.mjs comprobar"
  }
}
```

Los scripts `lint*` y `typecheck*` están blindados (cambiarlos pide la aprobación de Dru). Dentro de `npm run`, `tsc` y `eslint` son los de `node_modules/.bin`.

### Deuda de un repo empezado

- Lint: `node_modules/.bin/eslint . --suppress-all` escribe `eslint-suppressions.json` (supresiones nativas de ESLint; comprueba en su documentación que la versión que instalas las tiene), que ESLint aplica solo. Se versiona. Cuando un fichero se limpia, `node_modules/.bin/eslint . --prune-suppressions` quita las entradas que sobran.
- Tipos: `KIT_TSC=node_modules/.bin/tsc node .agents-kit/tsc-base.mjs generar` escribe `.agents-kit/tsc-base.json` (`{"<ruta>": <nº de errores>}`). `comprobar` falla con errores nuevos, y con `--cambiados` exige cero en esos ficheros.
- Las dos solo encogen con el trabajo normal (`kit-reglas.sh trinquete` en `kit-pr.sh fusionar`):
  - una PR que toca un fichero con deuda lo deja a cero, siempre, también con la aprobación de Dru;
  - una PR que las hace crecer (una regla nueva que congela con `--suppress-rule` lo que rompe en ficheros que no toca) solo se fusiona con la aprobación de Dru de esa regla (`kit-regla-aprobada`).

## `knip`: código muerto

Ficheros, exports y dependencias sin uso. Un `knip.json` mínimo:

```json
{
  "$schema": "https://unpkg.com/knip@<mayor>/schema.json",
  "entry": ["src/index.ts", "scripts/*.ts"],
  "project": ["src/**/*.{ts,tsx}", "scripts/**/*.ts"]
}
```

- `<mayor>`: la versión mayor de `knip` que instales.
- Los entry points tienen que estar todos (scripts sueltos, tests, páginas de Astro o Next): un entry point que falta da falsos huérfanos. Muchos frameworks los detecta solo con sus plugins; comprueba la salida antes de dar un hallazgo por bueno.
- Una dependencia que `knip` no ve (se carga por nombre, la usa una herramienta externa) va en `ignoreDependencies` con su porqué, nunca en una supresión en el código.

## Comandos para el marcador

Con el binario local, nunca con algo que pueda descargar:

- `lint.fichero` (cada edición, sin tipos, con caché):
  `--lint-fichero 'ts,tsx,mts,cts,js,jsx,mjs,cjs=KIT_LINT_RAPIDO=1 node_modules/.bin/eslint --cache --cache-location node_modules/.cache/agents-kit/eslint-rapido --no-warn-ignored --pass-on-unpruned-suppressions'`.
  Sin tipos no salen los errores de las reglas con tipos, y ESLint daría por sobrantes sus supresiones (exit 2, "suppressions left that do not occur anymore"): por eso `--pass-on-unpruned-suppressions` aquí, y solo aquí. `lint.turno` y `npm run lint` sí exigen podarlas.
  Con oxlint o Biome, su binario en su lugar (`node_modules/.bin/oxlint`, `node_modules/.bin/biome lint`).
- `lint.turno` (fin de turno: tipos y lint con tipos de lo cambiado): `--lint-turno 'bash .agents-kit/turno.sh'`. El script recibe los ficheros cambiados y lanza `node .agents-kit/tsc-base.mjs comprobar --cambiados <los .ts/.tsx>` más ESLint con tipos y `--cache` sobre los que tengan extensión de lint (`LINT_EXT`). Sin `node_modules`, sale con 127 y el hook no bloquea.
- `verificar.completo` (CI o gate local), detrás de lo que ya tuviera: `npm run lint && npm run typecheck && node_modules/.bin/knip`. `knip` entra solo cuando no tiene hallazgos (en un repo empezado, al fusionar su issue de limpieza).

## Python

Si el repo tiene Python:
- `ruff` (lint y formato), con un `select` amplio en `ruff.toml` (por ejemplo `["E", "F", "B", "UP", "SIM", "I"]`), y `pyright` estricto (`"typeCheckingMode": "strict"` en `pyrightconfig.json`).
- `lint.fichero`: `--lint-fichero 'py=.venv/bin/ruff check --quiet'` (o el `ruff` del PATH), nunca `uvx` ni `pipx run`.
- `ruff.toml` y `pyrightconfig.json` no están en el `blindado` por defecto. Propón añadirlos: la lista del marcador sustituye entera a la de por defecto, así que copia la de `templates/config.json` del kit y añádelos. Mejor en esos ficheros que en `pyproject.toml`, que blindado entero bloquearía cambios normales.

## Bash

- `shellcheck` sobre los scripts: `--lint-fichero 'sh,bash=shellcheck'`.
- Instalado en el sistema (`brew install shellcheck`), no como dependencia del repo; si falta, el hook no bloquea (127) y lo pilla el CI.
