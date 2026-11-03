# Reglas deterministas: plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: usa superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para implementar este plan tarea a tarea. Los pasos usan casillas (`- [ ]`) para el seguimiento.

**Objetivo:** que cada repo TS con el kit tenga una base obligatoria de lint, tipos y estructura que los agentes no pueden saltarse, con reglas propias aprobadas por Dru y una deuda que solo puede bajar.

**Arquitectura:**
- La configuración de las reglas vive en cada repo. El kit aporta cuatro piezas:
  - un script de comprobaciones, `scripts/kit-reglas.sh`;
  - un comprobador de la línea base de `tsc`, `templates/reglas/tsc-base.mjs`, que se copia al repo para que también lo use su CI;
  - tres hooks de plugin: antes de editar, después de editar y al terminar el turno;
  - puertas nuevas en `kit-pr.sh fusionar` y en `kit-issue.sh comprobar`.
- Una skill nueva, `kit-reglas`, instala la base y añade reglas, siempre con el OK de Dru.

**Stack:** bash (scripts y tests con stubs, como el resto del kit), `jq`, Node para `tsc-base.mjs` (sin dependencias), hooks de Claude Code (`PreToolUse`, `PostToolUse`, `Stop`).

**Spec:** [`docs/superpowers/specs/2026-11-03-reglas-deterministas-design.md`](../specs/2026-11-03-reglas-deterministas-design.md). Léelo entero antes de empezar: este plan razona desde él.

## Restricciones globales

- Convenciones de `AGENTS.md`:
  - scripts `kit-*`;
  - exit 0 bien, 1 uso o rechazo, 2 entorno;
  - última línea `FIN: ...` al terminar bien;
  - mensajes en español, sin rayas largas (U+2014);
  - nunca recortar la salida con `head` ni `tail`.
- Cada script nuevo empieza con la cabecera de uso que tienen los demás (ver `scripts/kit-verify.sh:1-21`).
- Las puertas leen el marcador de `origin/<rama por defecto>` (`kit_config_base`), nunca el del worktree: una PR no puede debilitar su propia puerta.
- Ninguna versión de dependencia de memoria: `kit-reglas` consulta el registro (`npm view <paquete> version`).
- Rendimiento:
  - hook después de editar: objetivo de 2 s y tope duro de 10 s (`KIT_LINT_TIMEOUT`);
  - hook al terminar el turno: tope de 120 s (`KIT_TURNO_TIMEOUT`);
  - un solo proceso de lint por repo a la vez (candado);
  - ni `knip` ni la suite completa en los hooks.
- Los hooks quedan inertes (exit 0 sin salida) si:
  - no hay `.agents-kit.json`;
  - el marcador tiene `"reglas": false`;
  - el marcador no tiene `lint`;
  - la entrada del hook no trae una ruta de fichero.
- Si falta la herramienta de lint (exit 126 o 127), los hooks no bloquean: la garantía es `fusionar` y el CI.
- `rules/core.md` se queda en 140 líneas o menos (`tests/test_rules.sh`).
- Las descripciones de las skills tienen 200 caracteres o menos y no usan él/ella (`tests/test_skills.sh`).

## Decisiones de este plan (técnicas, sobre lo que el spec deja al builder)

- **Claves nuevas del marcador**, que se añaden a la lista blanca `_KIT_REPO_KEYS` de `scripts/lib/config.sh`:
  - `lint`: `{"fichero": {"<ext>,<ext>": "<comando>"}, "turno": "<comando>"}`. Que exista equivale a "base instalada".
  - `blindado`: lista de rutas o globs, con valor por defecto en `templates/config.json`.
- **Valor por defecto de `blindado`:**
  ```
  eslint.config.*  *tsconfig*.json  knip.*  .dependency-cruiser.*  sgconfig.yml  eslint-suppressions.json
  .agents-kit/  .agents-kit.json  lefthook.yml  .husky/  .github/workflows/  reglas/
  ```
  Además, en `package.json`, cualquier cambio en `scripts.lint*` y `scripts.typecheck*` y quitar dependencias cuyo nombre contenga `eslint`, `typescript`, `knip` o `dependency-cruiser`.
