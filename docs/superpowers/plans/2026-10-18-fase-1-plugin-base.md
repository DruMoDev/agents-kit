# Fase 1 — Plugin base, reglas y activación: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convertir `agents-kit` en un plugin instalable en Claude Code y Codex que, solo en repos con `.agents-kit.json`, carga las reglas de trabajo de Dru, y que trae `kit-on`/`kit-off` para activarlo/desactivarlo por PR.

**Architecture:** Un repo que es a la vez plugin y marketplace para ambas herramientas, con una sola carpeta `skills/` y `rules/`. Un hook `SessionStart` inyecta `rules/core.md` si el repo tiene marcador. Lo mecánico vive en scripts bash (+ `git`, `gh`, `jq`); las skills ponen el criterio (p. ej. ordenar un `AGENTS.md` existente).

**Tech Stack:** bash, git, gh (autenticado como DruMoDev), jq. Tests en bash puro con stubs de `gh` en `PATH`. Sin dependencias nuevas.

**Spec:** `docs/superpowers/specs/2026-10-18-agents-kit-plugin-design.md`

Fases siguientes (plan propio cada una, escrito al terminar la anterior con lo aprendido): 2 flujo de issues y revisión, 3 changelog y avisos, 4 web.

## Global Constraints

- Sin `.agents-kit.json` en la raíz del repo, el plugin no hace nada: el hook no emite contexto y las skills se niegan.
- Nada entra en `main` sin PR, tampoco la activación ni la desactivación (squash merge, rama borrada).
- Todo canónico en el lado "agents": `AGENTS.md` fuente de verdad, `CLAUDE.md` contiene `@AGENTS.md`, skills del proyecto en `.agents/skills/`, symlink `.claude/skills -> ../.agents/skills`.
- El `AGENTS.md` del repo nunca recibe copia de las reglas del kit.
- Una sola carpeta `skills/` y `rules/` compartidas por `.claude-plugin/` y `.codex-plugin/`; nada duplicado.
- Etiquetas: `listo`, `propuesta`, `en-curso`, `necesita-decision`, `bloqueado`.
- Config por defecto del marcador: `maxReviewRounds: 10`, `notify: "claude-push"`, `autoMerge: true`, revisores por herramienta (`claude`: opus + sonnet), implementador `claude: opus`.
- Scripts: salida 0 = ok, 1 = rechazado con motivo en stderr, 2 = no pude decidir/error de entorno. Nunca canalizar salidas propias por `head`/`tail`.
- Textos de cara a Dru en español; sin em dashes en textos nuevos.

## Review Focus

1. **Hook lanzado desde un subdirectorio del repo** → debe encontrar el marcador en la raíz (`git rev-parse --show-toplevel`). Test en Task 4.
2. **Hook fuera de un repo git o con el plugin en un repo de Aikosmo sin marcador** → exit 0, cero bytes de salida. Test en Task 4.
3. **`kit-on` en un repo con `CLAUDE.md` o `AGENTS.md` previos con contenido** → se preserva todo y solo se añade lo que falta. Test en Task 5.
4. **`.claude/skills` es un directorio real con contenido** → no se toca, se avisa por stderr, el resto sigue. Test en Task 5.
5. **Rama por defecto distinta de `main`, o repo sin remoto de GitHub** → usar la rama por defecto real; sin remoto, los pasos locales se hacen y el paso GitHub sale con 1 y un motivo claro. Test en Task 6.

---

### Task 1: Verificar formatos de Codex (spike)

Desconocido real: cómo carga Codex los hooks de un plugin y qué JSON espera de un `SessionStart`. superpowers, instalado en ambas herramientas, declara `"hooks": {}` en `.codex-plugin/plugin.json` y tiene `hooks/hooks.json` para Claude.

**Files:**
- Create: `AGENTS.md` (sección "Formatos verificados" con los hallazgos)

- [ ] **Step 1:** Consultar la documentación actual de plugins y hooks de Codex (CLI `codex-cli 0.162.1`; `codex plugin --help`, `codex plugin marketplace --help`) y la de Claude Code (agente `claude-code-guide`). Anotar: campos de `.codex-plugin/plugin.json`, si un plugin de Codex puede declarar hooks y con qué ruta/formato, nombre del evento de inicio de sesión, JSON de salida para inyectar contexto, variable de entorno con la raíz del plugin, y comando para añadir un marketplace local en cada herramienta.
- [ ] **Step 2:** Probarlo: plugin mínimo en el scratchpad con un hook que imprime un contexto marcador; instalarlo en Codex desde marketplace local, abrir una sesión no interactiva (`codex exec "¿qué contexto extra tienes?"`) y comprobar que el marcador llega. Desinstalarlo después.
- [ ] **Step 3:** Si Codex no admite hooks de plugin: el fallback decidido es un hook global en `~/.codex/hooks.json` que llama a `hooks/session-start` del plugin (inerte sin marcador). Documentar cuál aplica.
- [ ] **Step 4:** Escribir los hallazgos en `AGENTS.md` (sección "Formatos verificados", estilo de reglas, sin cronología) y commit: `docs: verified Claude Code and Codex plugin/hook formats`.

