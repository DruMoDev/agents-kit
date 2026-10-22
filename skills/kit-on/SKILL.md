---
name: kit-on
description: Activa agents-kit en el repo actual (marcador, AGENTS.md, CHANGELOG, GitHub) y lo deja fusionado por PR. Úsala cuando Dru pida activar el kit en este repo o escriba kit-on.
---

# kit-on

Activa el kit en el repo donde estás. Los scripts hacen lo mecánico; tú preguntas a Dru, decides y explicas.

Ejecuta los scripts como `"${CLAUDE_PLUGIN_ROOT}/scripts/<nombre>"`; si esa variable está vacía, la raíz del plugin está dos directorios por encima del directorio base de esta skill.

Lee siempre la salida completa de cada script y su código de salida; nunca la recortes con `head` ni `tail`. Ante cada código distinto de 0, dile a Dru en español qué pasó y qué tiene que hacer, y para.

**El árbol de Dru no se toca.** Todo pasa en un worktree temporal de `origin/<rama por defecto>` que crea `kit-ship-pr.sh`; da igual que el clon principal tenga cambios, otra rama o commits sin publicar. Nunca hagas `git checkout`, `git stash`, `git pull` ni escribas ficheros en la raíz del repo: solo en `<wt>`.

Las preguntas a Dru, una cada vez y solo lo que falte.

## Pasos

1. **Raíz.** `git rev-parse --show-toplevel` da la `<raíz>` (si falla, no es un repo git: díselo y para).
2. **Worktree.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-ship-pr.sh" abrir <raíz> kit-on sin-marcador`. La línea `FIN: <ruta>` es el `<wt>` y `base:` la rama por defecto.
   - `ya existía` en la salida: una activación anterior se interrumpió; se retoma sobre ese worktree (cada paso de abajo dice qué cambia al retomar).
   - Exit 1: `el kit ya está activo`: díselo y termina. `ya hay un PR abierto`: dale la URL; que lo fusione o lo cierre y relance `kit-on`. Rama `kit-on` vieja (local u origin): repite el comando que da el script para borrarla. `sin remoto de GitHub`: el kit necesita GitHub; para.
   - Exit 2: error de entorno (`gh no autenticado`: que ejecute `gh auth login`); explícalo y para.
3. **Changelog.** Pregunta a Dru si este repo lleva `CHANGELOG.md` (una entrada por PR y el issue fijado "📦 Changelog"). Al retomar, si `jq .changelog <wt>/.agents-kit.json` ya da `true` o `false`, no lo vuelvas a preguntar.
4. **Activar.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-activate.sh" <wt> --changelog true|false` (idempotente). Fíjate en sus líneas `creado:` y `cambiado:` y transmite cada aviso de stderr.
   - `creada la configuración global en <ruta>`: díselo; ahí se cambian proveedores, revisores y avisos para todos sus repos.
   - Aviso de hooks de git (`core.hooksPath` o hooks versionados) sin `setup`: los worktrees del kit no los preparan. Busca en el repo un script que prepare el entorno o instale los hooks (por ejemplo `tools/agente/preparar-entorno.sh` o lo que digan su `AGENTS.md` y su README) y pregúntale a Dru si se declara como `setup`. Con su sí, relanza `kit-activate.sh <wt> --changelog <igual> --setup <ruta>`; si dice que no hace falta, sigue.
   - Exit 1 es un error de uso tuyo: corrígelo. Exit 2: error de entorno, explícalo y para.
