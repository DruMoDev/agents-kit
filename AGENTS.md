# AGENTS.md

## Qué es

Plugin personal `agents-kit` para Claude Code, Codex y OpenCode; el mismo repo es su marketplace en Claude Code y Codex.
Las reglas viven en `rules/` (`core.md` más `flujo.md`, o `sin-flujo.md` si el marcador dice `"flujo": false`) y las inyecta `hooks/session-start` solo si el repo tiene `.agents-kit.json` y no dice `"reglas": false` (en OpenCode, el plugin de `.opencode/plugins/` reutiliza ese script).

### Flujo de issues

Con `"flujo": false` en el marcador, nada entra en este flujo (`kit_require_flow` en `kit-issue.sh`: `siguiente`, `reparto`, `aparcar`, `reclamar`, `comprobar`, `crear`, `tomar-eje`); lo que ya estaba se puede soltar.

`kit-plan` y `kit-scout` crean issues con `kit-issue.sh crear` (con `--prio` y `--entorno`; los de `kit-scout`, `propuesta`); `kit-run` coge cualquier issue abierto fuera de `en-curso`, `necesita-respuesta`, `bloqueado`, `propuesta`, `someday` y `registro`, sin dependencias abiertas (`Depende de #N` / `Bloqueado por #N` en su cuerpo), sin su eje `serializa:<eje>` ocupado por otro issue `en-curso` y, en la nube (`lib/transport.sh`), con `entorno:nube` y sin ejes (por `prio:*` y antigüedad) y lo lleva hasta `main`; un issue en `necesita-respuesta` vuelve al reparto cuando, después de su último `<!-- kit-decision -->`, hay un comentario de la cuenta del kit sin marcador `<!-- kit-` (la respuesta de Dru, en el issue o en su PR abierta `issue-<N>-...`), y `reclamar` le quita la etiqueta: Dru responde con un comentario y nunca toca etiquetas (por eso todo comentario que publican los scripts del kit lleva su marcador); `reclamar` toma el candado de cada eje con un push que crea la referencia (solo gana uno) y lo sueltan `fusionar`, `soltar`, `decision` y `bloquear`; `kit-issue.sh tomar-eje` toma un eje descubierto a mitad de un issue y `liberar-eje` libera el de una sesión muerta. `esperar-ci` distingue una PR en borrador o en conflicto (GitHub no lanza su CI) de un repo sin CI. Tras fusionar, `kit-worktree.sh limpiar` avanza el clon de Dru por fast-forward (`principal al día` o `AVISO: ...`). `kit-run <N>` lleva solo ese issue (`kit-issue.sh siguiente <raíz> <N>` dice si se puede coger). Solo cuentan los issues y comentarios de la cuenta de `gh` del kit: `siguiente` filtra por autor y `kit-issue.sh leer` omite los comentarios de otras cuentas. `listo` y `necesita-decision` son de la v2: el primero ya no cuenta y el segundo excluye como `necesita-respuesta`. El estado vive en GitHub: esas etiquetas y marcadores HTML en los comentarios de issues y PRs. Los avisos salen de `kit-notify.sh` (`ntfy`, `claude-push` o `none`); el tema de ntfy solo lo pone el usuario (`~/.agents-kit/ntfy-topic` o `KIT_NTFY_TOPIC`), nunca el repo.

Aprobación de reglas: una PR que cambia ficheros blindados (`kit-reglas.sh blindado` contra `origin/<base>`) no se fusiona sin la aprobación de Dru. `kit-pr.sh regla` publica la propuesta con `<!-- kit-regla: <hash> -->` (`<hash>` = `sha256` del diff blindado), `kit-issue.sh decision` pregunta y avisa, Dru responde con un comentario normal y, al retomar, `kit-pr.sh aprobar-regla <wt> <pr> <id>` registra `<!-- kit-regla-aprobada: <hash> <id> -->`. `fusionar` exige ese marcador con el hash actual y que `<id>` sea un comentario de la cuenta del kit, sin marcador, posterior a la última propuesta: si el diff blindado cambia, hace falta otra propuesta y otra respuesta. En una sesión con Dru sobre la PR de un issue, `aprobar-regla --chat <fichero>` publica citada la respuesta del chat. Por qué respondiendo y no con una etiqueta: lo decidió Dru (no quiere tocar etiquetas), y la respuesta queda atada al diff exacto que aprueba. Límite conocido: agente y Dru usan la misma cuenta de `gh`, así que un agente que quisiera engañar podría falsificar la respuesta; contra el agente descuidado la barrera es sólida, y hacerla absoluta pediría otra cuenta.

### Reglas deterministas

