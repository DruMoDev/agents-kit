# Propuesta de regla

Lo que lee Dru para decidir. Va en el chat si Dru está en la sesión, y como fichero para `kit-pr.sh regla <wt> <pr> <fichero>` en `kit-run` (el script le pone delante el marcador `<!-- kit-regla: <hash> -->`; no lo escribas tú). Sirve igual para una regla nueva, una regla cambiada o quitada, una excepción nueva en la configuración y una opción más estricta de la base.

Es una valoración, no una venta: si al escribirla ves que la regla es ruidosa o no compensa, dilo y recomienda no añadirla. Una regla que Dru no entiende, o que enseña al agente a esquivarla, es peor que no tenerla.

## Plantilla

```markdown
## Regla propuesta: <nombre corto>

**Qué prohíbe:** <la construcción o el import, en una frase, y dónde aplica (carpetas, extensiones)>.

**Por qué:** <la convención que cubre y qué pasa hoy sin la regla: el error que se repite, dónde está escrita en prosa (AGENTS.md, una skill), cuántas veces se ha saltado>.

**Peldaño:** <configuración | ast-grep | regla a medida | test de estructura>, en `<fichero>`.

**Ejemplo del error:**
<el código que la dispara, en un bloque de código>
<el mensaje exacto que verá el agente, en otro bloque de código>

**Qué rompe y cómo queda:** <nº de errores y ficheros en el código de hoy>. <cómo se arreglan (uno o dos ejemplos de antes y después) y si se arreglan en este mismo cambio>. La deuda no puede crecer: lo que la regla rompe se arregla aquí, o la regla se acota.

**Valoración crítica:**
- Falsos positivos posibles: <casos legítimos que la regla marcaría, y cómo los evita (selector, `files`, `ignores`) o por qué no los hay>.
- ¿Existe un peldaño más barato? <sí, cuál y por qué no basta; o no, por qué>.
- Coste: <tiempo de lint añadido si se nota, dependencias nuevas con su versión del registro, mantenimiento>.
- Recomendación: <añadirla, añadirla acotada a ..., o no añadirla>.

**Para aprobarla o rechazarla:** responde con un comentario normal en el issue o en esta PR (sin etiquetas).
```

La última línea solo va en `kit-run`; en la sesión, Dru responde en el chat.
