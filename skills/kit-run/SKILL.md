---
name: kit-run
description: Lleva los issues abiertos del backlog hasta main uno a uno: worktree, tests, PR, CI, rondas de revisión con varios modelos y squash merge. Úsala cuando Dru escriba kit-run.
---

# kit-run

Bucle sobre los issues abiertos del repo que entran en el reparto hasta que no quede ninguno: todos salvo los que llevan `en-curso`, `necesita-respuesta` (o `necesita-decision` (v2), que cuenta igual), `bloqueado`, `propuesta`, `someday` o `registro`, por orden `prio:alta`, `prio:media`, sin prioridad, `prio:baja` y, dentro, el más antiguo. En un repo de la v2, `listo` ya no significa nada: un issue con `listo` es un issue abierto más. Los scripts hacen lo mecánico y guardan el estado en GitHub; tú encuadras, implementas, decides sobre cada hallazgo y explicas.

Ejecuta los scripts como `"${CLAUDE_PLUGIN_ROOT}/scripts/<nombre>"`; si esa variable está vacía, la raíz del plugin está dos directorios por encima del directorio base de esta skill. Abajo, `$PLUGIN` es esa raíz.

## Reglas

- Nunca te salgas del scope del issue. Lo que encuentres fuera se abre con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" crear <raíz> "<título>" <fichero> --prio <prio> --propuesta` (plantilla de `skills/kit-plan/references/issue.md`, con la evidencia; antes busca duplicados entre los abiertos).
- Nunca afirmes nada que no hayas ejecutado.
- Lee la salida completa de cada script hasta su línea `FIN:` y su código de salida; nunca la recortes con `head` ni `tail`. Exit 1 es un rechazo con motivo en stderr; exit 2, un error de entorno.
- Una duda de producto nunca la resuelves tú: ve al paso 7.
- Un exit 2 que no sepas resolver con lo de abajo: intenta soltar el issue con el motivo, para el bucle y explícaselo a Dru.
- Ficheros temporales (cuerpos, preguntas, rondas, salidas) siempre fuera del worktree, con `mktemp`.
- Cada línea `AVISO-CLAUDE: <texto>` en la salida de un script es un aviso para Dru: llama a la herramienta de notificación push de la sesión (en Claude Code, `PushNotification`) con ese texto; si la herramienta no existe, ignórala. Un `aviso: no se pudo avisar (...)` en stderr no para nada: cuéntalo en el resumen.
- Una línea `tema ntfy nuevo: <tema>` en la salida de cualquier script (aunque el aviso haya fallado) solo sale una vez: ponla siempre en el resumen final del chat con el tema y la instrucción "instala la app ntfy y suscríbete a ese tema", porque si no nadie recibe los avisos.

## Arranque

`git rev-parse --show-toplevel` da la `<raíz>`. Si no existe `<raíz>/.agents-kit.json`, di `kit no activado: ejecuta kit-on` y para. Saca el `<slug>` del repo (`owner/repo`) del remoto `origin`, como los scripts: `bash -c 'source "$1/scripts/lib/github-slug.sh"; cd "$2" && kit_origin_slug' _ "$PLUGIN" <raíz>`; si sale vacío, el remoto no es de GitHub: díselo y para. Genera el `<id>` de agente una sola vez por ejecución (`printf 'run-%s-%s\n' "$(date +%Y%m%d%H%M%S)" "$RANDOM"`) y reutiliza ese valor literal en todo el bucle. La configuración se lee con `bash -c 'source "$1/scripts/lib/config.sh"; kit_config "$2" "$3"' _ "$PLUGIN" <raíz> '<filtro>'` (`.maxReviewRounds`, `.autoMerge`, `.implementador`, `.proveedores`); mezcla el plugin, la configuración global (`~/.agents-kit/config.json`) y el marcador; exit 2 = `.agents-kit.json` o la configuración global rotos: díselo a Dru y para.

## Por cada issue