Lint, tipos y estructura que fallan solos, para que "terminado" sea "las comprobaciones en verde" y no "el agente cree que siguió el `.md`". La configuración vive en cada repo (`eslint.config.*`, `tsconfig.json`, `knip`...); el kit pone la skill `kit-reglas` (instala la base y propone reglas, con el OK de Dru), `kit-reglas.sh` (`estado`, `trinquete`, `blindado`, `abrir`, `cerrar`), las plantillas `templates/reglas/`, los hooks `pre-edit`, `post-edit`, `stop-check` y `pre-bash` (frena, sin ser barrera, los comandos de `Bash` que se saltan los hooks de git: `--no-verify` y sus prefijos, `-n` en `git commit`/`merge`/`am`, `core.hooksPath` al escribirlo (leerlo pasa), `HUSKY=0`, `HUSKY_SKIP_HOOKS`, `LEFTHOOK=0`, `SKIP=`; los scripts del kit que hacen commits sin hooks lo hacen dentro del script, que el hook no ve; inerte sin `lint`, como los demás), y las puertas de `kit-pr.sh fusionar` y `kit-issue.sh comprobar` (`falta la base de reglas` en un repo TS sin la base).
- Claves del marcador: `lint` (`{"fichero": {"<ext>,<ext>": "<comando>"}, "turno": "<comando>"}`; que exista activa los hooks, pero la base cuenta como instalada según `kit-reglas.sh estado`: las opciones de `tsconfig` (en un proyecto JS, solo `strictNullChecks`, que piden reglas de `strictTypeChecked`), `strictTypeChecked`, `noInlineConfig`, `knip` y `lint`; sus líneas `directivas-en-linea` y `plantilla` (copias de `templates/reglas/` desfasadas) son informativas) y `blindado` (lista de rutas o globs; sustituye entera a la de `templates/config.json`). `blindado` también se puede definir en `~/.agents-kit/config.json`: es el modelo de confianza del kit (lo global es de Dru, como `notify`).
- Monorepos: el kit va en la raíz y cubre todas las apps. Cada proyecto TS (la raíz, con `tsconfig.json` o `typescript` en su `package.json`, o cualquier directorio con `package.json` y `tsconfig.json`, buscados con `git ls-files` fuera de `node_modules`) lleva su base y su deuda en su directorio, con las claves relativas a ese directorio; `estado` da un bloque `proyecto: <dir> (...)` por cada uno, `comprobar` nombra los que no la tienen y `trinquete` y `blindado` miran los ficheros de deuda de la raíz y de cada directorio. Los hooks lanzan `lint.fichero` y `lint.turno` dentro del proyecto de cada fichero (`kr_proyecto` de `hooks/lib-reglas.sh`: el directorio más cercano con `package.json` y `tsconfig.json`, debajo de la raíz), con las rutas relativas a ese directorio, y en la raíz para los ficheros de ningún proyecto; `stop-check` lanza una vez por proyecto y `KIT_TURNO_TIMEOUT` es el tope de todas juntas. Por eso los mismos comandos del marcador valen para todas las apps; en este repo, `lint.turno` es `[ ! -f .agents-kit/turno.sh ] || bash .agents-kit/turno.sh` (la raíz no tiene `turno.sh`).
- Proyecto JS: un proyecto cuyo `tsconfig.json` tiene `allowJs: true` y sin ficheros `.ts`/`.tsx`/`.mts`/`.cts` propios (los de un proyecto anidado no cuentan; las declaraciones `.d.ts` tampoco). `estado` lo marca `(js, ...)` y le pide la base JS (`project_kind` y `base_checks` de `kit-reglas.sh`): lint, `strictTypeChecked`, `noInlineConfig` y `knip`, sin las opciones estrictas del `tsconfig` (con `checkJs: false` no comprueban nada; `checkJs` es una migración aparte). Su `eslint.config` apaga la familia `no-unsafe-*` y `restrict-template-expressions` (en JS sin anotar todo es `any`: medido el 2026-11-04 en un proyecto de 113 ficheros, 18.875 errores con la base TS y 530 sin esas reglas) y su `turno.sh` va con `TSC_EXT=""` (sin `tsc` ni `tsc-base.mjs`).
- `"reglas": false` en el marcador apaga a la vez la inyección de `core.md`, los hooks de reglas y la puerta de base (`falta la base de reglas` en `kit-issue.sh comprobar`).
- Las puertas leen el marcador de `origin/<base>` (`kit_config_base`): una PR no puede debilitar su propia puerta. Los hooks leen el del worktree, porque son un reductor de velocidad con un mensaje que dice qué hacer; la barrera es `fusionar` y el CI. Por lo mismo, si falta la herramienta de lint (126/127) o se pasa el tope, los hooks no bloquean.
- Los hooks van en el plugin (`hooks/hooks.json`), no en `.claude/settings.json` de cada repo: un agente no los quita editando el repo y se actualizan con el kit. Coste: Codex pide aprobarlos otra vez con `/hooks` cada vez que cambian.
- Deuda de un repo empezado: `eslint-suppressions.json` (nativo de ESLint) y `.agents-kit/tsc-base.json` (`{"<ruta>": <nº de errores>}`, lo comprueba `.agents-kit/tsc-base.mjs`, copia de la plantilla, para que también lo use el CI del repo). Solo baja: un fichero tocado queda a cero siempre; que crezca (una regla nueva que congela lo que rompe en otros ficheros) pasa solo con una aprobación válida que incluya el fichero de deuda. Los hallazgos de `knip` de hoy no van a deuda: van a un issue `propuesta` de limpieza, y `knip` entra en `verificar.completo` cuando se fusiona.
- `kit-on` y `kit-reglas` lanzada por Dru envían por `kit-ship-pr.sh`, sin la puerta de `kit-regla-aprobada`: son sesiones con Dru que aprueba cada pieza en el chat. `kit-ship-pr.sh` solo acepta las ramas `kit-on`, `kit-off` y `kit-reglas`: cualquier otra sale con 1.
- Lo que no se blinda, a propósito: los lockfiles, `.yarn/cache` y `.pnp.cjs` (cada dependencia nueva pediría aprobación: ruido), y los scripts de `package.json` encadenados con `npm-run-all`, `run-s`, `run-p` o `concurrently`, que el parser no sigue (blindar todo `scripts` daría ruido). Los cubren el CI y los revisores.
- Rendimiento (requisito de Dru: varias sesiones de agentes a la vez en su Mac): lint por edición sin tipos y con caché, objetivo de unos 2 s y tope de 10 s (`KIT_LINT_TIMEOUT`); fin de turno con tope de 120 s (`KIT_TURNO_TIMEOUT`); un solo lint por repo a la vez (candado en `<git-common-dir>/agents-kit/lint.lock`); nunca `knip`, lint con tipos del proyecto entero ni la suite en los hooks. Si el lint por edición con caché pasa de 2 s, va oxlint o Biome para eso.
- Tiempos medidos el 2026-11-03 en `tiktok-editor` (≈300 JS y ≈500 Python, sin TypeScript), en un worktree temporal con ESLint 10.14.0 (`js.configs.recommended`, sin tipos, `--cache`) y `ruff check` 0.15.2 del sistema, con los hooks reales alimentados por stdin: `post-edit` sobre un JS de 212 líneas, 0,21-0,40 s en frío y 0,16-0,19 s con caché; sobre un Python de 2.225 líneas, 0,07-0,11 s en frío y 0,07 s con caché; `stop-check` con 5 ficheros cambiados (3 JS y 2 Python, más 2 del andamiaje de la medición), 0,32-0,45 s en frío y 0,22-0,28 s con caché. Muy por debajo del objetivo de 2 s: no hizo falta oxlint. `tsc` y ESLint con tipos no se midieron ahí: ese repo no tiene TypeScript.
- Tiempos medidos el 2026-11-03 en `web/` de este repo (Astro 7 + TS, 22 ficheros de `src/`, `typescript` 7.0.2), en un worktree temporal, como repo git propio con la base de la skill sin commitear (`eslint.config.mjs` con `strictTypeChecked` y `eslint-plugin-astro` 3.2.1, ESLint 10.14.0, `typescript-eslint` 8.72.1, `.agents-kit/tsc-base.mjs`, `turno.sh` con `astro` en `LINT_EXT`, deuda congelada) y los hooks reales por stdin, tres veces cada uno: `post-edit` sobre un `.ts` de 181 líneas, 0,40-0,63 s en frío y 0,36-0,39 s con caché; sobre un `.astro` de 624 líneas, 0,43-0,44 s y 0,37-0,39 s; `stop-check` con 3 `.ts`, 1,79-2,33 s en frío y 0,54-0,63 s con `.tsbuildinfo` y caché; con 5 (4 `.ts` y 1 `.astro`), 2,57-2,87 s y 0,54-0,64 s. El `tsc` de TS 7 es nativo (0,2 s el proyecto entero); con el de TS 6 (`tsc6`), `stop-check` con 5 ficheros da 3,3-3,8 s en frío y 1,1-1,2 s con caché. Todo por debajo de los objetivos (2 s por edición, 120 s de tope del turno).
  - `typescript-eslint` 8.72.1 no soporta TS 7 (`typescript` 7 no trae la API de JS; peer `typescript <6.1.0`): con `typescript` 7 de dependencia, ESLint ni arranca. Para medir hizo falta la API de TS 6 (`@typescript/typescript6`) como `typescript` de `node_modules` y el `tsc` de TS 7 aparte; `astro-eslint-parser` carga `typescript` desde el `cwd`, así que no basta con anidarlo bajo `typescript-eslint`. El montaje está en la sección "TypeScript 7 o más nuevo" de `skills/kit-reglas/references/base.md`.
