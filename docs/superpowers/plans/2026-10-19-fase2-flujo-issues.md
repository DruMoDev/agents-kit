# Fase 2: flujo de issues y revisión multiagente. Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `kit-plan`, `kit-run` y `kit-scout` funcionando en repos activados. Llevan un issue de GitHub hasta `main`: worktree propio, PR, CI del SHA exacto, rondas de revisión con Claude (Opus, Sonnet) y GPT (vía OpenCode) sin repetir hallazgos, squash merge y limpieza.

**Architecture:**
- Los scripts bash hacen lo mecánico y las skills ponen el criterio, como en el prior art de `tiktok-editor`.
- Los revisores se lanzan por CLI desde un script (`claude -p`, `opencode run`). Así funcionan igual desde Claude Code, Codex u OpenCode, cada uno en un worktree desechable con `gh` y `git push` bloqueados.
- El historial de hallazgos vive en comentarios marcados de la PR. GitHub es la única fuente de verdad, y por eso se puede retomar tras una interrupción.

**Tech Stack:** bash, git, gh, jq, perl (solo para `alarm` como timeout, ya que macOS no trae `timeout`), node solo en tests de OpenCode. Sin dependencias nuevas.

**Spec:** `docs/superpowers/specs/2026-10-18-agents-kit-plugin-design.md`. Secciones "Flujo de issues", "Revisión multiagente" y "Configuración". El prior art está resumido en `/private/tmp/claude-501/-Users-drumorera-Documents-programacion-agents-kit/be731fe6-a076-4cab-ae8f-786559ae921f/scratchpad/tiktok-prior-art.md`, que es opcional y se lee solo si un detalle no está aquí.

## Global Constraints

- Convenciones de scripts de `AGENTS.md`:
  - Nombres `kit-*`.
  - Salida 0 bien, 1 rechazo o respuesta negativa válida, 2 error de entorno o "no pude decidir".
  - La última línea de un éxito es `FIN: ...`.
  - Mensajes en español neutro, sin rayas largas (—).
  - Nunca `head` ni `tail` sobre la salida propia.
- Cada llamada a `gh` lleva `--repo "$slug"`, con `slug` obtenido de `scripts/lib/github-slug.sh` (`kit_origin_slug`).
- Toda skill y script de flujo se niega sin `.agents-kit.json` en la raíz: exit 1 con `kit no activado: ejecuta kit-on`.
- Nunca leer un valor ilegible como "no": si `gh` falla, exit 2.
- Rutas absolutas siempre. Los scripts reciben la raíz o el worktree como primer argumento.
- Etiquetas: `listo`, `propuesta`, `en-curso`, `necesita-decision`, `bloqueado`.
- Marcadores HTML, verbatim:
  - `<!-- kit-reclamado: <id> -->`
  - `<!-- kit-soltado: <id> -->`
  - `<!-- kit-decision -->`
  - `<!-- kit-bloqueado -->`
  - `<!-- kit-revision: <herramienta>/<modelo> ronda <n> -->`
  - `<!-- kit-ronda: <n> -->`
  - `<!-- kit-gate-local: <sha40> -->`
- Rama de issue: `issue-<N>-<slug>`, con slug `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`. Worktrees en `${KIT_WORKTREES:-$HOME/.agents-kit/worktrees}/<nombre-repo>/issue-<N>-<slug>`.
- Los tests son bash con stubs y entran en `tests/run.sh` (todo `tests/test_*.sh`).

## Review Focus

1. **`gh` falla a mitad de una reclamación** (red, 5xx). Se espera exit 2 y que no quede `en-curso` puesto sin marcador propio. El test va en Task 2.
2. **Hay CI, pero el último check del SHA aún no existe justo tras el push** (lag de la API). Se espera "seguir esperando", nunca "verde" ni "sin CI". El test va en Task 4.
3. **El revisor no entrega** (timeout, salida sin `HALLAZGOS:`, CLI ausente). Se espera exit 2 con motivo, sin publicar un comentario vacío. El test va en Task 5.
4. **Un hallazgo de una ronda queda sin decisión escrita.** `fusionar` debe negarse si hay un comentario `kit-revision` posterior al último `kit-ronda`. El test va en Task 4.
5. **`limpiar` con cambios sin confirmar en el worktree**, o con la PR sin fusionar. Se espera que no borre nada y exit 1. El test va en Task 3.

