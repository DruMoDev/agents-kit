#!/usr/bin/env bash
# Usage: scripts/kit-deactivate.sh <repo_root>
# Removes the .agents-kit.json marker and nothing else. Does not commit.
# Exit: 0 ok, 1 usage or not activated, 2 environment error.
set -u

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "uso: $0 <repo_root>" >&2
  exit 1
fi
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
repo="$(cd "$1" && pwd)"
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "error: '$repo' no es un repositorio git" >&2; exit 2; }

marker="$repo/.agents-kit.json"
if [ ! -e "$marker" ] && [ ! -L "$marker" ]; then
  echo "no está activado: no existe $marker" >&2
  exit 1
fi
rm -f "$marker" || { echo "error: no se pudo borrar $marker" >&2; exit 2; }
echo "borrado: .agents-kit.json"
echo "FIN: ok"