- Tiempos medidos el 2026-11-04 en este repo, con la base ya instalada en `web/` y los hooks reales lanzando dentro de `web/` (desde un worktree con `npm ci` recién hecho en `web/`), tres veces cada uno: `post-edit` sobre `web/src/lib/ui.ts`, 6,15 s la primera vez (ESLint en frío, sin caché) y 0,47-0,48 s después; sobre `web/src/pages/index.astro`, 0,53-0,94 s. `stop-check` con 3 `.ts` y 1 `.astro` de `web/` cambiados (y los del propio cambio en la raíz, que no tienen `turno.sh`), 6,17 s en frío y 1,81-1,83 s con caché (incluye `astro sync`).

## Stack

- Bash (scripts y tests con stubs), `jq`, `git`, `gh` (GitHub CLI).
- Node, solo para cargar el plugin de OpenCode en los tests (`tests/opencode_harness.mjs`, `tests/opencode_v2_harness.mjs`).
- Herramientas que lo cargan: Claude Code, Codex (`codex-cli`) y OpenCode (V1 y V2); versiones verificadas en "Formatos verificados".
- `web/`: Astro 7 con `@astrojs/cloudflare` 14 sobre Cloudflare Workers (KV `SEEN`), detrás de Cloudflare Access.

## Comandos

- `tests/run.sh`: ejecuta todos los tests (con stubs).
- `tests/e2e/github.sh DruMoDev/agents-kit-sandbox [--con-revisores]`: prueba de punta a punta contra GitHub de verdad (issue con eje, candado, PR, changelog, gate o CI, ronda, fichero blindado rechazado y aprobado respondiendo en el issue, fusión, limpieza, candado de un issue cerrado). Antes de cada versión; tarda minutos, lánzala con `scripts/kit-bg.sh`. Deshace lo suyo si falla.
- `scripts/release.sh <semver>`: escribe la versión en los manifiestos y el marketplace.
- `claude plugin validate .`: valida manifiestos y skills.
- `cd web && npm test && npm run e2e`: tests de la web (no los lanza `tests/run.sh`). `npm run typecheck` y `npm run lint` van en `verificar.completo`, en ese orden: `typecheck` hace antes `astro sync`, que genera `web/.astro/` (sin versionar), y sin él el lint con tipos falla en un worktree nuevo con errores `no-unsafe-*` en `src/middleware.ts`.

## Mapa del código

- `.claude-plugin/`: manifiesto y marketplace de Claude Code.
- `.codex-plugin/`: manifiesto de Codex.
- `.agents/plugins/`: marketplace de Codex.
- `bin/`: `kit-fusionar` (`kit-pr.sh fusionar` como comando suelto: Claude Code pone el `bin/` del plugin en el PATH de `Bash`; ver "Modo auto de Claude Code").
- `hooks/`: `hooks.json`, el script `session-start` y los hooks de reglas `pre-edit`, `post-edit`, `stop-check` y `pre-bash` (con `lib-reglas.sh`).
- `.opencode/plugins/agents-kit.js`: plugin de OpenCode (skills, permiso, reglas y los hooks `pre-edit`/`post-edit` alrededor de las herramientas de edición).
- `rules/`: reglas inyectadas en las sesiones.
- `skills/`: `kit-on`, `kit-off`, `kit-plan`, `kit-scout`, `kit-revisar` (revisión del diff local, sin PR), `kit-reglas` (base de lint, tipos y estructura y reglas nuevas; `references/`: `base.md`, `escalera.md`, `propuesta.md`) y `kit-run` (con `references/`: plantilla de issue, prompts del revisor (`revisor.md` y `revisor-verificar.md`), esquema JSON de la revisión y formato de ronda).
- `scripts/`: scripts mecánicos de las skills (`kit-issue.sh`, `kit-worktree.sh`, `kit-pr.sh`, `kit-ship-pr.sh` (worktree temporal de `kit-on`/`kit-off`), `kit-agents-md.sh` (diff del reordenado de `AGENTS.md`), `kit-review.sh` y `kit-review-all.sh` (modo `completa` o `verificar` por puesto, según `revision.rondas`; `--local` revisa el árbol de trabajo sin PR para `kit-revisar` o el flujo propio del repo), `kit-verify.sh` (`verificar.rapido`/`completo` del marcador y estado de hook y CI para `kit-on`), `kit-bg.sh` (lanza un comando desacoplado y espera por su fichero de salida, con tope: todas las esperas largas), `kit-changelog.sh`, `kit-notify.sh`, `kit-reglas.sh` (comprobaciones de las reglas deterministas: `estado`, `trinquete`, `blindado`, `abrir`/`cerrar` de los ficheros de reglas), `kit-skills-check.sh` (citas rotas a ficheros en las skills; los tests lo pasan sobre el propio kit)...) y `release.sh`.
- `scripts/lib/`: helpers de bash que se cargan con `source` (`github-slug.sh`, parseo del remoto `origin`; `config.sh`, configuración en tres capas; `review-seats.sh`, familia del implementador y candidatos de cada puesto de revisión; `default-branch.sh` (con `kit_fetch`, fetch que reintenta si otra sesión tiene bloqueada la referencia); `transport.sh`, dónde corre la sesión; `locks.sh`, candados de eje `refs/locks/<eje>` de los issues `serializa:<eje>` (los usan `kit-issue.sh` y `kit-pr.sh`); `ci.sh`, estado y espera del CI de un commit (solo cuentan los workflows propios de `.github/workflows/`, no los `dynamic/` de GitHub ni los resultados de code scanning; jobs que GitHub no arrancó por falta de minutos = `sin-cuota`, que pide gate local y fusiona con `--admin`; si el bloqueo es de un mes anterior, `ci_wait` relanza una vez los jobs fallidos), con tiempo máximo de `ciTimeoutMin` o del historial del repo, y `ci_gh_retry` para errores transitorios de GitHub (lo usan `kit-pr.sh` y `kit-ship-pr.sh`); `repo-hook.sh`, scripts `setup` y `checks.pre-merge` del repo; `blindado.sh`, coincidencia de los globs de `blindado`, que comparten `kit-reglas.sh` y `hooks/pre-edit`; `comments.sh`, comentarios de un issue o PR por REST y el criterio de respuesta de Dru (cuenta de `gh` y sin `<!-- kit-`), que comparten `kit-issue.sh` y `kit-pr.sh`; `permiso.sh`, la regla `Bash(kit-fusionar *)` de `.claude/settings.json`, que ponen `kit-activate.sh` (con el flujo del kit) y quita `kit-deactivate.sh`).
- `templates/`: plantillas que copia `kit-on` (`agents-kit.json`, `AGENTS.md`, `CHANGELOG.md`), `reglas/` (`tsc-base.mjs`, línea base de errores de `tsc`, y `turno.sh`, el `lint.turno` de un repo TS; las copia `kit-reglas` a `.agents-kit/` del repo) y `config.json`, valores por defecto del kit y plantilla de la configuración global `~/.agents-kit/config.json` (o `KIT_CONFIG`). Precedencia: plugin < global < marcador del repo, que solo puede definir las claves de la lista blanca de `scripts/lib/config.sh`.
- `tests/`: tests de bash con stubs (`opencode_harness.mjs` y `opencode_v2_harness.mjs` cargan el plugin de OpenCode V1 y V2 con node). `tests/fixtures/changelog/` es el contrato del formato de `CHANGELOG.md`: la web lo reutilizará para probar su parser.
- `web/`: web de changelogs (Astro + Cloudflare Workers), app aparte con su `package.json` y su base de reglas (`eslint.config.mjs`, `knip.jsonc`, `eslint-suppressions.json`, `.agents-kit/`; TS 7 con la API de TS 6 al lado, ver `skills/kit-reglas/references/base.md`). Su parser (`web/src/lib/changelog.ts`) y el validador bash comparten `tests/fixtures/changelog/`: cambiar el formato es tocar los dos y los fixtures.

