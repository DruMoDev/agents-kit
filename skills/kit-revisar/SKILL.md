---
name: kit-revisar
description: Revisa con los revisores de varios modelos el cambio local, sin PR ni GitHub. Úsala cuando Dru escriba kit-revisar y antes de dar por terminado un cambio de código en un repo con "flujo": false.
---

# kit-revisar

Revisión de varios modelos sobre el diff local, para repos que siguen su propio flujo de git, PR y CI/CD (`"flujo": false` en `.agents-kit.json`) o para cualquier cambio que aún no está en una PR del kit. Los mismos puestos que `kit-run` (`revision.puestos`, con su foco, nivel, familia y fallback) revisan el árbol de trabajo contra la base; nada se publica en GitHub. Tú decides cada hallazgo y aplicas los que se sostienen; integrar el cambio (commit, push, PR) es cosa del flujo del repo, no de esta skill.

Ejecuta los scripts como `"${CLAUDE_PLUGIN_ROOT}/scripts/<nombre>"`; si esa variable está vacía, la raíz del plugin está dos directorios por encima del directorio base de esta skill. Abajo, `$PLUGIN` es esa raíz.

Lee siempre la salida completa de cada script y su código de salida; nunca la recortes con `head` ni `tail`. Ficheros temporales siempre en `~/.agents-kit/tmp/` (`mkdir -p ~/.agents-kit/tmp` y `mktemp ~/.agents-kit/tmp/<nombre>.XXXXXX`), nunca en el repo.

## Pasos

1. **Raíz.** `git rev-parse --show-toplevel` da la `<raíz>`. Si no existe `<raíz>/.agents-kit.json`, di `kit no activado: ejecuta kit-on` y para.
2. **Contexto.** Escribe en un fichero temporal, en dos o tres frases, para qué es el cambio y qué no entra (de la conversación, la tarea o los mensajes de commit). Los revisores lo leen en lugar del issue; sin ese texto solo tienen el diff.
3. **Base.** Por defecto, la revisión compara con `origin/<rama por defecto>` tal como está en el clon (no hace fetch). Si el repo integra en otra rama, o Dru dice desde dónde revisar, pásala con `--base <ref>`.
4. **Lanzar.** `"$PLUGIN/scripts/kit-bg.sh" lanzar <fichero> "$PLUGIN/scripts/kit-review-all.sh" <raíz> --local --contexto <fichero-contexto> [--base <ref>]` y espera con `"$PLUGIN/scripts/kit-bg.sh" esperar <fichero>` (límite de tu herramienta de al menos 10 minutos; repite mientras diga `sigue en marcha`; nunca esperes buscando procesos por nombre). La línea `SALIDA:` es su código de salida.
   - Añade `--implementador <familia>` (un nombre de `proveedores`) siempre en OpenCode, y siempre que el cambio lo escribió un subagente de otra familia que la de esta sesión: decide qué puestos van a otra familia. Exit 2 `pasa --implementador <familia>`: repite con esa opción.
   - No toques el árbol de trabajo mientras corre: un puesto que ve cambiar el repo queda sin confirmar (`integridad`).
   - Exit 1 `nada que revisar`: no hay cambios frente a la base; díselo a Dru. Exit 1 `indica la base con --base`: el clon no tiene `origin/<rama por defecto>`; pregúntale a Dru desde dónde. Exit 1 `sin puestos de revisión configurados`: revisa tú el cambio con todos los focos y dilo. Otro exit 1 o exit 2: díselo a Dru tal cual y para.
5. **Leer.** La salida da por puesto `ok`, `sin-confirmar (<motivo>: <detalle>)` o `fallback a ...`, líneas `aviso: ...`, `salidas: <dir>` y `FIN: <n> puestos, <m> sin confirmar, <h> hallazgos (<g> graves, <d> medios)`. Lee entero cada `<dir>/rev-<i>.out`. Un puesto sin confirmar nunca cuenta como "sin hallazgos": di cuál y por qué (con `acceso`, qué CLI hay que autenticar o qué modelo cambiar).
6. **Decidir.** Por cada hallazgo, compruébalo en el código (reprodúcelo si puedes) y decide: **aplicar** (falla de verdad y entra en el scope del cambio: arréglalo con su test) o **rechazar** con un motivo concreto (no se reproduce, ya cubierto en `ruta:línea`, fuera del scope). Lo que esté fuera del scope se lo cuentas a Dru con la evidencia, sin arreglarlo aquí. Pasa los tests rápidos del repo tras aplicar.
7. **Otra pasada.** Si aplicaste un arreglo grave o que cambia mucho código, relanza el paso 4 una vez sobre el árbol nuevo. No hagas más de tres pasadas: si sigue saliendo algo grave, para y cuéntaselo a Dru.
8. **Resumen.** Para Dru: cada hallazgo con su puesto y la decisión (aplicado o rechazado y por qué), los puestos sin confirmar, los avisos de login o cuota y qué ficheros cambiaste. No hagas commit, push ni PR salvo que Dru o el flujo del repo lo pidan.

## Desde el flujo propio del repo

El repo puede llamar a la revisión en el punto que decida (un hook de pre-push, un objetivo del `Makefile`, un paso de su propio script de entrega): `"<raíz del plugin>/scripts/kit-review-all.sh" <raíz> --local --estricto [--base <ref>] [--contexto <fichero>]` sale 1 si algún puesto queda sin confirmar o hay algún hallazgo grave o medio, y deja los informes en el directorio de `salidas:`. Tarda minutos: no lo pongas en un pre-commit.
