# agents-kit como plugin (Claude Code + Codex) — diseño

## Intención

`agents-kit` deja de ser un instalador por proyecto (`npx … init`) y pasa a ser **un plugin personal** que codifica cómo le gusta a Dru que trabajen los agentes. Se instala una vez en Claude Code y en Codex, y se **activa por repo**. Se itera editando este repo; al actualizar el plugin, todos los repos activados usan la versión nueva.

Por qué: el `init` copiaba reglas congeladas en cada repo (nunca se usó porque había que acordarse de lanzarlo y quedaba desactualizado). El plugin es la única fuente de verdad y además trae comandos, hooks y agentes revisores, cosa que el `init` no podía.

Usuario único: Dru. Nadie más ni ninguna otra herramienta trabaja en sus repos personales.

## Objetivos

1. **Reglas de trabajo siempre cargadas** en los repos activados: escalera lazy-senior-dev, reutilizar siempre, una sola fuente de verdad, mantenible y escalable, nada de errores tragados, tests (happy + error path), **e2e siempre que haya algo que comprobar de punta a punta, con casos límite explícitos**, nunca declarar "hecho" sin comprobar de verdad.
2. **Conocimiento del proyecto vivo**: el `AGENTS.md` del repo se mantiene correcto (stack, comandos, mapa, skills del proyecto) y las **skills del proyecto se automejoran**: los errores, malentendidos y trucos aprendidos se guardan para no repetirse. Se actualiza la skill existente antes que crear una; cada skill compacta (`SKILL.md` corto + `references/` + `scripts/`). Mantenimiento periódico que compacta, deduplica o borra skills hinchadas u obsoletas.
3. **Flujo autónomo de issues en GitHub**: planificar con Dru → issues → implementar → revisión multiagente → squash merge a `main` por PR → borrar rama y worktree → entrada en `CHANGELOG.md` → aviso.
4. **Changelog por repo** con formato fijo legible por máquina.
5. **Funciona igual en Claude Code y Codex.** Todo canónico en el lado "agents" (`AGENTS.md`, `.agents/skills/`), Claude por import/symlink.
6. **Web de changelogs** de todas las apps con el kit activado, desplegada en Cloudflare (ver su sección). *(Dru: incluida en este plan, como última fase.)*

## No objetivos (por ahora)

- **Frameworks y herramientas**: el kit no recomienda ni instala skills/MCPs de frameworks. Cada herramienta se instala aparte con sus skills oficiales al día. Se borra todo lo relacionado (`templates/frameworks/`, `recommendations.json`, catálogo MCP).
- **El instalador `init`/`update`/`mcp`** (`bin/cli.js`, `tests/smoke.sh`, `package.json` si queda sin uso): se elimina.
- **Ejecución en la nube** (agentes programados con el Mac apagado). Se empieza en local. El diseño no debe impedirla (ver "Transporte").
- **Telegram u otros canales extra**: no se configuran. El canal de avisos es una pieza intercambiable para poder añadirlos después.
- **Flujos en Codex**: reglas, hook de activación y `kit-on`/`kit-off` funcionan en ambos desde ya; `kit-plan`, `kit-run` y `kit-scout` se construyen y prueban **primero en Claude Code** (Dru solo tiene suscripción de Claude). Llevarlos a Codex será añadir su entrada en la configuración de revisores/implementador.
- **Migrar `tiktok-editor`**: su flujo `resolver-issue` sigue como está; el plugin se inspira en él (ver "Prior art"), no lo sustituye en esta fase.

## Anti-objetivos (fallaría aunque funcione técnicamente)

- Que toque repos donde no está activado (en particular los de Aikosmo, con otro flujo git). Sin marcador, el plugin no hace **nada**.
- Que los agentes **decidan producto**. Funcionalidad y comportamiento los discute y aprueba Dru; la implementación la deciden los agentes.
- PRs enormes, difíciles de revisar, o agentes que se salen del scope del issue.
- Que las skills crezcan hasta ser un montón de notas, o que el plugin copie reglas dentro de los repos (volver al problema del `init`).

## Experiencia de uso (decidido con Dru)