---

### Task 1: configuración de revisores y helper de config

**Files:**
- Modify: `templates/agents-kit.json`
- Create: `scripts/lib/config.sh`
- Test: `tests/test_config.sh`

**Interfaces:**
- Produces:
  - `kit_require_marker <root>`: exit 1 con `kit no activado: ejecuta kit-on` si falta el marcador.
  - `kit_config <root> <jq-filter>`: imprime el resultado de jq sobre `.agents-kit.json` fusionado sobre `templates/agents-kit.json`. Si una clave falta en el marcador, vale la de la plantilla. Si el JSON es inválido, exit 2 con `error: .agents-kit.json no es JSON válido`.
  - `kit_reviewers <root>`: una línea TSV por revisor, `herramienta<TAB>modelo<TAB>foco`, en el orden claude, opencode, codex.

- [ ] Step 1: añadir a `reviewers` en `templates/agents-kit.json` la clave `"opencode": [{ "model": "openai/gpt-6.1-sol", "focus": "fallos de uso real, seguridad y lo que otros revisores darían por bueno" }]`. Se conservan `claude` (opus, sonnet) y `codex: []`.
- [ ] Step 2: escribir `tests/test_config.sh`:
  - Sin marcador: `kit_require_marker` sale 1 con el mensaje exacto.
  - Un marcador `{}` devuelve los 3 revisores por defecto en orden (`claude opus`, `claude sonnet`, `opencode openai/gpt-6.1-sol`).
  - Un marcador con `{"reviewers":{"claude":[{"model":"sonnet","focus":"x"}]}}` devuelve solo esa línea. La clave `reviewers` del marcador sustituye entera a la de la plantilla, sin fusión profunda.
  - `kit_config <root> .maxReviewRounds` da `10` con un marcador `{}`.
  - Un JSON inválido sale 2.
- [ ] Step 3: ejecutar el test y verlo fallar.
- [ ] Step 4: implementar `scripts/lib/config.sh` como fichero que se carga con `source`, sin efectos al cargarlo. Usar `jq -s '.[0] * .[1]'` (plantilla primero, marcador después). `reviewers` se fusiona sustituyendo, así que el marcador `{}` deja la plantilla.
- [ ] Step 5: ejecutar `tests/run.sh` en verde y hacer commit.

### Task 2: `scripts/kit-issue.sh` y stub de gh con estado

**Files:**
- Create: `scripts/kit-issue.sh`
- Create: `tests/stubs/flow/gh`, un stub con estado, aparte del de la fase 1
- Modify: `tests/lib.sh` para añadir `use_flow_gh`
- Test: `tests/test_issue.sh`

