# La base obligatoria

Unos mínimos para todos los repos. Un proyecto JavaScript (su `tsconfig.json` con `allowJs` y sin ficheros `.ts`, `.tsx`, `.mts` ni `.cts` propios) lleva otra base: "JavaScript con `tsconfig` de solo inferencia", abajo. Lo propio de cada proyecto va encima, con la escalera (`escalera.md`). Las versiones nunca salen de aquí ni de memoria: `npm view <paquete> version` y `npm view <paquete> peerDependencies` antes de instalar. Los ejemplos usan `npm`; con otro gestor, el equivalente (`pnpm`, `yarn`, `bun`).

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
  // Ficheros JS de configuración de un proyecto TS: sin reglas con tipos, con los globales de Node (process...).
  // En un proyecto JS, nunca: apagaría las reglas con tipos en todo su código.
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

### TypeScript 7 o más nuevo

TypeScript 7 es nativo y su paquete `typescript` ya no trae la API de JS que usan `typescript-eslint` y los parsers de ESLint (el de Astro, por ejemplo). Mientras `typescript-eslint` no lo soporte, ESLint ni arranca (`typescript-eslint does not support TS 7.0`). Antes de decidir:
- `npm view typescript-eslint peerDependencies`: si su rango de `typescript` no incluye la versión del repo, sigue con lo de abajo; si la incluye, nada de esto hace falta.
- `npm view @typescript/typescript6 version`: el paquete que da la API de TS 6 (y un `tsc6`).

El montaje, lado a lado:
- `typescript` en `node_modules` es la API de TS 6, para ESLint: `"typescript": "npm:@typescript/typescript6@<versión>"` en `devDependencies`. Tiene que ser `typescript` en la raíz, no un paquete anidado bajo `typescript-eslint`: algunos parsers (el de Astro) cargan `typescript` desde el directorio del proyecto.
- El `tsc` de TS 7 queda aparte para `tsc-base.mjs` y `turno.sh`, con otro nombre: `"typescript7": "npm:typescript@<versión que ya usa el repo>"`. Llámalo por su ruta, `node_modules/typescript7/bin/tsc` (en `KIT_TSC`), nunca por `node_modules/.bin/tsc`: `@typescript/typescript6` 6.0.2 depende de `typescript` 6 con el alias `@typescript/old`, y su `tsc` puede quedarse con `node_modules/.bin/tsc` (visto el 2026-11-04 con npm 11.6.0). Comprueba después de instalar que `node_modules/typescript7/bin/tsc --version` da la 7 y que `node -e "console.log(require('typescript').version)"` da la 6.
- `knip` no ve `typescript7` (se usa por su ruta): va en `ignoreDependencies` de `knip.jsonc`, con su porqué en un comentario.
- Explícaselo a Dru como pieza propia: cambia cómo se declara `typescript` en `package.json`, y hay que deshacerlo cuando `typescript-eslint` soporte la 7.

### Scripts de `package.json`

```json
{
  "scripts": {
    "lint": "eslint .",
    "typecheck": "KIT_TSC=tsc node .agents-kit/tsc-base.mjs comprobar"
  }
}
```

En un proyecto con TypeScript 7, `KIT_TSC=node_modules/typescript7/bin/tsc` (ver arriba). En Astro, `typecheck` empieza por `astro sync`: sin `.astro/types.d.ts` (no versionado), los módulos `astro:*` no tienen tipos y `tsc` da errores que no son del código; la deuda se congela también después de `astro sync`.

Los scripts `lint*` y `typecheck*` están blindados (cambiarlos pide la aprobación de Dru). Dentro de `npm run`, `tsc` y `eslint` son los de `node_modules/.bin`.

### Directivas en línea

Con `noInlineConfig`, los comentarios `eslint-disable`, `eslint-enable` y `/* eslint ... */` que ya hubiera en el código dejan de funcionar: cada uno da el warning "has no effect because you have 'noInlineConfig'" (con `--max-warnings 0`, el lint falla) y la regla que desactivaban empieza a dar errores, que acabarían congelados en la deuda como si fueran código por arreglar. `kit-reglas.sh estado` los cuenta por proyecto (`directivas-en-linea: <n>`, informativo). Antes de congelar la deuda, cada uno pasa a la configuración y se quita del código:

```js
  {
    // Las expresiones regulares de este parser buscan caracteres de control a propósito.
    files: ["src/parser.mjs"],
    rules: { "no-control-regex": "off" },
  },
```