Instalar una vez (Claude Code; equivalente en Codex):
```
/plugin marketplace add ~/Documents/programacion/agents-kit
/plugin install agents-kit
```
El propio repo es el marketplace. No se publica en ningún sitio. (Más adelante, para la nube, bastará con tenerlo en GitHub privado.)

Comandos (skills invocables por el usuario):

| Comando | Qué hace |
|---|---|
| `kit-on` | Activa el kit en el repo actual |
| `kit-off` | Lo desactiva |
| `kit-plan <objetivo>` | Conversa de producto con Dru; tras su aprobación, crea issues |
| `kit-run` | Procesa issues listos uno tras otro hasta merge |
| `kit-scout` | Busca mejoras y crea issues como propuestas |

Trabajando "normal" sin comandos en un repo activado, las reglas también aplican (tests, PR, changelog, mantener AGENTS.md y skills).

## Componentes

### Activación por repo
- **Marcador**: `.agents-kit.json` en la raíz, commiteado. Contiene la configuración del repo (ver abajo). Su existencia es el interruptor.
- **Hook `SessionStart`** (Claude Code y Codex): si el repo tiene el marcador, inyecta las reglas del kit en el contexto; si no, no hace nada. (Patrón de superpowers.)
- Las skills de flujo (`kit-plan`, `kit-run`, `kit-scout`) comprueban el marcador y se niegan si falta, indicando `kit-on`.

`kit-on`:
- crea `.agents-kit.json` con valores por defecto y `CHANGELOG.md` con el formato fijo si no existe;
- crea u ordena `AGENTS.md` (solo contexto del proyecto, **nunca copia de las reglas del kit**) y deja `CLAUDE.md` con el import `@AGENTS.md`;
- garantiza `.agents/skills/` y el symlink `.claude/skills -> ../.agents/skills` (lo repara si está roto; no reemplaza un `.claude/skills` real con contenido, lo avisa);
- en GitHub: crea las etiquetas del flujo, activa `delete_branch_on_merge` y squash merge, crea y fija el issue "📦 Changelog";
- deja todo en una rama, abre una PR con la activación y la mergea él mismo (squash, borra la rama). **Nada entra en `main` sin PR**, tampoco la activación.

`kit-off` borra el marcador (también por PR) y deja lo demás (AGENTS.md, CHANGELOG, skills) porque es del proyecto.

### Configuración (`.agents-kit.json`)
Valores por defecto, decisión del diseñador salvo donde se indica:
- `reviewers` (organizado **por herramienta**, p. ej. `{"claude": [...], "codex": [...]}`; hoy solo se rellena `claude`): lista de revisores con modelo y foco. Por defecto solo Claude: **Opus** (corrección, casos límite, tests) y **Sonnet** (simplicidad, reutilización, scope). *Dru: los revisores dependen de sus suscripciones; hoy solo Claude. Añadir Codex u otro debe ser cambiar configuración, no código.*
- `implementer`: modelo que implementa, también por herramienta (por defecto Claude Opus).
- `notify`: canal de avisos, `"claude-push"` por defecto, `"ntfy"` como alternativa (con `ntfyTopic`), `"none"`.
- `maxReviewRounds`: tope duro (ver "Revisión").
- `autoMerge`: `true`.

### Reglas (cargadas por el hook)
Fuente: `templates/base.md` actual, ampliado con lo que ya practica Dru en sus repos (recogido de `tiktok-editor` y otros `AGENTS.md`):
- "Verde no es validado": si el cambio altera el resultado visible, comprobarlo con casos reales y contra la versión anterior.
- No afirmar nada que no se haya ejecutado; un supuesto sobre una herramienta externa no vale hasta ejecutarlo.
- Lo técnico lo decide el agente; lo de producto se pregunta (una pregunta cada vez, sin micro-preguntas).
- Lo repetitivo y determinista va a scripts, no a instrucciones.
- Un issue = una PR. Nada de refactors de paso.
- Sin compatibilidad hacia atrás en proyectos personales; ninguna dependencia nueva sin justificar.
- Rutas clicables al mostrar archivos; explicar qué y por qué.
- Flujo git en repos activados: todo entra en `main` por PR con squash; ramas y worktrees se borran tras el merge.
- Mantener `AGENTS.md` y skills del proyecto (ver "Automejora").
- `testing.md` y `docs-discipline.md` siguen como referencias que se leen cuando aplica.

