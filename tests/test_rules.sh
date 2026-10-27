#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1

rules="$REPO_ROOT/rules"
for f in core.md flujo.md sin-flujo.md testing.md docs-discipline.md; do
  [ -s "$rules/$f" ] || fail "rules/$f missing or empty"
done

for h in "## Escribe menos código" "## Tests y verificación" "## Producto vs implementación" "## Git" "## Automejora"; do
  grep -q "^$h" "$rules/core.md" || fail "core.md missing heading: $h"
done

lines="$(wc -l < "$rules/core.md")"
[ "$lines" -le 140 ] || fail "core.md has $lines lines (max 140)"

for ref in rules/testing.md rules/docs-discipline.md; do
  grep -qF "$ref" "$rules/core.md" || fail "core.md does not reference $ref"
done

# v3: precedence with its limit, content paths, method rules
for w in 'manda el proyecto' 'kit-skills-check.sh' 'por ruta' 'sin verificar' 'sección del flujo'; do
  grep -qF "$w" "$rules/core.md" || fail "core.md must cover: $w"
done
# the kit's own flow (PR, issues, kit-run, worktrees) lives only in flujo.md; with "flujo": false, sin-flujo.md defers to
# the repo's own flow and points to the local review
for w in 'por PR con squash merge' '`contenido`' 'kit-run <N>' 'worktree' '`propuesta`' 'CHANGELOG.md'; do
  grep -qF "$w" "$rules/flujo.md" || fail "flujo.md must cover: $w"
  if grep -qF "$w" "$rules/core.md"; then fail "core.md must not hold the kit flow: $w"; fi
done
for w in 'flujo propio del proyecto' 'kit-revisar' '"flujo": false'; do
  grep -qF "$w" "$rules/sin-flujo.md" || fail "sin-flujo.md must cover: $w"
done

if grep -rlF "docs/agent/" "$rules"; then fail "rules/ references docs/agent/"; fi
if grep -rlF "—" "$rules"; then fail "rules/ contains em dashes"; fi
echo "ok"