1. **Coger.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" siguiente <raíz>`: exit 0 da `<N>` en `FIN: <N>`; exit 1 (`no hay issues disponibles`) termina el bucle y vas al resumen. Después `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" reclamar <raíz> <N> <id>`:
   - Exit 1: otro agente lo cogió antes, o ya tiene `en-curso` (puesto por el kit u otro flujo). Vuelve a `siguiente`.
   - Exit 2 con `no se pudo comentar en`, o con `reclamación deshecha` sin `no se pudo deshacer`: no queda reclamo tuyo. Explícalo y para.
   - Cualquier otro exit 2, incluido `no se pudo deshacer` (el reclamo se publicó y puede seguir ahí): dile a Dru que puede quedar colgado y dale el comando exacto para soltarlo, `"$PLUGIN/scripts/kit-issue.sh" soltar <raíz> <N> <id> "reclamo sin confirmar"` con los valores reales. Para.
2. **Encuadrar.**
   - Lee el issue entero con sus comentarios (`gh issue view <N> --repo <slug> --comments`), incluidas las respuestas de Dru a un `<!-- kit-decision -->`; lee `AGENTS.md` y el código afectado.
   - Si el issue no tiene cuerpo (vacío o solo espacios), nunca se coge: escribe en un fichero qué detalle falta (problema, criterio observable, qué no entra) y ve al paso 7. Así queda sin cuerpo en `necesita-respuesta` hasta que Dru lo complete.
   - Verifica que lo que nombra el issue existe y sigue vigente.
   - Si está obsoleto o ya está hecho: `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" soltar <raíz> <N> <id> "<motivo>"`, luego `gh issue close <N> --repo <slug> --comment "<evidencia>"`, y siguiente issue.
   - Si le falta producto: paso 7.
   - Todo comportamiento visible para el usuario que el issue no define es una decisión de producto: usa el paso 7 (`kit-issue.sh decision`) salvo que solo haya una lectura razonable. En todo caso, lista esas interpretaciones en el cuerpo de la PR bajo `## Decisiones de comportamiento` y en el resumen final del chat.
   - Escribe en el chat 4 líneas: qué pide; sigue vigente (con la evidencia); qué vas a hacer; qué NO tocas.
3. **Implementar.**
   - Rama: si ya existe una `issue-<N>-*` (`git -C <raíz> branch --list 'issue-<N>-*'` o `git -C <raíz> ls-remote --heads origin 'issue-<N>-*'`), es un issue retomado: reutiliza su `<slug-rama>` tal cual. Si no, sácalo del título (minúsculas, `a-z0-9` y guiones).
   - `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-worktree.sh" abrir <raíz> <N> <slug-rama>`. La ruta es la línea `FIN: <wt>`; trabaja solo con esa ruta absoluta. Si la rama solo existe en origin, el worktree parte de `origin/<rama>`. Si el repo declara `setup`, el script lo ejecuta en el worktree nuevo; exit 2 con `setup falló` (o ruta de `setup` insegura) es un bloqueo: bloquea el issue con esa salida (ver abajo).
   - Tests primero (unitarios, e2e y casos límite), luego el código. Tests, lint y build de `AGENTS.md` en verde en local.
   - `.implementador` (`familia` y `nivel`) dice el modelo que implementa: `.proveedores[familia].modelos[nivel]`. Si la sesión no corre con ese modelo, delega la implementación en un subagente con ese modelo cuando la herramienta lo permita, pasándole la ruta del worktree, el issue y tus 4 líneas.
   - Si el diff toca rutas de `.protegido` (de `.agents-kit.json`, leído de la rama por defecto), el cuerpo de la PR lleva una sección `## Zonas protegidas` que nombra cada ruta protegida tocada y por qué; `fusionar` lo exige.
   - Automejora en la misma PR: si aprendiste algo, actualiza `AGENTS.md` y las skills del proyecto.
4. **PR.** Commit en el worktree y `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" abrir <wt> <N> "<título>" <fichero-cuerpo>` (empuja; añade `Cierra #<N>` si falta; si la rama ya tiene una PR abierta, como en un issue retomado, la reutiliza sin crear otra). La primera línea es `<pr>`. Si esa PR está en borrador (`gh pr view <pr> --repo <slug> --json isDraft`), quítaselo con `gh pr ready <pr> --repo <slug>`. Después añade la entrada de `CHANGELOG.md` con el formato del comentario de cabecera del propio fichero (ya con el número y la URL de la PR) y comprueba el formato con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-changelog.sh" validar <wt>` hasta que salga 0 (exit 1 señala `CHANGELOG.md:<línea>: <motivo>`: corrígelo). Si el cambio es visual, durante la comprobación e2e del estado final haz capturas con el navegador automatizado, solo las que aportan, guárdalas en `<wt>/docs/changelog/<pr>-<nombre>.png` comprimidas por debajo de 500 KB y enlázalas en la versión extendida de la entrada; sin cambio visual, sin capturas. Commit y `git -C <wt> push -q`. Entonces la puerta de CI:
   - `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" esperar-ci <wt> <pr>`. `FIN: verde`: sigue.
   - `FIN: sin-ci`: el repo no tiene workflows, o ninguno arrancó un check para ese SHA en `KIT_CI_GRACE` segundos (300 por defecto; por ejemplo, workflows sin disparador `pull_request`). Ejecuta en el worktree los comandos de test, lint y build de `AGENTS.md` sobre el último commit, guarda toda su salida en un fichero y, si todo pasa, `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" gate-local <wt> <pr> <fichero>`. Repite el gate tras cada push: vale solo para ese SHA, y solo mientras ese SHA no tenga ningún check (si aparece alguno, manda el CI).
   - Exit 1 `el CI terminó en ...`: lee el fallo (`gh run view --repo <slug> --log-failed`), corrígelo, commit, push y vuelve a esperar.
   - Exit 1 `no concluyó en ...`: hay checks que no terminan. Míralos con `gh pr checks <pr> --repo <slug>`; si no avanzan, bloquea el issue (ver abajo) explicando qué check se quedó colgado.
   - Exit 2 `la PR apunta a ...`: falta un push; empuja y repite.