### Automejora de conocimiento
- Al terminar una tarea (en `kit-run` es un paso obligatorio antes del merge; fuera de él, una regla): ¿aprendiste algo que evitaría un error futuro? → actualizar la skill del proyecto más cercana o crear una nueva en `.agents/skills/`; ¿cambió el stack, comandos o mapa? → actualizar `AGENTS.md`. Estos cambios van **en la misma PR** que los provocó.
- Formato de skill del proyecto: `SKILL.md` corto (cuándo usarla, flujo, restricciones), detalle en `references/`, lo determinista en `scripts/`.
- Higiene: `kit-scout` incluye una auditoría de skills (hinchadas, duplicadas, obsoletas, que contradicen el código) y propone o hace la compactación como issue.
- Un revisor comprueba que si el PR revela una lección, quedó registrada.

### Flujo de issues

**Etiquetas** (las crea `kit-on`): `listo` (elegible para `kit-run`), `propuesta` (creado por agentes, pendiente de Dru), `en-curso`, `necesita-decision`, `bloqueado`. Aprobar una propuesta = cambiarle `propuesta` por `listo`. *(Nombres en español: elección del diseñador, coherente con `tiktok-editor`.)*

**`kit-plan <objetivo>`** — producto primero:
1. Conversa con Dru sobre la funcionalidad y su comportamiento (casos, mensajes, flujos, qué no entra). Lo técnico no se pregunta.
2. Presenta el desglose en issues y espera aprobación explícita.
3. Crea los issues con `listo`. Cuerpo de cada issue: problema/objetivo, comportamiento esperado acordado, criterios de aceptación observables, cómo se comprueba (incluidos e2e y casos límite), qué NO entra, rutas relevantes, lo verificado y lo supuesto. Busca duplicados antes de crear.

**Tamaño de issue** *(Dru)*: cada issue es **un solo objetivo completo en sí mismo**, de punta a punta. No se limita por líneas ni se trocea al mínimo. Lo que se evita: PRs ultralargas, difíciles de revisar, objetivos difusos y agentes que se van del scope.

**`kit-scout`**: busca bugs, tests que faltan, duplicación, dependencias viejas y deuda de skills. Crea issues con `propuesta` (nunca `listo`). Todo lo que cambie comportamiento visible es propuesta para Dru por definición.

**`kit-run`** — en secuencia, uno a uno, hasta que no quedan `listo` (o solo quedan esperando a Dru):
1. **Coger**: el `listo` más prioritario; marcar `en-curso` con comentario marcado.
2. **Encuadrar**: verificar que lo que nombra el issue existe y sigue vigente; si está obsoleto o ambiguo, sacarlo del reparto (comentario + etiqueta) antes de soltarlo.
3. **Implementar** en rama y worktree propios: tests primero (unitarios + e2e + casos límite), luego código, todo en verde en local.
4. **PR** con `Cierra #N`, incluye la entrada del `CHANGELOG.md` (corta + extendida, con capturas si es visual) y los cambios de AGENTS.md/skills si los hay; esperar CI del SHA concreto.
5. **Revisión** (abajo).
6. **Merge**: condiciones = CI verde en el último SHA (si el repo no tiene CI: los comandos de test/lint/build de `AGENTS.md` ejecutados en local sobre el último commit, con su salida resumida en la PR; nunca un "sin checks" silencioso; *decisión del diseñador*), rama al día con `main`, todos los hallazgos resueltos por escrito, sin preguntas abiertas. Squash merge; GitHub borra la rama remota; borrar worktree y rama local; cerrar issue con comentario.
7. Siguiente issue.

**Duda de producto durante la implementación** *(Dru)*: el agente no la resuelve. Comentario con la pregunta en el issue, etiqueta `necesita-decision`, asignar a Dru (le llega notificación de GitHub), PR en borrador si existe, y pasar al siguiente issue.