### Task 2: Esqueleto del plugin y retirada del CLI

**Files:**
- Delete: `bin/cli.js`, `recommendations.json`, `templates/frameworks/`, `templates/AGENTS.header.md`, `tests/smoke.sh`, `package.json`, `.DS_Store` sueltos
- Create: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`, `.agents/plugins/marketplace.json`, `scripts/release.sh`, `tests/run.sh`, `tests/lib.sh`, `tests/test_release.sh`
- Modify: `.gitignore` (añadir `.DS_Store`)

**Interfaces:**
- Produces: `tests/run.sh` ejecuta cada `tests/test_*.sh` y sale ≠0 si alguno falla. `tests/lib.sh` define `fail <msg>`, `mk_repo` (repo git temporal con commit inicial en `main`, imprime su ruta) y `use_gh_stub` (antepone `tests/stubs` al `PATH`; el stub registra cada invocación en `$GH_LOG` y responde según `$GH_STUB_MODE`).
- Produces: `scripts/release.sh <semver>` escribe esa versión en `.claude-plugin/plugin.json`, la entrada del plugin en `.claude-plugin/marketplace.json` y `.codex-plugin/plugin.json`.

Valores: nombre del plugin `agents-kit`, versión inicial `2.0.0`, autor Dru, `skills: "./skills/"`. Manifiestos siguiendo los hallazgos de Task 1 y el modelo de superpowers (`~/.codex/plugins/cache/claude-plugins-official/superpowers/7.0.0/`).

- [ ] **Step 1: Test que falla** en `tests/test_release.sh`: copia el repo a un tmp, ejecuta `scripts/release.sh 2.1.0`, y comprueba con `jq` que los tres ficheros dicen `2.1.0` y siguen siendo JSON válido; `scripts/release.sh foo` sale con 1.
- [ ] **Step 2:** `tests/run.sh` → FAIL (no existe `release.sh`).
- [ ] **Step 3:** Borrar lo retirado, crear manifiestos, marketplaces, `release.sh` (usa `jq`, valida semver), `tests/run.sh`, `tests/lib.sh`, `tests/stubs/gh`.
- [ ] **Step 4:** `tests/run.sh` → PASS. `claude plugin validate .` si existe el comando (o el equivalente que encontró Task 1) → sin errores.
- [ ] **Step 5:** Commit `feat!: plugin skeleton for Claude Code and Codex; remove npx installer`.

### Task 3: Reglas

**Files:**
- Create: `rules/core.md`, `rules/testing.md`, `rules/docs-discipline.md`
- Delete: `templates/base.md`, `templates/docs/` (su contenido pasa a `rules/`)
- Test: `tests/test_rules.sh`

**Interfaces:**
- Produces: `rules/core.md` es lo que inyecta el hook (Task 4); referencia `testing.md` y `docs-discipline.md` por ruta relativa a la raíz del plugin.

Contenido de `rules/core.md`: `templates/base.md` actual, quitando "Skill memory" (lo sustituye la sección de automejora de abajo) y la referencia a `docs/agent/`, más, compacto y en el mismo tono:
- e2e siempre que haya algo que comprobar de punta a punta, con casos límite explícitos; "verde no es validado": cambios que alteran el resultado visible se comprueban con casos reales y contra la versión anterior.
- No afirmar nada no ejecutado; un supuesto sobre una herramienta externa no vale hasta ejecutarlo.
- Lo técnico lo decide el agente; el producto (funcionalidad, comportamiento) se pregunta a Dru, una pregunta cada vez.
- Lo repetitivo y determinista va a scripts, no a instrucciones.
- Un issue = una PR, un solo objetivo; nada fuera de scope (lo encontrado por el camino se abre como issue `propuesta`).
- Sin compatibilidad hacia atrás en proyectos personales; ninguna dependencia nueva sin justificar.
- Rutas clicables; explicar qué y por qué.
- Flujo git: todo a `main` por PR con squash; ramas y worktrees se borran tras el merge.
- Automejora: al terminar una tarea, registrar lo aprendido en la skill del proyecto más cercana (o una nueva en `.agents/skills/`, `SKILL.md` corto + `references/` + `scripts/`) y corregir `AGENTS.md` si cambió stack, comandos o mapa; en la misma PR.
- Changelog: cada PR que cambie algo para quien usa la app añade su entrada en `CHANGELOG.md` (formato en la fase 3; hasta entonces, la cabecera del fichero lo describe).

- [ ] **Step 1: Test que falla** `tests/test_rules.sh`: existen los tres ficheros; `core.md` contiene los encabezados `## Write less code`, `## Tests y verificación`, `## Producto vs implementación`, `## Flujo git`, `## Automejora`; `core.md` ≤ 140 líneas; ningún fichero de `rules/` contiene `docs/agent/`.
- [ ] **Step 2:** Ejecutar → FAIL.
- [ ] **Step 3:** Escribir los tres ficheros y borrar los antiguos.
- [ ] **Step 4:** Ejecutar → PASS.
- [ ] **Step 5:** Commit `feat: rules/ (core, testing, docs-discipline) with Dru's working rules`.

