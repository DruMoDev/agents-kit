# agents-kit

Plugin personal para Claude Code, Codex y OpenCode. Inyecta unas reglas de trabajo al arrancar cada sesión, solo en los repos donde el kit está activado, y trae dos skills para activarlo y desactivarlo. El mismo repo es el plugin y su propio marketplace en Claude Code y Codex.

## Instalar

### Claude Code

```
claude plugin marketplace add ~/Documents/programacion/agents-kit
claude plugin install agents-kit@agents-kit
```

### Codex

```
codex plugin marketplace add ~/Documents/programacion/agents-kit
codex plugin add agents-kit@agents-kit
```

Después, aprueba el hook una vez con `/hooks` dentro de Codex interactivo. Codex omite en silencio los hooks de plugin que no son de confianza. Si el hook cambia, hay que aprobarlo otra vez.

### OpenCode

```
mkdir -p ~/.config/opencode/plugins
ln -s ~/Documents/programacion/agents-kit/.opencode/plugins/agents-kit.js ~/.config/opencode/plugins/agents-kit.js
```

Es un enlace, así que OpenCode usa el código del repo: no hay caché ni aprobación de hooks. El plugin registra `kit-on` y `kit-off` en todos los repos (solo actúan si los pides). Solo en repos activados añade las reglas al primer mensaje de cada sesión y deja leer y ejecutar sin preguntar `scripts/`, `skills/`, `rules/` y `templates/` del plugin; en los demás, OpenCode pide permiso la primera vez que `kit-on` usa un script. OpenCode ya lee por su cuenta `AGENTS.md` y las skills de `.agents/skills/`.

## Uso

El kit es inerte en cualquier repo sin `.agents-kit.json` en su raíz.

- `kit-on`: activa el kit en el repo actual. Crea `.agents-kit.json`, `AGENTS.md`, `CLAUDE.md` y `CHANGELOG.md` si faltan, ordena un `AGENTS.md` existente, configura GitHub (etiquetas, issue de changelog, borrado de rama al fusionar) y lo envía todo por un PR que se fusiona. Si se interrumpe, se relanza y retoma.
- `kit-off`: borra `.agents-kit.json` por PR. `AGENTS.md`, `CHANGELOG.md` y las skills del proyecto se quedan.

Cómo se invocan:

- Claude Code: `/agents-kit:kit-on` y `/agents-kit:kit-off`.
- Codex y OpenCode: pídeselo por nombre (kit-on, kit-off).

Desde la siguiente sesión en un repo activado, se cargan las reglas de `rules/` (hook `SessionStart` en Claude Code y Codex, plugin en OpenCode).

## Iterar

1. Edita el repo.
2. Sube la versión: `scripts/release.sh <version>`.
3. Claude Code: `claude plugin update agents-kit@agents-kit` (hay que reiniciar la sesión para aplicarlo).
4. Codex copia el plugin a una caché: `codex plugin remove agents-kit@agents-kit` y `codex plugin add agents-kit@agents-kit`, y volver a aprobar el hook con `/hooks`.
5. OpenCode: reinicia `opencode` (carga el plugin al arrancar).

## Tests

```
tests/run.sh
claude plugin validate .
```

Próximas fases: flujo de issues, changelog y avisos, web.
