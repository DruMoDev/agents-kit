# agents-kit

Plugin personal para Claude Code y Codex. Inyecta unas reglas de trabajo al arrancar cada sesión, solo en los repos donde el kit está activado, y trae dos skills para activarlo y desactivarlo. El mismo repo es el plugin y su propio marketplace en ambas herramientas.

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

## Uso

El kit es inerte en cualquier repo sin `.agents-kit.json` en su raíz.

- `kit-on`: activa el kit en el repo actual. Crea `.agents-kit.json`, `AGENTS.md`, `CLAUDE.md` y `CHANGELOG.md` si faltan, ordena un `AGENTS.md` existente, configura GitHub (etiquetas, issue de changelog, borrado de rama al fusionar) y lo envía todo por un PR que se fusiona. Si se interrumpe, se relanza y retoma.
- `kit-off`: borra `.agents-kit.json` por PR. `AGENTS.md`, `CHANGELOG.md` y las skills del proyecto se quedan.

Cómo se invocan:

- Claude Code: `/agents-kit:kit-on` y `/agents-kit:kit-off`.
- Codex: pídeselo por nombre (kit-on, kit-off).

Desde la siguiente sesión en un repo activado, el hook `SessionStart` carga las reglas de `rules/`.

## Iterar

1. Edita el repo.
2. Sube la versión: `scripts/release.sh <version>`.
3. Claude Code: `claude plugin update agents-kit@agents-kit` (hay que reiniciar la sesión para aplicarlo).
4. Codex copia el plugin a una caché: `codex plugin remove agents-kit@agents-kit` y `codex plugin add agents-kit@agents-kit`, y volver a aprobar el hook con `/hooks`.

## Tests

```
tests/run.sh
claude plugin validate .
```

Próximas fases: flujo de issues, changelog y avisos, web.
