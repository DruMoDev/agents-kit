---
name: kit-off
description: Desactiva agents-kit en el repo actual: borra el marcador y lo fusiona por PR, sin tocar los ficheros del proyecto. Úsala cuando Dru pida desactivar el kit aquí o escriba kit-off.
---

# kit-off

Desactiva el kit en el repo donde estás. Los scripts hacen lo mecánico; tú decides y explicas.

Ejecuta los scripts como `"${CLAUDE_PLUGIN_ROOT}/scripts/<nombre>"`; si esa variable está vacía, la raíz del plugin está dos directorios por encima del directorio base de esta skill.

Lee siempre la salida completa de cada script y su código de salida; nunca la recortes con `head` ni `tail`. Ante cada código distinto de 0, dile a Dru en español qué pasó y qué tiene que hacer, y para.

## Pasos

1. **Raíz y marcador.** `git rev-parse --show-toplevel` da la raíz (si falla, no es un repo git: díselo y para). Si no existe `<raíz>/.agents-kit.json`:
   - Si no está confirmado en git (`git ls-files --error-unmatch .agents-kit.json` falla), el kit no está activo aquí. Díselo y termina.
   - Si está confirmado y `git status --porcelain` muestra solo su borrado, es una desactivación interrumpida: haz solo la comprobación de restos del paso 2 y sigue desde el paso 4.
   - Si está confirmado y hay más cambios, para: dile a Dru que hay árbol sucio y borrado del marcador pendiente, qué otras rutas cambiaron, y que las confirme o guarde antes de relanzar `kit-off`.
2. **Al día, árbol limpio y restos.** Antes de nada, `git fetch -q origin` y comprueba que HEAD no va por detrás de la rama por defecto (`git rev-list --count HEAD..origin/<rama por defecto>` debe dar 0; la rama por defecto sale de `git symbolic-ref --short refs/remotes/origin/HEAD` o de `gh repo view --json defaultBranchRef`). Si va por detrás, para: dile a Dru que haga `git pull` y relance `kit-off`. Si `git status --porcelain` no está vacío (fuera del caso retomado), para: dile a Dru que confirme o guarde sus cambios antes de `kit-off`. Si queda una rama `kit-off` (local en `git branch --list kit-off` o en origin en `git ls-remote --heads origin kit-off`) o un PR abierto (`gh pr list --head kit-off`), para y díselo: si el PR sigue abierto, que lo fusione o lo cierre; si no, que borre la rama vieja (`git branch -D kit-off`, `git push origin --delete kit-off`) y relance `kit-off`.
3. **Desactivar.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-deactivate.sh" <raíz>`. Exit 1 (`no está activado`): díselo y termina. Exit 2: error de entorno, explícalo y para.
4. **PR.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-ship-pr.sh" <raíz> kit-off "chore: desactivar agents-kit" "Borra .agents-kit.json. AGENTS.md, CHANGELOG.md y las skills del proyecto se quedan."`
   - Exit 1: rechazo (nada que enviar, la rama `kit-off` ya existe, commits sin publicar en la rama de partida, sin remoto de GitHub). Explica el motivo exacto y qué hacer.
   - Exit 2: error de entorno (por ejemplo `gh no autenticado`: que ejecute `gh auth login`). Si menciona un stash, dale a Dru el SHA: sus cambios están a salvo ahí y el árbol quedó limpio; que haga `git pull` en la rama por defecto y relance `kit-off`. Si el PR quedó abierto, dale la URL.
5. **Resumen.** Dile a Dru el PR ya fusionado (línea `PR fusionado:` con la URL; el cambio ya está en la rama por defecto), que la próxima sesión en este repo ya no carga las reglas del kit, y que `AGENTS.md`, `CHANGELOG.md` y las skills de `.agents/skills` se quedan porque son del proyecto.
