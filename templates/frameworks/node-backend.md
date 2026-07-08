# Node/TypeScript backend rules

- Services return `Result`/`ResultAsync` (neverthrow or equivalent): no `throw` and no `try/catch` inside services; errors are values — `err({ code, message })`. Ignoring an error result is a bug.
- Schema validation (Zod or equivalent) at every trust boundary: request bodies/params, environment variables, external API responses. Derive types with `z.infer`; share them from one package — never duplicate.
- Structured logger, never `console.log`.
- Work that doesn't need to block the response (document processing, crawling, batch jobs) goes to a background job runner.
- Any DB query inside a loop is an N+1: batch-select, filter in memory, batch-insert.
- Prefer functional style; `type` over `interface`.
