# agents-kit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zero-dependency npx CLI (`init`/`update`) that installs a reusable agent instruction set (AGENTS.md + CLAUDE.md shim + `docs/agent/*`) parameterized by framework.

**Architecture:** Plain-file templates copied verbatim by a single ~180-line ESM script (`bin/cli.js`). The only dynamic piece is which framework template is copied and one `{{FRAMEWORK_IMPORT}}` string replacement in the AGENTS.md header. Verification is a bash smoke test that exercises the CLI against temp directories.

**Tech Stack:** Node >= 18, ESM, `node:fs`/`node:path`/`node:readline` only. Bash for the smoke test.

**Spec:** `docs/superpowers/specs/2026-07-08-agents-kit-design.md` (same repo).

## Global Constraints

- Zero runtime dependencies. `package.json` must have no `dependencies`/`devDependencies`.
- Node >= 18, `"type": "module"`.
- All template content in English.
- Kit-owned files in a target project: everything under `docs/agent/`, the AGENTS.md header block, the `@AGENTS.md` line in CLAUDE.md. User content is NEVER overwritten or reordered.
- `init` is idempotent: re-running on an installed project changes zero bytes.
- The CLI never executes skill/MCP install commands — it only prints them.
- Working directory for all tasks: `/Users/drumorera/Documents/programacion/agents-kit`.

## File Structure

```
agents-kit/
├─ package.json                      Task 1
├─ .gitignore                        Task 1
├─ templates/
│  ├─ base.md                        Task 2 — core rules, always loaded
│  ├─ frameworks/
│  │  ├─ nextjs.md                   Task 3
│  │  ├─ astro.md                    Task 3
│  │  ├─ react.md                    Task 3
│  │  ├─ node-backend.md             Task 3
│  │  └─ python.md                   Task 3
│  ├─ docs/
│  │  ├─ testing.md                  Task 4 — lazy reference
│  │  └─ docs-discipline.md          Task 4 — lazy reference
│  └─ AGENTS.header.md               Task 5 — header + ## Project skeleton
├─ recommendations.json              Task 5
├─ bin/cli.js                        Task 6 (init) + Task 7 (update)
├─ tests/smoke.sh                    Task 6 (init sections) + Task 7 (update section)
└─ README.md                         Task 8
```

---

### Task 1: Repo scaffold

**Files:**
- Create: `package.json`
- Create: `.gitignore`