- **Deuda:**
  - lint: `eslint-suppressions.json` (nativo de ESLint, que lo aplica solo);
  - tipos: `.agents-kit/tsc-base.json`, de la forma `{"<ruta>": <nº de errores>}`, comprobado por `.agents-kit/tsc-base.mjs`, copia de `templates/reglas/tsc-base.mjs`.
- **Aprobación de reglas, respondiendo (decisión de Dru: nada de etiquetas).**
  1. `kit-pr.sh regla` publica en la PR `<!-- kit-regla: <hash> -->` con la explicación. `<hash>` es el `sha256` del diff de los ficheros blindados frente a `origin/<base>`.
  2. Después, `kit-issue.sh decision` publica la pregunta en el issue, pone `necesita-respuesta` y avisa.
  3. Dru responde con un comentario normal en el issue o en la PR.
  4. **Retomar sin tocar etiquetas:** `kit-issue.sh siguiente` vuelve a dar por disponible un issue en `necesita-respuesta` cuando, después de su último `<!-- kit-decision -->`, hay un comentario de la cuenta del kit sin marcador `<!-- kit-`. `reclamar` le quita `necesita-respuesta`. Esto vale para cualquier decisión, no solo para reglas.
     - Requisito que el builder comprueba: todo comentario que publican los scripts del kit lleva un marcador `<!-- kit-...`. Si alguno no lo lleva, se le añade.
  5. El agente lee la respuesta con `kit-issue.sh leer`.
     - Si Dru aprueba: `kit-pr.sh aprobar-regla <wt> <pr> <id-del-comentario-de-Dru>` publica `<!-- kit-regla-aprobada: <hash> <id> -->`.
     - Si rechaza: quita el commit de la regla.
  6. `fusionar` exige un `kit-regla-aprobada` con el hash actual. El `<id>` tiene que ser un comentario de la cuenta del kit, sin marcador, publicado en el issue o en la PR después del último `kit-regla`.
  7. Si el diff blindado cambia después, hace falta otra propuesta y otra respuesta.
  8. **En una sesión con Dru (chat):** el agente publica la respuesta de Dru tal cual, citada, como comentario en la PR (`kit-pr.sh aprobar-regla <wt> <pr> --chat <fichero>`, que publica el comentario y el marcador). Hay una limitación conocida, ya en el spec: con la misma cuenta de `gh`, un agente que quisiera engañar podría falsificarla.
- **Cómo pasa una edición aprobada el hook de antes de editar:** el hook deja pasar las ediciones de ficheros blindados si existe `$(git rev-parse --git-common-dir)/agents-kit/reglas-abiertas` con el `session_id` de la sesión. Lo crea `kit-reglas.sh abrir <wt> <session_id>` y lo borra `kit-reglas.sh cerrar <wt>`. Es un reductor de velocidad con un mensaje que dice qué hacer, no una barrera: la barrera es `fusionar`. Nunca se permiten `eslint-disable`, `@ts-ignore`, `@ts-nocheck` ni `as any`.
- **`knip` en repos empezados:** al instalar la base, sus hallazgos de hoy no van a un fichero de deuda. `kit-reglas` abre un issue de limpieza (`propuesta`, con la lista), y `knip` entra en `verificar.completo` cuando ese issue se fusiona.

## Foco de la revisión

1. **Hook con una ruta con espacios, relativa o fuera del repo:** el hook la resuelve contra el `cwd` de la entrada y no hace nada fuera del repo (tarea 5).
2. **Worktree recién creado, sin `node_modules`:** el comando de lint sale con 127 y el hook no bloquea ni repite el error en bucle (tarea 5).
3. **Dos sesiones editando el mismo repo a la vez:** la segunda no lanza otro lint mientras el primero sigue vivo, y un candado de un proceso muerto no se queda para siempre (tarea 5).
4. **Ficheros borrados o renombrados en lo cambiado:** el hook de fin de turno no le pasa al linter rutas que no existen. En `trinquete`, renombrar un fichero con deuda cuenta como tocarlo (tarea 3).
5. **Un fichero de deuda que encoge frente a uno que crece:** encoger no pide aprobación; crecer, o añadir una entrada nueva, sí (tareas 3 y 4).

---

### Tarea 1: claves `lint` y `blindado` en la configuración

