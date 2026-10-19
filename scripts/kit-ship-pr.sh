#!/usr/bin/env bash
# Usage: scripts/kit-ship-pr.sh <repo_root> <rama> <titulo> <cuerpo>
# Ships the working-tree changes as a PR from <rama> and squash-merges it.
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/github-slug.sh"

if [ $# -ne 4 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "uso: $0 <repo_root> <rama> <titulo> <cuerpo>" >&2
  exit 1
fi
for c in gh git jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "error: falta '$c' en el PATH" >&2; exit 2; }
done
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
repo="$(cd "$1" && pwd)"
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "error: '$repo' no es un repositorio git" >&2; exit 2; }
branch="$2"; title="$3"; body="$4"
cd "$repo" || exit 2

gh auth status >/dev/null 2>&1 || { echo "error: gh no autenticado (ejecuta 'gh auth login')" >&2; exit 2; }
git remote get-url origin >/dev/null 2>&1 || { echo "error: el repo no tiene un remoto 'origin'" >&2; exit 2; }
slug="$(kit_origin_slug)"
[ -n "$slug" ] || { echo "sin remoto de GitHub: el remoto 'origin' no es de GitHub" >&2; exit 1; }
info="$(gh repo view "$slug" --json nameWithOwner,defaultBranchRef 2>/dev/null)" \
  || { echo "sin remoto de GitHub" >&2; exit 1; }
base="$(printf '%s' "$info" | jq -r '.defaultBranchRef.name // empty')"
[ -n "$base" ] || { echo "error: no se pudo determinar la rama por defecto" >&2; exit 2; }

if [ -z "$(git status --porcelain)" ]; then
  echo "nada que enviar: no hay cambios en el árbol de trabajo" >&2
  exit 1
fi
git check-ref-format --branch "$branch" >/dev/null 2>&1 || { echo "nombre de rama inválido: $branch" >&2; exit 1; }
if git show-ref --verify -q "refs/heads/$branch"; then
  echo "la rama '$branch' ya existe en local; no se toca" >&2; exit 1
fi
git fetch -q --prune origin || { echo "error: git fetch origin falló" >&2; exit 2; }
if git show-ref --verify -q "refs/remotes/origin/$branch"; then
  echo "la rama '$branch' ya existe en origin; no se toca" >&2; exit 1
fi

start="$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)"
# Carry the working tree onto a new branch cut from the up-to-date default branch.
git rev-parse --verify -q "refs/remotes/origin/$base" >/dev/null \
  || { echo "error: origin/$base no existe" >&2; exit 2; }
if git show-ref --verify -q "refs/heads/$base"; then
  # local default must be a fast-forwardable ancestor of origin/$base
  git merge-base --is-ancestor "$base" "origin/$base" \
    || { echo "la rama local '$base' tiene commits que no están en origin; no se envía" >&2; exit 1; }
fi
# Refuse to replay a diff that sits on top of unpublished commits.
if [ "$(git rev-list --count "origin/$base..$start")" != 0 ]; then
  echo "'$start' tiene commits que no están en origin/$base; no se envía (publícalos o muévete a '$base')" >&2
  exit 1
fi
# Stash by exact SHA: never trust the top of the stash list.
stash_before="$(git rev-parse -q --verify refs/stash || true)"
git stash push -u -q -m "kit-ship-pr" || { echo "error: no se pudo guardar los cambios" >&2; exit 2; }
stash_sha="$(git rev-parse -q --verify refs/stash || true)"
if [ -z "$stash_sha" ] || [ "$stash_sha" = "$stash_before" ]; then
  echo "error: git stash no capturó los cambios (¿solo hay cambios dentro de un submódulo?); no se toca nada" >&2
  exit 2
fi
restore() {
  if git stash apply -q "$stash_sha" 2>/dev/null; then
    [ "$(git rev-parse -q --verify 'stash@{0}')" = "$stash_sha" ] && git stash drop -q
  else
    echo "aviso: cambios en 'git stash' (kit-ship-pr, $stash_sha)" >&2
  fi
}
if ! { git checkout -q "$base" 2>/dev/null || git checkout -q -b "$base" "origin/$base"; } \
   || ! git merge -q --ff-only "origin/$base"; then
  git checkout -q "$start" 2>/dev/null; restore
  echo "error: no se pudo actualizar '$base'" >&2; exit 2
