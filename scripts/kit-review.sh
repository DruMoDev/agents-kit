#!/usr/bin/env bash
# Usage: scripts/kit-review.sh <wt> <pr> <herramienta> <modelo> <foco> <ronda> <N>
# Runs one reviewer CLI (claude, opencode, codex) headless in a throwaway detached worktree of <wt>'s HEAD,
# with gh and git push blocked, and posts its report on PR <pr> as a kit-revision comment.
# Env: KIT_REVIEW_TIMEOUT (s, default 1800).
# Exit: 0 ok, 1 usage or rejected, 2 environment error or the reviewer did not deliver.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/github-slug.sh"
source "$here/lib/config.sh"
source "$here/lib/default-branch.sh"
template="$here/../skills/kit-run/references/revisor.md"

usage() {
  echo "uso: $0 <wt> <pr> <herramienta> <modelo> <foco> <ronda> <N>" >&2
  exit 1
}
[ $# -eq 7 ] && [ -n "$1" ] || usage
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
wt="$(cd "$1" && pwd)"
p="$2" tool="$3" model="$4" focus="$5" round="$6" n="$7"
kit_require_marker "$wt" || exit $?
num() { [[ $2 =~ ^[1-9][0-9]*$ ]] || { echo "$1 inválido: $2" >&2; exit 1; }; }
num "número de PR" "$p"; num "número de ronda" "$round"; num "número de issue" "$n"
[ -n "$model" ] || { echo "falta el modelo" >&2; exit 1; }
[ -n "$focus" ] || { echo "falta el foco" >&2; exit 1; }
timeout="${KIT_REVIEW_TIMEOUT:-1800}"
[[ $timeout =~ ^[1-9][0-9]*$ ]] || { echo "error: KIT_REVIEW_TIMEOUT debe ser un número de segundos" >&2; exit 2; }

case "$tool" in claude|opencode|codex) ;; *) echo "revisor no disponible: $tool" >&2; exit 2 ;; esac
command -v "$tool" >/dev/null 2>&1 || { echo "revisor no disponible: $tool" >&2; exit 2; }
for c in gh git jq perl; do
  command -v "$c" >/dev/null 2>&1 || { echo "error: falta '$c' en el PATH" >&2; exit 2; }
done
[ -r "$template" ] || { echo "error: no se encuentra la plantilla del revisor: $template" >&2; exit 2; }
cd "$wt" || exit 2
slug="$(kit_origin_slug)"
[ -n "$slug" ] || { echo "error: el remoto 'origin' no es de GitHub" >&2; exit 2; }

tmpd="$(mktemp -d)" || exit 2
scratch="$tmpd/wt"
cleanup() {
  # the throwaway worktree is ours alone: force-remove it, then the directory as a fallback
  [ -e "$scratch" ] && git -C "$wt" worktree remove --force "$scratch" >/dev/null 2>&1
  rm -rf "$tmpd"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# prompt inputs
issue="$(gh issue view "$n" --repo "$slug" --json title,body | jq -r '"# \(.title)\n\n\(.body // "")"')" \
  || { echo "error: no se pudo leer el issue #$n" >&2; exit 2; }
b="$(kit_default_branch)"
[ -n "$b" ] || { echo "error: no pude saber la rama por defecto de origin" >&2; exit 2; }
git fetch -q origin "+refs/heads/$b:refs/remotes/origin/$b" || { echo "error: git fetch falló" >&2; exit 2; }
hist="$(bash "$here/kit-pr.sh" historial "$wt" "$p")" || { echo "error: no se pudo leer el historial de la PR #$p" >&2; exit 2; }
hist="$(printf '%s\n' "$hist" | sed '${/^FIN: /d;}')"
# single pass, so text inside the substituted values is never re-expanded
prompt="$(jq -Rrs --arg FOCO "$focus" --arg RONDA "$round" --arg ISSUE "$issue" --arg BASE "origin/$b" --arg HISTORIAL "$hist" \
  '$ARGS.named as $m | gsub("\\{\\{(?<k>FOCO|RONDA|ISSUE|BASE|HISTORIAL)\\}\\}"; $m[.k])' "$template")" \
  || { echo "error: no se pudo construir el prompt" >&2; exit 2; }

git worktree add -q --detach "$scratch" HEAD >/dev/null 2>&1 \
  || { echo "error: no se pudo crear el worktree desechable" >&2; exit 2; }

limit=(perl -e 'alarm shift; exec @ARGV or exit 127' "$timeout")
oc_cfg='{"permission":{"bash":{"*":"allow","gh *":"deny","git push*":"deny"},"edit":"allow","external_directory":"deny"}}'
# outer 2>/dev/null only silences the shell's own "Alarm clock" job notice; the reviewer's stderr goes to err
{ (
  cd "$scratch" || exit 2
  case "$tool" in
    claude)
      exec "${limit[@]}" claude -p --model "$model" --permission-mode bypassPermissions \
        --disallowedTools "Bash(git push:*)" "Bash(gh:*)" --output-format text "$prompt" ;;
    opencode)
      OPENCODE_CONFIG_CONTENT="$oc_cfg" exec "${limit[@]}" opencode run -m "$model" "$prompt" ;;
    codex)
      exec "${limit[@]}" codex exec -m "$model" --sandbox workspace-write "$prompt" ;;
  esac
) </dev/null >"$tmpd/out" 2>"$tmpd/err"; rc=$?; } 2>/dev/null

strip() { sed $'s/\x1b\\[[0-9;?]*[A-Za-z]//g; s/\r$//' "$1"; }
undelivered() {
  echo "el revisor $tool/$model no entregó: $1" >&2
  if [ -s "$tmpd/err" ]; then
    echo "salida de error del revisor:" >&2
    strip "$tmpd/err" >&2
  fi
  exit 2
}
if [ $rc -eq 142 ]; then undelivered "agotó el tiempo (${timeout}s)"; fi
[ $rc -eq 0 ] || undelivered "terminó con código $rc"
strip "$tmpd/out" > "$tmpd/clean"
# report: from the first finding after the previous HALLAZGOS line (if any) through the last HALLAZGOS line
awk '
  { line[NR] = $0 }
  /^[[:space:]]*HALLAZGOS: [0-9]+[[:space:]]*$/ { prev = last; last = NR }
  END {
    if (!last) exit 3
    s = last
    for (i = prev + 1; i < last; i++) if (line[i] ~ /^[[:space:]]*[0-9]+\. \[(grave|medio|menor)\]/) { s = i; break }
    for (i = s; i <= last; i++) print line[i]
  }' "$tmpd/clean" > "$tmpd/report" || undelivered "la salida no tiene una línea HALLAZGOS: <n>"
total="$(sed -n '$s/^[[:space:]]*HALLAZGOS: \([0-9]*\).*/\1/p' "$tmpd/report")"
[ -n "$total" ] || undelivered "la salida no tiene una línea HALLAZGOS: <n>"

{
  echo "<!-- kit-revision: $tool/$model ronda $round -->"
  cat "$tmpd/report"
} > "$tmpd/body"
gh pr comment "$p" --repo "$slug" --body-file "$tmpd/body" >/dev/null \
  || { echo "error: no se pudo comentar en la PR #$p" >&2; exit 2; }
cat "$tmpd/report"
echo "FIN: $total hallazgos"
