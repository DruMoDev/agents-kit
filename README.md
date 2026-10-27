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

Es un enlace, así que OpenCode usa el código del repo: no hay caché ni aprobación de hooks. Sirve para OpenCode 1.x y 2.x. El plugin registra todas las skills del kit en todos los repos (solo actúan si las pides). Solo en repos activados añade las reglas a cada sesión y deja leer y ejecutar sin preguntar `scripts/`, `skills/`, `rules/` y `templates/` del plugin; en los demás, OpenCode 1.x pide permiso la primera vez que `kit-on` usa un script (2.x no pregunta por directorios externos salvo que lo configures). En macOS, si OpenCode 2.x falla con errores 500 en repos de `~/Documents`, su servicio de fondo no tiene permiso para esa carpeta: dáselo en Ajustes > Privacidad y seguridad, o usa `opencode --standalone`. OpenCode ya lee por su cuenta `AGENTS.md` y las skills de `.agents/skills/`.

## Uso

El kit es inerte en cualquier repo sin `.agents-kit.json` en su raíz.

- `kit-on`: activa el kit en el repo actual. Trabaja en un worktree temporal de `origin/<rama por defecto>` (en `~/.agents-kit/worktrees/<repo>/kit-on`), así que tu clon puede tener cambios o estar en otra rama: no se toca. Pregunta si el repo lleva `CHANGELOG.md` (`"changelog"` en el marcador), crea `.agents-kit.json`, `AGENTS.md`, `CLAUDE.md` y `CHANGELOG.md` si faltan, crea `~/.agents-kit/config.json` si falta, te enseña como diff el reordenado de un `AGENTS.md` existente y solo lo aplica con tu OK (sin OK solo añade `## Reglas del proyecto` si falta), avisa si el repo tiene hooks de git sin `setup`, te propone `contenido` (a partir de lo que el historial commitea sin PR) y `protegido` (a partir de lo que `AGENTS.md` dice que no se toca), configura GitHub (solo las etiquetas que faltan, issue de changelog, borrado de rama al fusionar), te lista los issues abiertos que entrarían en el reparto para pasar a `someday` los que digas, y lo envía todo por un PR que se fusiona en cuanto su CI sale verde (o si no hay CI; si el CI sigue en marcha al llegar al tiempo máximo, ver `ciTimeoutMin`, el PR queda abierto y `kit-ship-pr.sh fusionar <raíz> kit-on` espera al CI y lo fusiona sin repetir nada más). Si ya tenías un `CHANGELOG.md` con otro formato, te pregunta si te quedas con el tuyo (`"changelog": false`) o adoptas el del kit. El worktree se borra al final; si algo falla antes de crear el PR, te dice dónde está y relanzar `kit-on` lo retoma. El marcador llega a tu clon con `git pull`. En un repo ya activado (por ejemplo, con la v2), `kit-on` lo actualiza (ver "Migrar un repo desde la v2").
- `kit-off`: borra `.agents-kit.json` por PR, también desde un worktree temporal. `AGENTS.md`, `CHANGELOG.md` y las skills del proyecto se quedan.
- `kit-plan <objetivo>`: acuerda contigo el comportamiento (una pregunta cada vez), propone el desglose y, cuando lo apruebas, crea los issues con la prioridad acordada (`prio:alta`, `prio:media` o `prio:baja`), su entorno (`entorno:nube` o `entorno:mac`) y `Depende de #N` en el cuerpo cuando uno necesita otro antes.
- `kit-scout`: busca bugs, tests que faltan, deuda y docs obsoletas, y abre como máximo 5 issues `propuesta` (con prioridad puesta por el agente).
- `kit-run`: coge los issues abiertos por orden (ver "Backlog") y los lleva uno a uno hasta `main`: worktree propio, tests, PR, CI (solo cuentan los workflows propios del repo en `.github/workflows/`; los de GitHub, como Dependabot o CodeQL, no son CI; sin CI propio, o si GitHub no arranca el CI porque la cuenta se quedó sin minutos de Actions, gate local con `verificar.completo`; en este caso fusiona con `--admin` y, pasado el día 1, relanza el CI bloqueado por si ya hay minutos) en paralelo con las rondas de revisión hasta 0 hallazgos o `maxReviewRounds`, squash merge y limpieza (que deja tu clon al día con `main` si está en la rama por defecto y el avance es fast-forward; si no, te avisa de por qué). Al acabar resume las PRs fusionadas y lo que espera a tu respuesta.
- `kit-run <N>`: lo mismo para un solo issue. Lo coge solo si `kit-run` también podría cogerlo (abierto, de tu cuenta, sin etiquetas que lo excluyan ni dependencias abiertas) y, si no, dice por qué. Sirve para lanzarlo en segundo plano desde una sesión contigo, por ejemplo para arreglar un bug que has aprobado sin parar lo que estáis haciendo.

