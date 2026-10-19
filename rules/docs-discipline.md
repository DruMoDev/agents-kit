# Disciplina de docs

Léela antes de crear o reorganizar documentación.

## Dos tipos de docs

- **Guías replicables** (`docs/`): numeradas, paso a paso, reproducibles. Requisitos, comandos exactos, resolución de problemas, cómo deshacer. Prueba de fuego: "¿podría alguien seguirla paso a paso en una máquina limpia?"
- **Material de referencia** (`docs/reference/`): tablas de precios, instantáneas de APIs, benchmarks, investigación. Caduca: mantenlo fuera de las guías.

## Reglas

- Documenta cada integración o configuración nueva como su propia guía cuando el proyecto depende de ser replicable.
- Specs y planes son andamiaje: bórralos tras implementarlos. Conserva solo los aprendizajes no obvios (trampas de APIs, decisiones que volverán) como docs pequeños referenciados desde donde aplican: una skill, un README, la doc de un módulo.
- Una referencia a algo que ya no existe es un bug: al renombrar, mover o cambiar cualquier cosa, revisa docs y skills y corrige toda referencia obsoleta en el mismo cambio.
- Mantén los ejemplos genéricos (el patrón reutilizable), no el caso concreto que acabas de hacer.
