# AGENTS.md

## Qué es

Plugin personal `agents-kit` para Claude Code, Codex y OpenCode; el mismo repo es su marketplace en Claude Code y Codex.
Las reglas viven en `rules/` y las inyecta `hooks/session-start` solo si el repo tiene `.agents-kit.json` (en OpenCode, el plugin de `.opencode/plugins/` reutiliza ese script).

## Mapa del repo

- `.claude-plugin/`: manifiesto y marketplace de Claude Code.
- `.codex-plugin/`: manifiesto de Codex.
- `.agents/plugins/`: marketplace de Codex.
- `hooks/`: `hooks.json` y el script `session-start`.
- `.opencode/plugins/agents-kit.js`: plugin de OpenCode (skills, permiso y reglas).
- `rules/`: reglas inyectadas en las sesiones.
- `skills/`: `kit-on`, `kit-off`, `kit-plan`, `kit-scout` y `kit-run` (con `references/`: plantilla de issue, prompt del revisor, esquema JSON de la revisión y formato de ronda).
- `scripts/`: scripts mecánicos de las skills (`kit-issue.sh`, `kit-worktree.sh`, `kit-pr.sh`, `kit-review.sh` y `kit-review-all.sh`, `kit-changelog.sh`, `kit-notify.sh`...) y `release.sh`.
- `scripts/lib/`: helpers de bash que se cargan con `source` (`github-slug.sh`, parseo del remoto `origin`; `config.sh`, configuración en tres capas; `review-seats.sh`, familia del implementador y candidatos de cada puesto de revisión; `default-branch.sh`; `transport.sh`, dónde corre la sesión; `repo-hook.sh`, scripts `setup` y `checks.pre-merge` del repo).
- `templates/`: plantillas que copia `kit-on` (`agents-kit.json`, `AGENTS.md`, `CHANGELOG.md`) y `config.json`, valores por defecto del kit y plantilla de la configuración global `~/.agents-kit/config.json` (o `KIT_CONFIG`). Precedencia: plugin < global < marcador del repo, que solo puede definir las claves de la lista blanca de `scripts/lib/config.sh`.
- `tests/`: tests de bash con stubs (`opencode_harness.mjs` carga el plugin de OpenCode con node). `tests/fixtures/changelog/` es el contrato del formato de `CHANGELOG.md`: la web lo reutilizará para probar su parser.
- `web/`: web de changelogs (Astro + Cloudflare Workers), app aparte con su `package.json`. Su parser (`web/src/lib/changelog.ts`) y el validador bash comparten `tests/fixtures/changelog/`: cambiar el formato es tocar los dos y los fixtures.
- `docs/`: specs y planes.

## Flujo de issues

`kit-plan` y `kit-scout` crean issues con `kit-issue.sh crear` (con `--prio`; los de `kit-scout`, `propuesta`); `kit-run` coge cualquier issue abierto fuera de `en-curso`, `necesita-respuesta`, `bloqueado`, `propuesta`, `someday` y `registro` (por `prio:*` y antigüedad) y lo lleva hasta `main`. `listo` y `necesita-decision` son de la v2: el primero ya no cuenta y el segundo excluye como `necesita-respuesta`. El estado vive en GitHub: esas etiquetas y marcadores HTML en los comentarios de issues y PRs. Los avisos salen de `kit-notify.sh` (`ntfy`, `claude-push` o `none`); el tema de ntfy solo lo pone el usuario (`~/.agents-kit/ntfy-topic` o `KIT_NTFY_TOPIC`), nunca el repo.

## Comandos

- `tests/run.sh`: ejecuta todos los tests.
- `scripts/release.sh <semver>`: escribe la versión en los manifiestos y el marketplace.
- `claude plugin validate .`: valida manifiestos y skills.
- `cd web && npm test && npm run e2e`: tests de la web (no los lanza `tests/run.sh`).

## Convenciones de scripts

- Scripts `kit-*`. Códigos de salida: 0 bien, 1 error de uso o rechazo, 2 error de entorno.
- Al terminar con éxito (y en la salida 2 de PR abierto) la última línea de la salida es `FIN: ...`; en los demás errores solo hay mensaje en stderr.
- Nunca recortar la salida propia con `head` ni `tail`.
- Mensajes al usuario en español, sin rayas largas.

## Formatos verificados

Verificado contra Claude Code 2.1.302 y codex-cli 0.162.1 con un plugin de prueba real (hook ejecutado y contexto recibido por el modelo en ambos).

### Estructura del plugin (un único árbol sirve a ambas herramientas)

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

### Hooks en Codex