5. **Ordenar un `AGENTS.md` que ya existía.** Toca si la salida del paso 4 no tiene `creado: AGENTS.md`. Al retomar: si `git -C <wt> cat-file -e HEAD:AGENTS.md` falla lo creó el kit y no toca; si `git -C <wt> diff HEAD -- AGENTS.md` ya muestra el reordenado, no lo repitas. Si `AGENTS.md` es un symlink, no se ordena: díselo.

   Escribe la propuesta en un fichero temporal fuera del repo, con las secciones de `templates/AGENTS.md` del plugin: Qué es, Stack, Comandos, Skills del proyecto, Mapa del código y `## Reglas del proyecto`.
   - No pierdas información del proyecto: todo dato útil va a su sección.
   - Las reglas del proyecto van enteras a `## Reglas del proyecto`, aunque se parezcan a las del kit: si chocan con el kit, mandan las del proyecto. Quitar lo que ya cubre el kit es un paso aparte que se hace con Dru, no aquí.
   - Quita la cronología y el estado (avances, fechas, "hecho", pendientes).
   - Rellena lo que se deduzca del repo: comandos de `package.json`, `Makefile`, `pyproject.toml`; versiones del stack; directorios de primer nivel; skills de `.agents/skills`.
   - Borra las secciones que no apliquen y los comentarios de la plantilla que ya estén resueltos.

   Después `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-agents-md.sh" diff <wt> <propuesta>` (no escribe nada) y enséñale a Dru el diff completo. Solo con su OK: `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-agents-md.sh" aplicar <wt> <propuesta>`. Sin OK, `AGENTS.md` se queda como está (el paso 4 ya le añadió `## Reglas del proyecto` si faltaba). Exit 1 de `kit-agents-md.sh`: corrige la propuesta (por ejemplo, le falta `## Reglas del proyecto`).
6. **GitHub.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-github-setup.sh" <wt>`: crea solo las etiquetas que faltan (las existentes conservan color y descripción), activa squash y borrado de rama, y crea el issue "📦 Changelog" salvo con `"changelog": false`.
   - Exit 2 (`gh no autenticado` u otro error de entorno): dile que ejecute `gh auth login` o arregle lo que diga el error, que el worktree `<wt>` se queda y que relanzar `kit-on` lo retoma. Para.
7. **Backlog previo.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" reparto <wt>` lista los issues abiertos que entrarían en el reparto de `kit-run` (`#N`, prioridad y título, en el orden en que se cogerían); `FIN: <n>` es cuántos. Si `n` es 0, sigue. Si no, enséñale la lista y pregúntale si entran todos o si alguno (o todos) pasa a `someday`, fuera del reparto. Con los que diga: `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" aparcar <wt> <N>...`. La línea `de otras cuentas (nunca entran)` son issues que `kit-run` nunca coge porque no los abrió su cuenta de `gh`; menciónalos sin preguntar.
8. **Avisos.** Mientras existe el worktree (tiene el marcador): si `bash -c 'source "$1/scripts/lib/config.sh"; kit_config "$2" .notify' _ "${CLAUDE_PLUGIN_ROOT}" <wt>` da `ntfy`, ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-notify.sh" <wt> "agents-kit" "Avisos activados en <repo>"` y guarda el tema para el resumen: sale de `cat ~/.agents-kit/ntfy-topic` (lo crea el primer aviso; si `KIT_NTFY_TOPIC` está definida, el tema es su valor). Si el aviso sale distinto de 0, apúntalo para el resumen y sigue.
9. **PR.** Saca el cuerpo de `git -C <wt> status --porcelain`: una lista con cada fichero creado o cambiado, más `AGENTS.md ordenado` si el paso 5 lo aplicó, si lleva changelog, el `setup` declarado y los issues que pasaron a `someday`. Luego `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-ship-pr.sh" enviar <raíz> kit-on "chore: activar agents-kit" "<cuerpo>"`.
   - Exit 1 (`nada que enviar`): explícalo y borra el worktree con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-ship-pr.sh" descartar <raíz> kit-on`.
   - Exit 2 sin `FIN:`: el PR no se creó y el trabajo sigue en el worktree que nombra el error; dile a Dru esa ruta, qué falló y que relanzar `kit-on` lo retoma.
   - Exit 2 con `FIN: PR abierto`: el PR se creó pero no se fusionó; dale la URL para que lo revise y lo fusione. El worktree ya se borró: el trabajo está en el PR.
10. **Resumen.** Dile a Dru qué se creó o cambió y el PR ya fusionado (línea `PR fusionado:` con la URL). Su clon principal no se tocó: el marcador llega cuando haga `git pull` en `<base>`, y desde entonces cada sesión en el repo carga las reglas del kit. Si hubo aviso por ntfy, dale el tema con la instrucción: instalar la app ntfy y suscribirse a ese tema; si el aviso falló, díselo sin deshacer nada.

Si Dru cancela a mitad: `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-ship-pr.sh" descartar <raíz> kit-on` borra el worktree y su rama. Lo ya hecho en GitHub (etiquetas, issue "📦 Changelog", `someday`) se queda; díselo.
