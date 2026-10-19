# Plantilla del cuerpo de un issue

Lo leen `kit-run` y los revisores sin más contexto: todo lo acordado tiene que estar aquí. Frases cortas, sin relleno. Borra los comentarios.

```markdown
## Objetivo

<!-- Una o dos frases: qué cambia para quien usa la app y por qué. -->

## Comportamiento acordado

<!-- Lo decidido con Dru: flujo, casos, mensajes exactos que se ven. -->

## Criterios de aceptación

<!-- Observables desde fuera, uno por línea, comprobables con un sí o un no. -->
- [ ] ...

## Cómo se comprueba

<!-- Tests e2e de punta a punta y casos límite explícitos (vacío, error, permisos, repetición...). -->

## Qué NO entra

<!-- Lo que queda fuera aunque parezca relacionado. -->

## Rutas relevantes

<!-- Ficheros o directorios que probablemente se tocan. -->

## Verificado y supuesto

- Verificado: <!-- lo comprobado en el código o ejecutando, con la evidencia (ruta:línea, comando y salida). -->
- Supuesto: <!-- lo que se cree pero no se ha comprobado. -->
```
