# Changelog

<!--
Formato fijo (lo lee la web de changelogs). Fecha descendente: lo más reciente arriba.
Cada entrada tiene versión corta (obligatoria) y versión extendida (opcional, esperada en cambios visibles).

- Versión corta: `### <Tipo>: <título de una línea> · [#PR](enlace)`
- Tipos cerrados: Nuevo | Mejora | Arreglo | Interno
- Versión extendida: qué cambia para quien usa la app, en pocas frases; captura si el cambio es visual
  (guardada en docs/changelog/ con el número de PR en el nombre); ejemplo práctico si ayuda.
- Texto para quien usa la app, no técnico.

Ejemplo:

## 2026-10-18

### Nuevo: Login con Google · [#12](https://github.com/<owner>/<repo>/pull/12)
Ahora puedes entrar con tu cuenta de Google en un clic.

En la pantalla de acceso aparece el botón "Continuar con Google"; si la cuenta
ya existía con ese email, se vincula sola.

![Pantalla de acceso](docs/changelog/12-login.png)
-->

## 2026-11-05

### Mejora: las copias de la comprobación de fin de turno se ponen al día solas con el kit · [#57](https://github.com/DruMoDev/agents-kit/pull/57)
Cada repo guarda una copia de los scripts del kit que comprueban el lint y los tipos al final del turno. Antes se quedaban en la versión con la que se instalaron hasta que alguien las copiaba a mano y aprobaba el cambio. Ahora el siguiente `kit-run` de cada repo avisa de las copias viejas y las pone al día solo, sin pedir aprobación, siempre que sean la copia exacta del kit (con los ajustes propios del repo intactos).

### Arreglo: cada subagente revisa su propio lint y los fallos llegan resumidos · [#55](https://github.com/DruMoDev/agents-kit/pull/55)
Cuando una sesión de Claude Code lanzaba subagentes, la comprobación de fin de turno bloqueaba a la sesión principal por el código que los subagentes aún estaban escribiendo, y a ellos nunca los revisaba. Ahora cada subagente revisa lo que él cambió al terminar, y la sesión principal solo lo suyo.

La salida del lint ya no se vuelca entera en la conversación: llegan las primeras líneas y el resumen final, con la ruta del fichero que tiene la salida completa. En Claude Code se muestra como aviso de la comprobación y no como error del hook.

## 2026-11-04

### Interno: la web vuelve a usar la comprobación de fin de turno actual del kit · [#53](https://github.com/DruMoDev/agents-kit/pull/53)
La comprobación de fin de turno de la web era una copia de una versión anterior del kit. Ahora es la de la plantilla actual, con sus ajustes propios de la web (ficheros `.astro`, TypeScript 7 y la generación de tipos de Astro), y el estado de las reglas ya no la marca como desfasada. No cambia nada de lo que se comprueba.

### Interno: kit-reglas explica cómo sacar los entry points de knip en monorepos con Workers · [#52](https://github.com/DruMoDev/agents-kit/pull/52)
Cuando `knip` da casi todo como código sin uso, la guía de la base de reglas explica ya que casi siempre le faltan puntos de entrada, no que el código esté muerto, y cómo encontrarlos: el `main` de cada Worker (y por qué el plugin de Wrangler de `knip` no lo ve si el `wrangler.toml` está en un subdirectorio), los scripts sueltos, los tests y los ficheros que se lanzan por su ruta desde otro lenguaje o desde la configuración.

### Mejora: kit-reglas reconoce los repos Python y prepara solo los comandos del lint · [#51](https://github.com/DruMoDev/agents-kit/pull/51)
Un repo Python con `ruff.toml`, `requirements.txt`, `setup.py` o ficheros `.py` ya cuenta como Python, aunque no tenga `pyproject.toml`, y el estado de sus reglas dice si usa `ruff` (y qué reglas tiene activadas) y `pyright`. Al instalar la base, el kit saca solo los comandos de lint que van en el marcador (ESLint, `ruff` con el intérprete del repo, `shellcheck`), así que ya no tienes que aprobar líneas de comandos: te explica en una frase qué se comprueba al editar y al acabar cada turno.

### Mejora: la base de reglas JS pide strictNullChecks y avisa de directivas en línea y plantillas viejas · [#49](https://github.com/DruMoDev/agents-kit/pull/49)
En un proyecto JavaScript, la base exige ahora `strict` (o `strictNullChecks`) en el `tsconfig`: sin él, varias reglas del lint estricto fallaban en cada fichero con un aviso que no dice nada del código. `kit-reglas` cuenta además los `eslint-disable` y compañía que ya había en cada proyecto, que con la base dejan de funcionar, y los migra a la configuración, con su porqué, antes de congelar la deuda. Y dice si las copias de `turno.sh` o `tsc-base.mjs` de un proyecto son de una versión vieja del kit, para volver a copiarlas.

### Interno: la verificación completa del repo pasa en un worktree recién creado · [#45](https://github.com/DruMoDev/agents-kit/pull/45)
La verificación completa genera los tipos de la web antes de pasarle el lint, así que ya no sale en rojo en un worktree nuevo por algo que el cambio no ha tocado.