**Interfaces:**
- Produces: package `bin` entry `agents-kit -> bin/cli.js` (implemented in Task 6); ESM mode for the whole repo.

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "agents-kit",
  "version": "1.0.0",
  "description": "Install a reusable agent instruction set (AGENTS.md + CLAUDE.md + docs/agent) parameterized by framework",
  "type": "module",
  "bin": { "agents-kit": "bin/cli.js" },
  "engines": { "node": ">=18" },
  "license": "MIT"
}
```

- [ ] **Step 2: Write `.gitignore`**

```
node_modules/
.DS_Store
```

- [ ] **Step 3: Commit**

```bash
git add package.json .gitignore
git commit -m "chore: scaffold package (zero-dep ESM, bin entry)"
```

---

### Task 2: `templates/base.md` (core rules)

**Files:**
- Create: `templates/base.md`

**Interfaces:**
- Produces: the file copied verbatim to `docs/agent/base.md` by the CLI. Its lazy references (`docs/agent/testing.md`, `docs/agent/docs-discipline.md`) must match the filenames Task 4 creates and Task 6 installs.

- [ ] **Step 1: Write `templates/base.md` with exactly this content**

````markdown
# Engineering rules (always in context)

These rules apply to every task in this repository. Project-specific context lives in `AGENTS.md`.

## Write less code (lazy senior dev)

The best code is the code never written. Before writing any code, stop at the first rung that holds:

1. Does this need to exist at all? (YAGNI)
2. Does this codebase already have it? Reuse the existing helper, util, or pattern — never re-write it.
3. Does the standard library do it? Use it.
4. Does a native platform/framework feature cover it? Use it.
5. Does an already-installed dependency solve it? Use it.
6. Can it be one line? Make it one line.
7. Only then: write the minimum code that works.

Climb the ladder only after you understand the problem: read the task and the code it touches, trace the real flow end to end first. The smallest change in the wrong place is a second bug, not efficiency.

- Deletion over addition. Boring over clever. Fewest files possible.
- No abstractions, wrappers, or boilerplate nobody asked for. No new dependency if avoidable.
- Question complex requests: "do you actually need X, or does Y cover it?"
- Not lazy about: input validation at trust boundaries, error handling that prevents data loss, security, accessibility, anything explicitly requested.

## Failures to avoid

- Do not act before codebase research. Read the relevant files, call paths, and constraints first.
- Do not patch a module before understanding its contracts: data ownership, field meanings, invariants, downstream consumers. Fix the earliest contract violation, not the symptom.
- Do not duplicate logic that exists elsewhere.
- Do not add classes where functions solve it, or new types when existing shared ones fit.
- Do not swallow errors: no empty `catch`, no ignored error results, no dropped promise rejections.
- Do not add placeholder tests, or brittle tests that only assert exact internal constants, defaults, copy text, or wiring.
- Do not declare "fixed" or "done" without reproducing the problem and re-testing after the change.

## Architecture

- Single source of truth: every fact, constant, and type lives in exactly one place; everything else references it.
- Small files with a single responsibility and self-descriptive names. Entry points orchestrate; domain modules hold the logic.
- Keep UI separate from logic.
- Leave no orphaned or unused code behind. If you replace something, delete the old version.

## Skill memory

- When a task reveals useful learning, missing guidance, ambiguity, or imprecision in any skill you loaded or relied on, preserve that learning in skills before finishing.
- Prefer updating the most relevant existing skill. Create a new skill only when the learning does not fit any existing skill.
- Keep skill updates actionable and concise: when to use the guidance, the concrete workflow/constraint, and any command or file path needed to apply it.
- Do not leave important task-specific discoveries only in chat, plans, or final summaries if they would help future agents avoid mistakes.

## Debugging

- Reproduce the bug before changing code.
- Isolate the stage where behavior first diverges from expectation; treat one failing example as a symptom, not a root cause.
- Prefer source-of-truth or pipeline-stage fixes over patches at the visible symptom layer.
- Validate the fix end to end before claiming done.

## Docs and specs

- Instruction files (AGENTS.md, CLAUDE.md, skills) are stateless: context + rules only, never chronology or status.
- Specs and plans are ephemeral scaffolding: delete them once implemented (git keeps history). Keep only non-obvious learnings, as small docs referenced from where they apply.
- Before writing tests, read `docs/agent/testing.md`. Before adding docs, read `docs/agent/docs-discipline.md`.

## Hard rules

- No hardcoded secrets — environment variables, validated at startup.
- Validate all inputs at trust boundaries.
- New functionality ships with tests (happy path + error path minimum).
- No debug logging left in production code paths.
- Do not pin dependency versions from memory — check the registry for current versions.

## Plans

- Keep plans ultra-short. End every plan with the list of unresolved questions.
````

- [ ] **Step 2: Commit**

```bash
git add templates/base.md
git commit -m "feat: base.md core rules (ponytail ladder + failures-to-avoid + skill memory)"
```

---

### Task 3: Framework templates

**Files:**
- Create: `templates/frameworks/nextjs.md`
- Create: `templates/frameworks/astro.md`
- Create: `templates/frameworks/react.md`
- Create: `templates/frameworks/node-backend.md`
- Create: `templates/frameworks/python.md`

**Interfaces:**
- Produces: filenames consumed by the CLI's `FRAMEWORKS` map in Task 6 (`next -> nextjs.md`, `astro -> astro.md`, `react -> react.md`, `node-backend -> node-backend.md`, `python -> python.md`).

- [ ] **Step 1: Write `templates/frameworks/nextjs.md`**

````markdown
# Next.js rules

This may not be the Next.js you know. APIs, conventions, and file structure may differ from your training data. Before any framework-level change (routing, route handlers, Server Actions, metadata, config, middleware), read the matching guide in `node_modules/next/dist/docs/` and heed deprecation notices.

- Server Components by default. Client Components only where interactivity requires them, with `"use client"` as low in the tree as possible.
- Server Actions for all form submissions and mutations; call `revalidatePath()`/`revalidateTag()` after writes. Route handlers only for webhooks, crons, and OAuth callbacks — with Web-standard `Request`/`Response`.
- Never `useEffect + fetch` for data. Fetch in Server Components; on the client use the project's query library.
- Public/marketing surfaces are static-grade: nothing on them may break caching. Dynamic dashboards must not degrade public-page performance.
- Tailwind CSS v4 is CSS-first: configure in CSS (`@theme`), no `tailwind.config.js`.
- Generated UI-library components (e.g. shadcn's `components/ui/`) are managed by their CLI — do not hand-edit.
````

- [ ] **Step 2: Write `templates/frameworks/astro.md`**

````markdown
# Astro rules

- Zero JS by default. Add islands (`client:*`) only for real interactivity; static content ships no JS.
- Content lives in Content Collections with a typed, validated frontmatter schema — never loose markdown folders.
- SEO baseline on every page: unique `<title>` (max 60 chars) and meta description (max 155), canonical URL, Open Graph + Twitter cards, JSON-LD matching the page type, sitemap and RSS where applicable.
- Never ship fake structured data (invented ratings/reviews) — it can penalize the domain. Every CTA must reflect exactly what happens on click.
- Derive listings (categories, tags, counts) dynamically from content — never hardcode them.
- One `.astro` component per page section, small and focused. Tailwind utilities in components; global CSS only for tokens/imports.
````

- [ ] **Step 3: Write `templates/frameworks/react.md`**

````markdown
# React SPA rules

- TypeScript strict. No `any`, explicit or implicit. `import type` for type-only imports.
- Data fetching through TanStack Query (or the project's query layer) — never `useEffect + fetch`.
- Components stay presentational; logic lives in hooks and plain modules. If a component both fetches and holds complex logic, split it.
- Tailwind only: no inline `style={{}}` (except unavoidable dynamic values), no CSS modules, no styled-components.
- Shared types live in one place — never duplicated across app layers.
````

- [ ] **Step 4: Write `templates/frameworks/node-backend.md`**

````markdown
# Node/TypeScript backend rules

- Services return `Result`/`ResultAsync` (neverthrow or equivalent): no `throw` and no `try/catch` inside services; errors are values — `err({ code, message })`. Ignoring an error result is a bug.
- Schema validation (Zod or equivalent) at every trust boundary: request bodies/params, environment variables, external API responses. Derive types with `z.infer`; share them from one package — never duplicate.
- Structured logger, never `console.log`.
- Work that doesn't need to block the response (document processing, crawling, batch jobs) goes to a background job runner.
- Any DB query inside a loop is an N+1: batch-select, filter in memory, batch-insert.
- Prefer functional style; `type` over `interface`.
````

- [ ] **Step 5: Write `templates/frameworks/python.md`**

````markdown
# Python rules

- All dependencies live in the project venv. Run through `.venv/bin/python` or the project entrypoint — bare `python` will `ModuleNotFoundError`.
- Entry scripts and CLIs orchestrate only; logic lives in `lib/<domain>/` (or the project's package layout). To add a command, add the thin command layer and put the behavior in the domain module.
- Config-first: behavior changes go to config files first, code second.
- No new dependency without justification.
- Respect the established folder structure; ask before restructuring.
````

- [ ] **Step 6: Commit**

```bash
git add templates/frameworks/
git commit -m "feat: framework rule templates (nextjs, astro, react, node-backend, python)"
```

---

### Task 4: Lazy reference docs

**Files:**
- Create: `templates/docs/testing.md`
- Create: `templates/docs/docs-discipline.md`

**Interfaces:**
- Produces: files installed to `docs/agent/testing.md` and `docs/agent/docs-discipline.md` — the exact paths `base.md` (Task 2) references.

- [ ] **Step 1: Write `templates/docs/testing.md`**

````markdown
# Testing reference

Read this before writing tests.

## What to test

- Pyramid: many unit tests (fast, isolated), some integration tests (mocked externals), few E2E on critical flows only.
- New functionality: happy path + error path minimum.
- Test shipped behavior. Never write placeholder tests, or brittle tests asserting exact internal constants, provider/model defaults, copy text, or internal wiring — they break on refactor without catching bugs.
- A test that cannot fail when the logic breaks is worse than no test.

## E2E gotchas (Playwright)

- Empty-state: tests that require pre-existing data call `test.skip()` when the data is absent — never fail on empty databases.
- Query by role with the full label: `getByRole('option', { name: '0% (Exento)' })` — substring names collide ("0%" also matches "10%").
- Implicit ARIA roles don't match CSS selectors: use `getByRole('heading')`, not `locator('[role="heading"]')`.
- After `fill()` on a controlled input, `await expect(button).toBeEnabled()` before clicking — the framework must commit state first.
- When the same text appears in several regions, scope the locator (e.g. `page.locator('tfoot').getByText(...)`).
- Responsive layouts hide elements per viewport: set an explicit viewport before asserting on tables/columns.
````

- [ ] **Step 2: Write `templates/docs/docs-discipline.md`**

````markdown
# Docs discipline

Read this before creating or reorganizing documentation.

## Two kinds of docs

- **Replicable guides** (`docs/`): numbered, step-by-step, reproducible. Requirements, exact commands, troubleshooting, how to undo. Litmus test: "could someone follow this step by step on a fresh machine?"
- **Reference material** (`docs/reference/`): pricing tables, API snapshots, benchmarks, research. It expires — keep it out of the guides.

## Rules

- Document every new integration/config as its own guide when the project relies on being replicable.
- Specs and plans are scaffolding: delete after implementation. Keep only non-obvious learnings (API gotchas, decisions that will recur) as small docs referenced from where they apply — a skill, a README, a module doc.
- A reference to something that no longer exists is a bug: when you rename/move/change anything, sweep docs and skills and fix every stale reference in the same change.
- Keep examples generic (the reusable pattern), not the specific case you just did.
````

- [ ] **Step 3: Commit**

```bash
git add templates/docs/
git commit -m "feat: lazy reference docs (testing, docs-discipline)"
```

---

### Task 5: AGENTS.md header template + recommendations

**Files:**
- Create: `templates/AGENTS.header.md`
- Create: `recommendations.json`

**Interfaces:**
- Produces: `{{FRAMEWORK_IMPORT}}` placeholder (whole line) that the CLI replaces with `@docs/agent/<file>` or removes for `generic`; `recommendations.json` keyed by framework name (`next`, `react`, `astro`, `node-backend`, `python`, `generic`) plus a `notes` array — exactly the keys the CLI reads in Task 6.

- [ ] **Step 1: Write `templates/AGENTS.header.md`**

````markdown
**Mandatory reading before any work** (Claude Code auto-imports these; other agents: read them now):

@docs/agent/base.md
{{FRAMEWORK_IMPORT}}

## Project

<!-- Project-specific context. Keep it stateless: context + rules, never status/chronology. Suggested sections:
What this is: one paragraph.
Stack: bullet list with versions.
Commands: dev / test / lint / typecheck.
Skills to load: table of | skill | when to load it |
Codebase map: top-level dirs only, one line each.
-->
````

- [ ] **Step 2: Write `recommendations.json`**

```json
{
  "next": [
    "npx add-skill vercel-react-best-practices",
    "npx add-skill vercel-composition-patterns",
    "npx add-skill web-design-guidelines"
  ],
  "react": [
    "npx add-skill vercel-react-best-practices",
    "npx add-skill vercel-composition-patterns",
    "npx add-skill web-design-guidelines"
  ],
  "astro": [
    "npx add-skill web-design-guidelines"
  ],
  "node-backend": [],
  "python": [],
  "generic": [],
  "notes": [
    "Using Supabase? install its skill: npx add-skill supabase",
    "Want the full lazy-dev toolchain (audit/review commands)? install the ponytail plugin - base.md already ships the distilled ruleset"
  ]
}
```

- [ ] **Step 3: Commit**

```bash
git add templates/AGENTS.header.md recommendations.json
git commit -m "feat: AGENTS.md header template and per-framework recommendations"
```

---

### Task 6: Smoke test (init) + CLI with `init`

**Files:**
- Create: `tests/smoke.sh`
- Create: `bin/cli.js`

**Interfaces:**
- Consumes: all template files from Tasks 2-5.
- Produces: `node bin/cli.js init --framework <fw> [--force]` and `node bin/cli.js` (help). `update` exists but exits 1 with "not implemented" (Task 7 replaces it). Helper functions Task 7 reuses: `installFile(src, dest, force)`, `ensureAgentsMd(framework)`, `ensureClaudeMd()`, `kitFiles(framework)`, `report(status, file)`, `FRAMEWORKS` map, `AGENT_DIR`, `TPL(...)`.

- [ ] **Step 1: Write the failing smoke test `tests/smoke.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="node $KIT/bin/cli.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# 1. init --framework next on an empty project
cd "$TMP" && mkdir p1 && cd p1
$CLI init --framework next >out.txt
[ -f docs/agent/base.md ] || fail "base.md missing"
[ -f docs/agent/nextjs.md ] || fail "nextjs.md missing"
[ -f docs/agent/testing.md ] || fail "testing.md missing"
[ -f docs/agent/docs-discipline.md ] || fail "docs-discipline.md missing"
grep -q '^@docs/agent/base.md' AGENTS.md || fail "AGENTS.md missing base import"
grep -q '^@docs/agent/nextjs.md' AGENTS.md || fail "AGENTS.md missing framework import"
grep -q '^## Project' AGENTS.md || fail "AGENTS.md missing Project section"
[ "$(cat CLAUDE.md)" = "@AGENTS.md" ] || fail "CLAUDE.md shim wrong"
grep -q 'vercel-react-best-practices' out.txt || fail "next recommendations not logged"

