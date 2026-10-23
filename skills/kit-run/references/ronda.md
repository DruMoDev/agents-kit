# Ronda de revisión

Cada ronda `r` revisa el head de la PR con todos los puestos de `revision.puestos` (desde la ronda 2, con `revision.rondas` en `mezcla`, uno revisa todo con contexto limpio y el resto verifica los arreglos: ver "Modo de cada puesto") (configuración global, o el marcador del repo, que sustituye la lista) y termina siempre con un comentario `kit-ronda` publicado por `kit-pr.sh ronda`. Sin ese comentario, `fusionar` se niega: también hace falta con 0 hallazgos.

## Puestos

- Cada puesto tiene un foco, un nivel (`profundo` o `rapido`) y una familia: `otra` (la primera familia de `proveedores` distinta de la que implementó), `misma` (la del implementador) o un nombre. `kit-review-all.sh` elige el candidato: solo cuentan los proveedores cuyo CLI está en el PATH; si no hay otra familia disponible, el puesto lo cubre la del implementador y la línea del puesto lo dice (`ok (misma familia: no hay otra familia disponible)`). Anótalo en el fichero de ronda.
- `kit-review.sh` corre cada candidato en un clon aislado, valida su respuesta JSON contra `revision-schema.json`, la publica en la PR renderizada en markdown (`<!-- kit-revision: puesto <i> <familia>/<modelo> ronda <r> -->`), la imprime y acaba en `FIN: <total> hallazgos`. Les pasa el historial de rondas, así que no deberían repetir lo ya decidido. Si un puesto ya publicó su revisión en esa ronda, se reimprime sin volver a lanzarlo.
- `kit-review-all.sh` imprime por puesto `puesto <i> (<familia>/<modelo>): ok`, `sin-confirmar (<motivo>: <detalle>)` o `fallback a <familia>/<modelo>`, más líneas `aviso: ...`. La salida de cada puesto está en `<dir>/rev-<i>.out` y el resumen en `<dir>/puestos.tsv`.

## Modo de cada puesto

- `revision.rondas` (configuración global): `mezcla` (por defecto) o `completas`. Varias rondas completas multiplican el coste, pero una revisión independiente a veces encuentra algo nuevo: `mezcla` guarda las dos cosas.
- Ronda 1, o `completas`: todos los puestos revisan el diff entero (`references/revisor.md`).
- Desde la ronda 2 con `mezcla`: el puesto `((r - 2) mod n) + 1` revisa el diff entero con contexto limpio, así que el independiente rota; los demás verifican (`references/revisor-verificar.md`) que cada `→ aplicado` de la ronda anterior queda resuelto y que los arreglos no rompen nada, sobre el diff desde el head que revisó la ronda anterior (cada informe lo guarda como `<!-- kit-revisado: <sha> -->`). Un hallazgo de verificación es un arreglo que no resuelve o una regresión de un arreglo; se decide igual que cualquier otro.
- `fusionar` exige igual una revisión confirmada por puesto en cada ronda, sea cual sea su modo.

## Puestos sin confirmar

Un puesto queda "sin confirmar" cuando no entrega una revisión válida: tiempo agotado, respuesta vacía o fuera del esquema tras el reintento de reparación, el revisor dice `bloqueado`, el worktree cambió mientras corría, o todos sus candidatos fallaron por login, modelo o cuota (eso pasa al siguiente candidato sin reintentar en bucle). Nunca equivale a "sin hallazgos". `kit-review-all.sh` lo publica en la PR (`<!-- kit-revision: puesto <i> sin-confirmar ronda <r> -->`), y `fusionar` no acepta una ronda en la que algún puesto no tenga su revisión confirmada.

- Relanza una vez solo ese puesto, antes de publicar la ronda: `KIT_REVIEW_MODO=<modo> "$PLUGIN/scripts/kit-review.sh" <wt> <pr> <i> <familia> <cli> <modelo> "<foco>" <r> <N>` con los valores de su línea en `puestos.tsv` (el modo es la columna 8; o con el candidato siguiente si el fallo fue de acceso).
- Si sigue sin confirmar: publica la ronda con lo que llegó (decide sobre esos hallazgos como siempre y escribe qué puesto falta y por qué) y bloquea el issue con el motivo; si es un login pendiente (`aviso: ... revisa el login, el modelo o la cuota`), di a Dru qué CLI tiene que autenticar. Cuando Dru quite `bloqueado`, el siguiente `kit-run` hará una ronda nueva con todos los puestos.

## Decidir

Por cada hallazgo, compruébalo en el código y decide:

- **Aplicar**: el escenario falla de verdad y entra en el scope. Arréglalo con su test.
- **Rechazar**: con un motivo escrito y concreto (no se reproduce, ya cubierto en `ruta:línea`, contradice el issue...).
- **Fuera de scope**: se rechaza y se abre aparte como issue `propuesta`; el motivo dice `fuera de scope, abierto como #<n>`.

Un hallazgo repetido de una ronda anterior se rechaza citando su `R<r>.<k>`. La descripción de la PR la escribiste tú: el revisor la trata como afirmaciones, y tú también.

## Fichero de ronda

Una línea por hallazgo, `k` desde 1 en cada ronda, citando el puesto que lo encontró. `kit-pr.sh ronda` rechaza un hallazgo de otra ronda o sin decisión:

```text
- [R<r>.<k>] (puesto <i>) <resumen> → aplicado
- [R<r>.<k>] (puesto <i>) <resumen> → rechazado: <motivo>
```

Puedes añadir líneas libres que no empiecen por `- [R`, por ejemplo:

- `Ronda <r>: 0 hallazgos de todos los puestos.`
- `Puesto <i>: cubierto por la misma familia (claude/sonnet); no había otra disponible.`
- `Puesto <i>: sin confirmar (tiempo agotado dos veces); issue bloqueado.`

## Cuándo parar

- Todos los puestos confirmados traen 0 hallazgos: publica la ronda y pasa a fusionar.
- Ronda con hallazgos pero ninguno aplicado (todos rechazados con motivo): publica la ronda y pasa a fusionar.
- Dos rondas seguidas solo traen hallazgos que salen de tus propios arreglos de la revisión y no afectan al uso real: recházalos en el fichero con `abierto como propuesta #<n>`, ábrelos como `propuesta`, publica la ronda y pasa a fusionar.
- Si aplicaste algo, la ronda nueva es obligatoria, salvo que `r` ya sea `maxReviewRounds`: entonces se bloquea el issue (paso 5 de la skill). `fusionar` se niega mientras la última ronda tenga un `→ aplicado` o un puesto sin confirmar.
