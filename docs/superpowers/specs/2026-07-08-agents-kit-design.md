# agents-kit — Design

**Date:** 2026-07-08 · **Status:** approved pending final review · **Owner:** Dru (DruMoDev)

## Goal

A GitHub-hosted, zero-dependency npx CLI that installs a reusable, framework-parameterized agent instruction set into any project: a canonical `AGENTS.md`, a `CLAUDE.md` shim, and always-loaded rule files plus lazy reference docs under `docs/agent/`. The content is distilled from Dru's 8 real projects (tiktok-editor, chatbot-with-context, awesome-menu, multi-bank-finance-dashboard, net7 app+web, openclaw, aikosmo-monorepo) and from ponytail's lazy-senior-dev ruleset.

Non-goal: being extensive. The kit ships only the key, universally-applicable instructions; project-specific context stays in each project's `## Project` section.

## Sources mined

| Source | What we take |
|---|---|
| ponytail (DietrichGebert/ponytail) | The ladder (condensed), deletion over addition, shortest working diff after understanding, question complex requests, "not lazy about" list |
| aikosmo-monorepo | "Failures to avoid" negative-rule framing; skill memory canonical text; debugging protocol (repro first, isolate diverging stage, e2e validation before "done"); plan mode (ultra-short + unresolved questions); "Skills to load" routing-table pattern |
| awesome-menu | Skill memory (same canonical text); engineering direction (SOLID pragmatic, no over-engineering, reuse, no orphaned code); Next.js `node_modules/next/dist/docs` rule |
| multi-bank-finance-dashboard | MUST/DON'T phrasing; stateless instruction file rule (context + rules only, no chronology); don't pin remembered versions |
| chatbot-with-context | Frontend rules (React Query, never `useEffect+fetch`); backend rules (services return Result, Zod at boundaries, no try/catch in services, logger not console.log); testing pyramid + thresholds |
| net7 (app + web) | Next.js patterns (Server Components default, Server Actions for mutations, revalidatePath); Astro patterns (zero-JS default, content collections, SEO/JSON-LD requirements); E2E patterns for testing.md |
| openclaw | Docs discipline: replicable step-by-step guides vs `docs/reference/` for perishable info |
| tiktok-editor | Skill hygiene (generic playbooks, no stale refs, deterministic work goes to code); specs/plans as ephemeral scaffolding; 3-level resource hygiene (anti-clutter); config-first |

## Installed layout (in a target project)

```
AGENTS.md                     canonical, tool-agnostic (user-owned except header)
CLAUDE.md                     3-line shim; only missing @ lines are ever re-added
docs/agent/
  base.md                     core rules — always loaded (kit-owned)
  <framework>.md              framework rules — always loaded (kit-owned, omitted for generic)
  testing.md                  lazy reference (kit-owned)
  docs-discipline.md          lazy reference (kit-owned)
```

**`AGENTS.md`** starts with a mandatory-read header:

```markdown
> **Mandatory:** before any work, read `docs/agent/base.md` and `docs/agent/nextjs.md`.
> (Claude Code imports them automatically; other agents must read them now.)

## Project
<project-specific context: what it is, stack, commands, skills-to-load table, codebase map>
```

**`CLAUDE.md`** (static):

```markdown
@docs/agent/base.md
@docs/agent/nextjs.md
@AGENTS.md
```

Rationale: `@import` is Claude Code-only syntax and guarantees the rules are in context every session; other tools (Cursor, opencode, Codex, Warp) read `AGENTS.md` natively and follow the mandatory-read header. A symlink `CLAUDE.md -> AGENTS.md` was rejected because it loses the guaranteed imports.

**Ownership rule:** the kit owns everything under `docs/agent/` plus the AGENTS.md header and the CLAUDE.md shim. The user owns `## Project` and everything else. `update` only ever rewrites kit-owned files.

**`.agents/` convention (forward-looking, not in v1):** the kit installs no skills. When skills are added later they go in `.agents/skills/` (ecosystem-canonical) with a symlink `.claude/skills -> ../.agents/skills` for Claude Code. Documented in the kit README; the CLI creates no empty directories.

## CLI

Runs from GitHub without npm publish: `npx github:DruMoDev/agents-kit <cmd>` (if the repo is private, `npx git+ssh://git@github.com/DruMoDev/agents-kit`).

### `init [--framework next|astro|react|node-backend|python|generic] [--force]`