# 2. re-running init changes nothing (idempotent)
sum_before=$(find . -type f ! -name out.txt -exec shasum {} + | sort | shasum)
$CLI init --framework next >/dev/null
sum_after=$(find . -type f ! -name out.txt -exec shasum {} + | sort | shasum)
[ "$sum_before" = "$sum_after" ] || fail "re-run not idempotent"

# 3. generic installs no framework file and leaks no placeholder
cd "$TMP" && mkdir p2 && cd p2
$CLI init --framework generic >/dev/null
[ ! -f docs/agent/nextjs.md ] || fail "generic must not install a framework file"
grep -q '{{FRAMEWORK_IMPORT}}' AGENTS.md && fail "placeholder leaked into AGENTS.md" || true

# 4. pre-existing AGENTS.md / CLAUDE.md: user content preserved, kit lines added
cd "$TMP" && mkdir p3 && cd p3
printf '# My project\nMy content\n' > AGENTS.md
printf '# Old claude notes\n' > CLAUDE.md
$CLI init --framework astro >/dev/null
grep -q 'My content' AGENTS.md || fail "user AGENTS.md content lost"
head -1 AGENTS.md | grep -q 'Mandatory reading' || fail "header not prepended to AGENTS.md"
grep -q '^@AGENTS.md' CLAUDE.md || fail "@AGENTS.md line not added to CLAUDE.md"
grep -q 'Old claude notes' CLAUDE.md || fail "user CLAUDE.md content lost"

