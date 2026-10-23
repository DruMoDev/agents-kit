---
name: kit-off
description: Desactiva agents-kit en el repo actual: borra el marcador y lo fusiona por PR, sin tocar los ficheros del proyecto. Úsala cuando Dru pida desactivar el kit aquí o escriba kit-off.
---

# kit-off

Desactiva el kit en el repo donde estás. Los scripts hacen lo mecánico; tú decides y explicas.

Ejecuta los scripts como `"${CLAUDE_PLUGIN_ROOT}/scripts/<nombre>"`; si esa variable está vacía, la raíz del plugin está dos directorios por encima del directorio base de esta skill.

Lee siempre la salida completa de cada script y su código de salida; nunca la recortes con `head` ni `tail`. Ante cada código distinto de 0, dile a Dru en español qué pasó y qué tiene que hacer, y para.

**El árbol de Dru no se toca.** La desactivación pasa en un worktree temporal de `origin/<rama por defecto>` que crea `kit-ship-pr.sh`; da igual que el clon principal tenga cambios, otra rama o commits sin publicar. Nunca hagas `git checkout`, `git stash` ni `git pull` en la raíz del repo.

## Pasos

1. **Raíz.** `git rev-parse --show-toplevel` da la `<raíz>` (si falla, no es un repo git: díselo y para).
2. **Worktree.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-ship-pr.sh" abrir <raíz> kit-off con-marcador`. La línea `FIN: <ruta>` es el `<wt>` y `base:` la rama por defecto.
   - Exit 1: `el kit no está activo`: díselo y termina. `ya hay un PR abierto`: dale la URL; que lo fusione o lo cierre y relance `kit-off`. Rama `kit-off` vieja (local u origin): repite el comando que da el script para borrarla. `sin remoto de GitHub`: el kit necesita GitHub; para.
   - Exit 2: error de entorno (`gh no autenticado`: que ejecute `gh auth login`); explícalo y para.
3. **Desactivar.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-deactivate.sh" <wt>`. Exit 1 (`no está activado`): si la salida del paso 2 decía `ya existía`, es una desactivación interrumpida que ya borró el marcador: sigue al paso 4; si no, díselo y termina con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-ship-pr.sh" descartar <raíz> kit-off`. Exit 2: error de entorno, explícalo y para.
4. **PR.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-ship-pr.sh" enviar <raíz> kit-off "chore: desactivar agents-kit" "Borra .agents-kit.json. AGENTS.md, CHANGELOG.md y las skills del proyecto se quedan."`
   - Exit 1 (`nada que enviar`): explícalo y borra el worktree con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-ship-pr.sh" descartar <raíz> kit-off`.
   - Exit 2 sin `FIN:`: el PR no se creó y el cambio sigue en el worktree que nombra el error; dile a Dru esa ruta, qué falló y que relanzar `kit-off` lo retoma.
   - Exit 2 con `FIN: PR abierto`: el PR se creó pero no se fusionó. Si stderr dice que el CI sigue en marcha, relanza el comando `kit-ship-pr.sh fusionar <raíz> kit-off` que da (espera al CI y fusiona); si no, dale la URL y el motivo. El worktree ya se borró.
5. **Resumen.** Dile a Dru el PR ya fusionado (línea `PR fusionado:` con la URL; el cambio ya está en la rama por defecto). Su clon principal no se tocó: el marcador desaparece cuando haga `git pull` en `<base>`, y desde entonces las sesiones en este repo ya no cargan las reglas del kit. `AGENTS.md`, `CHANGELOG.md` y las skills de `.agents/skills` se quedan porque son del proyecto.