1. Prompts for framework if no flag (plain readline, numbered list).
2. Writes `docs/agent/base.md`, `docs/agent/<framework>.md`, `docs/agent/testing.md`, `docs/agent/docs-discipline.md`.
3. Creates `AGENTS.md` (header + empty `## Project` template with commented placeholders: skills-to-load table, codebase map, commands) if missing; if it exists, only ensures the mandatory-read header is present at the top.
4. Creates `CLAUDE.md` shim if missing; if a CLAUDE.md exists, prepends the missing `@` lines only.
5. Prints next steps from `recommendations.json`: framework-specific skill installs and MCP suggestions. Never executes them.

Idempotent: re-running changes nothing already in place; `--force` re-copies kit-owned files (same as `update`). Existing files with user content are never overwritten, only appended to as described.

### `update`

Overwrites kit-owned files under `docs/agent/` with the latest templates, re-ensures the AGENTS.md header and CLAUDE.md import lines, and prints which files changed. Detects the installed framework by which `docs/agent/<framework>.md` exists (`--framework` overrides).

### Implementation

Node >= 18, ESM, **zero runtime dependencies** (fast `npx github:` installs, nothing to break). Single `bin/cli.js` (~200 lines): arg parsing by hand, `readline` for the prompt, `fs` for file ops. Templates are plain files copied verbatim — no templating engine; the only dynamic parts are which framework file is copied and the filenames in the AGENTS.md header/CLAUDE.md shim.

## Kit repo structure

```
agents-kit/
├─ bin/cli.js
├─ templates/
│  ├─ base.md
│  ├─ AGENTS.header.md          mandatory-read header + ## Project skeleton
│  ├─ frameworks/
│  │  ├─ nextjs.md
│  │  ├─ astro.md
│  │  ├─ react.md
│  │  ├─ node-backend.md
│  │  └─ python.md
│  └─ docs/
│     ├─ testing.md
│     └─ docs-discipline.md
├─ recommendations.json          per-framework skill/MCP commands for the log
├─ package.json                  name, bin, engines; no deps
├─ README.md                     usage, what gets installed, per-framework skills table, .agents convention
└─ docs/superpowers/specs/       this design
```

## Template content (English)

### `base.md` (~70-90 lines, always loaded)

1. **Lazy senior dev core** (ponytail, condensed): before writing code, stop at the first rung that holds — does it need to exist (YAGNI)? does the codebase already have it? stdlib? platform? installed dep? one line? only then write the minimum that works. Deletion over addition, boring over clever, fewest files. Shortest working diff wins, but only after understanding the problem — read the code it touches and trace the real flow first. Question complex requests. Not lazy about: trust-boundary validation, error handling that prevents data loss, security, accessibility, anything explicitly requested.
2. **Failures to avoid** (aikosmo): do not act before codebase research; understand a module's contracts before patching it — fix the earliest contract violation, not the symptom; no duplicate logic; no wrappers around existing APIs; no classes where functions solve it; no new types when shared ones fit; no swallowed errors (no empty catch, no ignored Result.err, no dropped rejection); no placeholder tests; no brittle tests asserting internal constants/wiring; never declare "fixed" without repro + re-test.
3. **Architecture**: single source of truth for every fact/constant; small single-responsibility files; UI separated from logic; entry points orchestrate, domain modules contain the logic; no orphaned/unused code left behind.
4. **Skill memory** (canonical 4 bullets from awesome-menu/aikosmo): preserve task learnings in skills before finishing; prefer updating the most relevant existing skill; keep updates actionable and concise; never leave important discoveries only in chat/plans/summaries.
5. **Debugging**: reproduce first; isolate the stage where behavior first diverges before changing code; prefer source-of-truth fixes over symptom patches; validate end-to-end before claiming done.
6. **Docs & specs discipline**: instruction files are stateless (context + rules, never chronology/status); specs and plans are ephemeral scaffolding — delete after implementing, keep only non-obvious learnings where they apply; details in `docs/agent/docs-discipline.md` (lazy ref).
7. **Hard rules**: no hardcoded secrets (env vars, validated); validate inputs at trust boundaries; tests for new functionality; no console.log-style debugging left in production code; don't pin dependency versions from memory — check the registry.
8. **Plan mode**: plans ultra-short; end with the unresolved-questions list.
9. **Lazy references**: "Before writing tests, read `docs/agent/testing.md`. Before creating docs, read `docs/agent/docs-discipline.md`."