- Codex SÍ carga hooks de plugin: descubre `hooks/hooks.json` por defecto.
- NO declarar `"hooks"` en `.codex-plugin/plugin.json`. Cualquier valor explícito sustituye al descubrimiento por defecto; `"hooks": {}` (lo que hace superpowers) desactiva los hooks del plugin en Codex.
- Los hooks de plugin no son de confianza al instalar: Codex los omite en silencio (verificado) hasta que el usuario los aprueba con `/hooks` en el CLI interactivo. Según la documentación, la confianza se persiste por hash de la definición del hook, y un hook nuevo o modificado vuelve a omitirse hasta que se aprueba otra vez. Sin verificar: el flujo `/hooks`, el formato exacto de la clave en `config.toml` y qué cubre el hash (solo la entrada de `hooks.json` o también el script).
- Aviso: la documentación de Codex dice que los hooks de ciclo de vida de plugins solo están soportados para plugins instalados manualmente en la app de escritorio de Codex. Aun así, en codex-cli 0.162.1 un plugin instalado por CLI desde un marketplace local ejecutó su hook. Puede cambiar en versiones futuras.
- `codex exec --dangerously-bypass-hook-trust` ejecuta hooks sin confianza persistida (solo para pruebas).
- Codex copia el plugin a `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/`; tras editar el código fuente hay que reinstalar (`codex plugin remove` + `codex plugin add`).
- Estrategia decidida: hook de plugin (no hace falta el fallback global en `~/.codex/hooks.json`).

### Hook SessionStart (común)

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

### Variables de entorno en el hook

- Claude Code: `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_PROJECT_DIR`. Con marketplace de ruta local, `CLAUDE_PLUGIN_ROOT` apunta al directorio fuente (no a una copia).
- Codex: `PLUGIN_ROOT`, `PLUGIN_DATA` y los alias `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`. Usar `${CLAUDE_PLUGIN_ROOT}` en `hooks.json` para que funcione en ambas.
- No hay `CODEX_PLUGIN_ROOT`.

### Comandos

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

### OpenCode

Verificado contra opencode 1.19.0 (V1) con `opencode run` en un repo activado y en uno sin marcador.

- No lee plugins de Claude Code ni de Codex. Sus plugins son módulos JS: un fichero en `~/.config/opencode/plugins/` (se admite un enlace simbólico) se carga al arrancar.
- Lee `AGENTS.md` (o `CLAUDE.md` si falta) y skills de `.agents/skills/`, `.claude/skills/` y `.opencode/skills/`. No sigue los `@imports`.
- Hooks del plugin usados: `config` (añade `skills.paths` y, solo en repos activados, `permission.external_directory`) y `experimental.chat.messages.transform` (se ejecuta en cada paso con los mensajes recargados; hace falta una guarda para inyectar una sola vez). Mismo enfoque que superpowers.
- Sin permiso `external_directory`, `opencode run` rechaza leer o ejecutar los scripts del plugin, que están fuera del proyecto.
- OpenCode V2 (2.x) usa otra API (`default.setup`, `ctx.session.hook("context")`); sin soporte por ahora.

### Flujo de issues (fase 2)

Verificado de punta a punta el 2026-10-19 en un repo privado de pruebas, con `claude -p "/agents-kit:kit-run"` (Claude Code 2.1.302, opencode 1.19.0):
- Issue `listo` → PR fusionada tras 2 rondas, con los tres revisores por defecto (`claude/opus`, `claude/sonnet`, `opencode/openai/gpt-6.1-sol`) publicando `kit-revision` y un `kit-ronda` por ronda; sin CI, se usó `kit-gate-local`; worktree y rama borrados al final.
- Issue con producto sin definir → comentario `kit-decision` con opciones y propuesta, `necesita-decision`, asignado a Dru, reclamo soltado, sin rama ni PR.
- Los revisores corren sin interfaz por CLI: `claude -p --permission-mode bypassPermissions --disallowedTools "Bash(git push:*)" "Bash(gh:*)"` y `opencode run` con `OPENCODE_CONFIG_CONTENT` que niega `gh *` y `git push*`; ambos respetan el bloqueo.
- `claude -p` espera 3 s a stdin si no se le pasa `</dev/null`. La salida de `opencode run` lleva códigos ANSI.

### Changelog y avisos (fase 3)

Verificado de punta a punta el 2026-10-21 en el repo privado de pruebas con `claude -p "/agents-kit:kit-run"` (también con `SHELL=/bin/zsh`):
- Issue `listo` → PR fusionada con entrada de `CHANGELOG.md` validada por `kit-changelog.sh validar`, revisores lanzados por `kit-review-all.sh`, comentario `kit-resumen` en el issue "📦 Changelog" y aviso por ntfy (`curl` a ntfy.sh; se comprobó leyendo el tema con `https://ntfy.sh/<tema>/json?poll=1`).
- `PushNotification` de Claude Code es una herramienta del modelo: un script no puede llamarla y solo llega al móvil con Remote Control. Por eso el canal por defecto es ntfy y `claude-push` solo imprime `AVISO-CLAUDE:` para que la skill la llame.
- Un bloque de bash con arrays dentro de una skill falla si el agente lo ejecuta en zsh (`bad substitution`): lo mecánico va en scripts, no en bloques inline.