**Ficheros:**
- Modificar: `scripts/lib/config.sh:9` (`_KIT_REPO_KEYS`).
- Modificar: `templates/config.json` (añadir `blindado` por defecto).
- Test: `tests/test_config.sh`.

**Interfaces:**
- Produce: `kit_config <raíz> '.lint'` y `kit_config_base <wt> '.blindado[]' origin/<base>` devuelven los valores del marcador, o los del plugin si el marcador no los define.

- [ ] **Paso 1: tests que fallan** en `tests/test_config.sh`:
  - un marcador con `{"lint":{"turno":"x"}}` hace que `kit_config "$r" .lint.turno` dé `x`, sin aviso de clave ignorada en stderr;
  - sin `blindado` en el marcador, `kit_config "$r" '.blindado | index("eslint.config.*")'` no es `null`;
  - un `blindado` en el marcador sustituye la lista entera.
- [ ] **Paso 2:** `bash tests/test_config.sh`. Esperado: FAIL, porque `lint` se ignora con un aviso.
- [ ] **Paso 3:** añadir `"lint","blindado"` a `_KIT_REPO_KEYS` y la lista por defecto (sección "Decisiones") a `templates/config.json`.
- [ ] **Paso 4:** `bash tests/test_config.sh`. Esperado: `ok`.
- [ ] **Paso 5:** commit (`git add scripts/lib/config.sh templates/config.json tests/test_config.sh`).

### Tarea 2: comprobador de la línea base de `tsc`

**Ficheros:**
- Crear: `templates/reglas/tsc-base.mjs` (Node ≥ 20, sin dependencias).
- Test: `tests/test_tsc_base.sh` (con un `tsc` falso por `KIT_TSC`).

**Interfaces:**
- Produce: `node tsc-base.mjs generar` y `node tsc-base.mjs comprobar [--cambiados <fichero>...]`. Lo usan la tarea 3 (trinquete), la 5 (`lint.turno`) y el CI del repo.
  - Lanza `${KIT_TSC:-npx tsc} --noEmit --incremental --pretty false` en el directorio actual y cuenta los errores por fichero con el patrón `^(.+?)\(\d+,\d+\): error TS\d+`, con las rutas relativas a la raíz.
  - `generar` escribe `.agents-kit/tsc-base.json` (claves ordenadas) y termina con `FIN: <n> ficheros con deuda`.
  - `comprobar` sale con 1 si se da alguno de estos casos:
    - un fichero tiene más errores que su línea base;
    - un fichero sin línea base tiene errores;
    - un fichero de `--cambiados` tiene cualquier error, aunque esté en la línea base.

    Imprime cada error que cuenta y, si todo va bien, `FIN: ok`. Sin `tsc-base.json`, la línea base vacía equivale a "ningún error permitido".

- [ ] **Paso 1: tests que fallan.** Un `tsc` falso que imprime `src/a.ts(1,1): error TS1: x` dos veces y `src/b.ts(3,4): error TS2: y` una vez:
  - `generar` escribe `{"src/a.ts":2,"src/b.ts":1}`;
  - `comprobar` da exit 0;
  - con 3 errores en `a.ts`, exit 1 y la salida nombra `src/a.ts`;
  - `comprobar --cambiados src/b.ts` da exit 1;
  - un error en `src/c.ts` da exit 1.
- [ ] **Paso 2:** `bash tests/test_tsc_base.sh`. Esperado: FAIL (no existe).
- [ ] **Paso 3:** implementar `templates/reglas/tsc-base.mjs`.
- [ ] **Paso 4:** `bash tests/test_tsc_base.sh`. Esperado: `ok`.
- [ ] **Paso 5:** commit.

### Tarea 3: `scripts/kit-reglas.sh`

**Ficheros:**
- Crear: `scripts/kit-reglas.sh`.
- Test: `tests/test_reglas.sh` (repo real con origin local, como `tests/test_verify.sh:5-11`).