### `frameworks/nextjs.md` (~30-40 lines)

This-is-not-the-Next-you-know warning + read the matching guide in `node_modules/next/dist/docs/` before framework-level changes, heed deprecation notices. Server Components by default, Client Components only when interactivity requires. Server Actions for all mutations, `revalidatePath()` after; route handlers only for webhooks/crons/OAuth callbacks, using Web-standard Request/Response. Never `useEffect + fetch` for data. Tailwind v4 CSS-first (no tailwind.config.js). Public/marketing surfaces treated as static-grade; dynamic parts must not break caching.

### `frameworks/astro.md` (~30 lines)

Zero-JS by default; islands only for real interactivity. Content Collections with typed frontmatter for content. SEO baseline mandatory: unique title/description, canonical, OG/Twitter, JSON-LD appropriate to page type, sitemap, RSS where applicable; never fake structured data (aggregateRating with no real reviews penalizes). Derive listings (categories, tags) dynamically from content, never hardcode. Tailwind utilities in components; one component per section, small and focused.

### `frameworks/react.md` (SPA, ~25 lines)

Vite + TS strict. Data fetching with TanStack React Query — never `useEffect + fetch`. No `any` (explicit or implicit). Tailwind only; no inline styles except unavoidable dynamic values; no CSS modules/styled-components. Components presentational; logic in hooks/services. `import type` for type-only imports.

### `frameworks/node-backend.md` (~30 lines)

Services return `Result`/`ResultAsync` (neverthrow) — no `throw`, no `try/catch` inside services; errors as `err({ code, message })`. Zod validation at every boundary (requests, env, external data); types derived with `z.infer`, shared in one package — never duplicated. Structured logger, not console.log. Background/async work goes to a job runner, never blocks request handlers. Batch queries — any DB query inside a loop is an N+1.

### `frameworks/python.md` (~25 lines)

All deps live in the project venv — run via `.venv/bin/python` or the project entrypoint, never bare `python`. CLI/entry scripts orchestrate only; logic lives in `lib/<domain>/` (or package equivalent). Config-first: behavior changes go to config files before code. No new dependencies without justification. Respect the established folder structure.

### `docs/testing.md` (lazy, ~40 lines)

Pyramid (many unit / some integration / few E2E on critical flows). Tests for new functionality: at least happy path + error path. No placeholder tests; no brittle tests asserting exact internal constants, provider defaults, copy text, or wiring — test shipped behavior. Selected E2E gotchas from net7: conditional `test.skip()` on empty data; query by role with full label text (substring matches collide); wait for enabled state after filling controlled inputs; scope selectors when text appears in multiple regions.

### `docs/docs-discipline.md` (lazy, ~30 lines)

Two kinds of docs (openclaw): replicable step-by-step guides (numbered, in `docs/`) vs perishable reference material (`docs/reference/` — pricing tables, API snapshots, research). Litmus test: "would someone follow this step by step to reproduce it?" Specs/plans are deleted after implementation (git keeps history); only non-obvious learnings survive, as small .md files referenced from where they apply. Fix stale references the moment you rename/move anything.

## `recommendations.json` (seeds — data file, edit freely)

| Framework | Logged suggestions |
|---|---|
| next | `npx add-skill vercel-react-best-practices`, `npx add-skill vercel-composition-patterns`, `npx add-skill web-design-guidelines`; note: supabase skill if using Supabase |
| react | `npx add-skill vercel-react-best-practices`, `npx add-skill vercel-composition-patterns`, `npx add-skill web-design-guidelines` |
| astro | `npx add-skill web-design-guidelines` |
| node-backend | note: supabase skill if using Supabase |
| python | (none yet) |
| all | note: install ponytail (plugin) if you want the full lazy-dev toolchain (`ponytail-audit`, `ponytail-review`) — base.md already ships the distilled ruleset |

## Out of scope (v1)

Quality-gate hooks, kit-owned skills, Claude Code plugin packaging, npm publishing, Spanish template variants, monorepo multi-app installs (run `init` per app for now).

## Testing the kit itself

Manual smoke on a temp dir: `init` for each framework asserts expected files + idempotent re-run; `init` over a pre-existing CLAUDE.md/AGENTS.md preserves user content; `update` after editing a template changes only kit-owned files. A tiny `tests/smoke.sh` runs these with `node bin/cli.js` directly (no npx needed locally).