## Reglas del proyecto

<!-- Reglas propias de este repo. Si alguna choca con las del kit, manda esta. -->

### Convenciones de scripts

- Scripts `kit-*`. Códigos de salida: 0 bien, 1 error de uso o rechazo, 2 error de entorno.
- Al terminar con éxito (y en la salida 2 de PR abierto) la última línea de la salida es `FIN: ...`; en los demás errores solo hay mensaje en stderr.
- Nunca recortar la salida propia con `head` ni `tail`.
- Mensajes al usuario en español, sin rayas largas.

### Formatos verificados

Verificado contra Claude Code 2.1.302 y codex-cli 0.162.1 con un plugin de prueba real (hook ejecutado y contexto recibido por el modelo en ambos).

#### Estructura del plugin (un único árbol sirve a ambas herramientas)

- `.claude-plugin/plugin.json`: manifiesto de Claude Code (`name`, `version`, `description`, `author`...).
- `.claude-plugin/marketplace.json`: marketplace de Claude Code. Entrada local: `{"name": "<plugin>", "source": "./"}`; requiere `name` y `owner` en la raíz.
- `.codex-plugin/plugin.json`: manifiesto de Codex. Probado solo con `name`, `version`, `description`; `skills: "./skills/"` e `interface` salen de la documentación y de superpowers (sin probar en el spike). Rutas relativas a la raíz del plugin, con prefijo `./`.
- `.agents/plugins/marketplace.json`: marketplace de Codex. Cada entrada necesita `name`, `source`, `policy` y `category`. Entrada local:
  ```json
  {"name": "<plugin>", "source": {"source": "local", "path": "./"},
   "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
   "category": "Developer Tools"}
  ```
- `hooks/hooks.json`: lo leen ambas herramientas con el mismo formato.

#### Hooks en Codex

- Codex SÍ carga hooks de plugin: descubre `hooks/hooks.json` por defecto.
- NO declarar `"hooks"` en `.codex-plugin/plugin.json`. Cualquier valor explícito sustituye al descubrimiento por defecto; `"hooks": {}` (lo que hace superpowers) desactiva los hooks del plugin en Codex.
- Los hooks de plugin no son de confianza al instalar: Codex los omite en silencio (verificado) hasta que el usuario los aprueba con `/hooks` en el CLI interactivo. Según la documentación, la confianza se persiste por hash de la definición del hook, y un hook nuevo o modificado vuelve a omitirse hasta que se aprueba otra vez. Sin verificar: el flujo `/hooks`, el formato exacto de la clave en `config.toml` y qué cubre el hash (solo la entrada de `hooks.json` o también el script).
- Aviso: la documentación de Codex dice que los hooks de ciclo de vida de plugins solo están soportados para plugins instalados manualmente en la app de escritorio de Codex. Aun así, en codex-cli 0.162.1 un plugin instalado por CLI desde un marketplace local ejecutó su hook. Puede cambiar en versiones futuras.
- `codex exec --dangerously-bypass-hook-trust` ejecuta hooks sin confianza persistida (solo para pruebas).
- Codex copia el plugin a `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/`; tras editar el código fuente hay que reinstalar (`codex plugin remove` + `codex plugin add`).
- Estrategia decidida: hook de plugin (no hace falta el fallback global en `~/.codex/hooks.json`).

#### Hook SessionStart (común)

- `hooks/hooks.json`:
  ```json
  {"hooks": {"SessionStart": [{"matcher": "startup|resume|clear|compact|fork",
    "hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start\""}]}]}}
  ```
- Salida para inyectar contexto, válida en ambas herramientas (emitir solo esta, sin variantes snake_case ni top-level):
  ```json
  {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "<texto>"}}
  ```
- Texto plano por stdout también se inyecta como contexto en Codex.
- Sin salida (y exit 0) = no inyecta nada; así se mantiene inerte en repos sin `.agents-kit.json`.
- El stdin es JSON e incluye `cwd` en ambas: usar `cwd` para buscar `.agents-kit.json`. Campos: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `source` (+ `model`, `permission_mode` en Codex). El proceso arranca además con el `cwd` de la sesión como directorio de trabajo.
- Valores de `source` (según la documentación): `startup`, `resume`, `clear`, `compact`; Codex añade `fork`. En el spike solo se ejecutó `source=startup`.

#### Variables de entorno en el hook

- Claude Code: `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_PROJECT_DIR`. Con marketplace de ruta local, `CLAUDE_PLUGIN_ROOT` apunta al directorio fuente (no a una copia).
- Codex: `PLUGIN_ROOT`, `PLUGIN_DATA` y los alias `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`. Usar `${CLAUDE_PLUGIN_ROOT}` en `hooks.json` para que funcione en ambas.
- No hay `CODEX_PLUGIN_ROOT`.

#### Comandos

- Claude Code:
  - `claude plugin validate <dir>` (valida `plugin.json` y `marketplace.json`; `--strict` convierte avisos en error)
  - `claude plugin marketplace add <ruta-local>`
  - `claude plugin install <plugin>@<marketplace>` (`-s user|project|local`)
  - `claude plugin uninstall <plugin>@<marketplace>`; `claude plugin marketplace remove <marketplace>`
- Codex:
  - `codex plugin marketplace add <ruta-local>`
  - `codex plugin add <plugin>@<marketplace>`
  - `codex plugin list`; `codex plugin remove <plugin>@<marketplace>`; `codex plugin marketplace remove <marketplace>`
  - No existe comando de validación de plugins.

#### OpenCode

Verificado contra opencode 1.19.0 (V1) con `opencode run` en un repo activado y en uno sin marcador.

- No lee plugins de Claude Code ni de Codex. Sus plugins son módulos JS: un fichero en `~/.config/opencode/plugins/` (se admite un enlace simbólico) se carga al arrancar.
- Lee `AGENTS.md` (o `CLAUDE.md` si falta) y skills de `.agents/skills/`, `.claude/skills/` y `.opencode/skills/`. No sigue los `@imports`.
- Hooks del plugin usados: `config` (añade `skills.paths` y, solo en repos activados, `permission.external_directory`) y `experimental.chat.messages.transform` (se ejecuta en cada paso con los mensajes recargados; hace falta una guarda para inyectar una sola vez). Mismo enfoque que superpowers.
- Sin permiso `external_directory`, `opencode run` rechaza leer o ejecutar los scripts del plugin, que están fuera del proyecto.
- OpenCode V2 (2.x), verificado el 2026-10-27 con opencode 2.1.4 (`opencode run --standalone`) y otra vez con 1.19.4 el mismo fichero: un único `export default {id, setup, server}` sirve a las dos (V1 llama a `server`, V2 a `setup`). En V2 no hay hooks por nombre ni objeto de configuración: las skills van con `ctx.skill.transform` (editor `get`/`add`), las reglas con `ctx.session.hook("context")` en `event.system` (se rehace en cada llamada al modelo y no se guarda: sin guarda) y `external_directory` está permitido por defecto: un `ask` ahí siempre es una regla del usuario, así que el plugin no toca permisos (como en V1, la regla del usuario manda). Un plugin V1 en V2 no carga: `Plugin must export a default definition with an id and an effect or setup function` en `~/.local/share/opencode/log/`.
- V2 corre por defecto en un servicio de fondo compartido: no ve el entorno del proceso (`OPENCODE_CONFIG_CONTENT`) y, en macOS, puede no tener acceso a `~/Documents` (`EPERM`, 500 en `opencode plugin list`). `--standalone` arranca un servidor propio. `--pure` ya no existe; V2 lee los permisos V1 (`permission`) y los V2 (`permissions`, lista ordenada con `action`/`resource`/`effect`). Solo lee `AGENTS.md`, sin fallback a `CLAUDE.md`.

