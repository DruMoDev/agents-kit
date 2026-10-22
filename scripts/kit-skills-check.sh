#!/usr/bin/env bash
# Usage: scripts/kit-skills-check.sh <root> [--excluir <ruta>]...
# Fails when a skill cites, in inline code, a file that does not exist. Reads <root>/.agents/skills/*/SKILL.md and
# */references/*.md (and <root>/skills/ when <root> is the kit itself). Fenced blocks are skipped.
# A citation is a token with "/" and without placeholders (<>, *, $, ~, :, ..); it is checked when its first component
# exists: in the skill directory (references/...), else in <root>. "scripts/kit-*" and anything after
# ${CLAUDE_PLUGIN_ROOT}/ or $PLUGIN/ are files of the kit. Paths that only exist at run time are excluded by path
# (--excluir <ruta> skips that path and everything under it), never by the text of the line.
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
    if [ -z "$base" ]; then
      case "$tok" in
        scripts/kit-*) base="$kit" ;;
        *) if [ -e "$sdir/$first" ]; then base="$sdir"; elif [ -e "$root/$first" ]; then base="$root"; else continue; fi ;;
      esac
    fi
    excluded "$tok" && continue
    checked=$((checked + 1))
    if [ ! -e "$base/$tok" ]; then
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
