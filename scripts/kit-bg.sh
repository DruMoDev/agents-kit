#!/usr/bin/env bash
# Usage: scripts/kit-bg.sh lanzar <fichero> <comando> [args...]
#        scripts/kit-bg.sh esperar <fichero> [tope-segundos]
# Long waits of the flow (review seats, CI) without depending on the tool's background notification, which may never
# arrive: lanzar runs the command detached, with its whole output in <fichero> and, when it ends, a last line
# "SALIDA: <código>"; esperar polls that file until the line appears or the cap passes (KIT_BG_POLL s, default 10).
#   lanzar: prints "lanzado: <pid>" and "FIN: <fichero>" at once. <fichero> must be new or empty (mktemp): one with
#     content would be a stale result that looks done.
#   esperar: default cap 540 s, so it fits in one tool call under 10 min; repeat it while it says "sigue en marcha".
#     Done: prints the command's whole output (its "SALIDA: <código>" line included) and "FIN: terminado". Exit 1
#     "sigue en marcha" when the cap passes; 2 if the file does not exist or the command died without its SALIDA line.
# Exit: 0 ok, 1 usage or still running, 2 environment error.
set -u
usage() { echo "uso: $0 lanzar <fichero> <comando> [args...] | esperar <fichero> [tope-segundos]" >&2; exit 1; }
[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1" f="$2"; shift 2
case "$sub" in
  lanzar)
    [ $# -ge 1 ] || usage
    # an empty file is fine (mktemp creates it); one with content would be an old result that looks finished
    [ ! -s "$f" ] || { echo "el fichero $f ya tiene contenido: usa otro (un resultado viejo parecería terminado)" >&2; exit 1; }
    : > "$f" || { echo "error: no se pudo crear $f" >&2; exit 2; }
    rm -f "$f.rc"
    export KIT_BG_RC="$f.rc"
    # own process group (perl setpgrp, as lib/repo-hook.sh): a tool that kills the caller's group when its call returns
    # (or on a timeout) does not take the command with it. The code goes to <fichero>.rc, which only this wrapper
    # writes, so a "SALIDA:" line printed by the command itself never looks like the end.
    nohup perl -e 'setpgrp(0, 0); exec @ARGV or exit 127' bash -c '"$@" </dev/null; rc=$?; echo "$rc" > "$KIT_BG_RC"; echo "SALIDA: $rc"' _ "$@" \
      >> "$f" 2>&1 </dev/null &
    pid=$!
    echo "$pid" > "$f.pid"
    echo "lanzado: $pid"
    echo "FIN: $f"
    ;;
  esperar)
    tope="${1:-540}" poll="${KIT_BG_POLL:-10}"
    [[ $tope =~ ^[0-9]+$ ]] && [[ $poll =~ ^[1-9][0-9]*$ ]] || usage
    [ -e "$f" ] || { echo "error: no existe $f (¿se lanzó con kit-bg.sh lanzar?)" >&2; exit 2; }
    start=$SECONDS
    while :; do
      if [ -s "$f.rc" ]; then
        sleep 1 # let the wrapper's own SALIDA line land after the .rc file
        cat "$f"
        echo "FIN: terminado"
        exit 0
      fi
      pid="$(cat "$f.pid" 2>/dev/null)"
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
        sleep 1 # the SALIDA line may land right after the process ends
        [ -s "$f.rc" ] && continue
        echo "error: el comando terminó sin su línea SALIDA (¿lo mataron?); su salida está en $f" >&2
        exit 2
      fi
      [ $((SECONDS - start)) -lt "$tope" ] || { echo "sigue en marcha tras ${tope}s: vuelve a esperar con el mismo fichero" >&2; exit 1; }
      sleep "$poll"
    done
    ;;
  *) usage ;;
esac
