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

| Framework | Skills | MCP servers |
|---|---|---|
| next | vercel-react-best-practices + vercel-composition-patterns + web-design-guidelines (vercel-labs/agent-skills); frontend-design + webapp-testing (anthropics/skills); react-doctor (millionco/react-doctor) | next-devtools-mcp |
| react | same as next | — |
| astro | astro (astrolicious/agent-skills); web-design-guidelines; frontend-design + webapp-testing | official Astro docs MCP (`https://mcp.docs.astro.build/mcp`) |
| node-backend | none (no vendor-official skill exists for Express/Fastify/Nest/Hono) | — |
| python | FastAPI ships its own official skill (`npx skills add fastapi/fastapi --skill fastapi`) | — |
| all (notes) | Next task skills live in `vercel/next.js`; Supabase skills + MCP if using Supabase; playwright MCP for browser control (overlaps webapp-testing — pick one); deploy-to-vercel; find-skills to search the registry; ponytail plugin |

## Skills convention (future)

The kit ships no skills today. When skills are added, they go in `.agents/skills/` (ecosystem-canonical) with a symlink `.claude/skills -> ../.agents/skills` for Claude Code.

## Development

```bash
./tests/smoke.sh   # full CLI smoke test against temp dirs
```
