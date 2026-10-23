#!/usr/bin/env bash
# Usage: scripts/kit-ship-pr.sh <subcomando> <root> <rama> [args...]
#   abrir     <root> <rama> con-marcador|sin-marcador
#   enviar    <root> <rama> <titulo> <cuerpo>
#   descartar <root> <rama>
#   fusionar  <root> <rama>
# Changes of kit-on/kit-off go through a temporary worktree of origin/<default branch>, never through Dru's tree:
# ${KIT_WORKTREES:-$HOME/.agents-kit/worktrees}/<repo>/<rama>, on a new local branch <rama>.
#   abrir: checks that origin/<default> has (con-marcador) or lacks (sin-marcador) .agents-kit.json, that no open PR
#     comes from <rama> and that no stale <rama> exists; creates the worktree, or reuses it ("ya existía").
#   enviar: commits everything in the worktree (project hooks skipped: the worktree has no setup), pushes, opens the PR,
#     waits for its CI (lib/ci.sh: green or no CI; red or still running at the timeout leaves the PR open) and
#     squash-merges it. Once the PR exists the worktree and the local branch are removed (the work lives in the
#     PR); before that, any failure keeps the worktree and names its path.
#   descartar: removes the worktree (with its changes) and the local branch.
#   fusionar: for the open PR from <rama> (after enviar left it open), waits for its CI and squash-merges it, like enviar.
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error (also "FIN: PR abierto" when the PR stays open).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/github-slug.sh"
source "$here/lib/config.sh"
source "$here/lib/ci.sh"

usage() {
  echo "uso: $0 abrir <root> <rama> con-marcador|sin-marcador | enviar <root> <rama> <titulo> <cuerpo> | descartar <root> <rama> | fusionar <root> <rama>" >&2
  exit 1
}
[ $# -ge 3 ] && [ -n "$2" ] && [ -n "$3" ] || usage
sub="$1"
case "$sub" in
  abrir) [ $# -eq 4 ] || usage
    case "$4" in con-marcador|sin-marcador) ;; *) echo "estado inválido: $4 (con-marcador o sin-marcador)" >&2; exit 1 ;; esac ;;
  enviar) [ $# -eq 5 ] && [ -n "$4" ] || usage ;;
  descartar|fusionar) [ $# -eq 3 ] || usage ;;
  *) usage ;;
esac
git check-ref-format --branch "$3" >/dev/null 2>&1 || { echo "nombre de rama inválido: $3" >&2; exit 1; }
branch="$3"
command -v git >/dev/null 2>&1 || { echo "error: falta 'git' en el PATH" >&2; exit 2; }
[ -d "$2" ] || { echo "error: '$2' no es un directorio" >&2; exit 2; }
root="$(cd "$2" && pwd)"
git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "error: '$root' no es un repositorio git" >&2; exit 2; }
cd "$root" || exit 2

kitdir="${KIT_WORKTREES:-$HOME/.agents-kit/worktrees}/$(basename "$root")"
path="$kitdir/$branch"