**Interfaces:**
- Consumes: `kit_require_marker`, `kit_origin_slug`.
- Produces (todos con `<root>` primero; exit 2 si `gh` falla):
  - `kit-issue.sh siguiente <root>`: imprime el número del issue abierto más antiguo con `listo` y sin `en-curso`, `necesita-decision` ni `bloqueado`. Exit 1 con `no hay issues listos` si no hay.
  - `kit-issue.sh reclamar <root> <N> <id>`:
    - Comenta `<!-- kit-reclamado: <id> -->` con el texto `Cogido por el agente \`<id>\`.` y añade `en-curso`.
    - Relee los comentarios. Gana el primer `kit-reclamado` posterior al último `kit-soltado`.
    - Relee las etiquetas y verifica que `en-curso` está.
    - Si gana: `FIN: reclamado #<N>`, exit 0.
    - Si pierde: comenta `El agente \`<id>\` suelta este issue: lo había cogido antes \`<ganador>\`.` y sale con exit 1.
    - Si falla tras publicar el marcador: compensa (publica `kit-soltado` y quita `en-curso`) solo si el ganador es él, y sale con exit 2.
  - `kit-issue.sh soltar <root> <N> <id> [motivo]`:
    - Si el reclamo es de otro: exit 1 con `la reclamación de #<N> es de '<x>', no tuya`.
    - Si no, comenta `<!-- kit-soltado: <id> -->` (más `Motivo: ...` si se da) antes de quitar `en-curso`.
    - Termina con `FIN: soltado #<N>`.
  - `kit-issue.sh decision <root> <N> <id> <fichero-pregunta>`:
    - Comenta `<!-- kit-decision -->` seguido de la pregunta, añade `necesita-decision` y asigna `@me`.
    - Después ejecuta `soltar` con motivo `necesita decisión de producto`.
    - Termina con `FIN: necesita-decision #<N>`.
  - `kit-issue.sh bloquear <root> <N> <id> <fichero-motivo>`: igual que `decision`, con `<!-- kit-bloqueado -->` y `bloqueado`. Termina con `FIN: bloqueado #<N>`.
  - `kit-issue.sh crear <root> <titulo> <fichero-cuerpo> <listo|propuesta>`:
    - Si hay un issue abierto con el mismo título (sin distinguir mayúsculas), exit 1 con `ya existe #<N> con ese título`.
    - Si no, lo crea con esa etiqueta e imprime la URL. Termina con `FIN: <url>`.
- Stub `tests/stubs/flow/gh`, bash + jq:
  - El estado vive en `$GH_STATE/state.json`: issues con number, title, body, state, labels, assignees, comments [{id, body}] y PRs.
  - Soporta los subcomandos de `gh issue list/view/create/comment/edit/close` y `gh pr ...` que usen los scripts de las Tasks 2 a 4 con `--json` y `--jq`, más `gh api` para check-runs y workflows.
  - `GH_FAIL_ON="<subcomando>"` hace fallar con exit 1 la primera llamada que case con ese patrón. Sirve para el Review Focus 1.
  - Registra cada llamada en `$GH_LOG`.
  - Cada subcomando se implementa cuando lo necesita su test. No se adelanta nada.

- [ ] Step 1: escribir `tests/test_issue.sh` con repo `mk_repo`, remoto `https://github.com/dru/demo.git` y el stub de flujo:
  - `siguiente`: elige el `listo` más antiguo e ignora uno `listo`+`en-curso`, uno `listo`+`necesita-decision` y uno sin `listo`. Sin candidatos da exit 1.
  - `reclamar`: gana, y el issue queda con `en-curso` y el marcador. Con un `kit-reclamado: otro` previo, pierde con exit 1. Con un `kit-reclamado: otro` seguido de `kit-soltado: otro`, gana.
  - `reclamar` con `GH_FAIL_ON` en la edición de etiquetas da exit 2 y deja publicado `kit-soltado` propio.
  - `soltar`: el ajeno da exit 1. El propio deja el marcador antes de quitar la etiqueta, comprobado por el orden en `$GH_LOG`.
  - `decision`: comentario con marcador, etiqueta, asignado y `en-curso` quitado.
  - `crear`: un duplicado da exit 1; uno nuevo imprime la URL y lleva la etiqueta pedida.
  - Sin `.agents-kit.json`: todos los subcomandos dan exit 1 con `kit no activado: ejecuta kit-on`.
- [ ] Step 2: verlo fallar.
- [ ] Step 3: implementar el stub y el script. Cada cuerpo de comentario va por `--body-file`. El id del agente nunca sale del nombre de la rama: lo genera la skill con `kit-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')`.
- [ ] Step 4: `tests/run.sh` en verde y commit.

### Task 3: `scripts/kit-worktree.sh`

**Files:**
- Create: `scripts/kit-worktree.sh`
- Test: `tests/test_worktree.sh`