**Scope** *(Dru)*: nunca salirse. Si se encuentra otro problema por el camino, se abre un issue `propuesta` aparte en vez de arreglarlo en la PR. El revisor de scope lo comprueba explícitamente.

### Revisión multiagente
- Revisores = subagentes con contexto limpio, modelos según `reviewers` (hoy Opus + Sonnet con focos distintos).
- Cada hallazgo se **aplica o se rechaza con motivo escrito** en la PR; no existe "ignorado". Los comentarios del flujo llevan marcadores HTML para poder seguir el estado.
- Ronda nueva obligatoria si la anterior obligó a tocar código (los hallazgos graves salen en los arreglos).
- Parar con señal limpia (0 hallazgos), o si los hallazgos vienen ya de los propios arreglos sin afectar al uso real (lo pendiente se abre como issues).
- **Sin repetir** *(Dru)*: cada ronda recibe el historial de hallazgos anteriores (aplicados y rechazados con motivo). Los revisores no vuelven a plantear lo ya tratado; solo revisan lo nuevo y siempre dentro del scope del issue. Con foco y sin repeticiones, el ciclo converge.
- Tope duro `maxReviewRounds` (*Dru*: por defecto **10**, configurable y puede ser más): al alcanzarlo, PR en borrador, issue `bloqueado`, asignado a Dru.
- A los subagentes revisores: preguntas concretas, techo de llamadas, "entrega pase lo que pase", nunca mutar el árbol de trabajo. No editar mientras revisan; commit antes de lanzarlos.

### Changelog y avisos
- `CHANGELOG.md` por repo, formato fijo (lo lee la web de changelogs). Cada entrada tiene *(Dru)*:
  - **Versión corta**: tipo + título de una línea, conciso y claro, más fecha y enlace al PR.
  - **Versión extendida** (opcional pero esperada en cambios visibles): qué cambia para quien usa la app, en pocas frases; **capturas de pantalla** si el cambio es visual; **ejemplo práctico** si ayuda a entenderlo.
  Ejemplo orientativo (el formato exacto lo fija el builder, siempre legible en GitHub y parseable):
  ```
  ## 2026-10-18

  ### Nuevo: Login con Google · [#12](https://github.com/<owner>/<repo>/pull/12)
  Ahora puedes entrar con tu cuenta de Google en un clic.

  En la pantalla de acceso aparece el botón "Continuar con Google"; si la cuenta
  ya existía con ese email, se vincula sola.

  ![Pantalla de acceso](docs/changelog/12-login.png)
  ```
  Fecha descendente; tipos cerrados `Nuevo | Mejora | Arreglo | Interno`; texto para quien usa la app, no técnico. La entrada (y sus capturas) se escribe en la misma PR.
- **Capturas**: en cambios visuales, el agente las saca durante la comprobación e2e (navegador automatizado) del estado final y las guarda en `docs/changelog/` del repo con el número de PR en el nombre. Comprimidas y solo las que aportan. Si el cambio no es visual, sin capturas.
- **Avisos** *(Dru: sin apenas configuración)*. En local los agentes actúan con la cuenta de GitHub de Dru y GitHub no notifica las acciones propias, así que las menciones/asignaciones de GitHub **no** sirven como aviso.
  - Canal por defecto: **notificación push de Claude Code a la app de Claude en el móvil**. El builder debe verificar primero que funciona en el setup de Dru; si no, **ntfy** (app ntfy + tema secreto, `curl` sin cuenta ni token).
  - Cuándo se avisa: al marcar un issue `necesita-decision` o `bloqueado` (con enlace), y al terminar cada `kit-run` con el resumen de lo que entró en `main` (enlaces a PRs). *(Resumen por ejecución y no diario: decisión del diseñador, en local no hay proceso diario.)*
  - En GitHub queda igualmente el rastro: issue asignado a Dru con la pregunta, y el resumen como comentario en el issue fijado "📦 Changelog".
- El envío de avisos vive en un único script con adaptadores (`claude-push`, `ntfy`, `none`), para añadir Telegram u otro canal sin tocar el flujo.