5. **Revisión.** Rondas `r = k + 1, k + 2, ...`, con `k` de la línea `FIN: <k> rondas` de `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" historial <wt> <pr>` (0 en una PR nueva; las rondas previas cuentan para `.maxReviewRounds`). Sigue `references/ronda.md` (puestos, puestos sin confirmar, decidir, fichero de ronda, cuándo parar). Antes de cada ronda, todo confirmado y empujado: los revisores revisan el head de la PR. Lanza todos los puestos con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-review-all.sh" <wt> <pr> <r> <N>`, el único lanzador: los ejecuta en paralelo con su candidato y su fallback, espera a todos e imprime por puesto `puesto <i> (<familia>/<modelo>): ok`, `sin-confirmar (<motivo>: <detalle>)` o `fallback a <familia>/<modelo>`, líneas `aviso: ...`, `salidas: <dir>` y `FIN: <n> puestos, <m> sin confirmar`.
   - La familia del implementador decide qué puestos van a otra familia. La detecta del entorno (Codex → `gpt`, Claude Code → `claude`); añade `--implementador <familia>` (un nombre de `.proveedores`) siempre en OpenCode, y siempre que la implementación la hizo un subagente de otra familia que la de esta sesión: cuenta la del que implementó de verdad. Exit 2 `pasa --implementador <familia>`: repite añadiendo esa opción.
   - Si el límite de tiempo de tu herramienta es menor que `KIT_REVIEW_TIMEOUT` (1800 s por intento de cada puesto), lánzalo en segundo plano (por ejemplo `run_in_background` en Claude Code).
   - Exit 1 `sin puestos de revisión configurados`: `revision.puestos` está vacío; revisa tú el cambio con todos los focos y dilo en el fichero de ronda. Otro exit 1 (familia o nivel desconocido) o exit 2 (`.agents-kit.json` o la configuración global rotos): díselo a Dru y para.
   - Lee entero cada `<dir>/rev-<i>.out` (en `<dir>/puestos.tsv` está qué candidato cubrió cada puesto). Un puesto `sin-confirmar` nunca cuenta como "sin hallazgos": sigue "Puestos sin confirmar" de `references/ronda.md`. Cada `aviso: ... revisa el login, el modelo o la cuota` va al resumen final para Dru.
   - Escribe el fichero de ronda (cada hallazgo con su `(puesto <i>)`) y publícalo con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" ronda <wt> <pr> <r> <fichero>`; exit 1 señala la línea mal formada: corrígela y repite.
   - Si aplicaste algo: commit, push, puerta de CI del paso 4 y ronda nueva obligatoria.
   - Si la ronda no cambió código (0 hallazgos, o ninguno aplicado porque todos se rechazaron con motivo): no hay ronda nueva; pasa a fusionar.
   - Si `r` llega a `.maxReviewRounds` (o un issue retomado ya trae `k` rondas en el límite) y aún queda una ronda nueva por hacer: confirma y empuja lo que haya, `gh pr ready --undo <pr> --repo <slug>`, bloquea el issue con un resumen de lo pendiente y siguiente issue.