**Interfaces:**
- Consumes: el stub de flujo (`gh pr list/view`).
- Produces:
  - `kit-worktree.sh abrir <root> <N> <slug>`:
    - Valida N (solo dígitos) y slug (regex de Global Constraints): exit 1 si no cumplen.
    - Hace `git fetch -q origin <default>`.
    - Si la rama `issue-<N>-<slug>` ya existe con worktree, lo reutiliza e imprime `ya existía`.
    - Si existe sin worktree, la añade.
    - Si no existe, `git worktree add -b <rama> --no-track <ruta> origin/<default>`.
    - Imprime `worktree: <ruta>` y `rama: <rama>`, y termina con `FIN: <ruta>`.
    - Exit 1 si la ruta existe y no es ese worktree.
  - `kit-worktree.sh limpiar <root> <N>`:
    - Localiza el worktree de la rama `issue-<N>-*` con `git worktree list --porcelain`.
    - Exige la PR de esa rama en estado `MERGED`; si no, exit 1 con `la PR de <rama> no está fusionada`.
    - Exige `git -C <wt> status --porcelain` vacío; si no, exit 1 con `el worktree tiene cambios; no se borra nada`.
    - Ejecuta `git worktree remove` (nunca `--force`), luego `git branch -D` y `git fetch -q --prune origin`.
    - Termina con `FIN: limpio`.

- [ ] Step 1: escribir `tests/test_worktree.sh` con un remoto bare local como `origin`:
  - `abrir` crea la rama sin upstream y el worktree en `$KIT_WORKTREES/<repo>/issue-3-foo`, que se fija con `KIT_WORKTREES` a un temporal.
  - Repetir `abrir` es idempotente.
  - Un slug inválido da exit 1.
  - `limpiar` con la PR `OPEN` da exit 1 y conserva todo.
  - Con `MERGED` y cambios sin confirmar da exit 1 y conserva todo.
  - Con `MERGED` y limpio lo borra todo.
- [ ] Step 2: verlo fallar, implementar, `tests/run.sh` en verde y commit.

### Task 4: `scripts/kit-pr.sh`

**Files:**
- Create: `scripts/kit-pr.sh`
- Test: `tests/test_pr.sh`

