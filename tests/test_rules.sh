#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1

rules="$REPO_ROOT/rules"
for f in core.md testing.md docs-discipline.md; do
  [ -s "$rules/$f" ] || fail "rules/$f missing or empty"
done

for h in "## Escribe menos código" "## Tests y verificación" "## Producto vs implementación" "## Flujo git" "## Automejora"; do
  grep -q "^$h" "$rules/core.md" || fail "core.md missing heading: $h"
done

lines="$(wc -l < "$rules/core.md")"
[ "$lines" -le 140 ] || fail "core.md has $lines lines (max 140)"

for ref in rules/testing.md rules/docs-discipline.md; do
  grep -qF "$ref" "$rules/core.md" || fail "core.md does not reference $ref"
done

# v3: precedence with its limit, content paths, method rules
for w in 'manda el proyecto' '`contenido`' 'kit-run <N>' 'kit-skills-check.sh' 'por ruta' 'sin verificar' 'worktree'; do
  grep -qF "$w" "$rules/core.md" || fail "core.md must cover: $w"
done

if grep -rlF "docs/agent/" "$rules"; then fail "rules/ references docs/agent/"; fi
if grep -rlF "—" "$rules"; then fail "rules/ contains em dashes"; fi
echo "ok"
