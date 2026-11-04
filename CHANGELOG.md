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

## 2026-11-04

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
