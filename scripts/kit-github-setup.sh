#!/usr/bin/env bash
# Usage: scripts/kit-github-setup.sh <repo_root>
# Prepares the GitHub repo: missing kit labels (existing ones keep their colour and description), squash-merge
# settings and the pinned "📦 Changelog" issue (labelled registro; skipped when the marker says "changelog": false).
# Idempotent.
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/github-slug.sh"
source "$here/lib/config.sh"

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

# changelog: repo key, true unless the marker says false (no marker yet = default)
changelog=true
if [ -f "$repo/.agents-kit.json" ]; then
  c="$(kit_config "$repo" '.changelog')" || exit 2
  [ "$c" = false ] && changelog=false
fi

existing="$(gh label list --repo "$slug" --limit 1000 --json name)" \
  || { echo "error: no se pudieron listar las etiquetas" >&2; exit 2; }
existing="$(printf '%s' "$existing" | jq -r '.[].name')" || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
label() { # name color description: create it only if missing (never --force: keeps the project's colour/description)
  if printf '%s\n' "$existing" | grep -qxF -- "$1"; then
    echo "etiqueta: $1 (ya existía)"
    return
  fi
  gh label create "$1" --color "$2" --description "$3" --repo "$slug" >/dev/null \
    || { echo "error: no se pudo crear la etiqueta $1" >&2; exit 2; }
  echo "etiqueta: $1 (creada)"
}
label en-curso 1D76DB "Un agente la está trabajando"
label necesita-respuesta D93F0B "Espera una respuesta de Dru"
label bloqueado B60205 "No se pudo terminar, requiere a Dru"
label propuesta FBCA04 "Propuesta por un agente; se aprueba quitando la etiqueta"
label someday C5DEF5 "Fuera del reparto por ahora"
label registro EDEDED "Issue de registro del kit (📦 Changelog)"
label prio:alta B60205 "Prioridad alta"
label prio:media FBCA04 "Prioridad media"
label prio:baja 0E8A16 "Prioridad baja"
label entorno:nube 5319E7 "Se puede hacer en una sesión en la nube"
label entorno:mac 0052CC "Solo se puede hacer en el Mac de Dru"

gh repo edit "$slug" --enable-squash-merge --delete-branch-on-merge >/dev/null \
  || { echo "error: no se pudo configurar el repo" >&2; exit 2; }
echo "repo: squash merge y borrado de ramas activados"

if [ "$changelog" = false ]; then
  echo "sin changelog: el marcador dice \"changelog\": false; no se crea el issue 📦 Changelog"
else
  title="📦 Changelog"
  list="$(gh issue list --state open --search "in:title $title" --json number,title --repo "$slug")" \
    || { echo "error: no se pudo listar issues" >&2; exit 2; }
  num="$(printf '%s' "$list" | jq -r --arg t "$title" '[.[] | select(.title == $t)][0].number // empty')"
  if [ -z "$num" ]; then
    url="$(gh issue create --repo "$slug" --title "$title" --label registro --body "Aquí llegan los resúmenes de cambios de cada PR que el kit fusiona. No cerrar: es el registro vivo del repo.")" \
      || { echo "error: no se pudo crear el issue" >&2; exit 2; }
    num="${url##*/}"
    echo "issue creado: $url"
  else
    echo "issue existente: #$num"
    # a v2 repo's issue has no registro: add it so siguiente never picks it
    gh issue edit "$num" --repo "$slug" --add-label registro >/dev/null \
      || echo "aviso: no se pudo poner la etiqueta registro en #$num" >&2
  fi
  gh issue pin "$num" --repo "$slug" >/dev/null 2>&1 || echo "aviso: no se pudo fijar #$num (quizá ya está fijado)" >&2
fi

echo "FIN: ok"