**Interfaces:**
- Consume: `kit_config_base` y `.blindado` (tarea 1), `.agents-kit/tsc-base.json` (tarea 2).
- Produce: estos subcomandos, que usan las tareas 4, 5 y 7.
  - `estado <wt>`: una línea por hecho y al final `FIN: base completa` o `FIN: base incompleta`.
    - `lenguajes: ts|py|sh,...`: `ts` si existen `tsconfig.json` o `typescript` en `package.json`; `py` si existe `pyproject.toml`; `sh` si hay `*.sh` versionados.
    - `lint: declarado|sin declarar`.
    - `tsconfig: <flag> sí|no`, una por cada flag de la base del spec.
    - `eslint: strictTypeChecked sí|no` y `noInlineConfig sí|no` (grep sobre `eslint.config.*`).
    - `knip: sí|no` y `deuda-lint: <n entradas>|ninguna`.
    - `deuda-tsc: <n ficheros>|ninguna`.

    Es completa cuando `lint` está declarado y todas las líneas de `ts` dicen `sí`, o cuando no hay `ts`.
  - `trinquete <wt> <ref>`: exit 1, con una línea por motivo, en dos casos:
    - un fichero cambiado o borrado en `<ref>...HEAD` (`--no-renames`) sigue teniendo entradas en `eslint-suppressions.json` o en `tsc-base.json` del HEAD: `deuda en fichero tocado: <ruta> (lint|tipos)`;
    - el fichero de supresiones o la línea base añaden una clave o suben una cuenta frente a `<ref>`: `la deuda crece: <ruta> <regla>`.

    Si no, `FIN: ok`.
  - `blindado <wt> <ref>`: lista los ficheros blindados cambiados (globs de `.blindado` con `fnmatch` de bash; una entrada acabada en `/` es un prefijo) y los cambios de `package.json` descritos en "Decisiones", una línea por cada uno. Al final, `hash: <sha256 del diff de esos ficheros>` y `FIN: <n>`. `FIN: 0` sin línea `hash` si no hay ninguno. Un cambio que solo encoge `eslint-suppressions.json` o `tsc-base.json` no cuenta.
  - `abrir <wt> <session_id>` y `cerrar <wt>`: crean o borran `<git-common-dir>/agents-kit/reglas-abiertas` con el `session_id`, y terminan en `FIN: abierto` o `FIN: cerrado`.

- [ ] **Paso 1: tests que fallan**, uno por comportamiento de la interfaz:
  - `estado` en un repo sin TS da `FIN: base completa`;
  - con `tsconfig.json` sin `noUncheckedIndexedAccess`, `base incompleta`;
  - `trinquete` falla al tocar `src/a.ts` si está en las supresiones;
  - `trinquete` pasa si la misma PR quita sus entradas;
  - `trinquete` falla al añadir una entrada a un fichero no tocado;
  - borrar `src/a.ts` con deuda falla hasta podar la entrada;
  - `blindado` lista `eslint.config.mjs` y `package.json (scripts.lint)`, y no lista `package.json` si solo se añade una dependencia;
  - `blindado` da el mismo `hash` dos veces seguidas y otro tras otro cambio;
  - un `eslint-suppressions.json` que solo encoge da `FIN: 0`;
  - `abrir` y `cerrar` crean y borran el fichero.
- [ ] **Paso 2:** `bash tests/test_reglas.sh`. Esperado: FAIL.
- [ ] **Paso 3:** implementar `scripts/kit-reglas.sh` (ejecutable).
- [ ] **Paso 4:** `bash tests/test_reglas.sh`. Esperado: `ok`.
- [ ] **Paso 5:** commit.

### Tarea 4: puertas en `fusionar` y `comprobar`, más `kit-pr.sh regla`

**Ficheros:**
- Modificar: `scripts/kit-pr.sh`:
  - subcomando nuevo `regla <wt> <pr> <fichero>`;
  - en `fusionar`, motivos nuevos antes de `report` (cerca de `:424`);
  - uso y cabecera.
- Modificar: `scripts/kit-issue.sh`:
  - `comprobar`, `:345`;
  - `siguiente` y `reclamar`: issue respondido de vuelta en el reparto y fuera `necesita-respuesta` al reclamar;
  - la cabecera.
- Modificar: los scripts que publican comentarios sin marcador `<!-- kit-`, si los hay.
- Test: `tests/test_pr.sh` y `tests/test_issue.sh`.

