# Referencia de testing

Léela antes de escribir tests.

## Qué testear

- Pirámide: muchos tests unitarios (rápidos, aislados), algunos de integración (externos mockeados), e2e en los flujos que hay que comprobar de punta a punta, con sus casos límite.
- Funcionalidad nueva: camino feliz + camino de error como mínimo.
- Testea el comportamiento que se entrega. Nunca escribas tests de relleno, ni tests frágiles que comprueban constantes internas exactas, valores por defecto de proveedor o modelo, textos o cableado interno: se rompen al refactorizar sin cazar bugs.
- Un test que no puede fallar cuando la lógica se rompe es peor que no tener test.

## Trampas de e2e (Playwright)

- Estado vacío: los tests que necesitan datos previos llaman a `test.skip()` cuando no hay datos; nunca fallan con bases de datos vacías.
- Busca por rol con la etiqueta completa: `getByRole('option', { name: '0% (Exento)' })`. Los nombres parciales colisionan ("0%" también coincide con "10%").
- Los roles ARIA implícitos no coinciden con selectores CSS: usa `getByRole('heading')`, no `locator('[role="heading"]')`.
- Tras `fill()` en un input controlado, `await expect(button).toBeEnabled()` antes de hacer clic: el framework tiene que confirmar el estado primero.
- Cuando el mismo texto aparece en varias regiones, acota el locator (por ejemplo `page.locator('tfoot').getByText(...)`).
- Los layouts responsive ocultan elementos según el viewport: fija un viewport explícito antes de comprobar tablas o columnas.