### Task 4: Hook SessionStart condicionado al marcador

**Files:**
- Create: `hooks/hooks.json`, `hooks/session-start`
- Modify: `.codex-plugin/plugin.json` (registro del hook según Task 1)
- Test: `tests/test_session_start.sh`

**Interfaces:**
- Produces: `hooks/session-start` (ejecutable, bash). Lee JSON de stdin si lo hay (campo `cwd`); si no, usa `$PWD`. Raíz = `git -C <cwd> rev-parse --show-toplevel`. Si no hay raíz o no existe `<raíz>/.agents-kit.json`: exit 0 sin salida. Si existe: emite el JSON de inyección con el contenido de `rules/core.md` precedido de una línea que diga que el kit está activo en este repo y dónde están `testing.md` y `docs-discipline.md` (rutas absolutas dentro del plugin). Formato Claude (`hookSpecificOutput.additionalContext`, `hookEventName: "SessionStart"`) cuando está `CLAUDE_PLUGIN_ROOT`; formato Codex según Task 1 en otro caso. Raíz del plugin resuelta desde `$0` sin depender de `PATH` (patrón de superpowers).

- [ ] **Step 1: Tests que fallan** en `tests/test_session_start.sh`:
  - repo sin marcador → stdout vacío, exit 0
  - directorio fuera de git → stdout vacío, exit 0
  - repo con marcador, lanzado con `cwd` = subdirectorio `src/` → stdout es JSON válido (`jq -e`) y `.hookSpecificOutput.additionalContext` contiene `## Write less code` (con `CLAUDE_PLUGIN_ROOT` definido)
  - mismo caso sin `CLAUDE_PLUGIN_ROOT` → JSON válido en formato Codex con el mismo contenido
  - `core.md` con comillas, barras invertidas y tabuladores (copia temporal) → JSON sigue siendo válido
- [ ] **Step 2:** Ejecutar → FAIL.
- [ ] **Step 3:** Implementar el hook (escapado JSON con `jq -Rs` o sustitución bash) y `hooks/hooks.json` (matcher `startup|clear|compact`).
- [ ] **Step 4:** Ejecutar → PASS.
- [ ] **Step 5:** Commit `feat: SessionStart hook injects rules only in repos with .agents-kit.json`.

### Task 5: Activación local (`kit-activate.sh`) y plantillas

**Files:**
- Create: `scripts/kit-activate.sh`, `templates/agents-kit.json`, `templates/CHANGELOG.md`, `templates/AGENTS.md`
- Test: `tests/test_activate.sh`

**Interfaces:**
- Produces: `scripts/kit-activate.sh <repo_root>`: idempotente, solo ficheros locales, sin commit.
  - crea `.agents-kit.json` desde la plantilla si falta (no lo sobrescribe si existe)
  - crea `CHANGELOG.md` desde la plantilla si falta
  - crea `AGENTS.md` desde la plantilla si falta; si existe, no lo toca (ordenarlo es criterio de la skill)
  - `CLAUDE.md`: si falta, lo crea con `@AGENTS.md`; si existe sin una línea `@AGENTS.md`, la antepone conservando el resto
  - crea `.agents/skills/`; crea el symlink `.claude/skills -> ../.agents/skills`; si es un symlink roto o a otro sitio, lo rehace; si es un directorio real con contenido, no lo toca y escribe un aviso en stderr
  - imprime una línea por cada fichero creado o cambiado (`creado: X`, `cambiado: X`) y termina con `FIN: <n>` (n = cambios)
