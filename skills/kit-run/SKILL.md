---
name: kit-run
description: Lleva los issues `listo` hasta main uno a uno: worktree, tests, PR, CI, rondas de revisión con varios modelos y squash merge. Úsala cuando Dru escriba kit-run.
---

# kit-run

Bucle sobre los issues `listo` del repo hasta que no quede ninguno. Los scripts hacen lo mecánico y guardan el estado en GitHub; tú encuadras, implementas, decides sobre cada hallazgo y explicas.

Ejecuta los scripts como `"${CLAUDE_PLUGIN_ROOT}/scripts/<nombre>"`; si esa variable está vacía, la raíz del plugin está dos directorios por encima del directorio base de esta skill. Abajo, `$PLUGIN` es esa raíz.

## Reglas

- Nunca te salgas del scope del issue. Lo que encuentres fuera se abre con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" crear <raíz> "<título>" <fichero> propuesta` (plantilla de `skills/kit-plan/references/issue.md`).
- Nunca afirmes nada que no hayas ejecutado.
- Lee la salida completa de cada script hasta su línea `FIN:` y su código de salida; nunca la recortes con `head` ni `tail`. Exit 1 es un rechazo con motivo en stderr; exit 2, un error de entorno.
- Una duda de producto nunca la resuelves tú: ve al paso 7.
- Un exit 2 que no sepas resolver con lo de abajo: intenta soltar el issue con el motivo, para el bucle y explícaselo a Dru.
- Ficheros temporales (cuerpos, preguntas, rondas, salidas) siempre fuera del worktree, con `mktemp`.
- Cada línea `AVISO-CLAUDE: <texto>` en la salida de un script es un aviso para Dru: llama a la herramienta de notificación push de la sesión (en Claude Code, `PushNotification`) con ese texto; si la herramienta no existe, ignórala. Un `aviso: no se pudo avisar (...)` en stderr no para nada: cuéntalo en el resumen.
- Una línea `tema ntfy nuevo: <tema>` en la salida de cualquier script (aunque el aviso haya fallado) solo sale una vez: ponla siempre en el resumen final del chat con el tema y la instrucción "instala la app ntfy y suscríbete a ese tema", porque si no nadie recibe los avisos.

## Arranque

`git rev-parse --show-toplevel` da la `<raíz>`. Si no existe `<raíz>/.agents-kit.json`, di `kit no activado: ejecuta kit-on` y para. Saca el `<slug>` del repo (`owner/repo`) del remoto `origin`, como los scripts: `bash -c 'source "$1/scripts/lib/github-slug.sh"; cd "$2" && kit_origin_slug' _ "$PLUGIN" <raíz>`; si sale vacío, el remoto no es de GitHub: díselo y para. Genera el `<id>` de agente una sola vez por ejecución (`printf 'run-%s-%s\n' "$(date +%Y%m%d%H%M%S)" "$RANDOM"`) y reutiliza ese valor literal en todo el bucle. La configuración se lee con `bash -c 'source "$1/scripts/lib/config.sh"; kit_config "$2" "$3"' _ "$PLUGIN" <raíz> '<filtro>'` (`.maxReviewRounds`, `.autoMerge`, `.implementer`); exit 2 = `.agents-kit.json` roto: díselo a Dru y para.

## Por cada issue

1. **Coger.** `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" siguiente <raíz>`: exit 0 da `<N>` en `FIN: <N>`; exit 1 (`no hay issues listos`) termina el bucle y vas al resumen. Después `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" reclamar <raíz> <N> <id>`:
   - Exit 1: otro agente lo cogió antes. Vuelve a `siguiente`.
   - Exit 2 con `no se pudo comentar en`, o con `reclamación deshecha` sin `no se pudo deshacer`: no queda reclamo tuyo. Explícalo y para.
   - Cualquier otro exit 2, incluido `no se pudo deshacer` (el reclamo se publicó y puede seguir ahí): dile a Dru que puede quedar colgado y dale el comando exacto para soltarlo, `"$PLUGIN/scripts/kit-issue.sh" soltar <raíz> <N> <id> "reclamo sin confirmar"` con los valores reales. Para.
2. **Encuadrar.**
   - Lee el issue entero con sus comentarios (`gh issue view <N> --repo <slug> --comments`), incluidas las respuestas de Dru a un `<!-- kit-decision -->`; lee `AGENTS.md` y el código afectado.
   - Verifica que lo que nombra el issue existe y sigue vigente.
   - Si está obsoleto o ya está hecho: `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" soltar <raíz> <N> <id> "<motivo>"`, luego `gh issue close <N> --repo <slug> --comment "<evidencia>"`, y siguiente issue.
   - Si le falta producto: paso 7.
   - Todo comportamiento visible para el usuario que el issue no define es una decisión de producto: usa el paso 7 (`kit-issue.sh decision`) salvo que solo haya una lectura razonable. En todo caso, lista esas interpretaciones en el cuerpo de la PR bajo `## Decisiones de comportamiento` y en el resumen final del chat.
   - Escribe en el chat 4 líneas: qué pide; sigue vigente (con la evidencia); qué vas a hacer; qué NO tocas.