echo "ALL SMOKE TESTS PASSED"
```

- [ ] **Step 2: Make it executable and verify it fails**

```bash
chmod +x tests/smoke.sh
./tests/smoke.sh
```

Expected: FAIL — node exits with `Cannot find module .../bin/cli.js` (set -e aborts the script at section 1).

- [ ] **Step 3: Write `bin/cli.js`**

```js
#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline/promises';
import { fileURLToPath } from 'node:url';

const KIT_ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const TPL = (...p) => path.join(KIT_ROOT, 'templates', ...p);
const AGENT_DIR = path.join('docs', 'agent');
const HEADER_MARK = '@docs/agent/base.md';
const FRAMEWORKS = {
  next: 'nextjs.md',
  astro: 'astro.md',
  react: 'react.md',
  'node-backend': 'node-backend.md',
  python: 'python.md',
  generic: null,
};

const HELP = `agents-kit - install a reusable agent instruction set

Usage:
  npx github:DruMoDev/agents-kit init [--framework <fw>] [--force]
  npx github:DruMoDev/agents-kit update [--framework <fw>]

Frameworks: ${Object.keys(FRAMEWORKS).join(', ')}

init    installs docs/agent rules, AGENTS.md and the CLAUDE.md shim (idempotent)
update  rewrites kit-owned files under docs/agent/ with the latest templates
--force re-copies kit-owned files during init even if locally modified
`;