fi
if ! git checkout -q -b "$branch"; then
  git checkout -q "$start" 2>/dev/null; restore; exit 2
fi
# Snapshot untracked paths right before the apply: only what the apply creates may be removed afterwards.
root="$(git rev-parse --show-toplevel)" && cd "$root" || exit 2
root_phys="$(pwd -P)"
untracked_before="$(mktemp)"
git ls-files -o --exclude-standard -z > "$untracked_before"
if ! git stash apply -q "$stash_sha" 2>/dev/null; then
  git reset -q --hard 2>/dev/null
  # Remove only untracked paths created by the failed apply; never follow symlinks or leave the repo.
  while IFS= read -r -d '' f; do
    grep -qzxF -- "$f" "$untracked_before" && continue
    d="$(dirname -- "$f")"; unsafe=0; p=""
    if [ "$d" != . ]; then
      IFS=/ read -r -a parts <<< "$d"
      for c in "${parts[@]}"; do
        p="${p:+$p/}$c"
        [ -L "$p" ] && unsafe=1
      done
      [ "$unsafe" = 0 ] && case "$(cd "$d" 2>/dev/null && pwd -P)/" in "$root_phys"/*) ;; *) unsafe=1;; esac
    fi
    [ "$unsafe" = 0 ] || continue
    rm -f -- "$f"; [ "$d" = . ] || rmdir -p -- "$d" 2>/dev/null
  done < <(git ls-files -o --exclude-standard -z)
  rm -f "$untracked_before"
  leftover="$(git status --porcelain)"
  git checkout -q "$start" 2>/dev/null
  git branch -D "$branch" >/dev/null 2>&1
  if [ -z "$leftover" ]; then
    state_msg="el árbol quedó limpio"
  else
    state_msg="el árbol NO quedó limpio, quedan: $(printf '%s' "$leftover" | tr '\n' ';')"
  fi
  echo "error: conflicto al aplicar los cambios sobre '$base'; tus cambios están a salvo en el stash $stash_sha y $state_msg. Haz 'git pull' en '$base' y relanza kit-on/kit-off; la rama '$branch' se borró" >&2
  exit 2
fi
rm -f "$untracked_before"
[ "$(git rev-parse -q --verify 'stash@{0}')" = "$stash_sha" ] && git stash drop -q

abort() { # message code: leave the repo on the default branch with the changes intact
  echo "$1" >&2
  git checkout -q "$base" 2>/dev/null
  exit "${2:-2}"
}
if ! { git add -A && git commit -q -m "$title"; }; then
  git checkout -q "$base" 2>/dev/null
  git branch -D "$branch" >/dev/null 2>&1
  echo "error: no se pudo hacer commit; los cambios siguen en el árbol de trabajo y la rama '$branch' se borró, puedes reintentar" >&2
  exit 2
fi
git push -q -u origin "$branch" || abort "error: git push falló (rama local $branch conservada)"
url="$(gh pr create --repo "$slug" --base "$base" --head "$branch" --title "$title" --body "$body")" \
  || abort "error: gh pr create falló (rama $branch ya subida)"
merge_rc=0
gh pr merge "$url" --repo "$slug" --squash --delete-branch >/dev/null || merge_rc=$?

state="$(gh pr view "$url" --repo "$slug" --json state -q .state 2>/dev/null)"
if [ "$merge_rc" -ne 0 ] && [ "$state" != "MERGED" ]; then
  abort "error: gh pr merge falló; el PR sigue abierto: $url"
fi
if [ "$state" != "MERGED" ]; then
  git checkout -q "$base" 2>/dev/null
  echo "el PR sigue abierto (estado: ${state:-desconocido}): $url" >&2
  echo "FIN: PR abierto"
  exit 2
fi

git checkout -q "$base" || exit 2
git pull -q --ff-only origin "$base" || echo "aviso: no se pudo hacer pull de $base" >&2
git branch -D "$branch" >/dev/null 2>&1 || true
git fetch -q --prune origin || true
echo "PR fusionado: $url"
echo "FIN: ok"
