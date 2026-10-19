---
name: kit-scout
description: Revisa el repo en busca de bugs, tests que faltan, deuda y docs obsoletas, y abre hasta 5 issues `propuesta` para que Dru los apruebe. Úsala cuando Dru escriba kit-scout.
---

# kit-scout

Buscas trabajo que valga la pena y lo propones como issues. Nunca los dejas listos para `kit-run`: eso lo decide Dru.

Ejecuta los scripts como `"${CLAUDE_PLUGIN_ROOT}/scripts/<nombre>"`; si esa variable está vacía, la raíz del plugin está dos directorios por encima del directorio base de esta skill.

Lee siempre la salida completa de cada script y su código de salida; nunca la recortes con `head` ni `tail`.

## Pasos

1. **Marcador.** `git rev-parse --show-toplevel` da la raíz. Si no existe `<raíz>/.agents-kit.json`, di `kit no activado: ejecuta kit-on` y para.
2. **Buscar.** Lee `AGENTS.md` y recorre el código. Busca:
   - Bugs con un escenario concreto que falla.
   - Tests que faltan en caminos importantes o de error.
   - Duplicación de lógica.
   - Dependencias viejas (consulta el registro, no la memoria).
   - Deuda de las skills del proyecto (`.agents/skills/`): hinchadas, duplicadas, obsoletas o que contradicen el código.
   - `AGENTS.md` desactualizado frente al repo (comandos, stack, mapa).
   - Si el repo no tiene CI (`.github/workflows/` vacío o inexistente), puedes proponer añadirlo.

   Antes de proponer algo, mira los issues abiertos (`gh issue list --state open`) para no repetir.
3. **Elegir.** Como máximo 5 issues por ejecución, los de más valor. Cada uno es un objetivo completo de punta a punta.
4. **Crear.** Por cada uno, escribe el cuerpo con la plantilla de `skills/kit-plan/references/issue.md` del plugin en un fichero temporal (`mktemp`). En "Supuesto" pon la evidencia encontrada (ruta:línea, comando y salida). Ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" crear <raíz> "<título>" <fichero> propuesta`.
   - Exit 0: la URL es la línea `FIN: <url>`.
   - Exit 1 con `ya existe #<n> con ese título`: ya estaba propuesto; sigue con el siguiente.
   - Exit 2: error de entorno. Explícalo y para.
5. **Resumen.** Lista las URLs con una línea de por qué importa cada una. Explica a Dru cómo aprobar: en cada issue que quiera, cambiar la etiqueta `propuesta` por `listo` (`gh issue edit <n> --remove-label propuesta --add-label listo`). Los que no quiera, que los cierre.
