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

## Per-framework skill recommendations

Printed after `init` (never auto-run). Edit `recommendations.json` to change them.

| Framework | Skills |
|---|---|
| next / react | vercel-react-best-practices, vercel-composition-patterns, web-design-guidelines |
| astro | web-design-guidelines |
| all | supabase skill if using Supabase; ponytail plugin for its audit/review commands |

## Skills convention (future)

The kit ships no skills today. When skills are added, they go in `.agents/skills/` (ecosystem-canonical) with a symlink `.claude/skills -> ../.agents/skills` for Claude Code.

## Development

```bash
./tests/smoke.sh   # full CLI smoke test against temp dirs
```
