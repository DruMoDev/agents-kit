# AGENTS.md

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
  {"hooks": {"SessionStart": [{"matcher": "startup|resume|clear|compact",
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
