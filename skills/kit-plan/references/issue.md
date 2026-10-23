# Plantilla del cuerpo de un issue

Lo leen `kit-run` y los revisores sin más contexto: todo lo acordado tiene que estar aquí. Frases cortas, sin relleno. Borra los comentarios.

```markdown
## Problema

<!-- Una o dos frases: qué falla o falta para quien usa la app y por qué importa. El problema, no la solución; si Dru ya decidió la solución, escríbela explícita para que nadie la vuelva a discutir. -->

## Decisiones de producto

<!-- Lo decidido con Dru: comportamiento esperado, cómo se usa, cómo debe verse, mensajes exactos. -->

## Criterios de aceptación

<!-- Cómo se sabe que está hecho: observables desde fuera, uno por línea, comprobables con un sí o un no. "Que funcione bien" no vale. -->
- [ ] ...

## Cómo se comprueba

<!-- Tests e2e de punta a punta y casos límite explícitos (vacío, error, permisos, repetición...). -->

## Qué NO entra

<!-- La frontera del alcance: lo que queda fuera aunque parezca relacionado. Si al escribirlo salen dos cosas, son dos issues. -->

## Dónde toca

<!-- Rutas concretas (`lib/x/daemon.py`, no "el daemon"). Si necesita otro issue terminado antes: "Depende de #N" (varios: "Depende de #N y #M"); kit-run no lo coge mientras alguno siga abierto. Si toca un recurso que el AGENTS.md del proyecto declara como eje serializa:<eje> (no admite dos issues a la vez), créalo con --etiqueta serializa:<eje>. -->

## Lo verificado

<!-- Lo comprobado en el código o ejecutando, con la evidencia: ruta:línea, comando y salida. -->

## Lo que solo se cree

<!-- Suposiciones (sobre el código o sobre una herramienta externa: git, una API...), cada una marcada como "sin verificar". Un supuesto escrito como hecho manda a construir sobre arena; escrito como supuesto, lo primero que se hace es comprobarlo. -->
```