function die(msg) {
  console.error(msg);
  process.exit(1);
}

function parseArgs(argv) {
  const args = { cmd: argv[0], framework: null, force: false };
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === '--framework' || argv[i] === '-f') args.framework = argv[++i];
    else if (argv[i] === '--force') args.force = true;
    else die(`Unknown argument: ${argv[i]}\n\n${HELP}`);
  }
  if (args.framework && !(args.framework in FRAMEWORKS)) {
    die(`Unknown framework "${args.framework}". Options: ${Object.keys(FRAMEWORKS).join(', ')}`);
  }
  return args;
}

async function promptFramework() {
  const names = Object.keys(FRAMEWORKS);
  names.forEach((n, i) => console.log(`  ${i + 1}. ${n}`));
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await rl.question(`Framework [1-${names.length}]: `);
  rl.close();
  const pick = names[Number(answer) - 1];
  if (!pick) die('Invalid choice.');
  return pick;
}

// Kit-owned files for a framework: [destPath, templatePath][]
function kitFiles(framework) {
  const files = [
    ['base.md', TPL('base.md')],
    ['testing.md', TPL('docs', 'testing.md')],
    ['docs-discipline.md', TPL('docs', 'docs-discipline.md')],
  ];
  const fw = FRAMEWORKS[framework];
  if (fw) files.push([fw, TPL('frameworks', fw)]);
  return files.map(([name, src]) => [path.join(AGENT_DIR, name), src]);
}

