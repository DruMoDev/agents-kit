# Reglas deterministas: lint, tipos y hooks que los agentes no pueden saltarse

## Intención

Todo el código de Dru lo escriben agentes y Dru no lo revisa. Las convenciones de cada proyecto (arquitectura de carpetas, desde dónde se importa cada cosa, i18n en vez de texto a pelo, reutilizar los componentes del proyecto, tokens de diseño, la convención de la API) están escritas en `AGENTS.md` y en `rules/`, y los agentes se las saltan a menudo: la prosa es una sugerencia. Lo mismo pasa con reglas del propio kit como "no dejes código huérfano".

El objetivo es pasar lo máximo posible de esas convenciones a la parte determinista: reglas de lint, tipos estrictos, comprobaciones de estructura, hooks y CI que fallan solos, con mensajes que dicen al agente cómo arreglarlo. Así "terminado" significa "las comprobaciones salen en verde", y no "el agente cree que siguió el `.md`".

Es lo que hacen quienes más trabajan con agentes. Las tres fuentes principales:
- La guía de Anthropic: si repites una línea del `CLAUDE.md` y el agente sigue fallándola, esa línea tiene que ser un hook.
- Factory: el lint en verde es la definición de terminado; el agente redacta las reglas y una persona las aprueba.
- OpenAI ("harness engineering"): linters a medida generados por el agente, con mensajes de remedio.

Fuentes al final.

## Decisiones de Dru

- **Ámbito:** el 95 % de sus proyectos es TypeScript (Node y React), algunos Astro para landings. Python y bash son secundarios; móvil, en el futuro, con lenguaje sin decidir.
- **Reglas del proyecto:** cada proyecto desarrolla sus propias reglas. Hay una base común solo para lo que sea obligatorio en todos.
- **Proyectos nuevos y empezados:** las dos cosas, incluidos los repos que ya tienen el kit activado.
- **Aprobación:** toda regla nueva o cambiada se consulta a Dru. El agente explica qué prohíbe, por qué y cómo se ve el error, y es crítico con ella. Dru la entiende y la aprueba. Ningún agente puede evitar una regla aprobada.
- **Dónde va el cambio:** en la propia PR del issue que lo motivó, sin PR aparte, después de que el agente avise y explique y Dru apruebe.
- **Base obligatoria de verdad:** en un repo TS con el kit activo y `"reglas"` sin desactivar, `kit-run` no trabaja sin la base instalada (`kit-issue.sh comprobar`, o la comprobación equivalente, lo rechaza y dice que se lance `kit-reglas`). La base "se va construyendo con el repo": se instala desde el primer día, pero en un repo empezado entra con el trinquete (no bloquea por la deuda que ya existe) y las reglas propias se van sumando a medida que aparecen convenciones. Con `"flujo": false`, `kit-revisar` avisa de que falta la base, porque allí no hay `kit-run` que bloquear.
- **Contexto:** lo de los proyectos empezados (deuda, trinquete) no debe costar contexto en los proyectos nuevos.

## Objetivos

1. Una base obligatoria para todos los repos TS, instalada y explicada al activar el kit.
2. Un mecanismo para que cada proyecto convierta sus convenciones en reglas, con Dru aprobando cada una.
3. Adopción sin parar el proyecto en repos con código hecho: la deuda existente se congela y solo puede bajar.
4. Que un agente no pueda desactivar, debilitar ni esquivar una regla: ni con comentarios en línea, ni editando la configuración, ni saltándose el hook.
5. Comprobación durante la edición, no solo en el CI, para que el agente corrija en el momento.

## No objetivos

- Una configuración de ESLint universal para todos los proyectos. La base es pequeña; lo propio de cada proyecto lo escribe ese proyecto.
- Formateo como debate: se usa el formateador que tenga el repo; si no tiene, la skill propone uno.
- Móvil: queda fuera hasta que exista un proyecto.
- Revisar la lógica o el producto: eso sigue en los revisores de varios modelos.

## Antiobjetivos (sería un fracaso aunque funcione)

