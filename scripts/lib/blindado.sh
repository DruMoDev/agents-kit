#!/usr/bin/env bash
# Sourced helper: matching of the shielded globs (.blindado), shared by kit-reglas.sh and hooks/pre-edit.

# kit_blindado_match <ruta> <globs>: return 0 when <ruta> (relative to the repo root) matches one of <globs> (one per
# line). An entry ending in / is a prefix; any other is a bash pattern over the whole path ([[ == ]]: * crosses /).
kit_blindado_match() {
  local f="$1" g
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case "$g" in
      */) [[ "$f" == "$g"* ]] && return 0 ;;
      *) [[ "$f" == $g ]] && return 0 ;;
    esac
  done <<<"$2"
  return 1
}