function installFile(src, dest, force) {
  const content = fs.readFileSync(src, 'utf8');
  if (!fs.existsSync(dest)) {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, content);
    return 'created';
  }
  if (fs.readFileSync(dest, 'utf8') === content) return 'unchanged';
  if (!force) return 'skipped';
  fs.writeFileSync(dest, content);
  return 'updated';
}

function agentsHeader(framework) {
  const fw = FRAMEWORKS[framework];
  const importLine = fw ? `@docs/agent/${fw}\n` : '';
  return fs.readFileSync(TPL('AGENTS.header.md'), 'utf8').replace('{{FRAMEWORK_IMPORT}}\n', importLine);
}

function ensureAgentsMd(framework) {
  if (!fs.existsSync('AGENTS.md')) {
    fs.writeFileSync('AGENTS.md', agentsHeader(framework));
    return 'created';
  }
  const current = fs.readFileSync('AGENTS.md', 'utf8');
  if (current.includes(HEADER_MARK)) return 'unchanged';
  const header = agentsHeader(framework).split('## Project')[0].trimEnd() + '\n\n';
  fs.writeFileSync('AGENTS.md', header + current);
  return 'updated';
}

function ensureClaudeMd() {
  if (!fs.existsSync('CLAUDE.md')) {
    fs.writeFileSync('CLAUDE.md', '@AGENTS.md\n');
    return 'created';
  }
  const current = fs.readFileSync('CLAUDE.md', 'utf8');
  if (current.split('\n').some((l) => l.trim() === '@AGENTS.md')) return 'unchanged';
  fs.writeFileSync('CLAUDE.md', '@AGENTS.md\n\n' + current);
  return 'updated';
}

function report(status, file) {
  console.log(`  ${status.padEnd(9)} ${file}`);
}

