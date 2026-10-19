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
- `skills/`: `kit-on` y `kit-off`.
- `scripts/`: scripts mecánicos de las skills y `release.sh`.
- `scripts/lib/`: helpers de bash que se cargan con `source` (`github-slug.sh`, parseo del remoto `origin`).
- `templates/`: plantillas que copia `kit-on` (`agents-kit.json`, `AGENTS.md`, `CHANGELOG.md`).
- `tests/`: tests de bash con stubs (`opencode_harness.mjs` carga el plugin de OpenCode con node).
- `docs/`: specs y planes.

## Comandos

- `tests/run.sh`: ejecuta todos los tests.
- `scripts/release.sh <semver>`: escribe la versión en los manifiestos y el marketplace.
- `claude plugin validate .`: valida manifiestos y skills.

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