**Interfaces:**
- Consumes: el stub de flujo, `kit_origin_slug` y `kit_config`.
- Produces (`<wt>` es el worktree de la rama del issue):
  - `kit-pr.sh abrir <wt> <N> <titulo> <fichero-cuerpo>`:
    - Exige un árbol limpio y al menos un commit sobre `origin/<default>`.
    - Primero hace `git push -u origin HEAD` y después `gh pr create --base <default> --head <rama>`.
    - Exige que el cuerpo contenga `Cierra #<N>`; si no, lo añade al final.
    - Imprime el número de PR y termina con `FIN: <url>`.
  - `kit-pr.sh esperar-ci <wt> <pr>`:
    - El SHA local (`git rev-parse HEAD`, 40 caracteres) debe coincidir con `headRefOid`; si no, exit 2 con `la PR apunta a <x> y aquí estás en <y>: empuja o espera`.
    - Si el repo no tiene workflows (`gh api repos/<slug>/actions/workflows --jq .total_count` igual a 0), termina con `FIN: sin-ci`.
    - Si no, sondea `repos/<slug>/commits/<sha>/check-runs?filter=all&per_page=100`. Sin checks o con alguno sin `completed`, sigue esperando.
    - Si todos terminan en `success`, `skipped` o `neutral`, termina con `FIN: verde`.
    - Cualquier otra conclusión da exit 1 con `el CI terminó en '<x>'`.
    - Hay un tope `KIT_CI_TIMEOUT` (1800 s por defecto). Al agotarlo, exit 1 con `el CI de <sha8> no concluyó en <n>s`.
    - El intervalo sale de `KIT_CI_POLL` (15 s por defecto; los tests usan 0).
  - `kit-pr.sh gate-local <wt> <pr> <fichero-salida>`: comenta `<!-- kit-gate-local: <sha40> -->`, seguido de la salida de tests, lint y build. Termina con `FIN: gate-local <sha8>`.
  - `kit-pr.sh historial <wt> <pr>`: imprime en orden los cuerpos de todos los comentarios `kit-ronda`, separados por `-----`. Si no hay, imprime `(sin rondas previas)`. Termina con `FIN: <n> rondas`.
  - `kit-pr.sh ronda <wt> <pr> <n> <fichero>`:
    - Exige que cada línea de hallazgo del fichero (`- [R<n>.<k>] ...`) acabe en `→ aplicado` o en `→ rechazado: <motivo>`; si no, exit 1 indicando la línea.
    - Publica `<!-- kit-ronda: <n> -->` con el fichero y termina con `FIN: ronda <n>`.
  - `kit-pr.sh fusionar <wt> <pr> <N>`. Reúne todos los fallos antes de salir: exit 1 con `no se puede fusionar:` y una línea `  - <motivo>` por fallo. Puertas:
    - La PR no está en borrador.
    - El árbol está limpio.
    - El HEAD local es igual al `headRefOid`.
    - `origin/<default>` es ancestro del HEAD. Si no lo es, hace `git rebase origin/<default>` y `git push --force-with-lease`, y sale con exit 1 con `rebasada sobre <default>: vuelve a esperar el CI`. Si el rebase tiene conflicto, hace `git rebase --abort` y sale con exit 1 con `conflicto con <default>: resuélvelo`.
    - El CI está verde para ese SHA exacto, con la misma lógica que `esperar-ci` pero de una sola lectura, o existe un comentario `kit-gate-local: <ese sha>` si no hay CI.
    - Ningún comentario `kit-revision` tiene un id mayor que el último `kit-ronda`, y existe al menos un `kit-ronda`.
    - Si todo pasa: `gh pr merge <pr> --squash` y confirmar `state == MERGED`. Si el issue sigue abierto, `gh issue close <N> --comment "Resuelto en #<pr>."`. Imprime `PR fusionado: <url>` y termina con `FIN: ok`.

- [ ] Step 1: escribir `tests/test_pr.sh` con remoto bare, stub de flujo y `KIT_CI_POLL=0`:
  - `abrir` añade `Cierra #N` si falta.
  - `esperar-ci`:
    - 0 workflows da `FIN: sin-ci`.
    - Un check `in_progress` y después `success` da `FIN: verde`. El stub avanza el estado en cada lectura con `GH_CHECKS_SEQ`.
    - Sin checks al principio y después `success` da verde. Es el Review Focus 2.
    - `failure` da exit 1.
    - Un SHA distinto da exit 2.
  - `historial` con dos rondas sale en orden.
  - `ronda` con una línea sin decisión da exit 1.
  - `fusionar`:
    - Rechaza con `kit-revision` posterior a `kit-ronda`. Es el Review Focus 4.
    - Rechaza sin CI verde ni gate-local.
    - Rechaza en borrador, y lista los 3 motivos juntos si fallan a la vez.
    - Fusiona cuando todo está bien y cierra el issue.
- [ ] Step 2: verlo fallar, implementar, `tests/run.sh` en verde y commit.

### Task 5: `scripts/kit-review.sh` y prompt del revisor

**Files:**
- Create: `scripts/kit-review.sh`
- Create: `skills/kit-run/references/revisor.md`, la plantilla del prompt
- Test: `tests/test_review.sh`, con stubs `tests/stubs/review/claude` y `tests/stubs/review/opencode`