#### Hooks de reglas en Codex y OpenCode

Verificado el 2026-11-03 con codex-cli 0.165.0, opencode 2.1.4 (`run --standalone`) y opencode 1.19.4 (de `npm install opencode-ai@1.19.4` en un directorio temporal). Cada herramienta corrió aislada: `CODEX_HOME`, `HOME` y `XDG_*` temporales, plugin instalado desde una copia y un repo de prueba con `lint` falso. El modelo era un servidor local falso que repetía llamadas a herramientas fijadas de antemano, sin credenciales ni llamadas reales: Responses API para Codex, con `model_providers` y `-m gpt-6.1-sol`, y chat completions para OpenCode, con `@ai-sdk/openai-compatible`.
- Codex (`codex exec --dangerously-bypass-hook-trust`): `PreToolUse`, `PostToolUse` y `Stop` de `hooks/hooks.json` se ejecutan.
  - Las ediciones llegan como `tool_name: "apply_patch"` con `tool_input: {"command": "<parche>"}`, el parche entero con `*** Begin Patch`. Pasa igual si el modelo llama a `apply_patch` directamente o desde `exec` (el modo código de los modelos `gpt-6.x`, `tools.apply_patch(...)`).
  - El matcher `Edit|Write|MultiEdit|NotebookEdit` ya las recoge: Codex trata `apply_patch` como `Edit`/`Write`, y un `exec_command` no entró en ese matcher. No sé qué alias exactos admite.
  - La entrada trae `session_id`, `turn_id`, `cwd`, `model` y `permission_mode`; las de herramienta, también `tool_use_id` (visto en los logs). En `PostToolUse` llega además `tool_response` en texto, y en `Stop`, `stop_hook_active` y `last_assistant_message`.
  - Exit 2 en `PreToolUse` bloquea: el fichero no se crea y el modelo recibe `Command blocked by PreToolUse hook: <stderr>. Command: <parche>`.
  - Exit 2 en `PostToolUse` sustituye la salida de la herramienta por el stderr.
  - Exit 2 en `Stop` vuelve a llamar al modelo con el stderr dentro de `<hook_prompt>`. Codex no pone tope: un `Stop` que siempre falla dio 982 vueltas en 90 s. Por eso `stop-check` lleva su propio tope de 8 bloqueos seguidos (`KIT_TURNO_BLOQUEOS`), con una cuenta por sesión en `${TMPDIR}/agents-kit-<uid>/turno-bloqueos-<sha256 del session_id>`.
  - Sin `--dangerously-bypass-hook-trust` no corre ningún hook del plugin, ni siquiera `SessionStart`.
  - `lib-reglas.sh` (`kr_input`) convierte cada fichero del parche en una entrada aparte:
    - `Add` cuenta como `Write`;
    - `Update` cuenta como `MultiEdit`, con un hunk por edición (contexto más líneas `-` frente a contexto más líneas `+`);
    - `Move to` cuenta como `MultiEdit` sobre el destino;
    - `Delete` solo pasa por el blindado.
  - Las líneas se clasifican como en Codex:
    - en un `Add`, `+` es contenido;
    - en un `Update`, ` `, `+` y `-` son del hunk (una línea vacía es contexto vacío) y `@@` es la cabecera;
    - cualquier otra línea, recortada por los dos lados, tiene que ser un marcador (`*** Begin Patch`, `*** End Patch`, `*** End of File`, `*** Add|Update|Delete File:`, `*** Move to:`), también fuera de los ficheros.
    - En Codex real, un ` *** Add File:` con un espacio delante dentro de un `Add` abre otro fichero. Las rutas se recortan.
  - El parche es ilegible, y `pre-edit` bloquea, si:
    - una línea no es nada de lo anterior;
    - una línea de contexto es un marcador una vez recortada: es ambiguo, y en Codex real un ` *** Update File: README.md` como contexto metía el `as any` en el fichero de código;
    - falta la ruta o un `Move to` está fuera de sitio.
  - Los `***` sueltos y `***negrita***` de un markdown como contexto no bloquean.
  - Con un parche ilegible, `pre-edit` saca de forma tosca las rutas que siguen a `File:` y a `Move to:`. Bloquea si alguna cae en un repo con reglas (o si las tiene el del `cwd`).
  - Las rutas se normalizan sin tocar el disco, como `path.resolve`: `nodir/../src/x.ts` es `src/x.ts`, aunque `nodir` no exista (verificado en Codex real).
- La raíz es la del repo de cada fichero, no la del `cwd` (`kr_item`): `kit-run` edita en worktrees fuera del `cwd` de la sesión.
  - Si el repo del fichero no tiene marcador (repo anidado, submódulo), se sube al repo marcado más cercano que lo contenga.
  - `pre-edit` aplica las reglas de cualquier repo con marcador, porque solo lee JSON.
  - `post-edit`, `stop-check` y el apunte de sesión solo ejecutan el lint de repos de confianza. Lo son los que cumplen dos cosas:
    - tienen el mismo `git-common-dir` (con `pwd -P`) que el repo del `cwd`, o que el repo marcado que lo contiene si el `cwd` está en un repo anidado o submódulo sin marcador;
    - son su toplevel o uno de los worktrees de `git worktree list --porcelain`.
  - Así cuentan los worktrees del mismo clon y no los repos ajenos ni un directorio con un `.git` que apunte al gitdir del clon.
  - Con el `cwd` fuera de git, o con un `git-common-dir` en el que no se puede entrar, no se ejecuta nada (y `pre-edit` bloquea si ese repo tiene reglas).
  - Una edición permitida en un worktree de confianza que no contiene el `cwd` se apunta en `${TMPDIR}/agents-kit-<uid>/sesion-<sha256 del session_id>`, y `stop-check` revisa ese repo además del del `cwd`. En ese fichero `pre-edit` (al permitir, en un repo de confianza) y `post-edit` apuntan también cada fichero editado con su raíz, y `session-start` (con `session_id` y `lint`) escribe una vez por sesión la hora de inicio y la línea base de la raíz del `cwd`: los ficheros que ya estaban cambiados, con su `git hash-object` (en `resume`, `clear`, `compact` y `fork` no se rehace). En una raíz con apuntes, `stop-check` pasa los apuntados que siguen cambiados y cualquier otro cambiado que no estuviera al empezar: fuera de la línea base o con otro hash, o, en una raíz sin línea base (un worktree creado a mitad), más nuevo que el inicio de la sesión. Se salta lo que apuntó otra sesión viva (su fichero tocado en las últimas 24 h). Así ve lo que la sesión cambió por shell y no el trabajo a medias de otras sesiones. Una raíz sin apuntes se revisa entera. En macOS las rutas se comparan sin mayúsculas.
  - Ese directorio se crea con modo 0700 (el modo se comprueba con `find -maxdepth 0 -perm 700`, igual en macOS y Linux; `stat -f` de GNU es otra cosa). Si no es nuestro, es un enlace o tiene otro modo, no se usa: ni se apunta ni se lleva la cuenta del tope, y `Stop` bloquea sin tope. Los ficheros de más de 7 días se borran al crear uno nuevo.
