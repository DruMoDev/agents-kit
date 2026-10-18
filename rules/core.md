# Reglas de ingeniería (siempre en contexto)

Estas reglas se aplican a toda tarea en este repositorio. El contexto propio del proyecto está en `AGENTS.md`.

## Escribe menos código (senior vago)

El mejor código es el que nunca se escribe. Antes de escribir código, detente en el primer peldaño que se sostenga:

1. ¿Hace falta que exista? (YAGNI)
2. ¿Este código ya lo tiene? Reutiliza el helper, la utilidad o el patrón existente; nunca lo reescribas.
3. ¿Lo hace la librería estándar? Úsala.
4. ¿Lo cubre una funcionalidad nativa de la plataforma o el framework? Úsala.
5. ¿Lo resuelve una dependencia ya instalada? Úsala.
6. ¿Cabe en una línea? Que sea una línea.
7. Solo entonces: escribe el mínimo código que funcione.

Sube la escalera solo después de entender el problema: lee la tarea y el código que toca, y recorre antes el flujo real de punta a punta. El cambio más pequeño en el sitio equivocado es un segundo bug, no eficiencia.

- Borrar antes que añadir. Aburrido antes que ingenioso. El mínimo de ficheros posible.
- Nada de abstracciones, wrappers ni boilerplate que nadie ha pedido.
- Ninguna dependencia nueva sin justificarla.
- Lo repetitivo y determinista va a scripts, no a instrucciones.
- Cuestiona las peticiones complejas: "¿de verdad necesitas X, o lo cubre Y?"
- Sin compatibilidad hacia atrás en proyectos personales: cambia el código y sus llamadas, sin shims ni rutas antiguas.
- No seas vago con: validación de entradas en fronteras de confianza, manejo de errores que evita pérdida de datos, seguridad, accesibilidad, ni nada pedido explícitamente.

## Fallos a evitar

- No actúes antes de investigar el código. Lee primero los ficheros relevantes, los caminos de llamada y las restricciones.
- No parchees un módulo sin entender sus contratos: propiedad de los datos, significado de los campos, invariantes, consumidores aguas abajo. Corrige la primera violación del contrato, no el síntoma.
- No dupliques lógica que ya existe en otro sitio.
- No añadas clases donde bastan funciones, ni tipos nuevos cuando encajan los compartidos existentes.
- No te tragues errores: ningún `catch` vacío, ningún resultado de error ignorado, ninguna promesa rechazada sin tratar.
- No añadas tests de relleno, ni tests frágiles que solo comprueban constantes internas exactas, valores por defecto, textos o cableado.

## Tests y verificación

- Antes de escribir tests, lee `rules/testing.md`.
- Funcionalidad nueva sale con tests (camino feliz + camino de error como mínimo).
- e2e siempre que haya algo que comprobar de punta a punta, con los casos límite explícitos.
- Verde no es validado: si el cambio altera el resultado visible, compruébalo con casos reales y contra la versión anterior.
- No afirmes nada que no hayas ejecutado. Un supuesto sobre una herramienta externa no vale hasta ejecutarlo.
- No declares "arreglado" ni "hecho" sin reproducir el problema y volver a probar tras el cambio.

## Depuración

- Reproduce el bug antes de cambiar código.
- Aísla la etapa donde el comportamiento se desvía primero de lo esperado; un ejemplo que falla es un síntoma, no la causa raíz.
- Prefiere arreglos en la fuente de verdad o en la etapa del pipeline antes que parches en la capa visible del síntoma.
- Valida el arreglo de punta a punta antes de darlo por hecho.

## Arquitectura

- Fuente única de verdad: cada hecho, constante y tipo vive en un solo sitio; todo lo demás lo referencia.
- Ficheros pequeños con una sola responsabilidad y nombres autodescriptivos. Los puntos de entrada orquestan; los módulos de dominio contienen la lógica.
- Mantén la UI separada de la lógica.
- No dejes código huérfano ni sin usar. Si sustituyes algo, borra la versión vieja.

## Producto vs implementación

- Lo técnico lo decides tú, sin preguntar.
- El producto (funcionalidad, comportamiento, lo que ve quien usa la app) se pregunta a Dru: una pregunta cada vez, sin micro-preguntas.
- Un issue = una PR, con un solo objetivo. Nada fuera de scope, ni refactors de paso: lo que encuentres por el camino se abre como issue `propuesta`.

## Flujo git

- Todo entra en `main` por PR con squash merge.
- Ramas y worktrees se borran tras el merge.
- Changelog: cada PR que cambie algo para quien usa la app añade su entrada en `CHANGELOG.md` (el formato lo describe la cabecera del fichero).

## Automejora

Al terminar una tarea, en la misma PR que la provocó:

- ¿Aprendiste algo que evitaría un error futuro? Regístralo en la skill del proyecto más cercana, o crea una nueva en `.agents/skills/` (`SKILL.md` corto con cuándo usarla, flujo y restricciones; detalle en `references/`; lo determinista en `scripts/`).
- ¿Cambió el stack, los comandos o el mapa del repo? Corrige `AGENTS.md`.
- No dejes descubrimientos importantes solo en el chat, los planes o los resúmenes finales.

## Docs y specs

- Antes de añadir docs, lee `rules/docs-discipline.md`.
- Los ficheros de instrucciones (AGENTS.md, CLAUDE.md, skills) no tienen estado: contexto + reglas, nunca cronología ni estado.
- Specs y planes son andamiaje efímero: bórralos una vez implementados (git guarda el historial). Conserva solo los aprendizajes no obvios, como docs pequeños referenciados desde donde aplican.

## Reglas duras

- Ningún secreto hardcodeado: variables de entorno, validadas al arrancar.
- Valida todas las entradas en las fronteras de confianza.
- Ningún log de depuración en caminos de código de producción.
- No fijes versiones de dependencias de memoria: consulta el registro para ver las versiones actuales.

## Comunicación

- Muestra rutas de fichero clicables.
- Explica qué has hecho y por qué.
- Planes ultracortos. Termina cada plan con la lista de preguntas sin resolver.
