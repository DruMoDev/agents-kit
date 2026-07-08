# React SPA rules

- TypeScript strict. No `any`, explicit or implicit. `import type` for type-only imports.
- Data fetching through TanStack Query (or the project's query layer) — never `useEffect + fetch`.
- Components stay presentational; logic lives in hooks and plain modules. If a component both fetches and holds complex logic, split it.
- Tailwind only: no inline `style={{}}` (except unavoidable dynamic values), no CSS modules, no styled-components.
- Shared types live in one place — never duplicated across app layers.
