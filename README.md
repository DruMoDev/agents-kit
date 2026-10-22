# agents-kit

Plugin personal para Claude Code, Codex y OpenCode. Inyecta unas reglas de trabajo al arrancar cada sesión, solo en los repos donde el kit está activado. Trae skills para activarlo y desactivarlo y para llevar issues de GitHub hasta `main` con revisión de varios modelos. El mismo repo es el plugin y su propio marketplace en Claude Code y Codex.

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

Es un enlace, así que OpenCode usa el código del repo: no hay caché ni aprobación de hooks. El plugin registra todas las skills del kit en todos los repos (solo actúan si las pides). Solo en repos activados añade las reglas al primer mensaje de cada sesión y deja leer y ejecutar sin preguntar `scripts/`, `skills/`, `rules/` y `templates/` del plugin; en los demás, OpenCode pide permiso la primera vez que `kit-on` usa un script. OpenCode ya lee por su cuenta `AGENTS.md` y las skills de `.agents/skills/`.

## Uso

El kit es inerte en cualquier repo sin `.agents-kit.json` en su raíz.

- `kit-on`: activa el kit en el repo actual. Crea `.agents-kit.json`, `AGENTS.md`, `CLAUDE.md` y `CHANGELOG.md` si faltan, ordena un `AGENTS.md` existente, configura GitHub (etiquetas, issue de changelog, borrado de rama al fusionar) y lo envía todo por un PR que se fusiona. Si se interrumpe, se relanza y retoma.
- `kit-off`: borra `.agents-kit.json` por PR. `AGENTS.md`, `CHANGELOG.md` y las skills del proyecto se quedan.
- `kit-plan <objetivo>`: acuerda contigo el comportamiento (una pregunta cada vez), propone el desglose y, cuando lo apruebas, crea los issues con la prioridad acordada (`prio:alta`, `prio:media` o `prio:baja`).
- `kit-scout`: busca bugs, tests que faltan, deuda y docs obsoletas, y abre como máximo 5 issues `propuesta` (con prioridad puesta por el agente).
- `kit-run`: coge los issues abiertos por orden (ver "Backlog") y los lleva uno a uno hasta `main`: worktree propio, tests, PR, CI (o gate local si no corre ningún check sobre la PR), rondas de revisión hasta 0 hallazgos o `maxReviewRounds`, squash merge y limpieza. Al acabar resume las PRs fusionadas y lo que espera a tu respuesta.

Cómo se invocan:

- Claude Code: `/agents-kit:kit-on`, `/agents-kit:kit-off`, `/agents-kit:kit-plan`, `/agents-kit:kit-run`, `/agents-kit:kit-scout`.
- Codex y OpenCode: pídeselo por nombre (kit-on, kit-off, kit-plan, kit-run, kit-scout).

### Backlog

`kit-run` puede coger cualquier issue abierto salvo los que llevan `en-curso`, `necesita-respuesta`, `bloqueado`, `propuesta`, `someday` o `registro`. Orden: `prio:alta`, `prio:media`, sin prioridad, `prio:baja`; dentro de cada grupo, el más antiguo. Un issue sin cuerpo nunca se trabaja: pasa a `necesita-respuesta` pidiendo el detalle. `en-curso` excluye siempre, lo haya puesto el kit u otro flujo.

Etiquetas del kit (`kit-on` crea solo las que faltan; las que ya existen conservan su color y descripción): `en-curso`, `necesita-respuesta`, `bloqueado`, `propuesta`, `someday` (fuera del reparto por ahora), `registro` (el issue fijado "📦 Changelog") y `prio:alta|media|baja`. La única vía de alta es `scripts/kit-issue.sh crear <raíz> <título> <fichero> --prio alta|media|baja [--etiqueta X]... [--propuesta]`.

Repos activados con la v2: `listo` ya no significa nada (un issue con `listo` es un issue abierto más) y `necesita-decision` (v2) cuenta como `necesita-respuesta`, así que esos issues siguen fuera del reparto hasta que quites la etiqueta.

### Issues que esperan a Dru

