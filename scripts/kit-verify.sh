#!/usr/bin/env bash
# Usage: scripts/kit-verify.sh <subcomando> <wt> [args...]
#   correr     <wt> rapido|completo [--salida <fichero>]
#   estado     <wt>
#   medir-hook <wt>
# The repo's verification commands and what kit-on checks about its hook and CI. Policy (rules/core.md): the full CI on
# the PR is the gate (fusionar demands it); the pre-commit hook is light (format, strict lint, tests of what changed, in
# seconds), never full suites nor builds, which repeat the CI and cost minutes per commit to every agent.
#   correr: runs verificar.<nivel> of the marker of origin/<default branch> (a PR cannot change what it is checked with)
#     with bash in <wt>, timeout KIT_HOOK_TIMEOUT (1800 s); the whole output goes to --salida (default a temp file).
#     Prints "salida: <fichero>" and "FIN: ok"; exit 1 "sin verificar.<nivel>" (use the AGENTS.md commands) or
#     "falló (exit <n>)".
#   estado: one line per fact, for kit-on to propose what is missing: "ci: <n> workflows (<ficheros>)" or "ci: ninguno",
#     "ci-cancela: sí|no" (concurrency with cancel-in-progress: a new push stops the previous run of the PR),
#     "ci-cache: sí|no" (actions/cache or a setup-* action with cache), "hook: <dónde>" or "hook: ninguno",
#     "verificar.rapido: <comando>|sin declarar", "verificar.completo: <comando>|sin declarar"; FIN: estado.
#   medir-hook: runs the pre-commit hook (git hook run) in <wt> with nothing staged and prints "hook: <s> s (exit <n>)";
#     with nothing staged that is a lower bound. FIN: <s>. Exit 1 if there is no pre-commit hook. Runs the repo's
#     code: kit-on asks Dru first.
# Exit: 0 ok, 1 usage or rejected, 2 environment error.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/config.sh"
source "$here/lib/default-branch.sh"
source "$here/lib/repo-hook.sh"

usage() { echo "uso: $0 correr <wt> rapido|completo [--salida <fichero>] | estado <wt> | medir-hook <wt>" >&2; exit 1; }
[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1"; shift
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
wt="$(cd "$1" && pwd)"; shift
kit_require_marker "$wt" || exit $?
case "$sub" in
  correr)
    [ $# -ge 1 ] || usage
    nivel="$1"; shift
    case "$nivel" in rapido|completo) ;; *) usage ;; esac
    out=""
    while [ $# -gt 0 ]; do
      case "$1" in --salida) [ $# -ge 2 ] && [ -n "$2" ] || usage; out="$2"; shift 2 ;; *) usage ;; esac
    done ;;
  estado|medir-hook) [ $# -eq 0 ] || usage ;;
  *) usage ;;
esac
command -v jq >/dev/null 2>&1 || { echo "error: falta 'jq' en el PATH" >&2; exit 2; }
cd "$wt" || exit 2

# pre_commit_hook: print where the pre-commit hook lives, empty if none (core.hooksPath, or .git/hooks).
pre_commit_hook() {
  local hp f
  hp="$(git config --get core.hooksPath 2>/dev/null)"
  if [ -n "$hp" ]; then
    f="$hp/pre-commit"; case "$f" in /*) ;; *) f="$wt/$f" ;; esac
  else
    f="$(git rev-parse --git-common-dir)/hooks/pre-commit"; case "$f" in /*) ;; *) f="$wt/$f" ;; esac
  fi
  [ -x "$f" ] && printf '%s\n' "$f"
}

case "$sub" in
  correr)
    b="$(kit_default_branch)"
    [ -n "$b" ] || { echo "error: no pude saber la rama por defecto de origin" >&2; exit 2; }
    git fetch -q origin "+refs/heads/$b:refs/remotes/origin/$b" || { echo "error: git fetch falló" >&2; exit 2; }
    cmd="$(kit_config_base "$wt" ".verificar.$nivel // empty" "origin/$b")" || exit 2
    [ -n "$cmd" ] || { echo "sin verificar.$nivel en el marcador de origin/$b: usa los comandos de AGENTS.md" >&2; exit 1; }
    [ -n "$out" ] || out="$(mktemp)" || exit 2
    script="$(mktemp)" || exit 2
    printf '%s\n' "$cmd" > "$script"
    kit_hook_run "$wt" "$script"; rc=$?
    rm -f "$script"
    printf '$ %s\n%s' "$cmd" "$KIT_HOOK_OUT" > "$out" || { echo "error: no se pudo escribir $out" >&2; exit 2; }
    echo "salida: $out"
    if [ $rc -eq 142 ]; then echo "falló: verificar.$nivel superó KIT_HOOK_TIMEOUT" >&2; exit 1; fi
    [ $rc -eq 0 ] || { echo "falló (exit $rc): verificar.$nivel; salida completa en $out" >&2; exit 1; }
    echo "FIN: ok"
    ;;

  estado)
    wf=()
    for f in .github/workflows/*.yml .github/workflows/*.yaml; do [ -f "$f" ] && wf+=("$f"); done
    if [ ${#wf[@]} -eq 0 ]; then
      echo "ci: ninguno"
    else
      echo "ci: ${#wf[@]} workflows (${wf[*]})"
      if grep -qE '^[[:space:]]*cancel-in-progress:[[:space:]]*(true|\$\{\{)' "${wf[@]}"; then echo "ci-cancela: sí"; else echo "ci-cancela: no"; fi
      if grep -qE 'actions/cache@|^[[:space:]]*cache:[[:space:]]*[A-Za-z"'"'"']|cache-dependency-path:' "${wf[@]}"; then
        echo "ci-cache: sí"
      else
        echo "ci-cache: no"
      fi
    fi
    h="$(pre_commit_hook)"
    if [ -n "$h" ]; then
      echo "hook: ${h#"$wt/"}"
    else
      extra=""
      for f in .husky/pre-commit .pre-commit-config.yaml lefthook.yml .lefthook.yml; do [ -e "$f" ] && extra="$extra $f"; done
      if [ -n "$extra" ]; then echo "hook: ninguno instalado (el repo trae${extra}: sin instalar en este clon)"; else echo "hook: ninguno"; fi
    fi
    for nivel in rapido completo; do
      v="$(kit_config "$wt" ".verificar.$nivel // empty")" || exit 2
      echo "verificar.$nivel: ${v:-sin declarar}"
    done
    echo "FIN: estado"
    ;;

  medir-hook)
    h="$(pre_commit_hook)"
    [ -n "$h" ] || { echo "el repo no tiene hook de pre-commit instalado" >&2; exit 1; }
    script="$(mktemp)" || exit 2
    printf 'git hook run pre-commit\n' > "$script"
    start=$SECONDS
    kit_hook_run "$wt" "$script"; rc=$?
    s=$((SECONDS - start))
    rm -f "$script"
    echo "hook: $s s (exit $rc), sin cambios preparados: es una cota inferior"
    echo "FIN: $s"
    ;;
esac
