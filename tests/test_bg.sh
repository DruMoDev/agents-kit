#!/usr/bin/env bash
# Tests for scripts/kit-bg.sh (detached launch and capped wait on a result file).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
bg="$REPO_ROOT/scripts/kit-bg.sh"
export KIT_BG_POLL=1
d="$(mktemp -d)"

out="$(bash "$bg" lanzar "$d/a" bash -c 'echo hola; echo error >&2; exit 3')" || fail "lanzar: $out"
case "$out" in "lanzado: "[0-9]*"FIN: $d/a") ;; *) fail "lanzar salida: $out";; esac
out="$(bash "$bg" esperar "$d/a" 20)" || fail "esperar: $out"
case "$out" in *hola*error*"SALIDA: 3"*"FIN: terminado") ;; *) fail "esperar salida: $out";; esac
bash "$bg" lanzar "$d/a" true >/dev/null 2>&1; [ $? -eq 1 ] || fail "lanzar sobre un fichero existente debe dar 1"

# still running at the cap: exit 1, then done on the next wait
bash "$bg" lanzar "$d/b" bash -c 'sleep 3; echo listo' >/dev/null || fail "lanzar b"
err="$(bash "$bg" esperar "$d/b" 1 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "tope: exit $rc"
case "$err" in *"sigue en marcha tras 1s"*) ;; *) fail "tope msg: $err";; esac
out="$(bash "$bg" esperar "$d/b" 20)" || fail "esperar b: $out"
case "$out" in *listo*"SALIDA: 0"*) ;; *) fail "esperar b salida: $out";; esac

# a "SALIDA:" line printed by the command itself is not the end
bash "$bg" lanzar "$d/e" bash -c 'echo "SALIDA: 0"; sleep 3' >/dev/null || fail "lanzar e"
bash "$bg" esperar "$d/e" 1 >/dev/null 2>&1; [ $? -eq 1 ] || fail "un SALIDA del comando no debe contar como fin"
out="$(bash "$bg" esperar "$d/e" 20)" || fail "esperar e: $out"
# own process group: killing the launcher's group does not take the command with it
bash "$bg" lanzar "$d/f" bash -c 'sleep 2; echo vivo' >/dev/null || fail "lanzar f"
sleep 0.5; f_pgid="$(ps -o pgid= -p "$(cat "$d/f.pid")" | tr -d ' ')"
[ -n "$f_pgid" ] && [ "$f_pgid" != "$(ps -o pgid= -p $$ | tr -d ' ')" ] || fail "el comando no va en su propio grupo de procesos"
out="$(bash "$bg" esperar "$d/f" 20)" || fail "esperar f: $out"
case "$out" in *vivo*"SALIDA: 0"*) ;; *) fail "esperar f: $out";; esac

# killed without its SALIDA line: exit 2
bash "$bg" lanzar "$d/c" sleep 30 >/dev/null || fail "lanzar c"
w="$(cat "$d/c.pid")"; kids="$(pgrep -P "$w")"; kill -KILL "$w"; kill $kids 2>/dev/null
sleep 1
bash "$bg" esperar "$d/c" 5 >/dev/null 2>&1; [ $? -eq 2 ] || fail "muerto sin SALIDA debe dar 2"
bash "$bg" esperar "$d/no-existe" 1 >/dev/null 2>&1; [ $? -eq 2 ] || fail "sin fichero debe dar 2"
echo "OK test_bg"