- `templates/agents-kit.json`: exactamente los valores de Global Constraints, con `reviewers.claude` = `[{"model":"opus","focus":"corrección, casos límite y tests"},{"model":"sonnet","focus":"simplicidad, reutilización y scope"}]` y `reviewers.codex` = `[]`.
- `templates/CHANGELOG.md`: título `# Changelog` y un comentario HTML que explica el formato (corta + extendida, tipos `Nuevo | Mejora | Arreglo | Interno`, fecha descendente), con el ejemplo del spec.
- `templates/AGENTS.md`: esqueleto con las secciones sugeridas del antiguo `AGENTS.header.md` (Qué es, Stack, Comandos incluidos test/lint/build, Skills del proyecto, Mapa del código), sin reglas del kit.

- [ ] **Step 1: Tests que fallan** en `tests/test_activate.sh`:
  - repo vacío → existen los 6 elementos (marcador, CHANGELOG, AGENTS, CLAUDE, `.agents/skills`, symlink), `CLAUDE.md` == `@AGENTS.md`, `readlink .claude/skills` == `../.agents/skills`, `jq .maxReviewRounds` == 10, última línea `FIN: 6`
  - segunda ejecución → `FIN: 0` y sumas de los ficheros sin cambios
  - repo con `AGENTS.md` "Mi contenido" y `CLAUDE.md` "Notas" → ambos contenidos siguen, `CLAUDE.md` empieza por `@AGENTS.md`
  - repo con `.claude/skills/x/SKILL.md` real → sigue existiendo, stderr contiene `.claude/skills`, exit 0
  - repo con `.claude/skills` symlink roto → queda apuntando a `../.agents/skills`
- [ ] **Step 2:** Ejecutar → FAIL.
- [ ] **Step 3:** Implementar script y plantillas.
- [ ] **Step 4:** Ejecutar → PASS.
- [ ] **Step 5:** Commit `feat: kit-activate.sh and templates for repo activation`.

### Task 6: GitHub: configuración del repo y envío por PR

**Files:**
- Create: `scripts/kit-github-setup.sh`, `scripts/kit-ship-pr.sh`, `tests/stubs/gh` (ampliar el de Task 2)
- Test: `tests/test_github.sh`

**Interfaces:**
- Produces: `scripts/kit-github-setup.sh <repo_root>`: sin remoto GitHub (`gh repo view` falla) → exit 1 con `sin remoto de GitHub` en stderr. Si hay: crea/actualiza las 5 etiquetas (`gh label create --force`, con descripción en español y color fijo cada una), `gh repo edit --enable-squash-merge --delete-branch-on-merge`, y busca un issue abierto con título exacto `📦 Changelog`; si no existe lo crea (cuerpo: explica que aquí llegan los resúmenes) y lo fija (`gh issue pin`). Idempotente. Termina con `FIN: ok`.
- Produces: `scripts/kit-ship-pr.sh <repo_root> <rama> <titulo> <cuerpo>`: rama por defecto = `gh repo view --json defaultBranchRef`; si no hay cambios → exit 1 `nada que enviar`. Crea `<rama>` desde la por defecto actualizada, commit de todo con `<titulo>`, `git push -u`, `gh pr create --base <por defecto>`, `gh pr merge --squash --delete-branch`, vuelve a la rama por defecto y hace pull, borra la rama local. Imprime la URL del PR y `FIN: ok`.

- [ ] **Step 1: Tests que fallan** con el stub de `gh` (registra llamadas en `$GH_LOG`, `GH_STUB_MODE=no-remote|default-branch-trunk|ok`) y un remoto git local (`git init --bare`):
  - `no-remote` → setup sale 1, stderr `sin remoto de GitHub`
  - `ok` → `$GH_LOG` contiene 5 `label create` con `--force`, un `repo edit` con ambos flags, `issue create` con título `📦 Changelog` y `issue pin`; segunda ejecución con el issue "existente" no vuelve a crearlo
  - ship-pr con `default-branch-trunk` → el PR se crea con `--base trunk` y la rama local termina en `trunk`
  - ship-pr sin cambios → exit 1 `nada que enviar`
