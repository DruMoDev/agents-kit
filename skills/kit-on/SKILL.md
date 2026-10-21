---
name: kit-on
description: Activa agents-kit en el repo actual (marcador, AGENTS.md, CHANGELOG, GitHub) y lo deja fusionado por PR. Úsala cuando Dru pida activar el kit en este repo o escriba kit-on.
---

# kit-on

Activa el kit en el repo donde estás. Los scripts hacen lo mecánico; tú decides y explicas.

Ejecuta los scripts como `"${CLAUDE_PLUGIN_ROOT}/scripts/<nombre>"`; si esa variable está vacía, la raíz del plugin está dos directorios por encima del directorio base de esta skill.

Lee siempre la salida completa de cada script y su código de salida; nunca la recortes con `head` ni `tail`. Ante cada código distinto de 0, dile a Dru en español qué pasó y qué tiene que hacer, y para.

## Pasos

1. **Raíz y marcador.** `git rev-parse --show-toplevel` da la raíz (si falla, no es un repo git: díselo y para). Mira `<raíz>/.agents-kit.json`:
   - No existe: activación nueva, sigue al paso 2.
   - Existe y está confirmado (`git ls-files --error-unmatch .agents-kit.json` sale 0): el kit ya está activo aquí. Díselo y termina.
   - Existe sin confirmar (ese comando falla): activación interrumpida, se retoma. Sáltate la comprobación de árbol limpio del paso 2, pero haz su comprobación de cambios no relacionados.
2. **Al día y árbol limpio.** Antes de nada, `git fetch -q origin` y comprueba que HEAD no va por detrás de la rama por defecto (`git rev-list --count HEAD..origin/<rama por defecto>` debe dar 0; la rama por defecto es solo el nombre, sin el prefijo `origin/`: sale de `git symbolic-ref --short refs/remotes/origin/HEAD` quitándole `origin/`, o de `gh repo view --json defaultBranchRef`; si no, el rango sería `origin/origin/...`). Si va por detrás, para: dile a Dru que haga `git pull` y relance `kit-on`. 
   - Activación nueva: si `git status --porcelain` no está vacío, para: dile a Dru que tiene cambios sin confirmar y que los confirme o guarde antes de `kit-on`. La activación crea cambios a propósito; los envía el paso 6.
   - Activación retomada: `kit-ship-pr.sh` envía todo el árbol, así que en `git status --porcelain` solo puede haber `.agents-kit.json`, `CHANGELOG.md`, `AGENTS.md`, `CLAUDE.md`, `.agents/` y `.claude/`. Si aparece cualquier otra ruta, para: dile a Dru qué rutas son cambios no relacionados con la activación y que las confirme o guarde antes de relanzar `kit-on`.
   - En ambos casos, si queda una rama `kit-on` (local en `git branch --list kit-on` o en origin en `git ls-remote --heads origin kit-on`) o un PR abierto (`gh pr list --head kit-on`), para y díselo a Dru: si el PR sigue abierto, que lo fusione o lo cierre; si no, que borre la rama vieja (`git branch -D kit-on`, `git push origin --delete kit-on`) y relance `kit-on`.
3. **Activar.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-activate.sh" <raíz>` (idempotente, también al retomar). Fíjate en sus líneas `creado:` y `cambiado:` y transmite cualquier aviso de stderr. Exit 1 es un error de uso tuyo: corrígelo. Exit 2: error de entorno, explícalo y para.
4. **Ordenar un `AGENTS.md` que ya existía.** Decide así si toca:
   - Activación nueva: toca si la salida del paso 3 no tiene `creado: AGENTS.md`.
   - Activación retomada: si `AGENTS.md` no está confirmado en git, lo creó el kit y no toca. Si está confirmado y `git status --porcelain -- AGENTS.md` muestra cambios, ya se ordenó: revisa esos cambios con los criterios de abajo en vez de rehacerlo. Si está confirmado y sin cambios, toca.

   Para ordenarlo, reescríbelo con las secciones de `templates/AGENTS.md` del plugin: Qué es, Stack, Comandos, Skills del proyecto, Mapa del código.
   - No pierdas información del proyecto: todo dato útil va a su sección.
   - Quita la cronología y el estado (avances, fechas, "hecho", pendientes).
   - Quita cualquier copia de reglas genéricas de trabajo: el kit las inyecta por su cuenta y `AGENTS.md` nunca debe repetirlas.
   - Rellena lo que se deduzca del repo: comandos de `package.json`, `Makefile`, `pyproject.toml`; versiones del stack; directorios de primer nivel; skills de `.agents/skills`.
   - Borra las secciones que no apliquen y los comentarios de la plantilla que ya estén resueltos.
5. **GitHub.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-github-setup.sh" <raíz>`.
   - Exit 1 (`sin remoto de GitHub`): díselo; los cambios quedan en local sin confirmar, para confirmarlos a mano. No sigas con el PR.
   - Exit 2 (`gh no autenticado` u otro error de entorno): dile que ejecute `gh auth login` o arregle lo que diga el error, y para. Cuando lo arregle, puede relanzar `kit-on`: el paso 1 detecta la activación interrumpida y la retoma.
6. **PR.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-ship-pr.sh" <raíz> kit-on "chore: activar agents-kit" "<cuerpo>"`. Justo antes, saca el cuerpo de `git status --porcelain`: una lista con cada fichero creado o cambiado, más `AGENTS.md ordenado` si el paso 4 tocó.
   - Exit 1: rechazo (nada que enviar, la rama `kit-on` ya existe, commits sin publicar en la rama de partida). Explica el motivo exacto y qué hacer (por ejemplo, borrar la rama vieja o publicar esos commits).
   - Exit 2: error de entorno. Si menciona un stash, dale a Dru el SHA: sus cambios están a salvo ahí; repite lo que diga el script sobre el árbol: si dice "el árbol quedó limpio", díselo; si dice "el árbol NO quedó limpio", dile qué rutas quedan y que las revise antes de seguir; que haga `git pull` en la rama por defecto y relance `kit-on`. Si el PR quedó abierto, dale la URL.
7. **Resumen.** Dile a Dru qué se creó o cambió, el PR ya fusionado (línea `PR fusionado:` con la URL; el cambio ya está en la rama por defecto, no hay nada pendiente de fusionar) y que la próxima sesión en este repo ya carga las reglas del kit. Si `.notify` vale `ntfy` (`bash -c 'source "$1/scripts/lib/config.sh"; kit_config "$2" .notify' _ "${CLAUDE_PLUGIN_ROOT}" <raíz>`), ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-notify.sh" <raíz> "agents-kit" "Avisos activados en <repo>"` y dale a Dru el tema que sale de `cat ~/.agents-kit/ntfy-topic` (lo crea el primer aviso; si `KIT_NTFY_TOPIC` está definida, el tema es su valor), con la instrucción: instalar la app ntfy y suscribirse a ese tema. Si el aviso sale distinto de 0, díselo sin deshacer nada.