- **Reglas que Dru no entiende.** Cada regla tiene un porqué legible en su mensaje y en su ficha (ver "Registro de reglas").
- **Ruido:** reglas con falsos positivos que enseñan al agente a esquivarlas. Una regla ruidosa se afina o se quita.
- **Un bucle lento:** lint con tipos o `tsc` completos en cada edición, que multiplican el tiempo de cada issue.
- **Una PR gigante de "arreglar todo el lint"** en un proyecto empezado, o un proyecto parado hasta pagar la deuda.
- **Más contexto fijo en cada sesión:** las reglas viven en ficheros de configuración, no en prosa inyectada.
- **Que el agente se apruebe a sí mismo** un cambio de regla.

## Diseño

### 1. Dónde vive cada cosa

- **Reglas del kit (`rules/core.md`):** se añaden 4 o 5 líneas y nada más:
  - El lint, los tipos y las comprobaciones de estructura en verde son parte de "terminado".
  - Nunca desactives, debilites ni esquives una regla (`eslint-disable`, `@ts-ignore`, `@ts-nocheck`, `as any`, editar su configuración, `--no-verify`). Si una regla te parece mal, se propone el cambio (sección 5).
  - Si una convención se puede comprobar con una herramienta, propón la regla en vez de escribirla en un `.md`.
  - La sección "Automejora" cambia en ese sentido: antes de apuntar una convención en una skill o en `AGENTS.md`, intenta que sea una regla.
- **Skill nueva `kit-reglas`:** todo el detalle. La base, la escalera de reglas, el formato de los mensajes, el trinquete y el procedimiento de aprobación, con `references/` para el catálogo y las plantillas y `scripts/` para lo mecánico. Solo se carga cuando se usa.
- **Configuración en cada repo:** `eslint.config.*`, `tsconfig.json`, `knip` y `dependency-cruiser` (o lo que elija la skill), más el fichero de excepciones del trinquete si hay deuda. El agente ve una regla solo cuando le falla, con su mensaje de remedio.

### 2. Base obligatoria (TS)

