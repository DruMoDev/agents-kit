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
