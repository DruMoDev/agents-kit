## Flujo del kit: issues y PR

- Todo el código entra en la rama por defecto por PR con squash merge. Un `AGENTS.md` no lo anula.
- Un issue = una PR, con un solo objetivo. Nada fuera de scope, ni refactors de paso: lo que encuentres por el camino se abre como issue `propuesta`.
- Bug o mejora encontrada haciendo otra cosa: antes de contarlo, un subagente con contexto limpio intenta refutarlo (reproducirlo, leer el código, mirar si ya está resuelto en la rama por defecto). Si se sostiene, en una sesión con Dru se le propone con la evidencia y, con su OK, se abre el issue y se resuelve por debajo con `kit-run <N>` (en segundo plano y en su propio worktree), sin bloquear el trabajo en curso ni tocar sus ficheros. Dentro de un `kit-run` autónomo no se espera a nadie: se abre como `propuesta` con la evidencia.
- La verja es el CI completo en la PR. El hook de pre-commit es ligero, de segundos: formato, lint estricto y tests de lo cambiado. Nunca suites completas ni builds en el hook: repiten el CI y cuestan minutos por commit a cada agente. Los comandos del repo van en `verificar.rapido` y `verificar.completo` del marcador.
- Contenido: `.agents/skills/`, `AGENTS.md` y las rutas que el proyecto declare en `contenido` (`.agents-kit.json`) pueden ir directas a la rama por defecto en una sesión con Dru. Van por PR igualmente lo que haga `kit-run` (la mejora de una skill va en la PR del issue), un cambio mixto (contenido y código) y todo lo que vaya a una rama protegida.
- Ningún worktree muerto: en cuanto su trabajo está en la rama por defecto, se borra con su rama (`kit-run` lo hace con `kit-worktree.sh barrer`). Solo sobrevive el de un trabajo vivo.
- Changelog: si el repo lleva `CHANGELOG.md`, cada PR que cambie algo para quien usa la app añade su entrada (el formato lo describe la cabecera del fichero).
- Automejora: va en la misma PR que la provocó; en una sesión con Dru sin PR, directa a la rama por defecto (las skills y `AGENTS.md` son contenido).