**Interfaces:**
- Consume: `kit-reglas.sh trinquete`, `blindado` y `estado` (tarea 3).
- Produce:
  - `kit-pr.sh regla <wt> <pr> <fichero>`: publica el contenido de `<fichero>` en la PR precedido de `<!-- kit-regla: <hash> -->`, con el hash de `kit-reglas.sh blindado <wt> origin/<base>`, y termina en `FIN: <url>`. Exit 1 si `blindado` da `FIN: 0`.
  - Motivos de `fusionar`:
    - si el marcador base tiene `lint`, cada línea de `kit-reglas.sh trinquete` es un motivo;
    - si `blindado` da `n > 0`: `la PR cambia ficheros de reglas (<lista>) sin la aprobación de Dru: kit-pr.sh regla y espera su respuesta`, salvo que haya un `kit-regla-aprobada` válido (sección "Decisiones").
  - `kit-pr.sh aprobar-regla <wt> <pr> <id-comentario> | --chat <fichero>`: comprueba que el comentario es válido (sección "Decisiones") o publica la cita del chat, escribe `<!-- kit-regla-aprobada: <hash> <id> -->` y termina en `FIN: aprobada`. Exit 1 si no hay `kit-regla` con el hash actual o si el comentario no vale.
  - `kit-issue.sh comprobar`: exit 1 con `falta la base de reglas: ejecuta kit-reglas`, si `kit-reglas.sh estado` da `base incompleta` en un repo con `ts` y el marcador no tiene `"reglas": false`.

- [ ] **Paso 1: tests que fallan.**
  - `fusionar` rechaza una PR que toca `eslint.config.mjs` sin `kit-regla`.
  - `aprobar-regla` rechaza un comentario anterior al `kit-regla`, uno con marcador `<!-- kit-` y uno de otra cuenta.
  - `fusionar` acepta tras `aprobar-regla` con una respuesta posterior válida.
  - `fusionar` la rechaza otra vez si el diff blindado cambia tras aprobar (hash distinto).
  - `siguiente` da por disponible un issue en `necesita-respuesta` con una respuesta sin marcador posterior a su `kit-decision`, y no da uno sin respuesta.
  - `reclamar` le quita `necesita-respuesta`.
  - La rechaza con deuda en un fichero tocado.
  - `regla` sin ficheros blindados da exit 1.
  - `comprobar` rechaza un repo TS sin `lint` y acepta uno con `"reglas": false`.
- [ ] **Paso 2:** `bash tests/test_pr.sh && bash tests/test_issue.sh`. Esperado: FAIL en los casos nuevos.
- [ ] **Paso 3:** implementar.
- [ ] **Paso 4:** `tests/run.sh`. Esperado: todo PASS.
- [ ] **Paso 5:** commit.

### Tarea 5: hooks del plugin

**Ficheros:**
- Crear:
  - `hooks/lib-reglas.sh`: raíz desde el `cwd` de la entrada, marcador, `lint` y candado;
  - `hooks/pre-edit`, `hooks/post-edit` y `hooks/stop-check`, todos ejecutables.
- Modificar: `hooks/hooks.json`:
  - `PreToolUse` y `PostToolUse` con matcher `Edit|Write|MultiEdit|NotebookEdit`;
  - `Stop`;
  - comando `"${CLAUDE_PLUGIN_ROOT}/hooks/<nombre>"`.
- Test: `tests/test_hooks_reglas.sh`.