Acotado con `files` a los ficheros que lo necesitan, nunca la regla apagada en todo el proyecto, y con el porqué en un comentario.

### Deuda de un repo empezado

- Lint: `node_modules/.bin/eslint . --suppress-all` escribe `eslint-suppressions.json` (supresiones nativas de ESLint; comprueba en su documentación que la versión que instalas las tiene), que ESLint aplica solo. Se versiona. Cuando un fichero se limpia, `node_modules/.bin/eslint . --prune-suppressions` quita las entradas que sobran.
- Tipos: `KIT_TSC=node_modules/.bin/tsc node .agents-kit/tsc-base.mjs generar` escribe `.agents-kit/tsc-base.json` (`{"<ruta>": <nº de errores>}`). `comprobar` falla con errores nuevos, y con `--cambiados` exige cero en esos ficheros.
- Las dos solo encogen con el trabajo normal (`kit-reglas.sh trinquete` en `kit-pr.sh fusionar`):
  - una PR que toca un fichero con deuda lo deja a cero, siempre, también con la aprobación de Dru;
  - una PR que las hace crecer (una regla nueva que congela con `--suppress-rule` lo que rompe en ficheros que no toca) solo se fusiona con la aprobación de Dru de esa regla (`kit-regla-aprobada`).

### Plantillas del kit

`.agents-kit/turno.sh` y `.agents-kit/tsc-base.mjs` son copias de `templates/reglas/` del kit y no se actualizan solas. `kit-reglas.sh estado` compara las de cada proyecto con las del kit instalado (`plantilla: <fichero> al día|desfasada: ...`; en `turno.sh`, sin contar las líneas `TSC_EXT`, `LINT_EXT`, `TSC` y `ANTES_TSC`, que ajusta cada proyecto). Una copia desfasada puede fallar con lo que el kit ya soporta: un `turno.sh` de antes de `TSC_EXT=""` sale con "falta .agents-kit/tsc-base.mjs" en un proyecto JS. Se vuelve a copiar, conservando esas cuatro líneas, con el OK de Dru (están blindadas).

### Astro

`eslint-plugin-astro` (`astro.configs.recommended`, detrás de `strictTypeChecked`) y `extraFileExtensions: [".astro"]` en `parserOptions`. `astro-eslint-parser` no admite `projectService` (avisa en cada fichero y usa `project: true`): en los `.astro`, `{ files: ["**/*.astro"], languageOptions: { parserOptions: { projectService: false, project: true } } }`. Su ESLint tiene que correr desde el directorio del proyecto: el parser carga `typescript` desde el `cwd` (desde otro directorio, el lint sin tipos falla con `Parsing error` en los tipos del frontmatter).

### Un proyecto fuera de la raíz

En un monorepo, cada app (`web/`, `packages/<x>`) lleva su base en su directorio, con su `.agents-kit/turno.sh`. Los hooks lanzan los comandos del marcador dentro del proyecto de cada fichero (el directorio más cercano con `package.json` y `tsconfig.json`), con las rutas relativas a ese directorio, y en la raíz para los ficheros que no son de ninguno: `lint.fichero` y `lint.turno` son los de arriba, los mismos para todas las apps. Si la raíz no es un proyecto TS y no tiene su `turno.sh`: `--lint-turno '[ ! -f .agents-kit/turno.sh ] || bash .agents-kit/turno.sh'`.

Tiene que ser dentro del proyecto: desde la raíz, ESLint 10 encuentra el `eslint.config.*` del directorio del fichero, pero lee las supresiones del `cwd` (`--suppressions-location` no lo arregla: sus claves son relativas a la app) y el parser de Astro no encuentra `typescript`.

En `turno.sh` de un proyecto con TypeScript 7: `TSC="node_modules/typescript7/bin/tsc"`; en Astro, `ANTES_TSC="node_modules/.bin/astro sync"` y `astro` en `LINT_EXT`.

## JavaScript con `tsconfig` de solo inferencia

Un proyecto JS cuyo `tsconfig.json` existe solo para que `typescript-eslint` infiera tipos (`allowJs: true`, `checkJs: false`, `noEmit: true`). `kit-reglas.sh estado` lo marca `(js, ...)`. Su base: el lint declarado, `strictNullChecks` en el `tsconfig`, `strictTypeChecked`, `noInlineConfig` y `knip`; las otras opciones estrictas del `tsconfig` no entran.