- OpenCode V2 (2.1.4): `setup(ctx)` tiene `ctx.tool.hook("execute.before" | "execute.after", cb)`. Lo vi en el binario y lo usé de verdad.
  - Lanzar un error en `execute.before` bloquea la herramienta, y el mensaje llega al modelo como su error.
  - `execute.after` recibe `{tool, sessionID, input, status, result: {content, output, metadata}}`. Al añadir texto a `result.content`, el modelo lo lee con el resultado.
  - Herramientas: `write {path, content}` y `edit {path, oldString, newString, replaceAll}`. Los modelos `gpt-` (sin `oss` ni `gpt-4`) usan `patch {patchText}` en su lugar, con el mismo formato de parche que Codex.
- OpenCode V1 (1.19.4): `tool.execute.before` (lanzar un error bloquea) y `tool.execute.after` (se añade texto a `output.output`).
  - Herramientas: `write`/`edit` con `filePath`. Los modelos `gpt-` usan `apply_patch {patchText}`.
  - El plugin traduce todas estas herramientas a la entrada de Claude Code o a la de `apply_patch` de Codex, y llama a `hooks/pre-edit` y `hooks/post-edit` de forma asíncrona (`execFile`, con tope: 15 s el primero; 10 s por fichero más 15 el segundo). Si un hook no puede ejecutarse, la edición pasa, como en Claude Code. Los hooks de herramienta se registran después de `session.hook("context")` y dentro de un try/catch, así que un fallo ahí no deja la sesión sin reglas. `multiedit` (V1) se traduce, pero no lo vi en uso real.
  - Verificado en las dos versiones: `as any` y un fichero blindado bloquean, y el fallo del lint llega al modelo.