### Mejora: en Codex, kit-run avisa al arrancar si el sandbox no le deja trabajar · [#44](https://github.com/DruMoDev/agents-kit/pull/44)
Con el sandbox por defecto de Codex no hay red para GitHub ni permiso para escribir en el repositorio git, así que `kit-run` no podía reclamar, empujar ni fusionar y fallaba a mitad. Ahora para nada más empezar y dice cómo lanzar Codex (`--sandbox danger-full-access`). En OpenCode y en Claude Code no cambia nada: ninguno de los dos frena la fusión.

### Mejora: la base de reglas distingue los proyectos JavaScript de los TypeScript · [#42](https://github.com/DruMoDev/agents-kit/pull/42)
Un proyecto JavaScript con `tsconfig.json` solo para que el lint infiera tipos ya no recibe la base de TypeScript, que lo dejaba inservible con miles de avisos de `any` imposibles de arreglar sin anotar tipos. `kit-reglas` lo reconoce, lo marca como JS y le propone su propia base: el lint estricto con tipos sin las reglas que solo hacen ruido en JS sin anotar, y sin las opciones estrictas del `tsconfig`, que ahí no comprueban nada. Con esa base, `kit-run` trabaja en el proyecto. Activar `checkJs` queda como migración aparte.

### Interno: el test de la web que comprueba Access vuelve a pasar · [#40](https://github.com/DruMoDev/agents-kit/pull/40)
El test de punta a punta que comprueba que fuera de localhost se exige Access esperaba la respuesta de cuando Access aún no estaba configurado. Ahora espera el acceso denegado sin la sesión de Access.

### Mejora: en un monorepo, el lint de cada edición y de cada turno corre dentro de su app · [#38](https://github.com/DruMoDev/agents-kit/pull/38)
Mientras trabajan, los agentes ven el lint de cada app de un monorepo con su propia configuración y su deuda congelada, también la comprobación de tipos al terminar cada turno, y no solo la de la raíz. El kit busca la app de cada fichero cambiado y lanza los mismos comandos dentro de ella; los ficheros que no son de ninguna app siguen en la raíz. Un repo de una sola app funciona como antes.

### Interno: la web de changelogs sin código muerto, vigilada por knip · [#37](https://github.com/DruMoDev/agents-kit/pull/37)
Quitados de la web un export y dos tipos que nadie usaba, y `knip` entra en la verificación completa: el código sin uso ya no puede volver a colarse. Los tres ficheros tocados quedan sin deuda de lint ni de tipos, sin cambiar lo que hace la web.

### Mejora: la base de reglas cubre cada app de un monorepo · [#35](https://github.com/DruMoDev/agents-kit/pull/35)
Con el kit en la raíz de un monorepo, la base de lint y tipos ya no se da por instalada solo porque la raíz no tiene TypeScript: el kit encuentra cada app TS (`web/`, `packages/<x>`...), comprueba su base en su carpeta y, si a alguna le falta, `kit-run` dice cuál. La deuda congelada de cada app solo puede bajar, igual que la de la raíz. Un repo de una sola app funciona como antes.

La web de changelogs de este repo ya tiene su base: lint estricto con tipos y su deuda de hoy congelada.

### Mejora: un revisor sin cuota ya no te pide nada si otro cubre su puesto · [#34](https://github.com/DruMoDev/agents-kit/pull/34)
Cuando un revisor se queda sin su límite de uso (las 5 horas de Codex o de Claude, por ejemplo) y otro modelo revisa su puesto, el resumen ya no lo cuenta como un problema que tengas que arreglar: sale una línea informativa ("sin cuota, vuelve sola, cubierto por ...") y no llega como aviso de acción. Un login caducado o un modelo que no existe siguen avisándote como antes, y también una cuota que deja un puesto sin revisar.

## 2026-11-03

### Arreglo: kit-run fusiona también en el modo auto de Claude Code · [#31](https://github.com/DruMoDev/agents-kit/pull/31)
En el modo auto, Claude Code bloqueaba la fusión de `kit-run` como "fusión sin revisión" aunque la PR hubiera pasado las rondas de revisión y el CI, y el issue se quedaba a medias. Ahora `kit-on` deja en el repo una regla de permiso que solo deja pasar esa fusión, y va en git, así que funciona en cualquier Mac sin configurar nada. Para los repos ya activados, relanza `kit-on` una vez. `kit-off` la quita.

### Nuevo: reglas de lint, tipos y estructura que los agentes no pueden saltarse · [#28](https://github.com/DruMoDev/agents-kit/pull/28)
La skill nueva `kit-reglas` instala en cada repo una base estricta de lint, tipos y estructura y convierte en reglas las convenciones del proyecto, explicándote cada una y aplicando solo lo que apruebas. En un repo con código hecho, lo que hoy falla se congela y solo puede bajar.

Mientras trabajan, los agentes ven el lint del fichero que acaban de editar y, al terminar cada turno, el de todo lo cambiado; no pueden desactivar una regla ni tocar su configuración sin proponerlo. Un cambio de reglas no se fusiona hasta que respondes con un comentario normal en el issue o en la PR, y ya no tienes que quitar etiquetas para que un issue que espera tu respuesta siga: basta con responder (`bloqueado` sí se sigue quitando a mano).
