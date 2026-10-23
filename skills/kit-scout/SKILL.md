---
name: kit-scout
description: Revisa el repo en busca de bugs, tests que faltan, deuda y docs obsoletas, y abre hasta 5 issues `propuesta` para que Dru los apruebe. Úsala cuando Dru escriba kit-scout.
---

# kit-scout

Buscas trabajo que valga la pena y lo propones como issues `propuesta`, que quedan fuera del reparto de `kit-run` hasta que Dru los apruebe.

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

   Antes de proponer algo, busca duplicados entre los issues abiertos (`gh issue list --repo <slug> --state open --limit 300 --json number,title,labels`, con `<slug>` = `owner/repo` del remoto `origin`) por dos o tres palabras del problema, no por el título que le ibas a poner. Si ya existe, no lo repitas.
3. **Elegir.** Como máximo 5 issues por ejecución, los de más valor. Cada uno es un objetivo completo de punta a punta.
4. **Crear.** Por cada uno, escribe el cuerpo con la plantilla de `skills/kit-plan/references/issue.md` del plugin en un fichero temporal (`mktemp`). En "Lo verificado" pon la evidencia encontrada (ruta:línea, comando y salida); lo que no hayas comprobado va en "Lo que solo se cree", marcado como sin verificar. Pon tú la prioridad (`alta`, `media` o `baja`) y ejecuta `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" crear <raíz> "<título>" <fichero> --prio <prio> --entorno <entorno> --propuesta`, con `--entorno nube|mac` (`mac` si solo se puede hacer en el Mac de Dru: sesiones de navegador logueadas, secretos o ficheros que no están en el repo, apps o hardware locales; `nube` si basta un clon del repo; si el `AGENTS.md` del proyecto da un criterio, manda ese), (más un `--etiqueta <área>` por cada área del proyecto que aplique y ya exista en el repo).
   - Exit 0: la URL es la línea `FIN: <url>`.
   - Exit 1 con `ya existe #<n> con ese título`: ya estaba propuesto; sigue con el siguiente.
   - Exit 2: error de entorno. Explícalo y para.
5. **Resumen.** Lista las URLs con su prioridad y una línea de por qué importa cada una. Explica a Dru cómo aprobar: en cada issue que quiera, quitar la etiqueta `propuesta` (`gh issue edit <n> --repo <slug> --remove-label propuesta`), y si quiere, cambiar la prioridad. Los que no quiera, que los cierre o les ponga `someday`.
