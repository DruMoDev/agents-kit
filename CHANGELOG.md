# Changelog

<!--
Formato fijo (lo lee la web de changelogs). Fecha descendente: lo más reciente arriba.
Cada entrada tiene versión corta (obligatoria) y versión extendida (opcional, esperada en cambios visibles).

- Versión corta: `### <Tipo>: <título de una línea> · [#PR](enlace)`
- Tipos cerrados: Nuevo | Mejora | Arreglo | Interno
- Versión extendida: qué cambia para quien usa la app, en pocas frases; captura si el cambio es visual
  (guardada en docs/changelog/ con el número de PR en el nombre); ejemplo práctico si ayuda.
- Texto para quien usa la app, no técnico.

Ejemplo:

## 2026-10-18

### Nuevo: Login con Google · [#12](https://github.com/<owner>/<repo>/pull/12)
Ahora puedes entrar con tu cuenta de Google en un clic.

En la pantalla de acceso aparece el botón "Continuar con Google"; si la cuenta
ya existía con ese email, se vincula sola.

![Pantalla de acceso](docs/changelog/12-login.png)
-->

## 2026-11-03

### Nuevo: reglas de lint, tipos y estructura que los agentes no pueden saltarse · [#28](https://github.com/DruMoDev/agents-kit/pull/28)
La skill nueva `kit-reglas` instala en cada repo una base estricta de lint, tipos y estructura y convierte en reglas las convenciones del proyecto, explicándote cada una y aplicando solo lo que apruebas. En un repo con código hecho, lo que hoy falla se congela y solo puede bajar.

Mientras trabajan, los agentes ven el lint del fichero que acaban de editar y, al terminar cada turno, el de todo lo cambiado; no pueden desactivar una regla ni tocar su configuración sin proponerlo. Un cambio de reglas no se fusiona hasta que respondes con un comentario normal en el issue o en la PR, y ya no tienes que quitar etiquetas para que un issue que espera tu respuesta siga: basta con responder (`bloqueado` sí se sigue quitando a mano).
