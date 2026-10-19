#!/usr/bin/env bash
# Usage: scripts/kit-github-setup.sh <repo_root>
# Prepares the GitHub repo: labels, squash-merge settings, pinned changelog issue. Idempotent.
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/github-slug.sh"

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "uso: $0 <repo_root>" >&2
  exit 1
fi
for c in gh git jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "error: falta '$c' en el PATH" >&2; exit 2; }
done
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
repo="$(cd "$1" && pwd)"
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "error: '$repo' no es un repositorio git" >&2; exit 2; }

cd "$repo" || exit 2
gh auth status >/dev/null 2>&1 || { echo "error: gh no autenticado (ejecuta 'gh auth login')" >&2; exit 2; }
slug="$(kit_origin_slug)"
[ -n "$slug" ] || { echo "sin remoto de GitHub: el remoto 'origin' no es de GitHub" >&2; exit 1; }
if ! gh repo view "$slug" --json nameWithOwner,defaultBranchRef >/dev/null 2>&1; then
  echo "sin remoto de GitHub: este repo no tiene un remoto de GitHub accesible" >&2
  exit 1
fi

label() { # name color description
  gh label create "$1" --color "$2" --description "$3" --force --repo "$slug" >/dev/null \
    || { echo "error: no se pudo crear la etiqueta $1" >&2; exit 2; }
  echo "etiqueta: $1"
}
label listo 0E8A16 "Elegible para kit-run"
label propuesta FBCA04 "Creada por agentes, pendiente de Dru"
label en-curso 1D76DB "Un agente la está trabajando"
label necesita-decision D93F0B "Duda de producto para Dru"
label bloqueado B60205 "No se pudo terminar, requiere a Dru"

gh repo edit "$slug" --enable-squash-merge --delete-branch-on-merge >/dev/null \
  || { echo "error: no se pudo configurar el repo" >&2; exit 2; }
echo "repo: squash merge y borrado de ramas activados"

title="📦 Changelog"
list="$(gh issue list --state open --search "in:title $title" --json number,title --repo "$slug")" \
  || { echo "error: no se pudo listar issues" >&2; exit 2; }
num="$(printf '%s' "$list" | jq -r --arg t "$title" '[.[] | select(.title == $t)][0].number // empty')"
if [ -z "$num" ]; then
  url="$(gh issue create --repo "$slug" --title "$title" --body "Aquí llegan los resúmenes de cambios de cada PR que el kit fusiona. No cerrar: es el registro vivo del repo.")" \
    || { echo "error: no se pudo crear el issue" >&2; exit 2; }
  num="${url##*/}"
  echo "issue creado: $url"
else
  echo "issue existente: #$num"
fi
gh issue pin "$num" --repo "$slug" >/dev/null 2>&1 || echo "aviso: no se pudo fijar #$num (quizá ya está fijado)" >&2

echo "FIN: ok"
