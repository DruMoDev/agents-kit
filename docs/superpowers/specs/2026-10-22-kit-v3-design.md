# agents-kit v3: capa universal de método para todos los repos

## Por qué

Dru quiere trabajar igual en todos sus repos. El kit v2 (fases 1 a 4) funciona en un repo nuevo, pero al proponerlo en `tiktok-editor`, un repo real con un año de reglas y un flujo autónomo propio (`resolver-issue`, `crear-issue`, `tools/issues/issue.sh`, `tools/agente/pr.sh`), salieron choques y huecos. La v3 hace del kit la capa de **método** (cómo se trabaja) y deja a cada repo solo su **contexto y reglas propias**.

Fuentes: el análisis hecho desde `tiktok-editor` (resumen de Dru), su `AGENTS.md`, `.agents/skills/crear-issue` y `.agents/skills/resolver-issue`, y la skill `peer-review` de Aikosmo (revisión entre proveedores por CLI).

## Objetivos

- Un repo activado aporta solo lo suyo; el método vive en el kit y se cambia una vez para todos.
- Lo que depende de Dru (qué proveedores paga, avisos, rondas) se cambia en un único fichero global.
- `kit-on` aguanta repos reales sin romper nada.
- `tiktok-editor` puede migrar al kit sin perder lo aprendido.

## No objetivos (ahora)

- Sesiones en la nube (Claude Code web, `entorno:nube|mac`, transporte por MCP): fase posterior al piloto, empezando por verificar con una sesión real que el plugin carga. *(Dru)*
- Cambios en la web de changelogs.

## Anti-objetivos

- Que el kit pise reglas del proyecto, etiquetas existentes o un `AGENTS.md` sin enseñarlo.
- Revisores atados a un proveedor concreto.
- Borrar el flujo propio de `tiktok-editor` antes de que el kit demuestre que puede con ese repo.

## Decisiones

### 1. Contrato de capas

- `rules/core.md` declara la precedencia: **si una regla del `AGENTS.md` del proyecto choca con una regla de `rules/core.md`, manda el proyecto**. El kit aporta el método; el proyecto, contexto y reglas. *(Decisión del agente:)* la precedencia cubre las reglas escritas, no la mecánica de los scripts: lo que un repo puede cambiar de la mecánica es solo lo que admiten las claves de su `.agents-kit.json` (ver 3). No se anulan desde un `AGENTS.md`: código por PR, tests en verde, revisión y no decidir producto.
- "Todo por PR" aplica al código. Las rutas de **contenido** que el proyecto declare (`"contenido": ["projects/", "docs/ideas/"]` en `.agents-kit.json`) pueden ir directo a la rama por defecto en sesiones con Dru. Por defecto no hay ninguna. *(Decisión del agente:)* es una regla para el agente, sin lógica en scripts; `kit-run` siempre va por PR; un cambio mixto (contenido y código) va por PR; si la rama está protegida, va por PR.
- La plantilla `templates/AGENTS.md` tiene una sección `## Reglas del proyecto` donde vive lo propio del repo.

### 2. `kit-on` en repos reales

- Funciona aunque el árbol del clon principal tenga cambios: trabaja en un worktree temporal de `origin/<rama por defecto>` y nunca toca el árbol de Dru.
- Etiquetas: crea solo las que faltan; las existentes conservan su color y descripción.
- El reordenado de un `AGENTS.md` existente se le enseña a Dru como diff y solo se aplica si lo aprueba; si no, se deja como está y solo se añade lo mínimo (sección "Reglas del proyecto" si falta).
- Changelog opcional: `kit-on` le pregunta a Dru si este repo lleva `CHANGELOG.md` (`"changelog": true|false` en el marcador). Con `false` no hay fichero, ni entrada por PR, ni issue fijado; el resumen de `kit-run` va solo al chat y al aviso (sin URL). La web no cambia: sigue mostrando el repo (tiene marcador) como "sin cambios".

### 3. Configuración global

- `~/.agents-kit/config.json` (lo crea `kit-on` desde `templates/config.json` si falta). Precedencia: valores del plugin < global < `.agents-kit.json` del repo. El marcador de un repo típico queda en `{}` o con solo lo suyo (`contenido`, `protegido`, `setup`, `checks`, `changelog`).
- Claves globales: `proveedores`, `revision`, `notify`, `autoMerge`, `maxReviewRounds`.
- Seguridad *(decisión del agente)*: lista blanca explícita en `kit_config` de lo que un repo puede definir: `autoMerge`, `maxReviewRounds`, `revision.puestos` (sustituye la lista entera), `contenido`, `protegido`, `setup`, `checks`, `changelog`. `proveedores`, `implementador` y `notify` solo se leen del global (y el tema de ntfy, como hoy, de `~/.agents-kit/ntfy-topic` o `KIT_NTFY_TOPIC`); si un repo los pone, se ignoran con aviso.
- `implementador` *(decisión del agente)*: pasa al global como `{"familia": "claude", "nivel": "profundo"}` y sustituye a `implementer`. Se mantiene la delegación: si la sesión no corre con ese modelo, `kit-run` delega la implementación en un subagente con él cuando la herramienta lo permita. La familia que cuenta para asignar puestos es la del que implementó de verdad.