Desde la siguiente sesión en un repo activado, se cargan las reglas de `rules/` (hook `SessionStart` en Claude Code y Codex, plugin en OpenCode). Si una regla del `AGENTS.md` del proyecto choca con una del kit, manda la del proyecto (sección `## Reglas del proyecto`). El límite: el código va por PR, con tests en verde y revisión, y el producto lo decides tú; eso no lo cambia un `AGENTS.md`. `.agents/skills/`, `AGENTS.md` y las rutas que declares en `"contenido": ["docs/ideas/"]` pueden ir directas a la rama por defecto en una sesión contigo (así se mejoran las skills en caliente); `kit-run` siempre va por PR.

Cómo se invocan:

- Claude Code: `/agents-kit:kit-on`, `/agents-kit:kit-off`, `/agents-kit:kit-plan`, `/agents-kit:kit-run`, `/agents-kit:kit-scout`.
- Codex y OpenCode: pídeselo por nombre (kit-on, kit-off, kit-plan, kit-run, kit-scout).

### Backlog

`kit-run` puede coger cualquier issue abierto salvo los que llevan `en-curso`, `necesita-respuesta`, `bloqueado`, `propuesta`, `someday` o `registro`, los que dicen en su cuerpo `Depende de #N` o `Bloqueado por #N` mientras #N siga abierto, los que llevan una etiqueta `serializa:<eje>` mientras otro issue de ese eje está `en-curso` y, en una sesión en la nube, los que no llevan `entorno:nube` o llevan algún eje.

Un eje (`serializa:<eje>`, por ejemplo `serializa:migracion-d1`) es un recurso que no admite dos issues a la vez aunque sean distintos, como una numeración de migraciones que git mezclaría sin conflicto. Lo declara el `AGENTS.md` del proyecto y basta con poner la etiqueta. `reclamar` toma un candado por eje, la referencia `refs/locks/<eje>` de origin, con un push que solo gana el primero (las etiquetas tardan segundos en verse y no sirven para arbitrar); lo sueltan `fusionar`, `soltar`, `decision` y `bloquear`. En la nube no se puede crear esa referencia, así que allí no se cogen issues con eje. Si a mitad de un issue resulta que necesita un eje, `kit-issue.sh tomar-eje <raíz> <N> <id> <eje>` le pone la etiqueta y toma el candado; si el eje está ocupado, el issue se suelta y vuelve cuando quede libre. Si una sesión muere con un candado tomado, `kit-issue.sh liberar-eje <raíz> <eje>` lo libera (solo si nadie trabaja ese eje); el candado de un issue ya cerrado se recupera solo al reclamar. Orden: `prio:alta`, `prio:media`, sin prioridad, `prio:baja`; dentro de cada grupo, el más antiguo. Un issue sin cuerpo nunca se trabaja: pasa a `necesita-respuesta` pidiendo el detalle. `en-curso` excluye siempre, lo haya puesto el kit u otro flujo.

Etiquetas del kit (`kit-on` crea solo las que faltan; las que ya existen conservan su color y descripción): `en-curso`, `necesita-respuesta`, `bloqueado`, `propuesta`, `someday` (fuera del reparto por ahora), `registro` (el issue fijado "📦 Changelog"), `prio:alta|media|baja` y `entorno:nube|mac` (`mac`: solo se puede hacer en tu Mac). La única vía de alta es `scripts/kit-issue.sh crear <raíz> <título> <fichero> --prio alta|media|baja --entorno nube|mac [--etiqueta X]... [--propuesta]`.

Repos activados con la v2: `listo` ya no significa nada (un issue con `listo` es un issue abierto más) y `necesita-decision` (v2) cuenta como `necesita-respuesta`, así que esos issues siguen fuera del reparto hasta que quites la etiqueta.

### Issues que esperan a Dru