**Interfaces:**
- Consume: `.lint` del marcador del worktree (en la sesión el marcador es el local; la garantía es `fusionar`), `.blindado` y el fichero de `kit-reglas.sh abrir` (tarea 3).
- Produce: el comportamiento de los hooks.
  - `pre-edit`: lee `tool_input.file_path`, más `content`, `new_string` o `edits[].new_string`, y `session_id`. Sale con 2 y un mensaje con el remedio en estos casos:
    - el texto nuevo contiene `eslint-disable`, `@ts-ignore`, `@ts-nocheck` o `as any` (con límite de palabra). El mensaje es: "No desactives reglas ni tipos: arregla la causa. Si la regla está mal, propón el cambio (kit-reglas).";
    - la ruta es blindada y no hay `reglas-abiertas` con ese `session_id`. El mensaje es: "Fichero de reglas: solo se cambia con la aprobación de Dru (skill kit-reglas, o en kit-run un commit propio y kit-pr.sh regla)."
  - `post-edit`: busca la extensión del fichero en las claves de `.lint.fichero` (lista separada por comas) y ejecuta `<comando> <ruta>` desde la raíz:
    - con `perl alarm`, como `kit_hook_run`, y tope `KIT_LINT_TIMEOUT` (10 s);
    - candado `mkdir <git-common-dir>/agents-kit/lint.lock`, que se da por muerto si es más viejo que el tope;
    - si el candado está ocupado, exit 0;
    - si falla (exit distinto de 0, 126 y 127), exit 2 con la salida en stderr.
  - `stop-check`: los ficheros cambiados que existen (`git diff --name-only HEAD` más los no versionados de `git ls-files --others --exclude-standard`) se pasan como argumentos a `.lint.turno`:
    - mismo candado, tope `KIT_TURNO_TIMEOUT` (120 s);
    - exit 2 si falla;
    - nada que hacer si no hay cambios.

- [ ] **Paso 1: tests que fallan.** Cada hook se alimenta por stdin con JSON y un `lint` falso (scripts que escriben un registro y salen con el código que se pida).
  - **Inerte:** sin marcador, con `"reglas": false` o sin `lint`, los tres hooks dan exit 0 sin salida.
  - **`pre-edit`:**
    - `as any` da exit 2 y el mensaje;
    - `const x = any` no bloquea;
    - `eslint.config.mjs` da exit 2;
    - con `abrir` para ese `session_id` pasa, y con otro `session_id` no.
  - **`post-edit`:**
    - lint falso con exit 1 da exit 2 y su salida;
    - exit 127 da exit 0;
    - un fichero `.md` no lanza nada;
    - una ruta con espacios funciona;
    - una ruta fuera del repo no lanza nada;
    - con el candado tomado no lanza nada;
    - un candado de hace más de 10 s se recupera;
    - un lint que dura 20 s termina en `KIT_LINT_TIMEOUT=2` sin dejar procesos.
  - **`stop-check`:**
    - un fichero borrado no se pasa al linter;
    - sin cambios, exit 0.
  - **Tiempo:** la sobrecarga de `post-edit` con un lint que sale al momento se queda por debajo de 300 ms (`time`).
- [ ] **Paso 2:** `bash tests/test_hooks_reglas.sh`. Esperado: FAIL.
- [ ] **Paso 3:** implementar.
- [ ] **Paso 4:** `bash tests/test_hooks_reglas.sh && bash tests/test_session_start.sh && claude plugin validate .`. Esperado: `ok` y validación sin errores.
- [ ] **Paso 5:** commit.

### Tarea 6: reglas del kit

**Ficheros:**
- Modificar: `rules/core.md` (sección nueva `## Reglas deterministas` y frase en "Automejora" y en "Un cambio, un objetivo").
- Test: `tests/test_rules.sh`.

**Interfaces:**
- Produce: el texto que leen todos los agentes. Va literal, sin rayas largas:
  - "El lint, los tipos y las comprobaciones de estructura en verde son parte de terminado."
  - "Nunca desactives, debilites ni esquives una regla: `eslint-disable`, `@ts-ignore`, `@ts-nocheck`, `as any`, editar su configuración o `--no-verify`. Si una regla está mal, propón el cambio con la skill `kit-reglas`."
  - "Si una convención se puede comprobar con una herramienta, propón la regla en vez de escribirla en un `.md`." (va también en "Automejora")
  - "Si tocas un fichero con deuda de lint o tipos (`eslint-suppressions.json`, `.agents-kit/tsc-base.json`), déjalo a cero en el mismo cambio, en un commit propio: no cuenta como refactor de paso."

- [ ] **Paso 1: test que falla.** `tests/test_rules.sh` exige en `core.md` `## Reglas deterministas`, `kit-reglas`, `eslint-suppressions.json` y `as any`.
- [ ] **Paso 2:** `bash tests/test_rules.sh`. Esperado: FAIL.
- [ ] **Paso 3:** editar `rules/core.md`, a 140 líneas o menos.
- [ ] **Paso 4:** `bash tests/test_rules.sh`. Esperado: `ok`.
- [ ] **Paso 5:** commit.

