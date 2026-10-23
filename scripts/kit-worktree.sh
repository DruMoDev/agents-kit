#!/usr/bin/env bash
# Usage: scripts/kit-worktree.sh <subcomando> <root> [args...]
#   abrir   <root> <N> <slug>
#   limpiar <root> <N>
#   barrer  <root>
# Worktree per issue: ${KIT_WORKTREES:-$HOME/.agents-kit/worktrees}/<repo>/issue-<N>-<slug>.
# limpiar: after the merge, removes the issue's worktree and branch and fast-forwards <root> (update_main).
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/github-slug.sh"
source "$here/lib/config.sh"
source "$here/lib/default-branch.sh"
source "$here/lib/repo-hook.sh"

usage() {
  echo "uso: $0 abrir <root> <N> <slug> | limpiar <root> <N> | barrer <root>" >&2
  exit 1
}

[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1"; shift
case "$sub" in abrir|limpiar|barrer) ;; *) usage ;; esac
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
root="$(cd "$1" && pwd)"; shift
kit_require_marker "$root" || exit $?
case "$sub" in
  abrir) [ $# -eq 2 ] || usage ;;
  limpiar) [ $# -eq 1 ] || usage ;;
  barrer) [ $# -eq 0 ] || usage ;;
esac
n="${1:-}"
[ "$sub" = barrer ] || [[ $n =~ ^[1-9][0-9]*$ ]] || { echo "número de issue inválido: $n" >&2; exit 1; }
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
  base="$(kit_default_branch)"
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
      # a branch that only exists on origin (issue resumed elsewhere) is the start point; else origin/<default>
      start="origin/$base"
      git ls-remote --exit-code --heads origin "refs/heads/$branch" >/dev/null 2>&1; rc=$?
      case $rc in
        0) git fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch" \
             || { echo "error: git fetch de $branch falló" >&2; exit 2; }
           start="origin/$branch" ;;
        2) ;;
        *) echo "error: git ls-remote falló" >&2; exit 2 ;;
      esac
      git worktree add -q -b "$branch" --no-track "$path" "$start" || exit 2
    fi
  fi
  # setup of the repo: once per worktree (a marker in its git dir records success, so a retry after a failure runs it again)
  setup="$(kit_config "$root" 'if (.setup | type) == "string" then .setup else empty end')" || exit 2
  gd="$(git -C "$path" rev-parse --absolute-git-dir)" || exit 2
  if [ -n "$setup" ] && [ ! -e "$gd/kit-setup-ok" ]; then
    script="$(kit_hook_path "$root" "$path" setup "$setup")" || exit 2
    kit_hook_run "$path" "$script"; src=$?
    if [ "$src" -ne 0 ]; then
      if [ "$src" -eq 142 ]; then echo "setup agotó el tiempo (${KIT_HOOK_TIMEOUT:-1800}s):" >&2
      else echo "setup falló (exit $src):" >&2; fi
      printf '%s\n' "$KIT_HOOK_OUT" >&2
      exit 2
    fi
    : > "$gd/kit-setup-ok"
  fi
  echo "worktree: $path"
  echo "rama: $branch"
  echo "FIN: $path"
  exit 0
fi