### 4. Backlog: reparto y etiquetas *(Dru: cualquier issue abierto; nombres: decisión del agente)*

- Un agente puede coger **cualquier issue abierto** salvo los que llevan `en-curso`, `necesita-respuesta`, `bloqueado`, `propuesta`, `someday` o `registro`. Orden: `prio:alta`, `prio:media`, sin prioridad, `prio:baja`; dentro, el más antiguo primero.
- Backlog previo *(decisión del agente)*: `kit-on` lista los issues abiertos que entrarían en el reparto y le pregunta a Dru si entran todos o si se marcan con `someday` (todos o los que él diga). Un issue sin cuerpo nunca se coge: `kit-run` lo pasa a `necesita-respuesta` pidiendo el detalle.
- Convivencia con otros flujos *(decisión del agente)*: `en-curso` excluye siempre, lo haya puesto el kit u otro flujo (`resolver-issue`); `reclamar` rechaza un issue con `en-curso` aunque no tenga marcador del kit; el resumen de reclamos colgados muestra también los `en-curso` sin marcador, sin ofrecer soltarlos.
- Prioridad *(decisión del agente)*: en `kit-plan` el agente propone la `prio` de cada issue dentro del desglose que Dru aprueba; en `kit-scout` la pone el agente (son `propuesta` igualmente).
- Etiquetas del kit: `en-curso`, `necesita-respuesta` (sustituye a `necesita-decision`), `bloqueado`, `propuesta` (de `kit-scout`; se aprueba quitándola), `someday`, `registro` (el issue fijado "📦 Changelog"), `prio:alta|media|baja`. Desaparece `listo`.
- `kit-issue.sh crear` es la única vía de alta: exige `--prio`, admite `--etiqueta` extra (áreas del proyecto) y `--propuesta`.
- Del flujo de `crear-issue` se adoptan: buscar duplicados antes de crear; cuerpo con problema, criterio observable, qué no entra, decisiones de producto, dónde toca, **lo verificado** (con ruta) y **lo que solo se cree** (marcado sin verificar); "una pregunta cada vez, solo producto"; verificar etiquetas con `view`, no con `list`.

### 5. Revisores por familias *(Dru: proveedor cambiante, centralizado, distinto del implementador cuando se pueda; hallazgos en la PR; 3 puestos)*

- Global:
  ```json
  "proveedores": {
    "claude": {"cli": "claude",   "modelos": {"profundo": "opus", "rapido": "sonnet"}},
    "gpt":    {"cli": "opencode", "modelos": {"profundo": "openai/gpt-6.1-sol", "rapido": "openai/gpt-6.1-sol"}}
  },
  "revision": {"puestos": [
    {"foco": "corrección, casos límite y tests", "nivel": "profundo", "familia": "otra"},
    {"foco": "fallos de uso real, seguridad y lo que otros darían por bueno", "nivel": "profundo", "familia": "otra"},
    {"foco": "simplicidad, reutilización y scope", "nivel": "rapido", "familia": "misma"}
  ]}
  ```