**Interfaces:**
- Consumes: `kit-pr.sh historial` y `kit_config`.
- Produces: `kit-review.sh <wt> <pr> <herramienta> <modelo> <foco> <ronda> <N>`.
  1. Crea un worktree desechable con `git worktree add --detach <tmp> HEAD` desde `<wt>` y lo borra siempre al salir, con un trap.
  2. Construye el prompt desde `revisor.md`, sustituyendo `{{FOCO}}`, `{{RONDA}}`, `{{ISSUE}}`, `{{BASE}}` y `{{HISTORIAL}}`:
     - `{{ISSUE}}` es el título y cuerpo de `gh issue view <N>`.
     - `{{BASE}}` es `origin/<default>`.
     - `{{HISTORIAL}}` es la salida de `kit-pr.sh historial`.
  3. Lanza el revisor en el worktree desechable, con stdin `/dev/null` y un tope de `KIT_REVIEW_TIMEOUT` segundos (1800 por defecto) mediante `perl -e 'alarm shift; exec @ARGV'`:
     - `claude`: `claude -p --model <modelo> --permission-mode bypassPermissions --disallowedTools "Bash(git push:*)" "Bash(gh:*)" --output-format text "<prompt>"`.
     - `opencode`: `OPENCODE_CONFIG_CONTENT='{"permission":{"bash":{"*":"allow","gh *":"deny","git push*":"deny"},"edit":"allow","external_directory":"deny"}}' opencode run -m <modelo> "<prompt>"`.
     - `codex`: `codex exec -m <modelo> --sandbox workspace-write "<prompt>"`. No se prueba en esta fase y no tiene test real.
     - Una herramienta desconocida o una CLI ausente da exit 2 con `revisor no disponible: <herramienta>`.
  4. Si la salida no contiene una línea `HALLAZGOS: <n>`, o el proceso falla o agota el tiempo, sale con exit 2 con `el revisor <herramienta>/<modelo> no entregó: <motivo>` y no publica nada.
  5. Si entrega, publica en la PR un comentario `<!-- kit-revision: <herramienta>/<modelo> ronda <n> -->` con la salida desde el primer hallazgo hasta la línea `HALLAZGOS`. Después imprime esa misma salida y termina con `FIN: <n> hallazgos`.
- Contenido de `revisor.md`, en español:
  - Revisor con contexto limpio. Su único entregable es el informe, que entrega pase lo que pase aunque sea parcial y marcando lo no demostrado como NO VERIFICADO.
  - Lee el diff (`git diff {{BASE}}...HEAD`) y el issue.
  - Busca solo dentro del scope del issue y con su foco.
  - No repite nada de `{{HISTORIAL}}`, ni lo aplicado ni lo rechazado.
  - Puede ejecutar tests y modificar ficheros en su copia, pero nunca `git push`, `gh` ni comentarios.
  - Techo de unas 30 llamadas.
  - Formato de cada hallazgo: `<k>. [grave|medio|menor] <ruta>:<línea>: <problema>. Escenario: <entrada o estado concreto que falla>. Arreglo: <propuesta>`.
  - Última línea: `HALLAZGOS: <total>`, y `HALLAZGOS: 0` si no hay nada.

- [ ] Step 1: escribir `tests/test_review.sh`. Los stubs `claude` y `opencode` imprimen según `REVIEW_STUB_MODE`: `ok` da dos hallazgos más `HALLAZGOS: 2`, `cero` da `HALLAZGOS: 0`, `mudo` no imprime la línea `HALLAZGOS` y `lento` duerme. Casos:
  - `ok`: publica un comentario con marcador y termina con `FIN: 2 hallazgos`.
  - El stub recibe un prompt que contiene el foco, el historial y el issue. El stub vuelca sus argumentos a un fichero.
  - `mudo`: exit 2 sin comentario.
  - `lento` con `KIT_REVIEW_TIMEOUT=1`: exit 2.
  - Una herramienta inexistente da exit 2.
  - El worktree desechable no queda registrado (`git worktree list`) en ningún caso.
  - Los flags de bloqueo (`gh`, `git push`) aparecen en los argumentos de claude y en el entorno de opencode.
- [ ] Step 2: verlo fallar, implementar, `tests/run.sh` en verde y commit.

### Task 6: skills `kit-plan`, `kit-run`, `kit-scout` y documentación

