#!/usr/bin/env bash
# Usage: bash .agents-kit/turno.sh <fichero>...
# End-of-turn check of agents-kit (the "lint.turno" of .agents-kit.json; the Stop hook runs it from the repo root with
# the changed files that exist, each with ./ in front). Copied from templates/reglas/turno.sh by the kit-reglas skill.
#   - Types: node .agents-kit/tsc-base.mjs comprobar --cambiados <the files with a TSC_EXT extension>: no new tsc errors
#     against .agents-kit/tsc-base.json, and the changed files left at zero.
#   - Lint: typed ESLint, with cache, over the files with a LINT_EXT extension (compared without case).
# Nothing runs when no file has either extension. Local binaries only (never a download): without them, exit 127,
# which the hook does not block on (the guarantee is kit-pr.sh fusionar and the CI).
# Env: KIT_TSC (tsc command, default node_modules/.bin/tsc), KIT_ESLINT (default node_modules/.bin/eslint).
# Exit: 0 ok (FIN: ok, or FIN: nada que comprobar), 1 errors (printed), 127 missing tools.
set -u

# Extensions of this repo (kit-reglas adjusts them; space separated, lower case).
TSC_EXT="ts tsx mts cts"
LINT_EXT="ts tsx mts cts js jsx mjs cjs"
CACHE="node_modules/.cache/agents-kit/eslint-tipos"

tipos=(); lint=()
for f in "$@"; do
  base="${f##*/}"
  case "$base" in ?*.*) ext="${base##*.}" ;; *) continue ;; esac
  ext="$(printf '%s' "$ext" | tr 'A-Z' 'a-z')"
  case " $TSC_EXT " in *" $ext "*) tipos+=("$f") ;; esac
  case " $LINT_EXT " in *" $ext "*) lint+=("$f") ;; esac
done
if [ ${#tipos[@]} -eq 0 ] && [ ${#lint[@]} -eq 0 ]; then
  echo "FIN: nada que comprobar"
  exit 0
fi

falta=()
command -v node >/dev/null 2>&1 || falta+=("node")
if [ -z "${KIT_TSC:-}" ]; then
  [ -x node_modules/.bin/tsc ] || falta+=("node_modules/.bin/tsc")
  export KIT_TSC=node_modules/.bin/tsc
fi
eslint="${KIT_ESLINT:-node_modules/.bin/eslint}"
[ ${#lint[@]} -eq 0 ] || [ -n "${KIT_ESLINT:-}" ] || [ -x "$eslint" ] || falta+=("$eslint")
if [ ${#falta[@]} -gt 0 ]; then
  echo "agents-kit: falta ${falta[*]} (¿sin node_modules? instala las dependencias del repo); no se comprueba el turno" >&2
  exit 127
fi

rc=0
if [ ${#tipos[@]} -gt 0 ]; then
  node .agents-kit/tsc-base.mjs comprobar --cambiados "${tipos[@]}" || rc=1
else
  node .agents-kit/tsc-base.mjs comprobar || rc=1
fi
if [ ${#lint[@]} -gt 0 ]; then
  $eslint --cache --cache-location "$CACHE" --no-warn-ignored "${lint[@]}" || rc=1
fi
[ $rc -eq 0 ] || exit 1
echo "FIN: ok"
