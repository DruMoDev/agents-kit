#!/usr/bin/env bash
# Usage: bash web/.agents-kit/lint-fichero.sh <fichero>...
# The "lint.fichero" of this repo for web/: the hooks run it from the repo root with paths from the root (./web/...),
# but ESLint has to run inside web/ (its suppressions are relative to web/, and astro-eslint-parser loads typescript
# from the cwd). Lint per edit, without types and with cache; files outside web/ are skipped.
# Exit: ESLint's (127 without web/node_modules: the hook does not block).
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
args=()
for f in "$@"; do
  f="${f#./}"
  case "$f" in web/*) args+=("./${f#web/}") ;; esac
done
[ ${#args[@]} -gt 0 ] || exit 0
[ -x node_modules/.bin/eslint ] || { echo "falta web/node_modules: ejecuta npm ci en web/" >&2; exit 127; }
KIT_LINT_RAPIDO=1 exec node_modules/.bin/eslint --cache --cache-location node_modules/.cache/agents-kit/eslint-rapido \
  --no-warn-ignored --pass-on-unpruned-suppressions "${args[@]}"
