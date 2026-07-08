# Next.js rules

Framework knowledge and best practices come from the official sources (bundled docs below, plus the official skills the kit installer prints) — this file only pins this project's fixed choices.

This may not be the Next.js you know. APIs, conventions, and file structure may differ from your training data. Before any framework-level change (routing, route handlers, Server Actions, metadata, config, middleware), read the matching guide in `node_modules/next/dist/docs/` and heed deprecation notices.

- Server Components by default. Client Components only where interactivity requires them, with `"use client"` as low in the tree as possible.
- Server Actions for all form submissions and mutations; call `revalidatePath()`/`revalidateTag()` after writes. Route handlers only for webhooks, crons, and OAuth callbacks — with Web-standard `Request`/`Response`.
- Never `useEffect + fetch` for data. Fetch in Server Components; on the client use the project's query library.
- Public/marketing surfaces are static-grade: nothing on them may break caching. Dynamic dashboards must not degrade public-page performance.
- Tailwind CSS v4 is CSS-first: configure in CSS (`@theme`), no `tailwind.config.js`.
- Generated UI-library components (e.g. shadcn's `components/ui/`) are managed by their CLI — do not hand-edit.
