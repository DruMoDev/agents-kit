# La escalera de reglas

Para cada convención, el peldaño más barato que la cubra. Subir un peldaño cuesta más de escribir, de mantener y de explicar: hazlo solo cuando el de abajo no llega.

## Los cuatro peldaños

1. **Configuración** de ESLint: `no-restricted-imports` o `no-restricted-syntax` con un selector y un `message`. Sin código propio. Cubre "esto no se importa desde aquí" y "esta construcción no se usa".
2. **Regla de `ast-grep`** (`sgconfig.yml` y una carpeta de reglas en YAML): patrones del árbol sintáctico sin información de tipos. También sirve para Python y bash, donde ESLint no llega.
3. **Regla de ESLint a medida**, en el repo (por ejemplo en `reglas/`), con tests de `RuleTester` (casos válidos e inválidos, con el mensaje exacto). Cuando hace falta información de tipos o lógica entre nodos (un hook de React que solo se llama desde ciertos componentes, un tipo que no puede cruzar una capa).
4. **Test de estructura** con `dependency-cruiser` (o `eslint-plugin-boundaries`): capas, fronteras entre carpetas y ciclos, lo que una regla por fichero no ve.

## El mensaje

Cada mensaje de error dice qué hacer y nombra la alternativa exacta del repo, no solo lo que está mal. El agente que lo lee no tiene más contexto que ese texto.
- Mal: "Import no permitido."
- Bien: "No importes `axios` directamente: usa el cliente de `@/api/client` (`api.get`, `api.post`), que añade la autenticación y los reintentos."

Si el arreglo es mecánico y seguro, la regla trae autofix (peldaños 2 y 3).

## Ejemplos del peldaño 1

`no-restricted-imports`, contra un paquete y contra rutas relativas largas cuando el repo tiene alias:

```js
{
  files: ["src/**/*.{ts,tsx}"],
  rules: {
    "no-restricted-imports": ["error", {
      paths: [
        { name: "axios", message: "Usa el cliente de @/api/client (api.get, api.post): añade la autenticación y los reintentos." },
      ],
      patterns: [
        { group: ["../../*"], message: "Usa el alias @/ en vez de rutas relativas que suben más de un nivel." },
      ],
    }],
  },
}
```

`no-restricted-syntax`, contra una construcción, acotado con `files` y con una excepción en la propia configuración:

```js
{
  files: ["src/**/*.tsx"],
  ignores: ["src/ui/**"],
  rules: {
    "no-restricted-syntax": ["error",
      { selector: "JSXOpeningElement[name.name='button']",
        message: "Nada de <button> a pelo: usa Button de @/ui/Button, que ya trae estilos, foco y estado de carga." },
      { selector: "CallExpression[callee.name='fetch']",
        message: "fetch solo dentro de src/api/: usa el cliente de @/api/client." },
    ],
  },
}
```

Ojo: una regla con el mismo nombre en otro objeto de la configuración sustituye a la anterior para los ficheros que coinciden, no se suma. Junta todos los selectores de `no-restricted-syntax` (o de `no-restricted-imports`) que aplican a los mismos ficheros en un solo sitio.

## Catálogo de partida

Para proponer según lo que use el repo. Cada una con la plantilla de `propuesta.md`:
- **i18n:** `no-literal-string` en JSX (por ejemplo de `eslint-plugin-i18next`), con lista blanca para atributos técnicos (`className`, `data-*`, `type`) y fuera de tests.
- **Tokens de diseño:** Tailwind sin valores arbitrarios ni clases desconocidas (un plugin de Tailwind para ESLint), o colores a pelo prohibidos en CSS-in-JS con `no-restricted-syntax` sobre literales `#...`.
- **Componentes propios obligatorios:** `no-restricted-syntax` sobre el elemento nativo (`<button>`, `<a>`, `<img>`) con el componente del repo en el mensaje.
- **Capas de carpetas:** `dependency-cruiser` (la UI no importa de la base de datos; `domain/` no importa de `infra/`).
- **Convención de la API:** un cliente único, sin `fetch` ni `axios` sueltos fuera de su carpeta.

Antes de proponer un plugin, mira si está mantenido (`npm view <paquete> time.modified`) y si su versión es compatible (`npm view <paquete> peerDependencies`).