- `cli` es un adaptador del kit: `claude`, `opencode`, `codex`. Cambiar GPT de OpenCode a Codex es cambiar `"cli"`. Un proveedor nuevo es una entrada más y, si su CLI es nuevo, un adaptador.
- Implementador: se detecta por el entorno (`CODEX_THREAD_ID` → `gpt`, `CLAUDECODE` → `claude`); en OpenCode, o si se quiere forzar, la skill lo pasa explícito (`--implementador <familia>`). El orden de familias es el de `proveedores`.
- Asignación por puesto: `otra` = primera familia disponible distinta del implementador; `misma` = la del implementador; un nombre = esa familia. Si no hay ninguna `otra` disponible, el puesto lo cubre la misma familia y la ronda lo anota.
- Fallo en ejecución *(decisión del agente)*: si el candidato de un puesto falla por login o modelo, se prueba el siguiente candidato del mismo tipo y, agotados, la familia del implementador; si también falla, el puesto queda "sin confirmar" y la ronda no cuenta como completa para `fusionar`.
- Marcador por puesto *(decisión del agente)*: `<!-- kit-revision: puesto <i> <familia>/<modelo> ronda <r> -->`, así dos puestos con el mismo modelo no chocan. `kit-ronda` cita cada hallazgo como `(puesto <i>)`. Los marcadores v2 se siguen leyendo en el historial.
- Disponibilidad: comprobación previa barata (CLI en el PATH) y, en ejecución, un fallo de autenticación o modelo pasa al siguiente candidato sin reintentar en bucle; se avisa a Dru del login pendiente.
- De `peer-review` (Aikosmo) se adopta: salida con esquema JSON fijo (veredicto `sin_hallazgos|hallazgos|bloqueado`; cada hallazgo con severidad, confianza, fichero, línea, título, escenario de fallo, evidencia y sugerencia), validada, con un reintento de reparación en la misma sesión; entorno limpio (sin variables `CLAUDE*`, `CODEX_*`, `OPENCODE*` de la sesión que lanza); comprobación de que HEAD y el árbol no cambiaron; tiempo agotado o respuesta vacía = "revisión sin confirmar", nunca "sin hallazgos"; el texto de la PR se trata como afirmaciones a verificar.
- Se mantiene del kit: clon aislado sin credenciales con `gh` y `git push` bloqueados, historial de rondas para no repetir, comentario `kit-revision` por puesto y `kit-ronda` por ronda en la PR, tope `maxReviewRounds`.

### 6. Ganchos por repo

- `"protegido": ["lib/", "cli/"]`: si la PR toca una ruta protegida, su cuerpo debe tener `## Zonas protegidas` con cada ruta tocada y por qué; `fusionar` lo comprueba contra el diff.
- `"setup": "<script>"`: se ejecuta en cada worktree recién abierto (`kit-worktree.sh abrir`); si falla, el issue se bloquea con el motivo. `kit-on` avisa si el repo tiene hooks de git versionados (`core.hooksPath` distinto) y no declara `setup`.
- `"checks": {"pre-merge": "<script>"}`: `fusionar` lo ejecuta en el worktree sobre el head; salida distinta de 0 bloquea la fusión con su salida.

### 7. Reglas de método nuevas en `rules/core.md`

- Ningún worktree muerto: `kit-worktree.sh barrer <root>` elimina los worktrees limpios cuyo HEAD es ancestro de `origin/<rama por defecto>` (y su rama local), y `kit-run` lo ejecuta al terminar.
- Bug encontrado haciendo otra cosa: un subagente intenta refutarlo; si se sostiene, en una sesión con Dru se le propone con la evidencia y, con su OK, se abre el issue y se resuelve por debajo con `kit-run <N>` (modo de un solo issue, en segundo plano y en su propio worktree) sin bloquear el trabajo en curso. Dentro de un `kit-run` autónomo no se espera a nadie: se abre como `propuesta` con la evidencia, como ya hace hoy con lo que queda fuera del scope.
- Barridos de referencias: excluir por ruta, no por contenido.
- Medir en vez de deducir, también sobre herramientas externas (marcar como "sin verificar" lo que solo se cree).
- `scripts/kit-skills-check.sh <root>`: falla si una skill del proyecto (o del kit) cita en código en línea un fichero del repo o un script del kit que no existe. Lo usa el propio kit en sus tests y `kit-on` lo propone para el CI del proyecto.

### 8. Piloto en `tiktok-editor` (después de 1 a 7, fuera de este repo)

1. `kit-on` en `tiktok-editor` (diff del `AGENTS.md` aprobado por Dru; `protegido: ["lib/", "cli/"]`; `setup: tools/agente/preparar-entorno.sh`; `contenido` con las rutas de vídeos e ideas).
2. Quitar del `AGENTS.md` lo que ya cubre el kit.
3. `resolver-issue` y `crear-issue` conviven: se adelgazan a lo propio del proyecto solo cuando `kit-run` haya resuelto issues reales de ese repo.
4. Etiquetas: `tiktok-editor` ya usa `en-curso`, `necesita-respuesta`, `someday`, `prio:*`; solo se añaden `propuesta`, `bloqueado` y `registro`.

## Lo que queda a criterio del builder

- Formato exacto de `templates/config.json` y nombres de claves secundarias.
- Cómo se migra un repo ya activado con la v2 (`listo`, `necesita-decision`, `reviewers`): el kit debe seguir funcionando con un marcador viejo o dar un aviso claro de qué cambiar.
- El esquema JSON exacto de la revisión y el prompt del revisor (partiendo del actual `skills/kit-run/references/revisor.md`).