- **Aprobar una propuesta:** quítale la etiqueta `propuesta` (`gh issue edit <n> --remove-label propuesta`). Las que no quieras, ciérralas o ponles `someday`.
- **`necesita-respuesta`:** el agente dejó una pregunta en un comentario (de producto, o el detalle que le falta a un issue sin cuerpo) y la PR, si existía, en borrador. Responde en el issue (o completa el cuerpo) y quita `necesita-respuesta` (`gh issue edit <n> --remove-label necesita-respuesta`); no hace falta poner otra etiqueta. El siguiente `kit-run` lo retoma con tu respuesta. En issues de la v2, quita `necesita-decision`.
- **`bloqueado`:** el comentario explica qué falta (un check colgado, el límite de rondas...). Arréglalo, responde en el issue y quita `bloqueado`.
- **PR sin fusionar (`autoMerge` falso):** revísala y fusiónala tú. El issue se cierra solo, pero conserva la etiqueta `en-curso`: quítala a mano (`gh issue edit <n> --remove-label en-curso`).
- **Reclamo colgado:** el resumen de `kit-run` lista los issues con `en-curso` que no reclamó esa ejecución: los del kit con el comando `kit-issue.sh soltar` exacto (suéltalo solo si ningún agente lo está trabajando); los de otro flujo, solo para que lo sepas.

### Changelog

Cada PR que cambia algo para quien usa la app añade su entrada en `CHANGELOG.md` (formato en la cabecera del fichero; capturas en `docs/changelog/` si el cambio es visual). `kit-pr.sh fusionar` no fusiona si el fichero está mal formado; se comprueba a mano con `scripts/kit-changelog.sh validar <raíz>`. Al terminar, `kit-run` deja el resumen como comentario en el issue fijado "📦 Changelog".

### Avisos

Te llegan al móvil cuando un issue pasa a `necesita-respuesta` o `bloqueado` y al terminar cada `kit-run` (si fusionó algo o hay issues esperándote). Canal en `notify` de la configuración global `~/.agents-kit/config.json` (un repo no puede cambiarlo):

- `ntfy` (por defecto): instala la app ntfy y suscríbete al tema que te da `kit-on` (o `cat ~/.agents-kit/ntfy-topic`). El tema se genera una vez en tu máquina y sirve para todos tus repos; para usar otro, define `KIT_NTFY_TOPIC`. Un repo nunca elige el tema. El tema es el único secreto: los avisos pasan por ntfy.sh y quien lo conozca puede leerlos (llevan el nombre del repo y el título del issue).
- `claude-push`: notificación de Claude Code al móvil. Solo funciona dentro de una sesión de Claude Code con Remote Control conectado; no en Codex, OpenCode ni `claude -p`.
- `none`: sin avisos; todo queda en GitHub.

Si un aviso falla, el flujo sigue y lo cuenta en el resumen.

### Revisores

Los revisores (`revision.puestos` de `~/.agents-kit/config.json`, o del marcador del repo, que sustituye la lista) se ejecutan sin supervisión y con todos los permisos locales, cada uno en un clon aislado del head de la PR: sin credenciales de GitHub, con `gh` y `git push` bloqueados y sin la configuración de agente que traiga la PR. Aun así pueden ejecutar código del repo en tu máquina: es el mismo nivel de confianza que el agente que implementa.

Desde la siguiente sesión en un repo activado, se cargan las reglas de `rules/` (hook `SessionStart` en Claude Code y Codex, plugin en OpenCode).

## Web de changelogs

`web/` es una app aparte (Astro en Cloudflare Workers) donde ves, app por app, los cambios de cada repo con el kit activado y cuáles no has visto todavía. Lee en vivo de GitHub los repos de tu cuenta que tienen `.agents-kit.json` y su `CHANGELOG.md` (caché de 5 minutos en KV; "Actualizar" la salta). El estado "visto" se guarda en Cloudflare KV, así que es el mismo en el móvil y en el Mac. Las capturas de repos privados las sirve el propio worker.

- Desarrollo local con datos de ejemplo: `cd web && npm ci && cp .dev.vars.example .dev.vars && npm run dev`.
- Tests: `npm test` (parser, lógica, Access) y `npm run e2e` (Playwright contra el build con su CSP, datos de ejemplo).
- Despliegue: `npm run deploy` desde `web/` (compila y despliega; `wrangler deploy` a secas usa la última compilación). Necesita el KV `SEEN` (su id en `wrangler.jsonc`; guarda el estado visto y la caché de la lista de repos), el secreto `GITHUB_TOKEN` (token fine-grained de solo lectura: Contents en todos tus repos) puesto con `npx wrangler secret put GITHUB_TOKEN`, y Cloudflare Access delante con solo tu email; `ACCESS_TEAM_DOMAIN` y `ACCESS_AUD` en `wrangler.jsonc`. Sin Access configurado, la web responde 503.

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