### Tarea 7: skill `kit-reglas`

**Ficheros:**
- Crear:
  - `skills/kit-reglas/SKILL.md`;
  - `skills/kit-reglas/references/base.md`: tsconfig, ESLint, `knip`, Python y bash de la base del spec, con un ejemplo de `eslint.config.mjs` con `strictTypeChecked`, `noInlineConfig` y `reportUnusedDisableDirectives`;
  - `skills/kit-reglas/references/escalera.md`: los cuatro peldaños, el catálogo de partida y ejemplos de `no-restricted-syntax` y `no-restricted-imports` con `message`;
  - `skills/kit-reglas/references/propuesta.md`: la plantilla del comentario `kit-regla` (qué prohíbe, por qué, ejemplo del error, qué rompe y cómo queda, valoración crítica).
- Modificar: `tests/test_skills.sh` (añadir `kit-reglas` a la lista y comprobar que cita `kit-reglas.sh`, `tsc-base.mjs` y `kit-pr.sh" regla`).

**Interfaces:**
- Consume: `kit-reglas.sh estado`, `abrir`, `cerrar` y `trinquete`, `tsc-base.mjs` y `kit-activate.sh` (para escribir `lint` y `verificar`; si `kit-activate.sh` no admite `--lint`, la tarea añade `--lint-fichero <ext>=<cmd>` y `--lint-turno <cmd>` con sus tests en `tests/test_activate.sh`).
- Produce: los pasos que sigue el agente.
  1. `estado`.
  2. Para cada pieza que falte, explicar a Dru qué hace y pedir su OK, consultando versiones en el registro.
  3. `abrir` con su `session_id`.
  4. Instalar. En un repo con deuda, `npx eslint --suppress-all` y `node .agents-kit/tsc-base.mjs generar`. Dejar `lint.fichero` (ESLint con `--cache`, o oxlint o Biome si el repo ya los usa), `lint.turno` (`node .agents-kit/tsc-base.mjs comprobar --cambiados` más ESLint con tipos sobre los argumentos) y `verificar.completo` con lint, `tsc-base comprobar` y `knip`.
  5. Medir `lint.fichero` sobre un fichero (más de 2 s con caché: proponer oxlint o Biome para lo de por edición).
  6. `cerrar`.
  7. Modo "regla nueva": la escalera, la explicación crítica y el OK de Dru. En `kit-run`, el commit propio más `kit-pr.sh regla`.
  8. Si `knip` encuentra algo en un repo empezado, abrir el issue `propuesta` de limpieza.

  Con `"flujo": false`, sin PR del kit: en el diff local, con el OK de Dru en la sesión.

- [ ] **Paso 1:** ampliar `tests/test_skills.sh`. Esperado: FAIL (falta la skill).
- [ ] **Paso 2:** escribir la skill y sus referencias (genéricas, sin casos concretos).
- [ ] **Paso 3:** `bash tests/test_skills.sh && bash tests/test_skills_check.sh && claude plugin validate .`. Esperado: `ok`.
- [ ] **Paso 4:** commit.

### Tarea 8: integración en `kit-on`, `kit-run`, `kit-scout` y `kit-revisar`

**Ficheros:**
- Modificar:
  - `skills/kit-on/SKILL.md`: paso 5, tras "Verificación": `kit-reglas.sh estado`; con `base incompleta`, seguir la skill `kit-reglas` dentro del worktree de `kit-on`. Hacer lo mismo en "Actualizar un repo ya activado".
  - `skills/kit-run/SKILL.md`: el lint en verde es terminado. El commit de limpieza de deuda en los ficheros tocados. Antes de `fusionar`, si `kit-reglas.sh blindado` da `n > 0`: `kit-pr.sh regla` con la plantilla, `kit-issue.sh decision` (pone `necesita-respuesta` y avisa) y pasar al siguiente issue. Al retomar, leer la respuesta de Dru:
    - si aprueba: `kit-pr.sh aprobar-regla` con el id de su comentario;
    - si rechaza: quitar el commit, verificar y hacer una ronda nueva;
    - si no está claro: otra `decision`.

    En el "Qué hacer" para Dru del final: responder en el issue, sin etiquetas. Lo mismo para `necesita-respuesta` en general: actualizar la línea que hoy le pide quitar la etiqueta.
  - `skills/kit-scout/SKILL.md`: buscar convenciones repetidas en `AGENTS.md` que podrían ser reglas (propuesta con la plantilla crítica) y abrir issues de limpieza de deuda (una regla o una carpeta cada uno).
  - `skills/kit-revisar/SKILL.md`: `kit-reglas.sh trinquete <raíz> HEAD` y `blindado <raíz> HEAD` sobre el diff local; avisar si falta la base.
  - `tests/test_skills.sh`: cada skill cita lo suyo (`kit-reglas.sh`, `kit-pr.sh" regla`, `aprobar-regla`).

