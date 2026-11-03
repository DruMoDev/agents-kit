#!/usr/bin/env bash
# Sourced helper: matching of the shielded globs (.blindado), shared by kit-reglas.sh and hooks/pre-edit.

# kit_blindado_match <ruta> <globs> [nocase]: return 0 when <ruta> (relative to the repo root) matches one of <globs>
# (one per line). An entry ending in / is a prefix; any other is a bash pattern over the whole path ([[ == ]]: *
# crosses /). With a third argument, without case (hooks/pre-edit on macOS, where the file system ignores it).
kit_blindado_match() {
  local f="$1" g hit=1
  [ -z "${3:-}" ] || shopt -s nocasematch
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case "$g" in
      */) [[ "$f" == "$g"* ]] && hit=0 ;;
      *) [[ "$f" == $g ]] && hit=0 ;;
    esac
    [ $hit -eq 1 ] || break
  done <<<"$2"
  shopt -u nocasematch
  return $hit
}