3. **Implementar.**
   - Rama: si ya existe una `issue-<N>-*` (`git -C <raíz> branch --list 'issue-<N>-*'` o `git -C <raíz> ls-remote --heads origin 'issue-<N>-*'`), es un issue retomado: reutiliza su `<slug-rama>` tal cual. Si no, sácalo del título (minúsculas, `a-z0-9` y guiones).
   - `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-worktree.sh" abrir <raíz> <N> <slug-rama>`. La ruta es la línea `FIN: <wt>`; trabaja solo con esa ruta absoluta. Si la rama solo existe en origin, el worktree parte de `origin/<rama>`.
   - Tests primero (unitarios, e2e y casos límite), luego el código. Tests, lint y build de `AGENTS.md` en verde en local.
   - `.implementer` dice el modelo que implementa en cada herramienta. Si la sesión no corre con ese modelo, delega la implementación en un subagente con ese modelo cuando la herramienta lo permita, pasándole la ruta del worktree, el issue y tus 4 líneas.
   - Automejora en la misma PR: si aprendiste algo, actualiza `AGENTS.md` y las skills del proyecto.
4. **PR.** Commit en el worktree y `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" abrir <wt> <N> "<título>" <fichero-cuerpo>` (empuja; añade `Cierra #<N>` si falta; si la rama ya tiene una PR abierta, como en un issue retomado, la reutiliza sin crear otra). La primera línea es `<pr>`. Si esa PR está en borrador (`gh pr view <pr> --repo <slug> --json isDraft`), quítaselo con `gh pr ready <pr> --repo <slug>`. Después añade la entrada de `CHANGELOG.md` con el formato del comentario de cabecera del propio fichero (ya con el número y la URL de la PR) y comprueba el formato con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-changelog.sh" validar <wt>` hasta que salga 0 (exit 1 señala `CHANGELOG.md:<línea>: <motivo>`: corrígelo). Si el cambio es visual, durante la comprobación e2e del estado final haz capturas con el navegador automatizado, solo las que aportan, guárdalas en `<wt>/docs/changelog/<pr>-<nombre>.png` comprimidas por debajo de 500 KB y enlázalas en la versión extendida de la entrada; sin cambio visual, sin capturas. Commit y `git -C <wt> push -q`. Entonces la puerta de CI:
   - `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" esperar-ci <wt> <pr>`. `FIN: verde`: sigue.
   - `FIN: sin-ci`: el repo no tiene workflows, o ninguno arrancó un check para ese SHA en `KIT_CI_GRACE` segundos (300 por defecto; por ejemplo, workflows sin disparador `pull_request`). Ejecuta en el worktree los comandos de test, lint y build de `AGENTS.md` sobre el último commit, guarda toda su salida en un fichero y, si todo pasa, `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" gate-local <wt> <pr> <fichero>`. Repite el gate tras cada push: vale solo para ese SHA, y solo mientras ese SHA no tenga ningún check (si aparece alguno, manda el CI).
   - Exit 1 `el CI terminó en ...`: lee el fallo (`gh run view --repo <slug> --log-failed`), corrígelo, commit, push y vuelve a esperar.
   - Exit 1 `no concluyó en ...`: hay checks que no terminan. Míralos con `gh pr checks <pr> --repo <slug>`; si no avanzan, bloquea el issue (ver abajo) explicando qué check se quedó colgado.
   - Exit 2 `la PR apunta a ...`: falta un push; empuja y repite.
5. **Revisión.** Rondas `r = k + 1, k + 2, ...`, con `k` de la línea `FIN: <k> rondas` de `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" historial <wt> <pr>` (0 en una PR nueva; las rondas previas cuentan para `.maxReviewRounds`). Sigue `references/ronda.md` (lanzar revisores, decidir, fichero de ronda, cuándo parar). Antes de cada ronda, todo confirmado y empujado: los revisores revisan el head de la PR. Lanza los revisores en paralelo con un único comando; si el límite de tiempo de tu herramienta es menor que `KIT_REVIEW_TIMEOUT` (1800 s por revisor), lánzalo en segundo plano (por ejemplo `run_in_background` en Claude Code). Usa sintaxis de bash: ejecútalo tal cual, envuelto en `bash <<'EOS' ... EOS` (tu shell puede ser zsh), sustituyendo dentro los `<...>` por sus valores reales:
   ```bash
   bash <<'EOS'
   PLUGIN="<raíz del plugin>"; d="$(mktemp -d)"
   list="$(bash -c 'source "$1/scripts/lib/config.sh"; kit_reviewers "$2"' _ "$PLUGIN" "<raíz>" </dev/null)" || exit 2
   i=0; pids=()
   while IFS=$'\t' read -r tool model focus; do
     [ -n "$tool" ] && [ -n "$model" ] && [ -n "$focus" ] || continue
     i=$((i + 1)); printf '%s\t%s\t%s\t%s\n' "$i" "$tool" "$model" "$focus" >> "$d/revisores.tsv"
     "$PLUGIN/scripts/kit-review.sh" "<wt>" <pr> "$tool" "$model" "$focus" <r> <N> > "$d/rev-$i.out" 2>&1 &
     pids+=("$!")
   done <<< "$list"
   for j in "${!pids[@]}"; do wait "${pids[$j]}"; echo "revisor $((j + 1)): exit $?"; done
   echo "salidas en $d"
   EOS
   ```
   Si `kit_reviewers` no da ninguna línea completa (`i` queda en 0), no lances `kit-review.sh`: revisa tú el cambio con todos los focos y dilo en el fichero de ronda. Lee entero cada `rev-<i>.out`. Escribe el fichero de ronda y publícalo con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" ronda <wt> <pr> <r> <fichero>`; exit 1 señala la línea mal formada: corrígela y repite.
   - Si aplicaste algo: commit, push, puerta de CI del paso 4 y ronda nueva obligatoria.
   - Si la ronda no cambió código (0 hallazgos, o ninguno aplicado porque todos se rechazaron con motivo): no hay ronda nueva; pasa a fusionar.
   - Si `r` llega a `.maxReviewRounds` (o un issue retomado ya trae `k` rondas en el límite) y aún queda una ronda nueva por hacer: confirma y empuja lo que haya, `gh pr ready --undo <pr> --repo <slug>`, bloquea el issue con un resumen de lo pendiente y siguiente issue.