**Files:**
- Create: `skills/kit-plan/SKILL.md`, `skills/kit-plan/references/issue.md` (plantilla del cuerpo del issue)
- Create: `skills/kit-run/SKILL.md` (la carpeta `references/revisor.md` ya existe por la Task 5)
- Create: `skills/kit-scout/SKILL.md`
- Modify: `tests/test_skills.sh` para exigir las 5 skills; `README.md` y `AGENTS.md` (mapa, comandos, flujo)
- Modify: `rules/core.md` solo si una regla contradice el flujo. No añadir reglas nuevas.

**Interfaces:**
- Consumes: todos los scripts anteriores, con sus códigos y líneas `FIN:` exactos.
- Contenido de cada skill. Español, compacto, sin rayas largas. La descripción tiene como máximo 200 caracteres. Cita los scripts como `"${CLAUDE_PLUGIN_ROOT}/scripts/<nombre>"`, con la misma regla de raíz de respaldo que `kit-on`.
  - **kit-plan** (`kit-plan <objetivo>`):
    1. Comprueba el marcador.
    2. Habla de producto con Dru: comportamiento, casos, mensajes y lo que no entra. Una pregunta cada vez. Lo técnico no se pregunta.
    3. Propone el desglose: cada issue es un objetivo completo de punta a punta, sin trocear por líneas y sin PRs enormes. Espera una aprobación explícita.
    4. Crea cada issue con `kit-issue.sh crear ... listo` y un cuerpo según `references/issue.md`: objetivo, comportamiento acordado, criterios de aceptación observables, cómo se comprueba (e2e y casos límite), qué NO entra, rutas relevantes, y lo verificado frente a lo supuesto.
    5. Lista las URLs.
  - **kit-scout**:
    1. Comprueba el marcador.
    2. Busca bugs, tests que faltan, duplicación, dependencias viejas, deuda de skills del proyecto (hinchadas, duplicadas, obsoletas, que contradicen el código) y `AGENTS.md` desactualizado. Si el repo no tiene CI, puede proponer añadirlo.
    3. Crea como máximo 5 issues por ejecución con `kit-issue.sh crear ... propuesta`, nunca `listo`. Usa la misma plantilla de issue, y en "lo supuesto" pone la evidencia encontrada.
    4. Le dice a Dru cómo aprobar: cambiar `propuesta` por `listo`.
  - **kit-run**. Bucle hasta que `siguiente` dé exit 1. Al acabar, resumen en el chat con cada PR fusionada y cada issue que espera a Dru.
    1. **Coger.** Genera el id una sola vez por ejecución. Llama a `kit-issue.sh siguiente` y `reclamar`.
    2. **Encuadrar.**
       - Lee el issue entero, sus comentarios (incluidas las respuestas de Dru a un `kit-decision`), `AGENTS.md` y el código afectado.
       - Verifica que lo que nombra el issue existe y sigue vigente.
       - Si está obsoleto o ya está hecho, lo cierra con evidencia y suelta el reclamo.
       - Si le falta producto, usa `decision`.
       - Escribe en el chat un resumen de 4 líneas: qué pide, sigue vigente (con la evidencia), qué voy a hacer y qué NO toco.
    3. **Implementar.**
       - `kit-worktree.sh abrir` y trabajar solo con la ruta absoluta del worktree.
       - Tests primero (unitarios, e2e y casos límite) y luego el código.
       - Tests, lint y build en verde en local.
       - Si la sesión no corre con el modelo de `implementer`, delega la implementación en un subagente con ese modelo cuando la herramienta lo permita.
       - Automejora en la misma PR: actualizar `AGENTS.md` y las skills del proyecto si aprendió algo.
       - Entrada en `CHANGELOG.md` con el formato del comentario de cabecera del propio fichero.
    4. **PR.** Commit y `kit-pr.sh abrir`. Después `esperar-ci`. Si da `FIN: sin-ci`, ejecuta los comandos de test, lint y build de `AGENTS.md` sobre el último commit y llama a `gate-local` con su salida.
    5. **Revisión.** Ronda `r` desde 1:
       - Commit y push hechos antes de lanzar revisores.
       - Lanza en paralelo un `kit-review.sh` por cada línea de `kit_reviewers`: en segundo plano y esperando a todos. Para leer la lista se usa `bash -c 'source "$PLUGIN/scripts/lib/config.sh"; kit_reviewers <root>'`.
       - Si un revisor da exit 2 dos veces seguidas, la propia sesión revisa con ese foco y lo dice en la ronda.
       - Por cada hallazgo, decide si aplicarlo o rechazarlo con un motivo escrito. Lo que esté fuera del scope se rechaza y se abre aparte como `propuesta`.
       - Escribe el fichero de ronda con las líneas `- [R<r>.<k>] (<herramienta>/<modelo>) <resumen> → aplicado` o `→ rechazado: <motivo>` y llama a `kit-pr.sh ronda`.
       - Si aplicó algo: commit, push, `esperar-ci` o gate-local, y ronda nueva obligatoria.
       - Se para con 0 hallazgos de todos los revisores. También se para si dos rondas seguidas solo traen hallazgos que salen de sus propios arreglos sin afectar al uso real; en ese caso lo pendiente se abre como `propuesta`.
       - Al llegar a `maxReviewRounds` (con `kit_config`): `gh pr ready --undo`, `kit-issue.sh bloquear` con un resumen de lo pendiente, y siguiente issue.
    6. **Fusionar.** Con `autoMerge` verdadero, `kit-pr.sh fusionar`. Si da exit 1 por rebase, vuelve a `esperar-ci` y reintenta. Con otros fallos, los corrige o bloquea. Después, `kit-worktree.sh limpiar`.
    7. **Duda de producto en cualquier paso:** nunca la resuelve el agente. `kit-pr.sh` deja la PR en borrador si existe (`gh pr ready --undo`), llama a `kit-issue.sh decision` y pasa al siguiente issue.
    8. **Reglas.**
       - Nunca salirse del scope.
       - Nunca afirmar lo que no se ha ejecutado.
       - Nunca recortar la salida con `head` ni `tail`: leer hasta la línea `FIN:`.
       - Los avisos fuera de GitHub llegan en la fase 3.
