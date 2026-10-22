#!/usr/bin/env bash
# Usage: scripts/kit-agents-md.sh diff|aplicar <root> <propuesta>
# The reorder of an existing AGENTS.md is shown to Dru and only written with his OK.
#   diff:    unified diff from <root>/AGENTS.md to <propuesta>; writes nothing. FIN: con cambios | sin cambios.
#   aplicar: writes <propuesta> over <root>/AGENTS.md.
# The proposal must keep a "## Reglas del proyecto" section; AGENTS.md must be a regular file (never a symlink).
# Exit: 0 ok, 1 usage or rejected, 2 environment error.
set -u

usage() { echo "uso: $0 diff|aplicar <root> <propuesta>" >&2; exit 1; }
[ $# -eq 3 ] && [ -n "$2" ] && [ -n "$3" ] || usage
case "$1" in diff|aplicar) ;; *) usage ;; esac
sub="$1"; prop="$3"
[ -d "$2" ] || { echo "error: '$2' no es un directorio" >&2; exit 2; }
root="$(cd "$2" && pwd)"
agents="$root/AGENTS.md"
[ ! -L "$agents" ] || { echo "AGENTS.md es un symlink; no lo toco" >&2; exit 1; }
[ -f "$agents" ] || { echo "no existe $agents" >&2; exit 1; }
[ -f "$prop" ] && [ -r "$prop" ] || { echo "no se puede leer la propuesta: $prop" >&2; exit 1; }
grep -qx '## Reglas del proyecto' "$prop" \
  || { echo "la propuesta debe conservar la sección '## Reglas del proyecto'" >&2; exit 1; }

if [ "$sub" = diff ]; then
  git diff --no-index --no-color --src-prefix=actual/ --dst-prefix=propuesta/ -- "$agents" "$prop"; rc=$?
  case $rc in
    0) echo "FIN: sin cambios" ;;
    1) echo "FIN: con cambios" ;;
    *) echo "error: git diff falló" >&2; exit 2 ;;
  esac
  exit 0
fi
cat -- "$prop" > "$agents" || { echo "error: no se pudo escribir $agents" >&2; exit 2; }
echo "cambiado: AGENTS.md"
echo "FIN: ok"