Por qué otra base: en JS sin anotar casi todo es `any`, y la base TS lo deja inservible. La familia `no-unsafe-*` y `restrict-template-expressions` marcan casi cada línea (en un proyecto real de 113 ficheros, el 85% de 18.875 errores; sin ellas quedaron 530 en 70 ficheros, hallazgos útiles como `require-await` o `no-unnecessary-condition`). Congelarlos con el trinquete dejaría el proyecto intocable: cada fichero tocado tendría que quedar a cero, y esos errores no se arreglan sin anotar tipos. Y con `checkJs: false`, `tsc` no comprueba nada: las opciones estrictas del `tsconfig` y `tsc-base.mjs` serían teatro.

Salvo una: `"strict": true` (o solo `"strictNullChecks": true`) en `compilerOptions`. No es para `tsc`, sino para el lint: varias reglas de `strictTypeChecked` (`no-unnecessary-condition`, `no-unnecessary-boolean-literal-compare`, `no-useless-default-assignment`) exigen `strictNullChecks` y, sin esa opción, fallan en cada fichero con "This rule requires the strictNullChecks compiler option to be turned on to function correctly". Medido con ESLint 10.8.0 en un proyecto real de 113 ficheros JS (con la configuración de abajo y sin supresiones): sin ninguna de las dos, 1.071 errores en 112 ficheros, 336 de ellos ese aviso (una vez por fichero y regla); con `"strict": true`, 520 en 68; con solo `"strictNullChecks": true`, 519 en 68. Las otras opciones estrictas no cambian lo que infiere el lint. `"strict": true` con `"strictNullChecks": false` no vale: lo apaga (`estado` da `tsconfig: strictNullChecks no`).

`eslint.config.mjs` (o `.js`), la misma de TS con dos cambios: las reglas de abajo apagadas y ningún `disableTypeChecked` para `**/*.{js,mjs,cjs}`, que apagaría las reglas con tipos (`no-floating-promises`) en todo el código, justo lo que protegen:

```js
export default defineConfig(
  { ignores: ["dist/", "build/", "coverage/", "node_modules/"] },
  { linterOptions: { noInlineConfig: true, reportUnusedDisableDirectives: "error" } },
  js.configs.recommended,
  tseslint.configs.strictTypeChecked,
  {
    languageOptions: {
      globals: globals.node,
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
    rules: {
      "@typescript-eslint/no-floating-promises": "error",
      // JS sin anotar: todo lo que no infiere es `any`, y estas marcan casi cada línea sin encontrar nada.
      // Vuelven si el proyecto activa checkJs y anota sus tipos.
      "@typescript-eslint/no-unsafe-argument": "off",
      "@typescript-eslint/no-unsafe-assignment": "off",
      "@typescript-eslint/no-unsafe-call": "off",
      "@typescript-eslint/no-unsafe-member-access": "off",
      "@typescript-eslint/no-unsafe-return": "off",
      "@typescript-eslint/restrict-template-expressions": "off",
    },
  },
  rapido ? tseslint.configs.disableTypeChecked : {},
);
```

- Las reglas con tipos solo ven lo que el `tsconfig` deja tipar, y una que no puede tipar una expresión se calla en vez de fallar: `include` cubre todas las extensiones que se lintan (`**/*.mjs`, `**/*.js`, `**/*.cjs`), `lib` las APIs del entorno (`webworker` para `fetch` en un Worker) y `types` los de Node (`["node"]`, con `@types/node`). Compruébalo con un fichero de prueba que deja una promesa sin esperar (`fetch(...)` sin `await`): el lint tiene que fallar.
- Un fichero que el `include` no recoge (los de un directorio que empieza por punto, por ejemplo) da `was not found by the project service`: añádelo al `include` o a `ignores`.
- Las directivas en línea que ya tuviera (`eslint-disable`...) se migran a la configuración antes de congelar la deuda (ver "Directivas en línea").
- Sin `typecheck` ni `tsc-base.mjs`: `npm run lint` y `knip` en `verificar.completo`. `turno.sh` con `TSC_EXT=""` (sin tipos: solo ESLint con tipos) y en `LINT_EXT` las extensiones del proyecto. La deuda de lint que quede se congela igual (`--suppress-all`).
- **Pieza opcional, aparte: `checkJs`.** Activarlo es una migración (anotar tipos con JSDoc), no parte de la base: se propone a Dru como issue propio. Con `checkJs: true` entran las seis opciones del `tsconfig` de arriba, `tsc-base.mjs` con su deuda, el script `typecheck` y `TSC_EXT="js jsx mjs cjs"` en `turno.sh`; y cuando el código ya esté anotado, se pueden volver a encender las `no-unsafe-*`.

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