### Web de changelogs (fase 4)

Desplegada el 2026-10-22 en `https://agents-kit-changelogs.dev-morera.workers.dev` (worker `agents-kit-changelogs`, KV `SEEN`), detrás de Cloudflare Access ("Todo el tráfico", solo el email de Dru). Verificado: sin sesión, Access redirige al login; con Access sin configurar, el worker responde 503.
- `wrangler deploy` en un proyecto Astro usa la configuración compilada (`dist/server/wrangler.json`): sin compilar antes, sube la última compilación. Por eso `npm run deploy` compila y despliega.
- Despliegue continuo con Workers Builds conectado al repo: raíz `web`, compilación `npm ci && npm run build`, despliegue `npx wrangler deploy`, solo `main` y rutas `web/*`.
- En Astro 7 con @astrojs/cloudflare 14 los bindings se leen con `import { env } from "cloudflare:workers"`; la Cache API no sirve detrás de Access ni en workers.dev, así que la caché de repos va en KV.
- `wrangler kv namespace create` pregunta en modo interactivo; sin terminal no termina.

### Revisores por familias (v3)

Ayuda (`--help`) leída el 2026-10-22 con Claude Code 2.1.308, opencode 1.19.0 y codex-cli 0.163.0. Sin revisión real contra la red salvo donde se dice.
- Un proveedor es `{"cli": "<adaptador>", "modelos": {...}}` en `proveedores` del global; los adaptadores son `claude`, `opencode` y `codex` (`kit-review.sh`). Disponible = CLI en el PATH; un fallo de login, modelo o cuota en ejecución (motivo `acceso`) pasa al siguiente candidato del puesto.
- Las tres invocaciones corren en el clon desechable, con stdin cerrado, sin `GH_TOKEN`/`GITHUB_TOKEN`, con `GH_CONFIG_DIR` vacío, `GIT_CONFIG_GLOBAL=/dev/null`, `credential.helper` vacío y sin variables `CLAUDE*`, `CODEX_*`, `OPENCODE*` de la sesión (se conservan `CLAUDE_CONFIG_DIR` y `CODEX_HOME`, que guardan el login).
- `claude -p --model <m> --permission-mode bypassPermissions --setting-sources user --strict-mcp-config --no-session-persistence --disallowedTools "Bash(git push:*)" "Bash(gh:*)" --output-format json --json-schema <esquema> <prompt>`. Banderas en la ayuda. Sin verificar aquí: que la respuesta traiga `structured_output` e `is_error` (lo usa la skill `peer-review` de Aikosmo).
- `opencode run --pure --format json -m <m> [-s <sesión>] <prompt>` con `OPENCODE_CONFIG_CONTENT` que niega `gh *` y `git push*`. Banderas en la ayuda (`--format json` = eventos JSON en crudo; `--pure` = sin plugins externos). Sin verificar aquí: los eventos `text` (`part.text`, `part.messageID`), `error` y `sessionID` (de `peer-review`). Sin esquema nativo: va en el prompt, y una respuesta fuera de esquema tiene un reintento en la misma sesión (`-s`).
- `codex exec --ephemeral --ignore-user-config --ignore-rules --sandbox workspace-write -c 'approval_policy="never"' -c sandbox_workspace_write.network_access=false --color never -m <m> -C <clon> --output-schema <fichero> -o <fichero> <prompt>`. Banderas en la ayuda; codex-cli 0.163.0 aceptó esta línea completa (arrancó con `approval: never` y salió con código 1 con un modelo inexistente; fue una ejecución accidental de un test). `gh` y `git push` quedan bloqueados porque el sandbox `workspace-write` no tiene red (y no hay credenciales); `--ignore-user-config` evita servidores MCP del usuario con tokens. Sin verificar: que `approval_policy` y `sandbox_workspace_write.network_access` sean las claves exactas en 0.163.0, que el sandbox bloquee la red en macOS en ejecución anidada, y que `-o` escriba el JSON del esquema. Codex lee stdin aunque sea `/dev/null` ("Reading additional input from stdin..."), sin efecto.
- Entorno del implementador: `CODEX_THREAD_ID` en Codex y `CLAUDECODE` en Claude Code (los usa `peer-review`); `OPENCODE` en OpenCode, sin verificar aquí.
