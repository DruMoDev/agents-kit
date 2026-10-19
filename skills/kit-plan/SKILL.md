---
name: kit-plan
description: Convierte un objetivo de producto en issues `listo` de GitHub, acordando el comportamiento con Dru. Úsala cuando Dru escriba kit-plan <objetivo> o pida planificar trabajo en issues.
---

# kit-plan

Uso: `kit-plan <objetivo>`. Tú hablas de producto con Dru y escribes los issues; el script los crea.

Ejecuta los scripts como `"${CLAUDE_PLUGIN_ROOT}/scripts/<nombre>"`; si esa variable está vacía, la raíz del plugin está dos directorios por encima del directorio base de esta skill.

Lee siempre la salida completa de cada script y su código de salida; nunca la recortes con `head` ni `tail`. Ante cada código distinto de 0, dile a Dru en español qué pasó y qué tiene que hacer.

## Pasos

1. **Marcador.** `git rev-parse --show-toplevel` da la raíz. Si no existe `<raíz>/.agents-kit.json`, di `kit no activado: ejecuta kit-on` y para.
2. **Producto.** Lee `AGENTS.md` y el código que toca el objetivo para no preguntar lo que ya se sabe. Después habla con Dru de producto: comportamiento, casos, mensajes que se ven y lo que no entra. Una pregunta cada vez. Lo técnico no se pregunta: lo decides tú.
3. **Desglose.** Propón la lista de issues: título y una línea por cada uno. Cada issue es un objetivo completo de punta a punta que se puede probar solo: nada de trocear por capas o líneas de código, y nada de PRs enormes. Espera una aprobación explícita de Dru; si pide cambios, vuelve a proponer.
4. **Crear.** Por cada issue, escribe el cuerpo con la plantilla de `references/issue.md` en un fichero temporal (`mktemp`) y ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" crear <raíz> "<título>" <fichero> listo`. En "Verificado y supuesto" separa lo que comprobaste en el código de lo que das por hecho.
   - Exit 0: la URL es la línea `FIN: <url>`.
   - Exit 1 con `ya existe #<n> con ese título`: no lo dupliques; anótalo para el resumen.
   - Exit 2: error de entorno (gh, remoto). Explícalo, di qué issues quedan sin crear y para.
5. **Resumen.** Lista las URLs creadas y los que ya existían. `kit-run` los coge por orden de número.