`kit-reglas.sh marcador <wt>` los imprime ya hechos, listos para `kit-activate.sh`; aquí, qué es cada uno. Con el binario local, nunca con algo que pueda descargar:

- `lint.fichero` (cada edición, sin tipos, con caché):
  `--lint-fichero 'ts,tsx,mts,cts,js,jsx,mjs,cjs=KIT_LINT_RAPIDO=1 node_modules/.bin/eslint --cache --cache-location node_modules/.cache/agents-kit/eslint-rapido --no-warn-ignored --pass-on-unpruned-suppressions'`.
  Sin tipos no salen los errores de las reglas con tipos, y ESLint daría por sobrantes sus supresiones (exit 2, "suppressions left that do not occur anymore"): por eso `--pass-on-unpruned-suppressions` aquí, y solo aquí. `lint.turno` y `npm run lint` sí exigen podarlas.
  Con oxlint o Biome, su binario en su lugar (`node_modules/.bin/oxlint`, `node_modules/.bin/biome lint`).
- `lint.turno` (fin de turno: tipos y lint con tipos de lo cambiado): `--lint-turno 'bash .agents-kit/turno.sh'`. El script recibe los ficheros cambiados y lanza `node .agents-kit/tsc-base.mjs comprobar --cambiados <los .ts/.tsx>` más ESLint con tipos y `--cache` sobre los que tengan extensión de lint (`LINT_EXT`). Sin `node_modules`, sale con 127 y el hook no bloquea.
- `verificar.completo` (CI o gate local), detrás de lo que ya tuviera: `npm run lint && npm run typecheck && node_modules/.bin/knip`; para una app de un subdirectorio, `(cd <app> && npm ci && npm run lint && npm run typecheck)` (un worktree nuevo no tiene su `node_modules`). `knip` entra solo cuando no tiene hallazgos (en un repo empezado, al fusionar su issue de limpieza).

## Python

Si el repo tiene Python:
- `ruff` (lint y formato), con un `select` amplio en `ruff.toml` (por ejemplo `["E", "F", "B", "UP", "SIM", "I"]`), y `pyright` estricto (`"typeCheckingMode": "strict"` en `pyrightconfig.json`).
- `kit-reglas.sh estado` da `py` en `lenguajes:` con `pyproject.toml`, `ruff.toml`, `.ruff.toml`, `requirements*.txt`, `setup.py` o `setup.cfg` en la raíz, o con algún `.py` versionado, y sus líneas informativas (no cambian `base completa`): `ruff: sí|no`, `ruff select: <códigos>|ninguna|por defecto` y `pyright: sí|no`, de la configuración de la raíz (`.ruff.toml`, `ruff.toml` o `pyproject.toml`, el primero que exista, como `ruff`).
- `lint.fichero`: lo da `kit-reglas.sh marcador <wt>`. Con `--python <comando>`, `'py="<comando>" -m ruff check --quiet'`; si no se pasa, `.venv/bin/ruff check --quiet` si existe y, si no, el `ruff` del PATH (`ruff check --quiet`). Nunca `uvx` ni `pipx run`. Si el repo decide su intérprete con un script propio (un `tools/python.sh` que nombra su `AGENTS.md`, por ejemplo), pásalo: `--python '$(tools/python.sh)'` da `"$(tools/python.sh)" -m ruff check --quiet`, que se evalúa en cada edición. Sin ese intérprete (un worktree sin `.venv`), el comando sale con 127 y el hook no bloquea. En un monorepo, los hooks lanzan `lint.fichero` desde el proyecto de cada fichero (un `.py` dentro de una app JS, por ejemplo): por eso, con un proyecto en un subdirectorio, `marcador` ancla a la raíz las rutas relativas (`"$(git rev-parse --show-toplevel)/.venv/bin/ruff"`, `"$("$(git rev-parse --show-toplevel)"/tools/python.sh)"`).
- `ruff.toml` y `pyrightconfig.json` no están en el `blindado` por defecto. Propón añadirlos: la lista del marcador sustituye entera a la de por defecto, así que copia la de `templates/config.json` del kit y añádelos. Mejor en esos ficheros que en `pyproject.toml`, que blindado entero bloquearía cambios normales.

## Bash

- `shellcheck` sobre los scripts: `--lint-fichero 'sh,bash=shellcheck'`.
- Instalado en el sistema (`brew install shellcheck`), no como dependencia del repo; si falta, el hook no bloquea (127) y lo pilla el CI.