- [ ] Step 1: ampliar `tests/test_skills.sh` para que exija `kit-plan`, `kit-run` y `kit-scout` y que `skills/kit-run/references/revisor.md` exista. Las comprobaciones ya existentes (scripts citados que existan y sean ejecutables, sin rayas largas, sin él/ella, sin `| head`/`| tail`) se aplican solas.
- [ ] Step 2: escribir las skills y la plantilla. Actualizar `README.md`: comandos, cómo aprobar propuestas y qué hacer con `necesita-decision` (responder en el issue y quitar la etiqueta). Actualizar el mapa de `AGENTS.md`.
- [ ] Step 3: `tests/run.sh` y `claude plugin validate .` en verde, y commit.

### Task 7 (controlador): e2e real en `DruMoDev/agents-kit-sandbox`

Lo ejecuta el controlador, no un subagente.
1. Actualizar el `.agents-kit.json` del sandbox con los revisores nuevos mediante una PR.
2. Crear con `kit-issue.sh crear` un issue `listo` pequeño y real, por ejemplo añadir al README una sección "Uso" con un ejemplo.
3. Lanzar `kit-run` en Claude Code con `claude -p "kit-run"` en el clon del sandbox.
4. Comprobar:
   - La PR se fusiona.
   - Hay al menos una ronda con comentarios `kit-revision` de claude/opus, claude/sonnet y opencode/openai/gpt-6.1-sol, más un `kit-ronda`.
   - El issue queda cerrado.
   - La rama y el worktree están borrados.
5. Repetir con un issue que obligue a preguntar algo de producto y verificar que acaba en `necesita-decision`, asignado y sin PR fusionada.
6. Anotar en `AGENTS.md` ("Formatos verificados") lo comprobado de verdad.
