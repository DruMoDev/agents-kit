#!/usr/bin/env bash
# Usage: scripts/kit-worktree.sh <subcomando> <root> [args...]
#   abrir   <root> <N> <slug>
#   limpiar <root> <N>
# Worktree per issue: ${KIT_WORKTREES:-$HOME/.agents-kit/worktrees}/<repo>/issue-<N>-<slug>.
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/github-slug.sh"
source "$here/lib/config.sh"

usage() {
  echo "uso: $0 abrir <root> <N> <slug> | limpiar <root> <N>" >&2
  exit 1
}

[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1"; shift
case "$sub" in abrir|limpiar) ;; *) usage ;; esac
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
root="$(cd "$1" && pwd)"; shift
kit_require_marker "$root" || exit $?
case "$sub" in
  abrir) [ $# -eq 2 ] || usage ;;
  limpiar) [ $# -eq 1 ] || usage ;;
esac
n="$1"
[[ $n =~ ^[1-9][0-9]*$ ]] || { echo "número de issue inválido: $n" >&2; exit 1; }
if [ "$sub" = abrir ]; then
  [[ $2 =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { echo "slug inválido: $2" >&2; exit 1; }
fi

for c in git jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "error: falta '$c' en el PATH" >&2; exit 2; }
done
cd "$root" || exit 2

# wt_of <branch>: print the worktree path where the branch is checked out (empty if none).
wt_of() {
  git worktree list --porcelain | awk -v b="refs/heads/$1" '
    /^worktree / { p = substr($0, 10) }
    $0 == "branch " b { print p; exit }'
}

if [ "$sub" = abrir ]; then
  branch="issue-$n-$2"
  path="${KIT_WORKTREES:-$HOME/.agents-kit/worktrees}/$(basename "$root")/$branch"
  base="$(git ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p')"
  [ -n "$base" ] || { echo "error: no pude saber la rama por defecto de origin" >&2; exit 2; }
  git fetch -q origin "$base" || { echo "error: git fetch falló" >&2; exit 2; }

  existing="$(wt_of "$branch")"
  if [ -n "$existing" ]; then
    echo "ya existía"
    # keep the canonical spelling when git reports the same directory through a symlink
    [ "$(cd "$existing" && pwd -P)" = "$(cd "$path" 2>/dev/null && pwd -P)" ] || path="$existing"
  elif [ -e "$path" ]; then
    echo "la ruta $path ya existe y no es el worktree de $branch" >&2
    exit 1
  else
    mkdir -p "$(dirname "$path")" || exit 2
    if git rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
      git worktree add -q "$path" "$branch" || exit 2
    else
      git worktree add -q -b "$branch" --no-track "$path" "origin/$base" || exit 2
    fi
  fi
  echo "worktree: $path"
  echo "rama: $branch"
  echo "FIN: $path"
  exit 0
fi

# limpiar
branch="$(git worktree list --porcelain | sed -n "s|^branch refs/heads/\\(issue-$n-.*\\)\$|\\1|p")"
[ -n "$branch" ] || { echo "no hay worktree para el issue $n" >&2; exit 1; }
[ "$(printf '%s\n' "$branch" | wc -l)" -eq 1 ] || { echo "hay varios worktrees para el issue $n" >&2; exit 1; }
path="$(wt_of "$branch")"
command -v gh >/dev/null 2>&1 || { echo "error: falta 'gh' en el PATH" >&2; exit 2; }
slug="$(kit_origin_slug)"
[ -n "$slug" ] || { echo "error: el remoto 'origin' no es de GitHub" >&2; exit 2; }
prs="$(gh pr list --repo "$slug" --head "$branch" --state all --json number,state)" \
  || { echo "error: gh pr list falló" >&2; exit 2; }
printf '%s' "$prs" | jq -e 'any(.[]; .state == "MERGED")' >/dev/null 2>&1 \
  || { echo "la PR de $branch no está fusionada" >&2; exit 1; }
status="$(git -C "$path" status --porcelain)" || exit 2
[ -z "$status" ] || { echo "el worktree tiene cambios; no se borra nada" >&2; exit 1; }
git worktree remove "$path" || exit 2
git branch -D "$branch" >/dev/null || exit 2
git fetch -q --prune origin || exit 2
echo "FIN: limpio"
