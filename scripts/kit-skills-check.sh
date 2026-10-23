#!/usr/bin/env bash
# Usage: scripts/kit-skills-check.sh <root> [--excluir <ruta>]...
# Fails when a skill cites, in inline code, a file that does not exist. Reads <root>/.agents/skills/*/SKILL.md and
# */references/*.md (and <root>/skills/ when <root> is the kit itself). Fenced blocks are skipped.
# A citation is a token with "/" and without placeholders (<>, *, $, ~, :, ..); it is checked when its first component
# exists in the skill directory, in <root> or in another skill (references/... of a sibling), and it is fine when it
# exists in any of them. A Python module counts as a file: "lib/x" or "lib/x.func" when lib/x.py exists. Paths that
# .gitignore excludes are skipped (secrets, outputs). "scripts/kit-*" and anything after ${CLAUDE_PLUGIN_ROOT}/ or
# $PLUGIN/ are files of the kit. Other paths that only exist at run time are excluded by path (--excluir <ruta> skips
# that path and everything under it), never by the text of the line.
# Output: one line per broken citation on stderr ("<fichero>:<línea>: <cita> no existe"); FIN: <n> citas comprobadas.
# Exit: 0 ok, 1 usage or broken citations, 2 environment error.
set -u
kit="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() { echo "uso: $0 <root> [--excluir <ruta>]..." >&2; exit 1; }
[ $# -ge 1 ] && [ -n "$1" ] || usage
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
root="$(cd "$1" && pwd)"; shift
excl=()
while [ $# -gt 0 ]; do
  case "$1" in
    --excluir) [ $# -ge 2 ] && [ -n "$2" ] || usage; e="${2#./}"; excl+=("${e%/}"); shift 2 ;;
    *) usage ;;
  esac
done

files=()
for f in "$root"/.agents/skills/*/SKILL.md "$root"/.agents/skills/*/references/*.md; do
  [ -f "$f" ] && files+=("$f")
done
self=false
if [ "$(jq -r '.name // empty' "$root/.claude-plugin/plugin.json" 2>/dev/null)" = agents-kit ]; then
  self=true
  for f in "$root"/skills/*/SKILL.md "$root"/skills/*/references/*.md; do
    [ -f "$f" ] && files+=("$f")
  done
fi
$self && kit="$root"

skilldirs=()
for d in "$root"/.agents/skills/*/; do [ -d "$d" ] && skilldirs+=("${d%/}"); done
ignored() { # <path>: true if .gitignore excludes it (never when <root> is not a git repo)
  git -C "$root" check-ignore -q -- "$1" 2>/dev/null || git -C "$root" check-ignore -q -- "$1/" 2>/dev/null
}
exists_in() { # <base> <path>: the file, or the Python module it names ("lib/x" or "lib/x.func" for lib/x.py)
  [ -e "$1/$2" ] || [ -e "$1/$2.py" ] && return 0
  case "${2##*.}" in md|py|sh|js|mjs|ts|tsx|json|yml|yaml|toml|txt|html|css|csv|ndjson|jpg|png|mp4|mov) return 1 ;; esac
  case "${2##*/}" in *.*) [ -e "$1/${2%.*}.py" ] ;; *) return 1 ;; esac
}

excluded() { # <path>
  local e
  for e in ${excl[@]+"${excl[@]}"}; do
    [ "$1" = "$e" ] || [ "${1#"$e"/}" != "$1" ] && return 0
  done
  return 1
}

checked=0; broken=0
for f in ${files[@]+"${files[@]}"}; do
  case "$f" in */references/*) sdir="$(dirname "$(dirname "$f")")" ;; *) sdir="$(dirname "$f")" ;; esac
  rel="${f#"$root"/}"
  # "<line>TAB<token>" for every word of every inline code span outside fenced blocks
  while IFS=$'\t' read -r line tok; do
    base=""
    case "$tok" in
      '${CLAUDE_PLUGIN_ROOT}/'*) tok="${tok#'${CLAUDE_PLUGIN_ROOT}/'}"; base="$kit" ;;
      '$CLAUDE_PLUGIN_ROOT/'*) tok="${tok#'$CLAUDE_PLUGIN_ROOT/'}"; base="$kit" ;;
      '$PLUGIN/'*) tok="${tok#'$PLUGIN/'}"; base="$kit" ;;
    esac
    tok="${tok#./}"
    while case "$tok" in */|*.|*:|*,) true ;; *) false ;; esac; do tok="${tok%?}"; done
    case "$tok" in */*) ;; *) continue ;; esac
    case "$tok" in /*|*'<'*|*'>'*|*'*'*|*'$'*|*'~'*|*:*|*..*|*'{'*|*'}'*|*'['*|*'?'*|*'#'*|*'@'*) continue ;; esac
    first="${tok%%/*}"
    bases=()
    if [ -n "$base" ]; then bases=("$base")
    else
      case "$tok" in
        scripts/kit-*) bases=("$kit") ;;
        *) for b in "$sdir" "$root" ${skilldirs[@]+"${skilldirs[@]}"}; do [ -e "$b/$first" ] && bases+=("$b"); done ;;
      esac
    fi
    [ ${#bases[@]} -gt 0 ] || continue
    excluded "$tok" && continue
    [ -z "$base" ] && [ "${bases[0]}" != "$kit" ] && ignored "$tok" && continue
    checked=$((checked + 1))
    ok=false
    for b in "${bases[@]}"; do exists_in "$b" "$tok" && { ok=true; break; }; done
    if ! $ok; then
      echo "$rel:$line: $tok no existe" >&2
      broken=$((broken + 1))
    fi
  done < <(awk '
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    {
      s = $0
      while (match(s, /`[^`]+`/)) {
        span = substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH)
        n = split(span, w, /[ \t"\047(),;=|]+/)
        for (i = 1; i <= n; i++) if (w[i] != "") print NR "\t" w[i]
      }
    }' "$f")
done
[ "$broken" -eq 0 ] || exit 1
echo "FIN: $checked citas comprobadas"
