---
name: kit-on
description: Activa agents-kit en el repo actual (marcador, AGENTS.md, CHANGELOG, GitHub) y lo deja fusionado por PR. Úsala cuando Dru pida activar el kit en este repo o escriba kit-on.
---

# kit-on

Activa el kit en el repo donde estás. Los scripts hacen lo mecánico; tú decides y explicas.

Ejecuta los scripts como `"${CLAUDE_PLUGIN_ROOT}/scripts/<nombre>"`; si esa variable está vacía, la raíz del plugin está dos directorios por encima del directorio base de esta skill.

Lee siempre la salida completa de cada script y su código de salida; nunca la recortes con `head` ni `tail`. Ante cada código distinto de 0, dile a Dru en español qué pasó y qué tiene que hacer, y para.

## Pasos

1. **Raíz y marcador.** `git rev-parse --show-toplevel` da la raíz (si falla, no es un repo git: díselo y para). Si existe `<raíz>/.agents-kit.json`, dile que el kit ya está activo aquí y termina.
2. **Árbol limpio.** Antes de activar nada, si `git status --porcelain` no está vacío, para: dile a Dru que tiene cambios sin confirmar y que los confirme o guarde antes de `kit-on`. La activación crea cambios a propósito; los envía el paso 6.
3. **Activar.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-activate.sh" <raíz>`. Guarda las líneas `creado:` y `cambiado:` para el cuerpo del PR y transmite cualquier aviso de stderr. Exit 1 es un error de uso tuyo: corrígelo. Exit 2: error de entorno, explícalo y para.
4. **Ordenar un `AGENTS.md` existente.** Solo si `AGENTS.md` no aparece como `creado:` (ya existía). Reescríbelo con las secciones de `templates/AGENTS.md` del plugin: Qué es, Stack, Comandos, Skills del proyecto, Mapa del código.
   - No pierdas información del proyecto: todo dato útil va a su sección.
   - Quita la cronología y el estado (avances, fechas, "hecho", pendientes).
   - Quita cualquier copia de reglas genéricas de trabajo: el kit las inyecta por su cuenta y `AGENTS.md` nunca debe repetirlas.
   - Rellena lo que se deduzca del repo: comandos de `package.json`, `Makefile`, `pyproject.toml`; versiones del stack; directorios de primer nivel; skills de `.agents/skills`.
   - Borra las secciones que no apliquen y los comentarios de la plantilla que ya estén resueltos.
5. **GitHub.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-github-setup.sh" <raíz>`.
   - Exit 1 (`sin remoto de GitHub`): díselo; los cambios quedan en local sin confirmar para que los confirme él. No sigas con el PR.
   - Exit 2 (`gh no autenticado` u otro error de entorno): dile que ejecute `gh auth login` o arregle lo que diga el error, y para. Cuando lo arregle, retoma desde este paso: relanzar desde el paso 1 se pararía porque el marcador ya existe.
6. **PR.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-ship-pr.sh" <raíz> kit-on "chore: activar agents-kit" "<cuerpo>"`. El cuerpo es una lista con cada fichero `creado:` y `cambiado:` de la salida del paso 3, más `AGENTS.md ordenado` si hiciste el paso 4.
   - Exit 1: rechazo (nada que enviar, la rama `kit-on` ya existe, commits sin publicar en la rama de partida). Explica el motivo exacto y qué hacer (por ejemplo, borrar la rama vieja o publicar esos commits).
   - Exit 2: error de entorno. Si menciona un stash, dale a Dru el SHA y dile que sus cambios están ahí para aplicarlos a mano. Si el PR quedó abierto, dale la URL.
7. **Resumen.** Dile a Dru qué se creó o cambió, la URL del PR (línea `PR:`) y que a partir de la próxima sesión en este repo se cargan las reglas del kit.