- [ ] **Paso 1:** ampliar `tests/test_skills.sh`. Esperado: FAIL.
- [ ] **Paso 2:** editar las cuatro skills.
- [ ] **Paso 3:** `tests/run.sh`. Esperado: todo PASS.
- [ ] **Paso 4:** commit.

### Tarea 9: Codex y OpenCode

**Ficheros:**
- Modificar: `.opencode/plugins/agents-kit.js`, solo si la API lo permite:
  - V1: `tool.execute.before` y `tool.execute.after`, que llaman a `hooks/pre-edit` y `post-edit` con el mismo JSON;
  - V2: lo que ofrezca `ctx`.
- Modificar: `tests/opencode_harness.mjs`, `tests/opencode_v2_harness.mjs` y `tests/test_opencode.sh`, si se toca el plugin.
- Modificar: `AGENTS.md` ("Formatos verificados": sección nueva con lo comprobado y lo que no).

- [ ] **Paso 1:** con codex-cli real, en un repo de prueba con `lint` falso, comprobar si `PreToolUse`, `PostToolUse` y `Stop` de `hooks/hooks.json` se ejecutan (tras `/hooks`), con qué forma de `tool_input` (`apply_patch`) y si exit 2 devuelve el stderr al modelo. Si la forma es otra, `lib-reglas.sh` extrae las rutas de la entrada de Codex (test en `tests/test_hooks_reglas.sh`).
- [ ] **Paso 2:** con opencode 1.x y 2.x reales, comprobar los eventos de herramienta. Si existen, implementar con su test en el harness; si no, documentarlo.
- [ ] **Paso 3:** anotar en `AGENTS.md` versiones, fecha y resultado, con "sin verificar" donde toque.
- [ ] **Paso 4:** `tests/run.sh`. Esperado: todo PASS. Commit.

### Tarea 10: medir en un repo real, documentar y versionar

**Ficheros:**
- Modificar:
  - `AGENTS.md`: mapa del repo (`kit-reglas.sh`, `hooks/` nuevos, `templates/reglas/`, la skill) y tiempos medidos;
  - manifiestos (por `scripts/release.sh 3.8.0`).
- Borrar: `docs/superpowers/specs/2026-11-03-reglas-deterministas-design.md` y este plan (andamiaje; lo no obvio va a `AGENTS.md` o a la skill).

- [ ] **Paso 1:** en `/Users/drumorera/Documents/tiktok/tiktok-editor` (lo eligió Dru), seguir `kit-reglas` en un worktree temporal fuera de su árbol de trabajo, sin publicar nada ni tocar su clon, y anotar los tiempos:
  - `post-edit` en frío y con caché;
  - `stop-check` con 5 ficheros cambiados.

  Si `post-edit` con caché pasa de 2 s, aplicar la alternativa de la skill y volver a medir.
- [ ] **Paso 2:** `tests/e2e/github.sh DruMoDev/agents-kit-sandbox` lanzado con `scripts/kit-bg.sh`. Esperado: termina en verde. Añade al e2e el caso de una PR con un fichero blindado: se rechaza sin aprobación y se fusiona tras `kit-regla`, una respuesta en el issue y `aprobar-regla`.
- [ ] **Paso 3:** `scripts/release.sh 3.8.0`, `tests/run.sh` y `claude plugin validate .`. Esperado: todo PASS.
- [ ] **Paso 4:** borrar el spec y el plan, actualizar `AGENTS.md` y hacer commit. La PR sigue el flujo del repo del kit.
