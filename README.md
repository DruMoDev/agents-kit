# agents-kit

Installs a reusable agent instruction set into any project, parameterized by framework. Distilled from real projects + [ponytail](https://github.com/DietrichGebert/ponytail)'s lazy-senior-dev ruleset.

## Usage

```bash
# in your project root
npx github:DruMoDev/agents-kit init --framework next   # next | astro | react | node-backend | python | generic
npx github:DruMoDev/agents-kit update                   # pull the latest kit rules into the project
```

If the repo is private, use `npx git+ssh://git@github.com/DruMoDev/agents-kit <cmd>`.

## What it installs

```
AGENTS.md              canonical instructions (header + your ## Project section)
CLAUDE.md              one line: @AGENTS.md (Claude Code imports resolve recursively)
docs/agent/
  base.md              core engineering rules — always in context
  <framework>.md       framework rules — always in context
  testing.md           read before writing tests
  docs-discipline.md   read before adding docs
```

- `AGENTS.md` is the single source of truth; every agent tool (Claude Code, Cursor, opencode, Codex, Warp) reads it. The header's `@` lines are real imports for Claude Code and plain references for everything else.
- The kit owns `docs/agent/*`, the AGENTS.md header, and the CLAUDE.md line. Your `## Project` section and anything else you add are never touched.
- `init` is idempotent; `update` rewrites only kit-owned files.

## Framework knowledge vs project choices

The kit deliberately does NOT maintain framework best practices — those live in official, vendor-maintained sources: [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills) for React/Next, the [official Astro skill](https://github.com/astrolicious/agent-skills), and Next.js's own bundled docs (`node_modules/next/dist/docs/`). The kit's `<framework>.md` files only pin *your fixed stack choices* (e.g. Tailwind-only, React Query over `useEffect+fetch`, zero-JS Astro).

Install commands for the official skills are printed after `init` (never auto-run). Edit `recommendations.json` to change them.

| Framework | Printed commands |
|---|---|
| next / react | `npx skills add vercel-labs/agent-skills --skill vercel-react-best-practices --skill vercel-composition-patterns --skill web-design-guidelines` |
| astro | `npx skills add astrolicious/agent-skills --skill astro` + web-design-guidelines |
| all (notes) | Supabase skills if using Supabase; anthropics frontend-design for distinctive UI; ponytail plugin for its audit/review commands |

## Skills convention (future)

The kit ships no skills today. When skills are added, they go in `.agents/skills/` (ecosystem-canonical) with a symlink `.claude/skills -> ../.agents/skills` for Claude Code.

## Development

```bash
./tests/smoke.sh   # full CLI smoke test against temp dirs
```