if [ "$sub" = barrer ]; then
  base="$(kit_default_branch)"
  [ -n "$base" ] || { echo "error: no pude saber la rama por defecto de origin" >&2; exit 2; }
  git fetch -q origin "+refs/heads/$base:refs/remotes/origin/$base" || { echo "error: git fetch falló" >&2; exit 2; }
  command -v gh >/dev/null 2>&1 || { echo "error: falta 'gh' en el PATH" >&2; exit 2; }
  slug="$(kit_origin_slug)"
  [ -n "$slug" ] || { echo "error: el remoto 'origin' no es de GitHub" >&2; exit 2; }
  dir="${KIT_WORKTREES:-$HOME/.agents-kit/worktrees}/$(basename "$root")"
  [ -d "$dir" ] || { echo "FIN: 0 borrados"; exit 0; }
  dir="$(cd "$dir" && pwd -P)"
  main="$(cd "$root" && pwd -P)"
  count=0
  while IFS= read -r p; do
    [ -n "$p" ] && [ -d "$p" ] || continue
    rp="$(cd "$p" && pwd -P)"
    case "$rp" in "$dir"/*) ;; *) continue ;; esac   # only the kit's worktrees of this repo
    [ "$rp" != "$main" ] || continue
    b="$(git -C "$p" symbolic-ref -q --short HEAD)" || continue
    st="$(git -C "$p" status --porcelain)" || continue
    [ -z "$st" ] || { echo "aviso: $p tiene cambios; no se borra" >&2; continue; }
    h="$(git -C "$p" rev-parse HEAD)" || continue
    # dead = (a) merged PR whose head is the branch tip, or (b) closed issue and no commits beyond the base
    dead=false
    prs="$(gh pr list --repo "$slug" --head "$b" --state all --json number,state,headRefOid)" \
      || { echo "aviso: gh pr list falló para $b; no se borra $p" >&2; continue; }
    if printf '%s' "$prs" | jq -e --arg t "$h" 'any(.[]; .state == "MERGED" and .headRefOid == $t)' >/dev/null 2>&1; then
      dead=true
    elif [[ $b =~ ^issue-([0-9]+)- ]]; then
      ist="$(gh issue view "${BASH_REMATCH[1]}" --repo "$slug" --json state --jq .state)" \
        || { echo "aviso: gh issue view falló para $b; no se borra $p" >&2; continue; }
      if [ "$ist" = CLOSED ]; then
        ahead="$(git -C "$p" rev-list --count "refs/remotes/origin/$base..HEAD")" || continue
        [ "$ahead" = 0 ] && dead=true
      fi
    fi
    [ "$dead" = true ] || continue
    git worktree remove "$p" || { echo "aviso: no se pudo borrar $p" >&2; continue; }
    git branch -D "$b" >/dev/null 2>&1 || echo "aviso: no se pudo borrar la rama $b" >&2
    echo "borrado: $p"
    count=$((count + 1))
  done < <(git worktree list --porcelain | sed -n 's/^worktree //p')
  echo "FIN: $count borrados"
  exit 0
fi

# update_main: bring what was just merged to the main clone (<root>), where Dru works, so the session can keep going
# with the fix without a manual pull. Only --ff-only and only on the default branch: git itself refuses when the
# advance would overwrite a modified file, so uncommitted work is never touched. Not a failure of limpiar (that is
# done): prints "principal al día con origin/<base> (<sha>)" or an "AVISO: ..." on stderr saying why not.
update_main() {
  local base cur err
  base="$(kit_default_branch)"
  [ -n "$base" ] || { echo "AVISO: no pude saber la rama por defecto de origin: el principal NO está al día." >&2; return 0; }
  cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [ "$cur" != "$base" ]; then
    echo "AVISO: el repo principal está en '$cur', no en '$base': no se actualiza." >&2
    return 0
  fi
  if ! git fetch -q origin "$base" 2>/dev/null; then
    echo "AVISO: no se pudo hacer fetch de origin/$base: el principal NO está al día." >&2
    return 0
  fi
  if err="$(git merge --ff-only -q "origin/$base" 2>&1)"; then
    echo "principal al día con origin/$base ($(git rev-parse --short HEAD))"
  else
    echo "AVISO: el principal NO se pudo avanzar a origin/$base, sigue con el código viejo:" >&2
    printf '%s\n' "$err" | sed 's/^/  /' >&2
  fi
}

# limpiar
branch="$(git worktree list --porcelain | sed -n "s|^branch refs/heads/\\(issue-$n-.*\\)\$|\\1|p")"
[ -n "$branch" ] || { echo "no hay worktree para el issue $n" >&2; exit 1; }
[ "$(printf '%s\n' "$branch" | wc -l)" -eq 1 ] || { echo "hay varios worktrees para el issue $n" >&2; exit 1; }
path="$(wt_of "$branch")"
command -v gh >/dev/null 2>&1 || { echo "error: falta 'gh' en el PATH" >&2; exit 2; }
slug="$(kit_origin_slug)"
[ -n "$slug" ] || { echo "error: el remoto 'origin' no es de GitHub" >&2; exit 2; }
prs="$(gh pr list --repo "$slug" --head "$branch" --state all --json number,state,headRefOid)" \
  || { echo "error: gh pr list falló" >&2; exit 2; }
printf '%s' "$prs" | jq -e 'any(.[]; .state == "MERGED")' >/dev/null 2>&1 \
  || { echo "la PR de $branch no está fusionada" >&2; exit 1; }
# the merged PR must contain the branch tip, else local commits would be lost
tip="$(git rev-parse "refs/heads/$branch")" || exit 2
printf '%s' "$prs" | jq -e --arg t "$tip" 'any(.[]; .state == "MERGED" and .headRefOid == $t)' >/dev/null 2>&1 \
  || { echo "la rama tiene commits que no están en la PR fusionada; no se borra nada" >&2; exit 1; }
status="$(git -C "$path" status --porcelain)" || exit 2
[ -z "$status" ] || { echo "el worktree tiene cambios; no se borra nada" >&2; exit 1; }
git worktree remove "$path" || exit 2
git branch -D "$branch" >/dev/null || exit 2
git fetch -q --prune origin || echo "aviso: git fetch --prune falló; ya se borraron el worktree y la rama" >&2
update_main
echo "FIN: limpio"
