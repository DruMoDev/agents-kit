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