6. **Fusionar.** Con `.autoMerge` verdadero: `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-pr.sh" fusionar <wt> <pr> <N>`.
   - Exit 0: guarda la línea `PR fusionado: <url>` para el resumen y ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-worktree.sh" limpiar <raíz> <N>` (`FIN: limpio`).
   - Exit 1 con `rebasada sobre ...`: el script ya rebasó y empujó. Vuelve a la puerta de CI del paso 4 y reintenta.
   - Otro exit 1: lee cada motivo. Corrige lo que puedas (conflicto, CI, ronda pendiente) y reintenta; si no, bloquea. `la última ronda aplicó cambios: falta una ronda nueva` significa volver al paso 5 con la ronda siguiente.
   - Con `.autoMerge` falso: deja la PR lista sin fusionar ni limpiar; el issue sigue `en-curso` y se cierra solo al fusionarla Dru. Anótala para el resumen.
7. **Duda de producto, en cualquier paso.** Si ya hay PR, `gh pr ready --undo <pr> --repo <slug>`. Escribe la pregunta (contexto, opciones y lo que propones) en un fichero y ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" decision <raíz> <N> <id> <fichero>` (`FIN: necesita-decision #<N>`). El worktree se queda. Siguiente issue.

**Bloquear:** escribe el motivo y lo pendiente en un fichero y ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" bloquear <raíz> <N> <id> <fichero>` (`FIN: bloqueado #<N>`). Si había PR, antes `gh pr ready --undo <pr> --repo <slug>`. El worktree se queda.

## Resumen final

Cuando `siguiente` da exit 1, antes del texto del chat: si en esta ejecución fusionaste alguna PR o hay issues que pasaron a `necesita-decision` o `bloqueado` en esta ejecución (los que ya esperaban antes de empezar no cuentan), escribe el resumen en un fichero temporal (cada PR fusionada con su línea corta del changelog y su URL, y cada uno de esos issues con su URL y qué tiene que hacer Dru) y publícalo con `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-changelog.sh" resumen <raíz> <id> <fichero>`; la URL del comentario es la línea `FIN: <url>` (si ya estaba publicado, no se duplica). Después `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-notify.sh" <raíz> "<repo>: kit-run terminado" "<n> fusionadas, <m> esperan" <url del comentario>`; si `resumen` falla, avisa igual sin URL (sin el último argumento). Si no pasó nada de eso, ni resumen ni aviso. Si alguno de los dos falla (por ejemplo, exit 2 `no hay issue "📦 Changelog": ejecuta kit-on`), no pares: cuéntalo en el chat.

Después escribe en el chat:

- Cada PR fusionada (su URL) y cada issue cerrado por obsoleto.
- Si algún script imprimió `tema ntfy nuevo: <tema>`: el tema y "instala la app ntfy y suscríbete a ese tema".
- Cada issue que espera a Dru, con su URL y qué tiene que hacer:
  - `necesita-decision` o `bloqueado`: responde en el issue y quita `necesita-decision` (o `bloqueado`); `listo` sigue puesto, no hay que volver a ponerlo. El siguiente `kit-run` lo retoma.
  - PR sin fusionar por `autoMerge` falso: revisarla y fusionarla; después, quitar a mano `listo` y `en-curso` del issue cerrado.
- Posibles reclamos colgados: los issues abiertos con `listo` y `en-curso` que no reclamaste en esta ejecución (`gh issue list --repo <slug> --state open --label listo --label en-curso --json number,url`). Para cada uno, saca el `<id>` del último `<!-- kit-reclamado: <id> -->` de sus comentarios (`gh issue view <N> --repo <slug> --comments`) y dale a Dru el comando exacto con los valores reales: `"$PLUGIN/scripts/kit-issue.sh" soltar <raíz> <N> <id> "reclamo colgado"`. Avisa de que solo debe soltarlo si ningún agente lo está trabajando.