La base son unos mínimos; lo concreto lo decide el builder consultando versiones en el registro, nunca de memoria:
- **`tsconfig` estricto:** `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `verbatimModuleSyntax`, `noImplicitOverride`, `noFallthroughCasesInSwitch`.
- **`typescript-eslint` `strictTypeChecked`:** en error, `no-explicit-any`, `no-floating-promises`, `ban-ts-comment` (solo `@ts-expect-error` con descripción, si se permite) y `reportUnusedDisableDirectives`.
- **Directivas en línea prohibidas:** `linterOptions.noInlineConfig: true`. Si un repo necesita excepciones, van en la configuración con su porqué, nunca en el código.
- **Código muerto y huérfanos:** `knip` (ficheros, exports y dependencias sin uso), con sus entry points configurados (Astro, scripts, tests) para que no dé falsos huérfanos.
- **Imports del proyecto:** el alias del proyecto en vez de rutas relativas largas, con `no-restricted-imports` cuando el repo tenga alias.
- **Python** (si el repo lo tiene): `ruff` y `pyright` estricto. **Bash:** `shellcheck`.

### 3. Reglas propias del proyecto: la escalera

Para cada convención, el peldaño más barato que la cubra. Esta escalera va en la skill:
1. **Configuración:** `no-restricted-imports` o `no-restricted-syntax` con selector y `message`. Por ejemplo, "nada de `<button>` a pelo: usa `@/ui/Button`" o "`fetch` solo dentro de `src/api/`".
2. **Regla de `ast-grep`:** para patrones sin tipos, también en Python y bash.
3. **Regla de ESLint a medida, con tests (`RuleTester`):** cuando hace falta información de tipos o lógica entre nodos.
4. **Test de estructura (`dependency-cruiser` o equivalente):** capas, fronteras entre carpetas y ciclos, que una regla por fichero no ve.

Catálogo de partida para proponer, según lo que use el repo:
- i18n: `no-literal-string` en JSX, con lista blanca para atributos y tests.
- Tokens de diseño: Tailwind sin valores arbitrarios ni clases desconocidas, o colores a pelo prohibidos en CSS-in-JS.
- Componentes propios obligatorios.
- Capas de carpetas.
- Convención de la API: un cliente único, sin `fetch` suelto.

Cada mensaje de error dice qué hacer y nombra la alternativa exacta. Por ejemplo: "Color suelto: usa un token de `src/styles/tokens.css` (por ejemplo `text-primary`); no añadas colores sin token." Si es seguro, incluye autofix.

### 4. Proyectos empezados: el trinquete

- La misma base, y lo que hoy falla se congela con las supresiones de ESLint (`eslint-suppressions.json` versionado; para lo que no sea ESLint, un mecanismo equivalente que elija el builder, por ejemplo una lista base de `knip`).
- El código nuevo tiene que cumplir, y todo fichero que se toque queda a cero deuda en la misma PR (sección 10).
- El fichero de excepciones solo puede encoger. Una comprobación del CI y de `fusionar` rechaza una PR que añada entradas y obliga a podar (`--prune-suppressions`) las que ya no hacen falta.
- La deuda baja sola: `kit-scout` (o `kit-reglas` en modo limpieza) propone issues de limpieza acotados (una regla o una carpeta cada uno) a partir del fichero.
- En un proyecto nuevo ese fichero no existe y nada de esto se carga.

### 5. Aprobación de reglas

Una regla nueva, cambiada o quitada, una excepción nueva en la configuración o un fichero de excepciones que crece, todo pasa por Dru. Hay tres situaciones:
- **En una sesión con Dru** (`kit-reglas` o un trabajo interactivo): el agente explica la regla y Dru dice sí o no allí mismo.
- **En `kit-run` autónomo:** el agente sigue trabajando, pero mete el cambio de regla en un commit propio de la PR del issue. Publica en la PR un comentario con marcador `kit-regla` con:
  - qué prohíbe;
  - por qué;
  - un ejemplo del mensaje de error;
  - qué código existente rompe y cómo queda;
  - una valoración crítica: falsos positivos posibles y si cabe un peldaño más barato.

  Avisa con `kit-notify.sh` y deja el issue en `necesita-respuesta`. Si Dru aprueba, se fusiona como siempre. Si rechaza, el agente quita ese commit y sigue sin la regla.
- **En repos con `"flujo": false`:** como en la sesión con Dru. `kit-revisar` señala los cambios de reglas del diff local para que el agente los consulte.

La garantía mecánica: `fusionar` no fusiona una PR que toque los ficheros de reglas sin la aprobación de Dru registrada en esa PR. Cómo se registra lo decide el builder; algo que el agente no haga en el camino normal, coherente con los marcadores HTML que ya usa el kit. **Limitación conocida:** si el agente usa la misma cuenta de `gh` que Dru, un agente que intente engañar a propósito podría falsificar la aprobación. Contra el caso real (el agente descuidado) la barrera es sólida. Si hace falta que sea absoluta, el kit tendría que usar una cuenta de `gh` distinta. Fuera de alcance por ahora.

### 6. Blindaje contra las trampas

- **En el código:** `noInlineConfig`, `ban-ts-comment` y `no-explicit-any` hacen que las trampas en línea fallen en el propio lint.
- **Hook `PreToolUse` en Edit/Write** (Claude Code): sale con código 2 si una edición de trabajo normal toca los ficheros de reglas o mete `eslint-disable`, `@ts-ignore`, `@ts-nocheck` o `as any`. El mensaje le dice al agente que proponga el cambio por la sección 5. Durante el flujo aprobado (la skill `kit-reglas` o el commit de regla de `kit-run`) se permite; el builder decide cómo distinguirlo sin que eso abra una puerta trivial.
- **Bash:** `--no-verify`, `HUSKY=0`, `LEFTHOOK=0` y similares, bloqueados por hook o reglas `deny`. La regla del kit ya lo prohíbe en prosa.
- **El CI es la última palabra:** corre la base, las reglas del proyecto, `knip`, la estructura y el trinquete. Ningún hook local sustituye al CI.

### 7. Cuándo corre cada cosa

- **Durante la edición** (hook `PostToolUse`, Claude Code): lint rápido del fichero editado, de segundos. Si el repo lo permite, oxlint o Biome; si no, ESLint solo sobre ese fichero. El código 2 devuelve los errores al agente en el momento.
- **Al terminar el turno** (hook `Stop`): `tsc --noEmit` y lint con tipos de lo cambiado. Sin suites completas.
- **Pre-commit:** la política actual del kit (ligero, segundos, `verificar.rapido`), ahora con la base dentro.
- **CI** (`verificar.completo` o el CI del repo): todo, también `knip`, la estructura y el trinquete.

**Rendimiento (requisito de Dru):** todo tiene que ser rápido y no puede reventar los recursos del Mac, donde corren varias sesiones de agentes a la vez.
- **Por edición:** lint del fichero editado, sin tipos y con caché, en unos 2 s como máximo. Nunca lanza `tsc` ni lint con tipos del proyecto.
- **Fin de turno:** `tsc` incremental (`--incremental` o `tsc -b`, con su `.tsbuildinfo`) y lint con tipos solo de los ficheros cambiados, con caché.
- **Lo pesado (`knip`, estructura, lint con tipos completo):** en el CI y, sin CI, en el gate local. No en los hooks.
- **Sin acumular procesos:** el hook no lanza otro si ya hay uno corriendo para la misma sesión y repo. Si el lint con caché todavía no ha bajado de unos 2 s, el hook usa un linter más rápido (oxlint o Biome) para lo de por edición.
- **Medido, no supuesto:** el builder mide los tiempos en un repo real del tamaño de los de Dru (primera ejecución y con caché) y los anota. Un hook que pase del objetivo se aligera antes de darlo por bueno.

### 8. Codex y OpenCode

Los hooks de Claude Code no corren en Codex ni en OpenCode. Lo portable, y lo que garantiza las reglas, es la configuración del repo, el pre-commit y el CI. Lo que se añade donde se pueda:
- **Codex:** el plugin ya carga `hooks/hooks.json` (con la aprobación por `/hooks`). El builder comprueba si los eventos de edición y de fin de turno existen y funcionan igual, y lo marca como verificado o sin verificar en `AGENTS.md`.
- **OpenCode:** el plugin de `.opencode/plugins/` puede engancharse a las ediciones si la API lo permite (V1 y V2). El builder lo comprueba.
- Si no hay equivalente, esa herramienta se queda con pre-commit y CI, sin pérdida de garantía, solo de velocidad de corrección.

### 9. Integración con el kit

- **`kit-on`:** al activar (o en modo actualizar), detecta si el repo tiene la base y, si no, lanza `kit-reglas`. La base es obligatoria, pero Dru aprueba cada pieza y su configuración concreta. Sigue la política actual: nada se instala sin el OK de Dru, y los cambios del hook y del CI se hacen como hoy.
- **Repos ya activados:** Dru lanza `kit-reglas` una vez, o se lo sugiere `kit-on` al actualizar.
- **`kit-run`:** el lint en verde forma parte de terminado, y se aplica la sección 5 cuando descubre una convención.
- **`kit-scout`:** puede proponer reglas (como `propuesta`, con la misma explicación crítica) e issues de limpieza de la deuda.
- **El marcador `.agents-kit.json`:** si hace falta declarar los ficheros de reglas para el blindaje y para `fusionar`, va en una clave nueva de la lista blanca de `scripts/lib/config.sh` (podría reutilizar o parecerse a `protegido`).

### 10. Decisiones técnicas tomadas (decisión de Claude, no de Dru)

- **Hooks en el plugin**, en `hooks/hooks.json`, no en `.claude/settings.json` de cada repo. Se mantienen inertes sin marcador, con `"reglas": false` o sin la base instalada (como `session-start`). Así un agente no los borra editando el repo y se actualizan con el kit. Coste aceptado: Codex pide aprobarlos otra vez con `/hooks` en cada versión que los cambie.
- **Tocar un fichero con deuda obliga a limpiarlo (decisión de Dru).** Si una PR modifica un fichero que tiene entradas en el fichero de supresiones o en la línea base de `tsc`, esa PR deja ese fichero a cero deuda. La limpieza va en un commit propio dentro de la PR. Así la deuda baja con el trabajo normal hasta llegar a cero. Hay que añadir una excepción explícita a "nada de refactors de paso" de `rules/core.md`: limpiar la deuda de lint y tipos de los ficheros que tocas es parte del cambio. La comprobación es mecánica (CI y `fusionar`): ningún fichero cambiado en la PR puede seguir con supresiones ni errores de la línea base.
- **Deuda de `tsc` en proyectos empezados:** línea base de errores versionada. El hook `Stop` y el CI fallan solo con errores nuevos frente a esa línea base. El hook `Stop` bloquea (código 2) solo por errores nuevos de lo cambiado; la deuda vieja no lo dispara.
- **`kit-run` y la propuesta de regla:** el issue termina sus rondas y el CI con la regla incluida, y aparca justo antes de `fusionar`, con el comentario `kit-regla`, el aviso y `necesita-respuesta`. Si Dru aprueba, se fusiona. Si rechaza, el agente quita el commit de la regla, repite la verificación y hace una ronda de revisión nueva sobre lo que cambió.
- **Ficheros de reglas:** una lista declarada en el marcador con un valor por defecto. Incluye:
  - las configuraciones de lint, tipos, `knip` y estructura;
  - los ficheros de supresiones y líneas base;
  - las reglas a medida del repo;
  - la configuración del pre-commit y `.github/workflows/`;
  - `.agents-kit.json`.

  De `package.json` solo cuentan los scripts de lint y tipos y quitar dependencias de lint, no añadir dependencias normales.
- **Repos con Biome u oxlint:** la base con tipos va en ESLint con `typescript-eslint`. Biome u oxlint se quedan si el repo ya los usa y pueden ser el lint rápido del hook por edición. Las supresiones del trinquete son las de ESLint; las reglas que ya cubre el otro linter no se duplican.

## Restricciones

- Las del kit:
  - lo mecánico en scripts `kit-*` con sus códigos de salida y su línea `FIN:`;
  - mensajes en español, sin rayas largas;
  - tests de bash con stubs en `tests/`;
  - nada se instala ni se cambia en un repo sin el OK de Dru;
  - el árbol de Dru no se toca (worktrees).
- Versiones de dependencias consultadas en el registro, nunca de memoria.
- El hook por edición tiene que durar segundos.
- Las mismas reglas para todas las herramientas: la garantía no puede depender de los hooks de Claude Code.

## Lo que queda para el builder

- Los nombres finales (skill, marcador de comentario, clave del marcador).
- Las herramientas concretas dentro de cada peldaño (ESLint u oxlint en el hook rápido, `dependency-cruiser` o `eslint-plugin-boundaries`), según el repo.
- El mecanismo exacto de registro de la aprobación y de cómo el hook distingue el flujo aprobado.
- Cómo se reparte entre la skill y los scripts.
- El equivalente del trinquete para lo que no es ESLint.
- La verificación real en Codex y OpenCode.

## Fuentes

- Anthropic, buenas prácticas de Claude Code: https://code.claude.com/docs/en/best-practices y hooks: https://code.claude.com/docs/en/hooks
- Factory, linters para dirigir agentes: https://factory.com/using-linters-to-direct-agents y su plugin de ejemplo: https://github.com/Factory-AI/eslint-plugin
- OpenAI, harness engineering (copia leída; el original devolvió 403): https://ericfode.github.io/agent-harness-wiki/raw/articles/openai-harness-engineering
- Supresiones de ESLint: https://eslint.org/docs/latest/use/suppressions
- oxlint con plugins JS: https://oxc.rs/docs/guide/usage/linter/js-plugins
- Código muerto con agentes: https://stevekinney.com/courses/self-testing-ai-agents/dead-code-detection