function printNextSteps(framework) {
  const rec = JSON.parse(fs.readFileSync(path.join(KIT_ROOT, 'recommendations.json'), 'utf8'));
  const cmds = rec[framework] ?? [];
  if (cmds.length) {
    console.log('\nRecommended skills for this framework (run them yourself):');
    for (const c of cmds) console.log(`  ${c}`);
  }
  console.log('\nNotes:');
  for (const n of rec.notes) console.log(`  - ${n}`);
}

async function init(args) {
  const framework = args.framework ?? (await promptFramework());
  console.log(`Installing agent rules (framework: ${framework})`);
  for (const [dest, src] of kitFiles(framework)) report(installFile(src, dest, args.force), dest);
  report(ensureAgentsMd(framework), 'AGENTS.md');
  report(ensureClaudeMd(), 'CLAUDE.md');
  printNextSteps(framework);
}

function update(args) {
  die('update: not implemented yet');
}

const args = parseArgs(process.argv.slice(2));
if (args.cmd === 'init') await init(args);
else if (args.cmd === 'update') update(args);
else {
  console.log(HELP);
  if (args.cmd && args.cmd !== 'help') process.exit(1);
}
```

- [ ] **Step 4: Make it executable and run the smoke test**

```bash
chmod +x bin/cli.js
./tests/smoke.sh
```

Expected: `ALL SMOKE TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add bin/cli.js tests/smoke.sh
git commit -m "feat: CLI init command with smoke tests"
```

---

### Task 7: `update` command

**Files:**
- Modify: `bin/cli.js` (replace the `update` stub)
- Modify: `tests/smoke.sh` (add section 5 before the final `echo`)

**Interfaces:**
- Consumes: `kitFiles`, `installFile`, `ensureAgentsMd`, `ensureClaudeMd`, `report`, `FRAMEWORKS`, `AGENT_DIR` from Task 6.
- Produces: `node bin/cli.js update [--framework <fw>]` — overwrites kit-owned files, auto-detects framework from which `docs/agent/<file>` exists.

- [ ] **Step 1: Add the failing smoke section**

In `tests/smoke.sh`, insert before the final `echo "ALL SMOKE TESTS PASSED"`:

```bash
# 5. update overwrites kit-owned edits and auto-detects the framework
cd "$TMP/p1"
echo 'LOCAL EDIT' >> docs/agent/base.md
$CLI update >upd.txt
grep -q 'LOCAL EDIT' docs/agent/base.md && fail "update did not overwrite base.md" || true
grep -q 'Framework: next' upd.txt || fail "update framework detection failed"
grep -q 'My content' "$TMP/p3/AGENTS.md" || fail "sanity: p3 user content"
```

- [ ] **Step 2: Run to verify it fails**

```bash
./tests/smoke.sh
```

Expected: FAIL at section 5 — CLI exits 1 with "update: not implemented yet".

- [ ] **Step 3: Implement `update`** (replace the stub in `bin/cli.js`)

```js
function detectFramework() {
  for (const [name, file] of Object.entries(FRAMEWORKS)) {
    if (file && fs.existsSync(path.join(AGENT_DIR, file))) return name;
  }
  return 'generic';
}

function update(args) {
  const framework = args.framework ?? detectFramework();
  console.log(`Framework: ${framework}`);
  for (const [dest, src] of kitFiles(framework)) report(installFile(src, dest, true), dest);
  report(ensureAgentsMd(framework), 'AGENTS.md');
  report(ensureClaudeMd(), 'CLAUDE.md');
}
```

- [ ] **Step 4: Run the smoke test**

```bash
./tests/smoke.sh
```

Expected: `ALL SMOKE TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add bin/cli.js tests/smoke.sh
git commit -m "feat: update command with framework auto-detection"
```

---

### Task 8: README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: everything — README documents the shipped behavior exactly (commands, layout, framework names).

- [ ] **Step 1: Write `README.md`**

````markdown
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
````

- [ ] **Step 2: Run the smoke test one last time**

```bash
./tests/smoke.sh
```

Expected: `ALL SMOKE TESTS PASSED`

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README with usage, layout, and conventions"
```