### Transporte (preparado para la nube)
La lógica no debe asumir el Mac. La detección de "dónde corro" vive en un único script, por la firma del entorno, nunca con `command -v gh` ni con una llamada REST de prueba (lección de `tiktok-editor`: en cloud la REST de repo responde 200 pero GraphQL, CI y `gh pr/issue` dan 403). En esta fase solo se implementa y prueba el transporte local; la nube queda como siguiente paso.

## Estructura final del repo

```
agents-kit/
  .claude-plugin/
    plugin.json            manifiesto Claude Code (skills, hooks, agents)
    marketplace.json       el repo es su propio marketplace
  .codex-plugin/
    plugin.json            manifiesto Codex (mismas skills y hooks)
  hooks/
    hooks.json             SessionStart
    session-start          inyecta rules/ solo si existe .agents-kit.json
  rules/
    core.md                reglas siempre cargadas (base.md evolucionado)
    testing.md             se lee antes de escribir tests
    docs-discipline.md     se lee antes de añadir docs
  skills/
    kit-on/  kit-off/  kit-plan/  kit-run/  kit-scout/
      SKILL.md + references/ (+ scripts/ si aplica)
  agents/                  definiciones de subagentes revisores
  scripts/                 lo determinista: issues, PR/CI/merge, worktrees,
                           changelog, avisos, transporte
  templates/
    agents-kit.json        config por defecto del marcador
    CHANGELOG.md           cabecera del formato
    AGENTS.md              esqueleto de contexto de proyecto
  web/                     web de changelogs (Astro + Cloudflare, wrangler)
  tests/                   tests de scripts y del hook
  AGENTS.md                cómo desarrollar el propio kit (+ CLAUDE.md -> @AGENTS.md)
  README.md                instalar, activar, comandos, cómo iterar
```
Una sola carpeta `skills/` compartida por los dos manifiestos, sin copias. Se eliminan `bin/`, `recommendations.json`, `templates/frameworks/`, `templates/AGENTS.header.md` (sustituido), `tests/smoke.sh` y, si queda sin uso, `package.json`.

En cada repo activado:
```
.agents-kit.json   CHANGELOG.md   AGENTS.md   CLAUDE.md (@AGENTS.md)
.agents/skills/    .claude/skills -> ../.agents/skills
```

### Web de changelogs (última fase)
Qué es: una web privada donde Dru ve, **app por app**, qué ha cambiado en cada una. Debe ser *(Dru)* **supervisual y fácil de entender**: saber de un vistazo qué pasa en cada app y qué hay nuevo que aún no ha visto. Durante su construcción se usan las skills de diseño (`frontend-design` / `impeccable`).
- **Datos, sin Actions ni rebuilds** *(decidido con Dru)*: al abrirla, el servidor pide los `CHANGELOG.md` a la API de GitHub y cachea el resultado unos minutos. Repos incluidos: los de la cuenta de Dru que tienen `.agents-kit.json` en la rama por defecto (descubiertos por la API y cacheados; decisión del diseñador).
- **Vista** *(Dru: cada app por separado, no una línea común)*:
  - **Inicio**: una tarjeta por app con nombre, fecha del último cambio y **cuántos cambios nuevos sin ver** tiene. Las apps con novedades destacan.
  - **Página de app**: sus cambios por fecha (más reciente primero), cada uno en **versión corta** (tipo, título, fecha); al abrirlo, **versión extendida** con descripción, capturas y ejemplos. Filtro por tipo.
  - **"Nuevo / no visto"**: los cambios posteriores a la última visita de Dru a esa app se marcan como nuevos; al verlos pasan a vistos, y hay "marcar todo como visto". El estado se guarda en el servidor (Cloudflare KV) para que sea el mismo en el móvil y en el Mac (decisión del diseñador).
  - Funciona bien en móvil.