- **Aprobar una propuesta:** quítale la etiqueta `propuesta` (`gh issue edit <n> --remove-label propuesta`). Las que no quieras, ciérralas o ponles `someday`.
- **`necesita-respuesta`:** el agente dejó una pregunta en un comentario (de producto, o el detalle que le falta a un issue sin cuerpo) y la PR, si existía, en borrador. Responde en el issue (o completa el cuerpo) y quita `necesita-respuesta` (`gh issue edit <n> --remove-label necesita-respuesta`); no hace falta poner otra etiqueta. El siguiente `kit-run` lo retoma con tu respuesta. En issues de la v2, quita `necesita-decision`.
- **`bloqueado`:** el comentario explica qué falta (un check colgado, el límite de rondas...). Arréglalo, responde en el issue y quita `bloqueado`.
- **PR sin fusionar (`autoMerge` falso):** revísala y fusiónala tú. El issue se cierra solo, pero conserva la etiqueta `en-curso`: quítala a mano (`gh issue edit <n> --remove-label en-curso`). Si el issue tenía un eje, su candado se queda tomado, pero el siguiente `reclamar` de ese eje ve que el issue que lo tenía ya está cerrado y lo recupera solo.
- **Reclamo colgado:** el resumen de `kit-run` lista los issues con `en-curso` que no reclamó esa ejecución: los del kit con el comando `kit-issue.sh soltar` exacto (suéltalo solo si ningún agente lo está trabajando); los de otro flujo, solo para que lo sepas.

### Changelog

Cada PR que cambia algo para quien usa la app añade su entrada en `CHANGELOG.md` (formato en la cabecera del fichero; capturas en `docs/changelog/` si el cambio es visual). `kit-pr.sh fusionar` no fusiona si el fichero está mal formado; se comprueba a mano con `scripts/kit-changelog.sh validar <raíz>`. Al terminar, `kit-run` deja el resumen como comentario en el issue fijado "📦 Changelog".

Con `"changelog": false` en el marcador (el repo no lleva el changelog del kit, o tiene uno propio con otro formato) no hay entrada por PR, ni issue fijado, ni validación al fusionar: el resumen de `kit-run` queda en el chat y en el aviso.

### Avisos

Te llegan al móvil cuando un issue pasa a `necesita-respuesta` o `bloqueado` y al terminar cada `kit-run` (si fusionó algo o hay issues esperándote). Canal en `notify` de la configuración global `~/.agents-kit/config.json` (un repo no puede cambiarlo):

- `ntfy` (por defecto): instala la app ntfy y suscríbete al tema que te da `kit-on` (o `cat ~/.agents-kit/ntfy-topic`). El tema se genera una vez en tu máquina y sirve para todos tus repos; para usar otro, define `KIT_NTFY_TOPIC`. Un repo nunca elige el tema. El tema es el único secreto: los avisos pasan por ntfy.sh y quien lo conozca puede leerlos (llevan el nombre del repo y el título del issue).
- `claude-push`: notificación de Claude Code al móvil. Solo funciona dentro de una sesión de Claude Code con Remote Control conectado; no en Codex, OpenCode ni `claude -p`.
- `none`: sin avisos; todo queda en GitHub.

Si un aviso falla, el flujo sigue y lo cuenta en el resumen.

### Revisores

Cada ronda tiene tres puestos de revisión (`revision.puestos` de `~/.agents-kit/config.json`, o del marcador del repo, que sustituye la lista; los revisores dependen de lo que pagas en cada momento, así que van en el global y un repo solo los sobrescribe por una necesidad muy concreta, nunca porque un agente lo proponga sin que se lo pidas), cada uno con su foco, su nivel (`profundo` o `rapido`) y su familia: `otra` (distinta de la que implementó), `misma` o un nombre de `proveedores`. Los proveedores son lo que pagas y se cambian solo en el global: `"gpt": {"cli": "opencode", ...}` pasa a Codex cambiando `"cli": "codex"`, y una familia nueva es una entrada más (`cli` es `claude`, `opencode` o `codex`). Al cambiar de CLI revisa también `modelos`, porque cada CLI nombra los modelos a su manera: OpenCode usa `proveedor/modelo` y Codex solo el modelo. Por ejemplo, `"gpt": {"cli": "codex", "modelos": {"profundo": "gpt-6.1-sol", "rapido": "gpt-6.1-sol"}}`; el adaptador de Codex quita un `openai/` inicial por si acaso, pero con otro prefijo el modelo no existe, el puesto cae a la familia del implementador y `kit-run` te avisa. Cuenta el proveedor cuyo CLI está en el PATH; si falla por login, modelo o cuota, el puesto prueba el siguiente y, agotados, la familia del implementador (`kit-run` te avisa del login pendiente). Un puesto que no entrega (tiempo agotado, respuesta inválida) queda "sin confirmar" y la PR no se fusiona hasta que entregue. Los puestos salen del marcador de la rama por defecto, como cuenta `fusionar`: una PR no puede quitar ni rebajar sus revisores. Con `"revision": {"puestos": []}` no hay puestos: `kit-run` revisa el cambio por su cuenta y `fusionar` solo exige la ronda, sin revisiones por puesto.

