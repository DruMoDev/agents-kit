#!/usr/bin/env bash
# Usage: scripts/kit-ship-pr.sh <repo_root> <rama> <titulo> <cuerpo>
# Ships the working-tree changes as a PR from <rama> and squash-merges it.
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error.
set -u

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

info="$(gh repo view --json nameWithOwner,defaultBranchRef 2>/dev/null)" \
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
git fetch -q origin 2>/dev/null || { echo "error: git fetch origin falló" >&2; exit 2; }
if git show-ref --verify -q "refs/remotes/origin/$branch"; then
  echo "la rama '$branch' ya existe en origin; no se toca" >&2; exit 1
fi

start="$(git rev-parse --abbrev-ref HEAD)"
# Carry the working tree onto a new branch cut from the up-to-date default branch.
git rev-parse --verify -q "refs/remotes/origin/$base" >/dev/null \
  || { echo "error: origin/$base no existe" >&2; exit 2; }
if git show-ref --verify -q "refs/heads/$base"; then
  # local default must be a fast-forwardable ancestor of origin/$base
  git merge-base --is-ancestor "$base" "origin/$base" \
    || { echo "la rama local '$base' tiene commits que no están en origin; no se envía" >&2; exit 1; }
fi
git stash push -u -q -m "kit-ship-pr" || { echo "error: no se pudo guardar los cambios" >&2; exit 2; }
restore() { git stash pop -q 2>/dev/null || echo "aviso: cambios en 'git stash' (kit-ship-pr)" >&2; }
if ! { git checkout -q "$base" 2>/dev/null || git checkout -q -b "$base" "origin/$base"; } \
   || ! git merge -q --ff-only "origin/$base" 2>/dev/null; then
  git checkout -q "$start" 2>/dev/null; restore
  echo "error: no se pudo actualizar '$base'" >&2; exit 2
fi
if ! git checkout -q -b "$branch"; then
  git checkout -q "$start" 2>/dev/null; restore; exit 2
fi
if ! git stash pop -q 2>/dev/null; then
  echo "error: conflicto al aplicar los cambios sobre '$base'; revisa 'git stash' y la rama $branch" >&2
  exit 2
fi

abort() { # message code: leave the repo on the default branch with the changes intact
  echo "$1" >&2
  git checkout -q "$base" 2>/dev/null
  exit "${2:-2}"
}
git add -A && git commit -q -m "$title" || abort "error: no se pudo hacer commit (rama $branch conserva los cambios)"
git push -q -u origin "$branch" 2>/dev/null || abort "error: git push falló (rama local $branch conservada)"
url="$(gh pr create --base "$base" --head "$branch" --title "$title" --body "$body")" \
  || abort "error: gh pr create falló (rama $branch ya subida)"
gh pr merge "$url" --squash --delete-branch >/dev/null \
  || abort "error: gh pr merge falló; el PR sigue abierto: $url"

git checkout -q "$base" || exit 2
git pull -q --ff-only origin "$base" 2>/dev/null || echo "aviso: no se pudo hacer pull de $base" >&2
git branch -D "$branch" >/dev/null 2>&1 || true
echo "PR: $url"
echo "FIN: ok"