6. **Fusionar.** Con `.autoMerge` verdadero: `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" fusionar <wt> <pr> <N>`.
   - Exit 0: guarda la línea `PR fusionado: <url>` para el resumen y ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-worktree.sh" limpiar <raíz> <N>` (`FIN: limpio`).
   - `fusionar` también ejecuta `checks.pre-merge` del repo y exige `## Zonas protegidas` si procede; todos los motivos salen juntos. Las puertas leen el marcador de la rama por defecto, no el de la PR.
   - Exit 1 con `rebasada sobre ...`: el script ya rebasó y empujó. Vuelve a la puerta de CI del paso 4 y reintenta.
   - Otro exit 1: lee cada motivo. Corrige lo que puedas (conflicto, CI, ronda pendiente) y reintenta; si no, bloquea. `la última ronda aplicó cambios: falta una ronda nueva` significa volver al paso 5 con la ronda siguiente. `la ronda <r> tiene puestos sin confirmar (...)`: sigue "Puestos sin confirmar" de `references/ronda.md`.
   - Con `.autoMerge` falso: deja la PR lista sin fusionar ni limpiar; el issue sigue `en-curso` y se cierra solo al fusionarla Dru. Anótala para el resumen.
7. **Duda de producto, en cualquier paso.** Si ya hay PR, `gh pr ready --undo <pr> --repo <slug>`. Escribe la pregunta (contexto, opciones y lo que propones) en un fichero y ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" decision <raíz> <N> <id> <fichero>` (`FIN: necesita-respuesta #<N>`; pone `necesita-respuesta`). El worktree se queda, si lo había. Siguiente issue.

**Bloquear:** escribe el motivo y lo pendiente en un fichero y ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" bloquear <raíz> <N> <id> <fichero>` (`FIN: bloqueado #<N>`). Si había PR, antes `gh pr ready --undo <pr> --repo <slug>`. El worktree se queda.

**Barrido:** al terminar la tanda (cuando `siguiente` da exit 1), antes del resumen, ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-worktree.sh" barrer <raíz>` (`FIN: <n> borrados`): borra los worktrees limpios del kit ya terminados (PR fusionada con esa punta, o issue cerrado sin commits propios). Si falla, cuéntalo en el chat y sigue.

## Resumen final

Cuando `siguiente` da exit 1, antes del texto del chat: si en esta ejecución fusionaste alguna PR o hay issues que pasaron a `necesita-respuesta` o `bloqueado` en esta ejecución (los que ya esperaban antes de empezar no cuentan), escribe el resumen en un fichero temporal (cada PR fusionada con su línea corta del changelog y su URL, y cada uno de esos issues con su URL y qué tiene que hacer Dru) y publícalo con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-changelog.sh" resumen <raíz> <id> <fichero>`; la URL del comentario es la línea `FIN: <url>` (si ya estaba publicado, no se duplica). Después `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-notify.sh" <raíz> "<repo>: kit-run terminado" "<n> fusionadas, <m> esperan" <url del comentario>`; si `resumen` falla, avisa igual sin URL (sin el último argumento). Si no pasó nada de eso, ni resumen ni aviso. Si alguno de los dos falla (por ejemplo, exit 2 `no hay issue "📦 Changelog": ejecuta kit-on`), no pares: cuéntalo en el chat.

Después escribe en el chat:

- Cada PR fusionada (su URL) y cada issue cerrado por obsoleto.
- Cada proveedor que dio `aviso: ... revisa el login, el modelo o la cuota` en `kit-review-all.sh`: qué CLI tiene que autenticar Dru (o qué modelo no existe).
- Si algún script imprimió `tema ntfy nuevo: <tema>`: el tema y "instala la app ntfy y suscríbete a ese tema".
- Cada issue que espera a Dru, con su URL y qué tiene que hacer:
  - `necesita-respuesta` o `bloqueado`: responde en el issue (o completa el cuerpo) y quita `necesita-respuesta` (o `bloqueado`). No hay que poner ninguna otra etiqueta: el siguiente `kit-run` lo retoma. Un issue de la v2 con `necesita-decision` (v2) se trata igual: quita `necesita-decision`.
  - PR sin fusionar por `autoMerge` falso: revisarla y fusionarla; después, quitar a mano `en-curso` del issue cerrado.
- Posibles reclamos colgados: los issues abiertos con `en-curso` que no reclamaste en esta ejecución (`gh issue list --repo <slug> --state open --label en-curso --json number,url`). Para cada uno, mira sus comentarios (`gh issue view <N> --repo <slug> --comments`):
  - Con marcador del kit: saca el `<id>` del último `<!-- kit-reclamado: <id> -->` y dale a Dru el comando exacto con los valores reales: `"$PLUGIN/scripts/kit-issue.sh" soltar <raíz> <N> <id> "reclamo colgado"`. Avisa de que solo debe soltarlo si ningún agente lo está trabajando.
  - Sin marcador del kit (lo puso otro flujo, como `resolver-issue`): lístalo con su URL como "en curso por otro flujo"; no ofrezcas soltarlo.
