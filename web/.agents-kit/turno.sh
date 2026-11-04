#!/usr/bin/env bash
# Usage: bash .agents-kit/turno.sh <fichero>...
# End-of-turn check of agents-kit (the "lint.turno" of .agents-kit.json; the Stop hook runs it from the repo root, or
# from the directory of a TS project of a monorepo, with its changed files that exist, each with ./ in front). Copied from templates/reglas/turno.sh by the kit-reglas skill.
#   - Types: node .agents-kit/tsc-base.mjs comprobar --cambiados <the files with a TSC_EXT extension>: no new tsc errors
#     against .agents-kit/tsc-base.json, and the changed files left at zero. A changed *tsconfig*.json (name without
#     case) also runs it, with --cambiados only if there are such files. Without .agents-kit/tsc-base.mjs, exit 1.
#     With TSC_EXT empty (a JS project without checkJs: tsc checks nothing there) there are no types: no tsc, no
#     tsc-base.mjs.
#   - Lint: typed ESLint, with cache, over the files with a LINT_EXT extension (compared without case).
# Nothing runs when no file has either extension and no tsconfig changed. Local binaries only (never a download): without them, exit 127,
# which the hook does not block on (the guarantee is kit-pr.sh fusionar and the CI).
# Env: KIT_TSC (tsc command, default $TSC), KIT_ESLINT (default node_modules/.bin/eslint).
# Exit: 0 ok (FIN: ok, or FIN: nada que comprobar), 1 errors (printed) or no .agents-kit/tsc-base.mjs, 127 missing tools.
set -u

# Of this repo or TS project (kit-reglas adjusts them). Extensions space separated, lower case. A JS project without
# checkJs: TSC_EXT="".
TSC_EXT="ts tsx mts cts"
LINT_EXT="ts tsx mts cts js jsx mjs cjs astro"
# tsc when KIT_TSC is not set (TypeScript 7 next to the API of TS 6: node_modules/typescript7/bin/tsc).
TSC="node_modules/typescript7/bin/tsc"
# Run before the types, output hidden unless it fails (Astro: node_modules/.bin/astro sync, for .astro/types.d.ts).
ANTES_TSC="node_modules/.bin/astro sync"
CACHE="node_modules/.cache/agents-kit/eslint-tipos"

tipos=(); lint=(); tsconfig=false
for f in "$@"; do
  base="${f##*/}"
  case "$(printf '%s' "$base" | tr 'A-Z' 'a-z')" in *tsconfig*.json) tsconfig=true ;; esac
  case "$base" in ?*.*) ext="${base##*.}" ;; *) continue ;; esac
  ext="$(printf '%s' "$ext" | tr 'A-Z' 'a-z')"
  case " $TSC_EXT " in *" $ext "*) tipos+=("$f") ;; esac
  case " $LINT_EXT " in *" $ext "*) lint+=("$f") ;; esac
done
[ -n "$TSC_EXT" ] || tsconfig=false
if [ ${#tipos[@]} -eq 0 ] && [ ${#lint[@]} -eq 0 ] && [ "$tsconfig" = false ]; then
  echo "FIN: nada que comprobar"
  exit 0
fi
if [ -n "$TSC_EXT" ] && [ ! -f .agents-kit/tsc-base.mjs ]; then
  echo "falta .agents-kit/tsc-base.mjs: cópialo con kit-reglas" >&2
  exit 1
fi

falta=()
command -v node >/dev/null 2>&1 || falta+=("node")
if [ -n "$TSC_EXT" ] && [ -z "${KIT_TSC:-}" ]; then
  [ -x "$TSC" ] || falta+=("$TSC")
  export KIT_TSC="$TSC"
fi
eslint="${KIT_ESLINT:-node_modules/.bin/eslint}"
[ ${#lint[@]} -eq 0 ] || [ -n "${KIT_ESLINT:-}" ] || [ -x "$eslint" ] || falta+=("$eslint")
if [ ${#falta[@]} -gt 0 ]; then
  echo "agents-kit: falta ${falta[*]} (¿sin node_modules? instala las dependencias del repo); no se comprueba el turno" >&2
  exit 127
fi

rc=0
if [ -n "$TSC_EXT" ] && [ -n "$ANTES_TSC" ] && ! salida="$($ANTES_TSC 2>&1)"; then
  printf '%s\n' "$salida"
  echo "agents-kit: falló '$ANTES_TSC', lo de antes de los tipos" >&2
  exit 1
fi
if [ -z "$TSC_EXT" ]; then
  :
elif [ ${#tipos[@]} -gt 0 ]; then
  node .agents-kit/tsc-base.mjs comprobar --cambiados "${tipos[@]}" || rc=1
else
  node .agents-kit/tsc-base.mjs comprobar || rc=1
fi
if [ ${#lint[@]} -gt 0 ]; then
  $eslint --cache --cache-location "$CACHE" --no-warn-ignored "${lint[@]}" || rc=1
fi
[ $rc -eq 0 ] || exit 1
echo "FIN: ok"