- OpenCode no tiene equivalente a `Stop` que pueda bloquear: ningún hook de sesión de V2 (`context`, `generate`, `compaction`, `model.request`...) ni el evento `session.idle` de V1. `stop-check` no corre ahí, y lo frenan `fusionar` y el CI.
- Sin verificar:
  - la aprobación con `/hooks` en el CLI interactivo de Codex: tocaría la configuración real;
  - un modelo de verdad que corrige tras el bloqueo: el falso no razona;
  - `multiedit` de V1 en uso real;
  - la cifra del tope de bloqueos de `Stop` en Claude Code (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`).
- `tests/test_hooks_reglas.sh` pasa también en Linux: verificado el 2026-11-03 en docker con `debian:stable-slim` (bash 5, GNU coreutils 9.7).
- Límite conocido: las ediciones hechas por shell no pasan por `pre-edit` ni `post-edit`, igual que el `Bash` de Claude Code. En Codex se vio con un `exec_command` que escribió un fichero. En OpenCode serían `bash`/`shell`, pero no lo probé. Solo las ve `stop-check`, en Codex y Claude Code. `pre-bash` va con el matcher `Bash`, el nombre con el que llega el `exec_command` de Codex (visto arriba), y en OpenCode el plugin lo llama para su herramienta `bash` (`{command}`); sin verificar en Codex ni OpenCode reales, solo con stubs y los harness.

#### Flujo de issues (fase 2)

Verificado de punta a punta el 2026-10-19 en un repo privado de pruebas, con `claude -p "/agents-kit:kit-run"` (Claude Code 2.1.302, opencode 1.19.0):
- Issue `listo` → PR fusionada tras 2 rondas, con los tres revisores por defecto (`claude/opus`, `claude/sonnet`, `opencode/openai/gpt-6.1-sol`) publicando `kit-revision` y un `kit-ronda` por ronda; sin CI, se usó `kit-gate-local`; worktree y rama borrados al final.
- Issue con producto sin definir → comentario `kit-decision` con opciones y propuesta, `necesita-decision`, asignado a Dru, reclamo soltado, sin rama ni PR.
- Los revisores corren sin interfaz por CLI: `claude -p --permission-mode bypassPermissions --disallowedTools "Bash(git push:*)" "Bash(gh:*)"` y `opencode run` con `OPENCODE_CONFIG_CONTENT` que niega `gh *` y `git push*`; ambos respetan el bloqueo.
- `claude -p` espera 3 s a stdin si no se le pasa `</dev/null`. La salida de `opencode run` lleva códigos ANSI.

#### Changelog y avisos (fase 3)

Verificado de punta a punta el 2026-10-21 en el repo privado de pruebas con `claude -p "/agents-kit:kit-run"` (también con `SHELL=/bin/zsh`):
- Issue `listo` → PR fusionada con entrada de `CHANGELOG.md` validada por `kit-changelog.sh validar`, revisores lanzados por `kit-review-all.sh`, comentario `kit-resumen` en el issue "📦 Changelog" y aviso por ntfy (`curl` a ntfy.sh; se comprobó leyendo el tema con `https://ntfy.sh/<tema>/json?poll=1`).
- `PushNotification` de Claude Code es una herramienta del modelo: un script no puede llamarla y solo llega al móvil con Remote Control. Por eso el canal por defecto es ntfy y `claude-push` solo imprime `AVISO-CLAUDE:` para que la skill la llame.
- Un bloque de bash con arrays dentro de una skill falla si el agente lo ejecuta en zsh (`bad substitution`): lo mecánico va en scripts, no en bloques inline.

#### Web de changelogs (fase 4)

Desplegada el 2026-10-22 en `https://agents-kit-changelogs.dev-morera.workers.dev` (worker `agents-kit-changelogs`, KV `SEEN`), detrás de Cloudflare Access ("Todo el tráfico", solo el email de Dru). Verificado: sin sesión, Access redirige al login; con Access sin configurar, el worker responde 503.
- `wrangler deploy` en un proyecto Astro usa la configuración compilada (`dist/server/wrangler.json`): sin compilar antes, sube la última compilación. Por eso `npm run deploy` compila y despliega.
- Despliegue continuo con Workers Builds conectado al repo: raíz `web`, compilación `npm ci && npm run build`, despliegue `npx wrangler deploy`, solo `main` y rutas `web/*`.
- En Astro 7 con @astrojs/cloudflare 14 los bindings se leen con `import { env } from "cloudflare:workers"`; la Cache API no sirve detrás de Access ni en workers.dev, así que la caché de repos va en KV.
- `wrangler kv namespace create` pregunta en modo interactivo; sin terminal no termina.

#### Revisores por familias (v3)

Ayuda (`--help`) leída el 2026-10-22 con Claude Code 2.1.308, opencode 1.19.0 y codex-cli 0.163.0. Sin revisión real contra la red salvo donde se dice.
- Un proveedor es `{"cli": "<adaptador>", "modelos": {...}}` en `proveedores` del global; los adaptadores son `claude`, `opencode` y `codex` (`kit-review.sh`). Disponible = CLI en el PATH; un fallo de login o modelo en ejecución (motivo `acceso`) o un límite de uso agotado (motivo `cuota`) pasa al siguiente candidato del puesto. `kit-review-all.sh` da `aviso:` (Dru actúa) por cada `acceso` y por cada `cuota` de un puesto que se queda sin confirmar, e `info:` (vuelve sola) por la `cuota` de un puesto que cubre otro candidato.
- Textos reales de cada fallo (vistos el 2026-11-04 con Claude Code 2.1.318 y codex-cli 0.165.0; la cuota, en `~/.agents-kit/tmp/revision.*` de revisiones reales de octubre y noviembre). Todos salen con código 1. Claude, en `result` del JSON con `is_error: true`: cuota `You've hit your 5-hour limit · resets 1:40am (Europe/Madrid)` y `You've hit your session limit · resets ...`; sin login (`CLAUDE_CONFIG_DIR` vacío) `Not logged in · Please run /login`; modelo inexistente `There's an issue with the selected model (<m>). It may not exist...` (`api_error_status: 404`). Codex, en stderr, después de repetir el prompt, en sus últimas líneas `ERROR: ...`: cuota `You’ve hit your usage limit. Upgrade to Pro (...) or try again at 1:50 PM.` (apóstrofo tipográfico); sin login (`CODEX_HOME` vacío) `unexpected status 401 Unauthorized: Missing bearer or basic authentication...`; modelo inexistente `{"type":"error","status":400,...,"code":"model_not_found"}`. `kit-review.sh` (`access_fail`) cuenta como cuota `hit your ... limit` en el `result` de Claude o en la última línea de stderr si es `ERROR: `: el prompt repetido puede traer ese texto desde la PR. Sin verificar: un 429 o el límite semanal (se quedan en `acceso`, salvo que digan `hit your ... limit`) y cualquier fallo de OpenCode, que no está en los proveedores de Dru.
- Las tres invocaciones corren en el clon desechable, con stdin cerrado, sin `GH_TOKEN`/`GITHUB_TOKEN`, con `GH_CONFIG_DIR` vacío, `GIT_CONFIG_GLOBAL=/dev/null`, `credential.helper` vacío y sin variables `CLAUDE*`, `CODEX_*`, `OPENCODE*` de la sesión (se conservan `CLAUDE_CONFIG_DIR` y `CODEX_HOME`, que guardan el login).
- `claude -p --model <m> --permission-mode bypassPermissions --setting-sources user --strict-mcp-config --no-session-persistence --disallowedTools "Bash(git push:*)" "Bash(gh:*)" --output-format json --json-schema <esquema> <prompt>`. Banderas en la ayuda. Sin verificar aquí: que la respuesta traiga `structured_output` e `is_error` (lo usa la skill `peer-review` de Aikosmo).
- `opencode run --pure --format json -m <m> [-s <sesión>] <prompt>` (en opencode 2.x, `--standalone` en vez de `--pure`, según `opencode --version`; verificado con 2.1.4: mismos eventos JSON y `gh`/`git push` denegados) con `OPENCODE_CONFIG_CONTENT` que niega `gh *` y `git push*`. Banderas en la ayuda (`--format json` = eventos JSON en crudo; `--pure` = sin plugins externos). Sin verificar aquí: los eventos `text` (`part.text`, `part.messageID`), `error` y `sessionID` (de `peer-review`). Sin esquema nativo: va en el prompt, y una respuesta fuera de esquema tiene un reintento en la misma sesión (`-s`).
- `codex exec --ephemeral --ignore-user-config --ignore-rules --sandbox workspace-write -c 'approval_policy="never"' -c sandbox_workspace_write.network_access=false --color never -m <m> -C <clon> --output-schema <fichero> -o <fichero> <prompt>`. Banderas en la ayuda; codex-cli 0.163.0 aceptó esta línea completa (arrancó con `approval: never` y salió con código 1 con un modelo inexistente; fue una ejecución accidental de un test). `gh` y `git push` quedan bloqueados porque el sandbox `workspace-write` no tiene red (y no hay credenciales); `--ignore-user-config` evita servidores MCP del usuario con tokens. Sin verificar: que `approval_policy` y `sandbox_workspace_write.network_access` sean las claves exactas en 0.163.0, que el sandbox bloquee la red en macOS en ejecución anidada, y que `-o` escriba el JSON del esquema. Codex lee stdin aunque sea `/dev/null` ("Reading additional input from stdin..."), sin efecto.
- Entorno del implementador: `CODEX_THREAD_ID` en Codex y `CLAUDECODE` en Claude Code (los usa `peer-review`); `OPENCODE` en OpenCode, sin verificar aquí.

#### GitHub en uso real (e2e de la 3.5)

Visto con `tests/e2e/github.sh` el 2026-10-23, no con stubs:
- `git push -q` sigue escribiendo en stderr las líneas `remote: Create a pull request...` de GitHub: un script que mezcla stderr con su salida las cuela antes de su primera línea. Los pushes del kit las ocultan salvo si fallan.
- Tras un push, la PR tarda unos segundos en reflejar el nuevo head (`headRefOid`): comparar justo después da un falso "la PR apunta a otro commit". `esperar-ci` espera hasta 60 s si el commit ya está en origin.
- Los workflows integrados de GitHub (Dependabot, CodeQL por defecto, Copilot) salen en `actions/workflows` con ruta `dynamic/...`, y los resultados de code scanning publican checks de la app `github-advanced-security` en las PRs (comprobado en `dependabot/dependabot-core` y `github/codeql-action`): ninguno es CI del repo.

#### Modo auto de Claude Code

Visto el 2026-10-27 (2.1.311) y el 2026-11-03 (2.1.317): en el modo auto, el clasificador niega `kit-pr.sh fusionar` con el motivo "Merge Without Review", aunque la PR haya pasado las rondas y el CI; en `bypassPermissions` no hay clasificador. Verificado el 2026-11-03 con 2.1.317 (`claude -p --plugin-dir <plugin> --permission-mode dontAsk` en un repo de prueba):
- Los ficheros del `bin/` del plugin están en el PATH de `Bash` y se llaman por su nombre suelto.
- Una regla `Bash(<comando> *)` en `permissions.allow` deja pasar ese comando; sin ella, `dontAsk` lo niega.
- Las reglas `allow` del `.claude/settings.json` versionado solo valen en una carpeta de confianza (aceptada en interactivo). Si no, sale `Ignoring 1 permissions.allow entry from .claude/settings.json: this workspace has not been trusted` (`settings.local.json`, sin versionar, no lo necesita).
- Según la documentación (sin verificar contra el clasificador real): una acción que casa con una regla `allow` se resuelve sin el clasificador del modo auto; un plugin no puede traer reglas de permisos (su `settings.json` solo admite `agent` y `subagentStatusLine`); un hook `PreToolUse` que devuelve `allow` no consta como vía para saltarse el clasificador.
- Por eso la regla nombra `kit-fusionar` sin comodín delante: con un `*` delante del comando (por ejemplo `Bash(*kit-pr.sh fusionar *)`) casaría cualquier programa cuya línea contenga ese texto.
- En uso real, el 2026-11-04 (Claude Code de una sesión de Dru en modo auto): `kit-fusionar` como comando suelto pasó el clasificador y fusionó las PRs #35, #37 y #38.

#### Fusión en Codex y OpenCode

Visto el 2026-11-04 con codex-cli 0.165.0, opencode 2.1.4 (`run --standalone`) y opencode 1.19.4, aislados como en "Hooks de reglas en Codex y OpenCode" (`HOME`, `CODEX_HOME` y `XDG_*` temporales, modelo falso local que pide una sola llamada a la herramienta de shell). El comando, en un clon de `DruMoDev/agents-kit-sandbox`: una sonda (escribir fuera del repo y en su `.git`, `curl` a `api.github.com`, `gh api user`, `git ls-remote`), `kit-pr.sh fusionar <clon> 999999 12` y `kit-ship-pr.sh fusionar <clon> kit-on`. Con acceso completo, el primero llega a GitHub y sale con 2 (`no se pudo leer la PR #999999`) y el segundo con 1 (`no hay un PR abierto desde 'kit-on'`): así se ve hasta dónde llegan sin fusionar nada.
- Ninguna de las tres herramientas tiene un clasificador ni pide aprobación para ese comando: lo ejecutan.
- OpenCode V1 y V2, con permisos por defecto, con y sin el plugin del kit: ejecuta con red, `gh` autenticado y escritura fuera del repo y en `.git`. Los dos scripts llegan a GitHub. No frena la fusión.
- Codex (`codex exec -c 'approval_policy="never"'`): lo frena el sandbox, no un permiso. Sin preguntar, ejecuta el comando dentro del sandbox, y el comando falla:
  - El sandbox por defecto fue `read-only` con el repo sin confianza y `workspace-write` con el repo de confianza (`trust_level = "trusted"` en `config.toml`, como los repos de Dru; tras las primeras ejecuciones, Codex lo escribió solo en el `config.toml` temporal).
  - En los dos: sin red (`Could not resolve host`, `CODEX_SANDBOX_NETWORK_DISABLED=1`), sin escribir fuera del directorio de trabajo, `/tmp` y `$TMPDIR`, y con el `.git` del repo en solo lectura aunque esté dentro.
  - `kit-pr.sh fusionar` sale con 2 en `gh api user` y `kit-ship-pr.sh fusionar` con 2 (`gh no autenticado`). Lo mismo le pasaría a cualquier paso de `kit-run` que use `gh` o `git push`, y a todo lo que escribe en `~/.agents-kit/worktrees`.
  - Con `-c sandbox_workspace_write.network_access=true`, `gh` tiene red y está autenticado, pero `kit-ship-pr.sh fusionar` falla en `git fetch` (`cannot open '.git/FETCH_HEAD': Operation not permitted`).
  - Con `--dangerously-bypass-approvals-and-sandbox` (`danger-full-access`) la sonda escribe en todas partes y tiene red.
- Codex, dos vías por repo, probadas con `codex exec` en el sandbox por defecto (de confianza):
  - Un `.codex/config.toml` del repo se aplica: con `[sandbox_workspace_write]`, `network_access = true` y `writable_roots` (rutas absolutas; el `.git` del repo vale si se nombra), los dos scripts llegan a GitHub. Abre la red a cualquier comando del agente en ese repo.
  - Un `.codex/rules/<nombre>.rules` del repo se aplica: `prefix_rule(pattern = ["<ruta del script>"], decision = "allow")` ejecuta ese comando fuera del sandbox, con red y escritura, y lo demás sigue dentro. Pero Codex no pone el `bin/` del plugin en el PATH (`kit-fusionar` no está), así que la regla tiene que nombrar la ruta absoluta del script, y en Codex esa ruta lleva la versión del plugin (`~/.codex/plugins/cache/agents-kit/agents-kit/<versión>/scripts/`).
- Decidido por Dru (#32): ningún cambio en el repo. En Codex, `kit-run` y `kit-on` se lanzan sin sandbox (`--sandbox danger-full-access`), y `kit-issue.sh comprobar` sale con 1 antes de llamar a `gh` si ve `CODEX_SANDBOX_NETWORK_DISABLED=1`, para que `kit-run` pare al arrancar y no a mitad. Visto con codex-cli 0.165.0 (`codex exec`, mismo montaje): con el sandbox por defecto sale con 1 y ese mensaje; con `network_access=true`, `FIN: v3`. Las suites que llaman a `comprobar` quitan esa variable: un revisor de Codex corre los tests dentro de su sandbox.
- Sin verificar: la aprobación interactiva de Codex (`on-request`, la que pide subir de sandbox), un modelo real que pide `sandbox_permissions: require_escalated`, y los modos de aprobación de OpenCode configurados por el usuario.

#### Sin minutos de Actions

Visto el 2026-10-25 en `DruMoDev/video-editor` (privado, cuenta Free): agotados los minutos, cada job sale como check run `failure`, sin pasos ni runner, en 1-2 s, con una anotación `failure` "The job was not started because recent account payments have failed or your spending limit needs to be increased...". El run y el check suite también salen `failure`. Según la documentación de GitHub, los 2000 min de Free son de la cuenta (todos sus repos privados), vuelven al empezar el periodo de facturación (día 1, 00:00 UTC) y los repos públicos no gastan. Leer el uso por API (`/users/<u>/settings/billing/usage`) pide el scope `user` de `gh`.

#### agents-kit v3

Verificado de punta a punta el 2026-10-22 en el repo privado de pruebas (`claude -p`, Claude Code 2.1.302, opencode 1.19.0, codex-cli 0.163.0):
- `kit-on` sobre un repo v2 con el árbol sucio: modo actualizar por PR desde un worktree temporal, sin tocar el árbol; etiquetas v3 creadas, claves v2 fuera del marcador, `~/.agents-kit/config.json` creado. `kit-issue.sh comprobar` rechaza el repo hasta el `git pull`.
- `kit-run` con los puestos por defecto e implementador Claude: puestos 1 y 2 a `gpt/openai/gpt-6.1-sol` por OpenCode, puesto 3 a `claude/sonnet`; marcadores `kit-revision: puesto <i> ...` y ronda completa aceptada por `fusionar`.
- Fallback real: con `gpt` en `cli: "codex"`, Codex rechazó el modelo (`not supported when using Codex with a ChatGPT account`); los puestos `otra` cayeron en Claude, la ronda lo anotó y el resumen pidió cambiar `proveedores.gpt.modelos`.
- Con la cuenta de ChatGPT de Dru sin plan, `codex exec` rechazó todos los modelos. Con el plan Plus (verificado el 2026-10-27, codex-cli 0.163.0), la línea completa del adaptador revisó de verdad con `gpt-6-astra` y con `gpt-6.1-sol` (informes válidos contra el esquema), y un modelo inexistente salió con código 1, motivo `acceso`, y el puesto cayó a `claude/opus`. Los errores `401 token_expired` al refrescar la lista de modelos no impiden la ejecución.