- **Capturas**: las imágenes de repos privados se sirven a través del propio servidor (con el token), con caché.
- **Stack** *(decidido con Dru)*: Astro en modo servidor sobre Cloudflare, desplegado con `wrangler` desde la CLI.
- **Privada**: protegida con Cloudflare Access, solo el email de Dru (los datos vienen de repos privados).
- **Secretos**: un token de GitHub de solo lectura de contenidos, guardado como secreto en Cloudflare, nunca en el repo.
- **Dónde vive el código** *(Dru: en este repo, como app separada)*: carpeta `web/` con su propio `package.json`, independiente del plugin, para que el formato del changelog y su parser estén en un solo sitio (decisión del diseñador). El formato se define una vez y lo usan tanto los scripts del kit como la web.
- **Pasos que necesitan a Dru**: `wrangler login` si no hay sesión, crear el token de GitHub, y confirmar antes del primer despliegue y de configurar Access.
- Tests: parser del changelog (entradas con y sin versión extendida, con imágenes, mal formadas que se ignoran sin romper la página, repo sin changelog), lógica de "no visto", y e2e de inicio → app → abrir un cambio → marcar visto, con datos de ejemplo.

## Restricciones

- Mismo comportamiento en Claude Code y Codex; donde un formato difiera (manifiestos, hooks), se adapta en el manifiesto, nunca duplicando skills o reglas.
- Scripts sin dependencias nuevas (shell + `gh` + `git`; Python solo-stdlib si hace falta criterio estructurado, como en `tiktok-editor`).
- Nada que se active sin marcador.
- Solo GitHub.

## Prior art: `tiktok-editor` (`resolver-issue` + `crear-issue`)

Dru ya tiene una versión de este flujo en `~/Documents/tiktok/tiktok-editor` (`.agents/skills/resolver-issue`, `.agents/skills/crear-issue`, `tools/issues/issue.sh`, `tools/agente/pr.sh`, `tools/agente/transporte.sh`, `tools/agente/nucleo/`). El builder debe leerlo y reutilizar su patrón y sus lecciones, generalizándolo (quitando lo específico: áreas del repo, `entorno:nube|mac`, ejes D1, validación de renders, bot de Codex).

Patrón a conservar: **los scripts hacen lo mecánico (reparto, esperas, CI, cursores, merge) y la skill pone el criterio**; núcleo con salidas 0 = sí, 1 = no, 2 = no pude decidir.

Lecciones a conservar:
- No canalizar salidas de scripts por `head`/`tail` (se perdieron hallazgos); usar línea `FIN: N` / `PIPESTATUS`.
- Varios check runs por SHA: alguno sin terminar = en curso; manda el más reciente. SHA completo de 40 caracteres. Una PR en conflicto no lanza CI; el lag de la API tras un push no es CI rojo.
- Cursores y marcadores: todo comentario del flujo lleva marcador; los cursores se leen, nunca se inventan.
- Subagentes revisores a menudo no entregan: techo y plazo; si callan dos veces, revisar uno mismo contra sus preguntas.
- Worktrees: rutas absolutas siempre; el cwd vuelve al clon principal entre llamadas; un test en verde puede estar probando el árbol equivocado.
- Etiquetas no son atómicas y las listas tardan en reflejarlas: verificar con `view`. Reclamar = comentario + etiqueta + verificación.
- `core.hooksPath` no viaja en el clone: preparar el entorno explícitamente en cada worktree.
- Ningún skip silencioso en CI.

## Lo que queda a criterio del builder

- Ejecución con subagentes *(Dru)*: el plan se implementa con subagentes, en fases: (1) plugin base + reglas + activación, (2) flujo de issues y revisión, (3) changelog y avisos, (4) web.

- Formato exacto de manifiestos y hooks para cada herramienta (verificar contra la documentación actual de Claude Code y Codex; superpowers, instalado en ambos, es la referencia práctica).
- Cómo se nombran los comandos en cada herramienta (p. ej. prefijo del plugin en Claude Code).
- Detalle interno de los scripts y del protocolo de revisores, siguiendo el prior art.
- Repos sin CI: además del gate local, `kit-scout` puede proponer como issue añadir un workflow mínimo (nunca lo crea `kit-on`).
- Iterar el kit: editar el repo no llega a las sesiones hasta actualizar el plugin. Habrá un script que sube la versión en los dos manifiestos, y el README documenta `/plugin update` (y el equivalente en Codex). *Decisión del diseñador.*
- Prioridad entre issues `listo` (sin etiquetas de prioridad salvo que haga falta).
- Contenido exacto de `rules/core.md` a partir de `templates/base.md` y la lista de arriba, manteniéndolo compacto.