Los revisores se ejecutan sin supervisión y con todos los permisos locales, cada uno en un clon aislado del head de la PR: sin credenciales de GitHub, con `gh` y `git push` bloqueados y sin la configuración de agente que traiga la PR. Aun así pueden ejecutar código del repo en tu máquina: es el mismo nivel de confianza que el agente que implementa.

### Configuración global

`~/.agents-kit/config.json` (o la ruta de `KIT_CONFIG`) guarda lo que depende de ti y vale para todos tus repos; `kit-on` la crea desde `templates/config.json` si falta. Precedencia: valores del plugin < global < `.agents-kit.json` del repo.

- `proveedores`: familias de modelos que pagas, cada una con su `cli` (`claude`, `opencode` o `codex`) y sus modelos `profundo` y `rapido`. Solo en el global.
- `revision.puestos`: los puestos de revisión (ver "Revisores").
- `revision.rondas` (solo en el global): `mezcla` (por defecto) o `completas`. Con `mezcla`, desde la ronda 2 un puesto, que rota cada ronda, revisa todo el diff con contexto limpio y los demás revisan entero lo que cambió desde la ronda anterior (arreglos de la revisión, del CI o de otro motivo) y verifican que los arreglos resuelven sus hallazgos: cuesta menos que repetir revisiones completas y conserva una mirada independiente por ronda.
- `implementador`: `{"familia": "claude", "nivel": "profundo"}`, el modelo que implementa en `kit-run`. Solo en el global.
- `notify`: canal de avisos (ver "Avisos"). Solo en el global.
- `autoMerge` y `maxReviewRounds`.
- `verificar`: `{"rapido": "<comando>", "completo": "<comando>"}`. `rapido` es lo que `kit-run` pasa en local mientras trabaja (formato, lint estricto y tests de lo cambiado, en segundos) y `completo` la suite entera, que usa como gate local cuando la PR no tiene CI (`kit-verify.sh correr`). Sin ellos, `kit-run` usa los comandos de `AGENTS.md`. La política del kit: el CI completo en la PR es la verja y el pre-commit es ligero, nunca suites completas ni builds. `kit-on` lo comprueba (`kit-verify.sh estado`: CI, cancelación de CI viejos, caché, hook y `verificar`), mide el hook si le dejas y te propone lo que falte como issues `propuesta`; no instala nada sin tu OK.
- Ficheros temporales: el kit y sus agentes los dejan en `~/.agents-kit/tmp/` (o `KIT_TMP`): cuerpos de PR, rondas, salidas de los revisores y esperas. Se pueden borrar cuando no haya ningún `kit-run` en marcha.
- `ciTimeoutMin`: minutos que el kit espera al CI de un PR antes de dejarlo abierto. Sin ella, el kit lo calcula del historial del repo: 1,5 veces la ejecución verde más lenta de las últimas 20, entre 30 minutos y 3 horas (`KIT_CI_TIMEOUT`, en segundos, manda sobre ambos).

Un repo solo puede definir en su marcador `autoMerge`, `maxReviewRounds`, `revision.puestos` (sustituye la lista entera), `contenido`, `protegido`, `setup`, `checks`, `changelog`, `ciTimeoutMin` y `verificar`. Cualquier otra clave se ignora con un aviso que dice dónde va (sale una vez por hora y repo, no en cada script).

### Modelo de confianza