# wt_of <branch>: print the worktree path where the branch is checked out (empty if none).
wt_of() {
  git worktree list --porcelain | awk -v b="refs/heads/$1" '
    /^worktree / { p = substr($0, 10) }
    $0 == "branch " b { print p; exit }'
}
# kit_wt: print the kit's worktree of $branch (empty if none); exit 1 if the branch is checked out elsewhere.
kit_wt() {
  local w kd
  w="$(wt_of "$branch")"
  [ -n "$w" ] || return 0
  kd="$(cd "$kitdir" 2>/dev/null && pwd -P)"
  case "$(cd "$w" && pwd -P)/" in
    "$kd"/*) printf '%s\n' "$w" ;;
    *) echo "la rama '$branch' está en un worktree que no es del kit ($w); no lo toco" >&2; exit 1 ;;
  esac
}

if [ "$sub" = descartar ]; then
  w="$(kit_wt)" || exit 1
  [ -n "$w" ] || { echo "no hay worktree del kit para '$branch'" >&2; exit 1; }
  git worktree remove --force "$w" || { echo "error: no se pudo borrar el worktree $w" >&2; exit 2; }
  git branch -D "$branch" >/dev/null || { echo "error: no se pudo borrar la rama $branch" >&2; exit 2; }
  echo "borrado: $w"
  echo "FIN: descartado"
  exit 0
fi

for c in gh jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "error: falta '$c' en el PATH" >&2; exit 2; }
done
gh auth status >/dev/null 2>&1 || { echo "error: gh no autenticado (ejecuta 'gh auth login')" >&2; exit 2; }
git remote get-url origin >/dev/null 2>&1 || { echo "error: el repo no tiene un remoto 'origin'" >&2; exit 2; }
slug="$(kit_origin_slug)"
[ -n "$slug" ] || { echo "sin remoto de GitHub: el remoto 'origin' no es de GitHub" >&2; exit 1; }
info="$(gh repo view "$slug" --json nameWithOwner,defaultBranchRef 2>/dev/null)" \
  || { echo "sin remoto de GitHub: no se pudo leer $slug" >&2; exit 1; }
base="$(printf '%s' "$info" | jq -r '.defaultBranchRef.name // empty')"
[ -n "$base" ] || { echo "error: no se pudo determinar la rama por defecto" >&2; exit 2; }
if ! git fetch -q origin "+refs/heads/$base:refs/remotes/origin/$base"; then
  if [ "$sub" = enviar ] && [ -d "$path" ]; then echo "error: git fetch origin falló; tu trabajo sigue en el worktree $path" >&2
  else echo "error: git fetch origin falló" >&2; fi
  exit 2
fi

if [ "$sub" = abrir ]; then
  if git cat-file -e "refs/remotes/origin/$base:.agents-kit.json" 2>/dev/null; then
    [ "$4" = sin-marcador ] && { echo "el kit ya está activo en origin/$base (tiene .agents-kit.json)" >&2; exit 1; }
  else
    [ "$4" = con-marcador ] && { echo "el kit no está activo en origin/$base (no tiene .agents-kit.json)" >&2; exit 1; }
  fi
  prs="$(gh pr list --repo "$slug" --head "$branch" --state open --json number,url)" \
    || { echo "error: gh pr list falló" >&2; exit 2; }
  url="$(printf '%s' "$prs" | jq -r '.[0].url // empty')" || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
  [ -z "$url" ] || { echo "ya hay un PR abierto desde '$branch': $url. Fusiónalo o ciérralo y relanza." >&2; exit 1; }

  w="$(kit_wt)" || exit 1
  if [ -n "$w" ]; then
    echo "ya existía"
    # keep the canonical spelling when git reports the same directory through a symlink
    [ "$(cd "$w" && pwd -P)" = "$(cd "$path" 2>/dev/null && pwd -P)" ] || path="$w"
  else
    if git show-ref --verify -q "refs/heads/$branch"; then
      echo "la rama '$branch' ya existe en local y no tiene worktree del kit: bórrala (git branch -D $branch) y relanza" >&2
      exit 1
    fi
    git ls-remote --exit-code --heads origin "refs/heads/$branch" >/dev/null 2>&1; rc=$?
    case $rc in
      0) echo "la rama '$branch' ya existe en origin sin PR abierto: bórrala (git push origin --delete $branch) y relanza" >&2; exit 1 ;;
      2) ;;
      *) echo "error: git ls-remote falló" >&2; exit 2 ;;
    esac
    [ ! -e "$path" ] || { echo "la ruta $path ya existe y no es el worktree de $branch" >&2; exit 1; }
    mkdir -p "$(dirname "$path")" || exit 2
    # project hooks (post-checkout...) need the repo's setup, which a fresh worktree does not have
    git -c core.hooksPath=/dev/null worktree add -q -b "$branch" --no-track "$path" "refs/remotes/origin/$base" \
      || { echo "error: no se pudo crear el worktree $path" >&2; exit 2; }
  fi
  echo "worktree: $path"
  echo "rama: $branch"
  echo "base: $base"
  echo "FIN: $path"
  exit 0
fi

# ship_merge <url> <sha>: wait for the CI of <sha> and squash-merge <url> (like kit-pr.sh fusionar: an admin merge would
# skip required checks). Sets state (the PR state afterwards) and prints the reason on stderr when it does not merge.
ship_merge() {
  local ci="" ci_rc=0 merge_rc=0 t
  [ -n "$2" ] || ci_rc=2
  if [ "$ci_rc" -eq 0 ]; then
    # kit-off's worktree has no marker any more: then the config comes from Dru's clone
    t="$(ci_timeout ${w:+"$w"} "$root")"
    echo "esperando al CI del PR (hasta $((t / 60)) min): $1"
    ci="$(ci_wait "$2" "$t")" || ci_rc=$?
  fi
  if [ "$ci_rc" -eq 0 ]; then
    echo "CI: $ci"
    # no --delete-branch: gh would try to switch branches in the worktree; the remote branch is deleted in ship_end
    # --match-head-commit: never merge a head other than the one whose CI was just checked
    ci_gh_retry pr merge "$1" --repo "$slug" --squash --match-head-commit "$2" >/dev/null || merge_rc=$?
  elif [ "$ci_rc" -eq 3 ]; then
    echo "no se fusiona todavía: el CI sigue en marcha. Para esperarlo y fusionar solo el PR, relanza: $0 fusionar $root $branch" >&2
  else
    echo "no se fusiona: el CI del PR no salió verde" >&2
  fi
  state="$(gh pr view "$1" --repo "$slug" --json state -q .state 2>/dev/null)"
  [ "$state" = MERGED ] || [ "$merge_rc" -eq 0 ] || echo "error: gh pr merge falló" >&2
}
# ship_end <url>: final lines after ship_merge; exit 2 with "FIN: PR abierto" if the PR did not merge.
ship_end() {
  if [ "$state" != MERGED ]; then
    echo "el PR sigue abierto (estado: ${state:-desconocido}): $1" >&2
    echo "FIN: PR abierto"
    exit 2
  fi
  git push -q origin --delete "$branch" >/dev/null 2>&1 || true # usually already gone (delete-branch-on-merge)
  # another session may be fetching the same clone ("cannot lock ref"): retry once, quietly; the merge already happened
  git fetch -q --prune origin 2>/dev/null || { sleep 2; git fetch -q --prune origin 2>/dev/null; } \
    || echo "aviso: git fetch --prune falló; el PR ya está fusionado (haz git fetch más tarde)" >&2
  echo "PR fusionado: $1"
  echo "FIN: ok"
  exit 0
}

if [ "$sub" = fusionar ]; then
  # only PRs from this repo's own branch: --head also matches a fork's branch with the same name
  prs="$(gh pr list --repo "$slug" --head "$branch" --state open --json url,headRefOid,isCrossRepository)" \
    || { echo "error: gh pr list falló" >&2; exit 2; }
  prs="$(printf '%s' "$prs" | jq -c 'map(select(.isCrossRepository == false))')" \
    || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
  case "$(printf '%s' "$prs" | jq length)" in
    0) echo "no hay un PR abierto desde '$branch'" >&2; exit 1 ;;
    1) url="$(printf '%s' "$prs" | jq -r '.[0].url')" ;;
    *) echo "hay varios PR abiertos desde '$branch'; fusiona el bueno a mano" >&2; exit 1 ;;
  esac
  w="$(kit_wt)" || exit 1
  [ -z "$w" ] || { echo "el worktree $w sigue ahí: envía con enviar o bórralo con descartar" >&2; exit 1; }
  ship_merge "$url" "$(printf '%s' "$prs" | jq -r '.[0].headRefOid // empty')"
  ship_end "$url"
fi

# enviar
title="$4"; body="$5"
w="$(kit_wt)" || exit 1
[ -n "$w" ] || { echo "no hay worktree del kit para '$branch': ejecuta antes abrir" >&2; exit 1; }
keep="tu trabajo sigue en el worktree $w (rama $branch)"
git -C "$w" add -A || { echo "error: git add falló; $keep" >&2; exit 2; }
if ! git -C "$w" diff --cached --quiet; then
  git -C "$w" -c core.hooksPath=/dev/null commit -q --no-verify -m "$title" \
    || { echo "error: no se pudo hacer commit; $keep" >&2; exit 2; }
fi
ahead="$(git -C "$w" rev-list --count "refs/remotes/origin/$base..HEAD")" || exit 2
[ "$ahead" != 0 ] || { echo "nada que enviar: el worktree $w no tiene cambios; bórralo con descartar" >&2; exit 1; }
git -C "$w" push -q -u origin "$branch" \
  || { echo "error: git push falló; $keep. Arregla el problema y relanza abrir y enviar" >&2; exit 2; }
url="$(gh pr create --repo "$slug" --base "$base" --head "$branch" --title "$title" --body "$body")" \
  || { echo "error: gh pr create falló; la rama $branch ya está en origin y $keep. Relanza abrir y enviar" >&2; exit 2; }
sha="$(git -C "$w" rev-parse HEAD)" || sha=""
ship_merge "$url" "$sha"

# the PR holds the work from here on: the worktree and the local branch go away, merged or not
if git worktree remove "$w" 2>/dev/null || git worktree remove --force "$w"; then
  git branch -D "$branch" >/dev/null 2>&1 || echo "aviso: no se pudo borrar la rama local $branch" >&2
else
  echo "aviso: no se pudo borrar el worktree $w; bórralo con descartar" >&2
fi
ship_end "$url"