- [ ] **Step 2:** Ejecutar → FAIL.
- [ ] **Step 3:** Implementar ambos scripts.
- [ ] **Step 4:** Ejecutar → PASS.
- [ ] **Step 5:** Commit `feat: GitHub setup and ship-by-PR scripts`.

### Task 7: Skills `kit-on` y `kit-off`

**Files:**
- Create: `skills/kit-on/SKILL.md`, `skills/kit-off/SKILL.md`, `scripts/kit-deactivate.sh`
- Test: `tests/test_deactivate.sh`, `tests/test_skills.sh`

**Interfaces:**
- Consumes: `kit-activate.sh`, `kit-github-setup.sh`, `kit-ship-pr.sh` (Tasks 5–6).
- Produces: `scripts/kit-deactivate.sh <repo_root>`: borra `.agents-kit.json` (exit 1 `no está activado` si no existe); no toca nada más; `FIN: ok`.

`kit-on` (criterio de la skill, descripción corta en el frontmatter que la haga invocable como comando):
1. Raíz del repo; si ya hay marcador, decir que ya está activo y salir.
2. Árbol de trabajo sucio → parar y decírselo a Dru.
3. `kit-activate.sh`; leer su salida completa (sin `head`/`tail`).
4. Si `AGENTS.md` ya existía: ordenarlo según la plantilla (contexto del proyecto: qué es, stack, comandos, skills, mapa), sin perder información, quitando cronología/estado y cualquier copia de reglas genéricas que ahora da el kit. Rellenar lo que se pueda deducir del repo (comandos de `package.json`, etc.).
5. `kit-github-setup.sh` (si sale 1 por no tener remoto: decirlo y no seguir con el PR).
6. `kit-ship-pr.sh <raíz> kit-on "chore: activar agents-kit" <cuerpo con lo creado>`.
7. Resumen a Dru: qué se creó, URL del PR, y que la siguiente sesión ya carga las reglas.

`kit-off`: marcador presente; árbol limpio; `kit-deactivate.sh`; `kit-ship-pr.sh <raíz> kit-off "chore: desactivar agents-kit" ...`; avisar de que `AGENTS.md`, `CHANGELOG.md` y skills se quedan porque son del proyecto.

- [ ] **Step 1: Tests que fallan**: `test_deactivate.sh` (con marcador → lo borra y `FIN: ok`; sin marcador → exit 1); `test_skills.sh` comprueba que cada `skills/*/SKILL.md` tiene frontmatter con `name` igual al nombre de la carpeta y `description` de ≤ 200 caracteres, y que los scripts que nombra existen.
- [ ] **Step 2:** Ejecutar → FAIL.
- [ ] **Step 3:** Escribir las dos skills y el script.
- [ ] **Step 4:** Ejecutar `tests/run.sh` completo → PASS.
- [ ] **Step 5:** Commit `feat: kit-on and kit-off skills`.

### Task 8: Documentación, instalación local y prueba real

**Files:**
- Modify: `README.md` (reescribir: qué es, instalar en Claude Code y Codex, `kit-on`/`kit-off`, cómo iterar con `scripts/release.sh` + update, tests)
- Modify: `AGENTS.md` (cómo desarrollar el kit: mapa del repo, comandos, `tests/run.sh`, convenciones de scripts 0/1/2 y `FIN:`); crear `CLAUDE.md` con `@AGENTS.md`

- [ ] **Step 1:** Escribir README y AGENTS.md. `tests/run.sh` → PASS.
- [ ] **Step 2:** Instalar el plugin desde el marketplace local en Claude Code y en Codex (comandos de Task 1). `claude plugin list` / `codex plugin list` lo muestran.
- [ ] **Step 3:** En un repo sin marcador (p. ej. este mismo antes de activar nada), abrir sesión no interactiva en cada herramienta y comprobar que no aparece el contexto del kit.
- [ ] **Step 4 (requiere OK de Dru: crea un repo en GitHub):** crear el repo privado `DruMoDev/agents-kit-sandbox`, clonarlo, ejecutar `kit-on` en Claude Code. Comprobar: PR mergeado y rama borrada, 5 etiquetas, issue `📦 Changelog` fijado, `delete_branch_on_merge` activo, y que una sesión nueva en ese repo (Claude Code y Codex) recibe las reglas. Ejecutar `kit-off` y comprobar que la sesión siguiente ya no las recibe.
- [ ] **Step 5:** Commit `docs: README and AGENTS.md for the plugin` y borrar `docs/superpowers/plans/2026-10-18-fase-1-plugin-base.md` cuando la fase quede verificada (el spec se conserva hasta terminar la fase 4).