- **Solo tus issues y tus comentarios.** `kit-run` solo coge issues abiertos por la cuenta de `gh` con la que corre, y lee cada issue con `kit-issue.sh leer`, que muestra solo los comentarios de esa cuenta y cuenta los demás sin enseñarlos: los comentarios de otras personas nunca son instrucciones, aunque digan venir de ti. En un repo público cualquiera puede abrir issues o comentar; nada de eso llega al agente como orden.
- **Las puertas de fusión vienen de la rama por defecto.** `fusionar` lee `protegido`, `checks`, `changelog` y `revision.puestos` del marcador de la rama por defecto (y `kit-review-all.sh` lanza los puestos de ahí) y rechaza una PR que modifique el `pre-merge`: una PR no puede aflojar sus propias puertas.
- **Reclamos solo de tu cuenta.** Los marcadores `kit-reclamado` y `kit-soltado` solo cuentan si los escribió la cuenta de `gh` del kit: un comentario ajeno no bloquea ni libera un issue.
- **Lo tuyo no lo cambia un repo.** `proveedores`, `implementador`, `notify` y el tema de ntfy solo se leen de tu máquina: un repo no puede elegir qué CLI se ejecuta ni adónde van los avisos.
- **Revisores aislados.** Cada revisor corre en un clon desechable sin credenciales, con `gh` y `git push` bloqueados (ver "Revisores"). El texto de la PR se le pasa como afirmaciones que tiene que comprobar.


### Ganchos por repo

En `.agents-kit.json` del repo (rutas relativas al repo, sin `..` ni absolutas; tiempo máximo `KIT_HOOK_TIMEOUT`, 1800 s por defecto):

- `"setup": "tools/preparar.sh"`: se ejecuta con `bash` en cada worktree nuevo (`kit-worktree.sh abrir`); si falla, `kit-run` bloquea el issue con su salida.
- `"protegido": ["lib/", "cli/"]`: si la PR toca esas rutas, su cuerpo debe tener `## Zonas protegidas` nombrándolas.
- `"checks": {"pre-merge": "tools/pre-merge.sh"}`: `kit-pr.sh fusionar` lo ejecuta en el worktree (desde su sitio, así que puede cargar ficheros hermanos con `$(dirname "$0")`); si falla, no fusiona y muestra su salida. Si la PR modifica ese script, no se fusiona: se cambia en una PR que no dependa de él.

`fusionar` lee `protegido`, `checks`, `changelog` y `revision.puestos` del marcador de la rama por defecto y exige que el script `pre-merge` sea el de ella: una PR no puede aflojar sus propias puertas. `kit-worktree.sh barrer <raíz>` borra los worktrees limpios del kit ya terminados (PR fusionada con la punta de la rama, o issue cerrado sin commits propios) y su rama local; ante un fallo de gh no borra; `kit-run` lo ejecuta al terminar.

### Migrar un repo desde la v2

Tras actualizar el plugin, `kit-run` no trabaja en un repo de la v2: al arrancar dice `kit en versión anterior: ejecuta kit-on para actualizar` si faltan etiquetas de la v3 o el marcador tiene claves de la v2. `kit-on` en un repo ya activado lo actualiza por PR, y puedes relanzarlo sin riesgo:

1. **Marcador.** Quita `reviewers`, `implementer` y `notify` y te dice adónde va cada una, con su valor anterior: `reviewers` a `revision.puestos` (en el global, o en el marcador si el repo necesita su propia lista), `implementer` a `implementador` del global y `notify` a `notify` del global. Si tu canal era `none` o `claude-push`, ponlo en el global: si no, los avisos salen por ntfy.
2. **Etiquetas.** Crea las que faltan (`necesita-respuesta`, `someday`, `registro`, `prio:*`) y marca el issue "📦 Changelog" con `registro`. `necesita-decision` (v2) cuenta como `necesita-respuesta` hasta que la quites. `listo` ya no significa nada: cuando ningún issue la use, puedes borrarla (`gh label delete listo --repo <owner/repo>`).
3. **Backlog.** En la v3 cualquier issue abierto de tu cuenta entra en el reparto: `kit-on` te lista los que `kit-run` cogería y aparca en `someday` los que digas.
4. **Changelog.** Si tu `CHANGELOG.md` no tiene el formato del kit, te pregunta si te quedas con el tuyo (`"changelog": false`) o adoptas el del kit.
5. **PRs a medias.** Una PR abierta con la v2 cuya última ronda no tiene revisión por puesto necesita una ronda nueva antes de fusionarse.

Para cambiar de proveedor no se toca ningún repo: en el global, cambia el `cli` de una familia y sus `modelos` (ver "Revisores"), o añade una familia nueva.

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

