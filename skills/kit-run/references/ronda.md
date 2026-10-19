# Ronda de revisión

Cada ronda `r` revisa el head de la PR con todos los revisores de `kit_reviewers` y termina siempre con un comentario `kit-ronda` publicado por `kit-pr.sh ronda`. Sin ese comentario, `fusionar` se niega: también hace falta con 0 hallazgos.

## Revisores

- `kit-review.sh` publica el informe en la PR (`<!-- kit-revision: <herramienta>/<modelo> ronda <r> -->`), lo imprime y acaba en `FIN: <total> hallazgos`. Les pasa el historial de rondas, así que no deberían repetir lo ya decidido.
- Exit 1: error de uso tuyo (argumentos). Corrígelo y relanza ese revisor.
- Exit 2: el revisor no entregó (no disponible, tiempo agotado, sin línea `HALLAZGOS`). Relánzalo una vez, solo ese. Si vuelve a dar exit 2, revisa tú el cambio (`git -C <wt> diff <base>...HEAD`) con ese foco y dilo en el fichero de ronda.

## Decidir

Por cada hallazgo, compruébalo en el código y decide:

- **Aplicar**: el escenario falla de verdad y entra en el scope. Arréglalo con su test.
- **Rechazar**: con un motivo escrito y concreto (no se reproduce, ya cubierto en `ruta:línea`, contradice el issue...).
- **Fuera de scope**: se rechaza y se abre aparte como issue `propuesta`; el motivo dice `fuera de scope, abierto como #<n>`.

Un hallazgo repetido de una ronda anterior se rechaza citando su `R<r>.<k>`.

## Fichero de ronda

Una línea por hallazgo, `k` desde 1 en cada ronda. `kit-pr.sh ronda` rechaza un hallazgo de otra ronda o sin decisión:

```text
- [R<r>.<k>] (<herramienta>/<modelo>) <resumen> → aplicado
- [R<r>.<k>] (<herramienta>/<modelo>) <resumen> → rechazado: <motivo>
```

Puedes añadir líneas libres que no empiecen por `- [R`, por ejemplo:

- `Ronda <r>: 0 hallazgos de todos los revisores.`
- `El revisor <herramienta>/<modelo> no entregó dos veces; la sesión revisó con su foco.` Los hallazgos de esa revisión propia llevan `(sesión/<herramienta>/<modelo>)`.

## Cuándo parar

- Todos los revisores (y tu revisión propia, si la hubo) traen 0 hallazgos: publica la ronda y pasa a fusionar.
- Dos rondas seguidas solo traen hallazgos que salen de tus propios arreglos de la revisión y no afectan al uso real: recházalos en el fichero con `abierto como propuesta #<n>`, ábrelos como `propuesta`, publica la ronda y pasa a fusionar.
- Si hubo hallazgos, aunque todos se rechazaran, toca otra ronda: solo se para por las dos reglas de arriba o por el límite.
- Si aplicaste algo, la ronda nueva es obligatoria, salvo que `r` ya sea `maxReviewRounds`: entonces se bloquea el issue (paso 5 de la skill).
