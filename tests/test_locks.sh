#!/usr/bin/env bash
# Tests for the serializa:<eje> axis locks (scripts/lib/locks.sh and their use in kit-issue.sh): stateful gh stub,
# real git with a local bare origin (the lock is a ref pushed there).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
issue="$REPO_ROOT/scripts/kit-issue.sh"
export PATH="$TESTS_DIR/stubs/notify:$PATH"
export HOME="$(mktemp -d)" CURL_LOG="$(mktemp)" KIT_NTFY_TOPIC=tema-test
unset CURL_FAIL KIT_NTFY_SERVER CLAUDE_CODE_REMOTE
last_line() { printf '%s\n' "$1" | sed -n '$p'; }

r="$(mk_repo)"; o="$(mktemp -d)"
git init -q --bare "$o"
echo '{}' > "$r/.agents-kit.json"
(cd "$r" && git remote add origin https://github.com/dru/demo.git \
  && git config "url.$o.insteadOf" "https://github.com/dru/demo.git" && git push -q -u origin main) >/dev/null 2>&1 \
  || fail "setup remoto"
lock_msg() { git -C "$o" log -1 --format=%B "refs/locks/$1" 2>/dev/null | sed -n 1p; }
take_as() { # <eje> <agente> <N>: a lock taken by someone else (another clone, another flow)
  local sha; sha="$(git -C "$r" commit-tree "$(git -C "$r" hash-object -t tree /dev/null)" -m "agente:$2 issue:$3 eje:$1")"
  git -C "$r" push -q origin "$sha:refs/locks/$1" || fail "take_as $1"
}

use_flow_gh
flow_add_issue 10 "migración A" serializa:mig en-curso
flow_add_issue 11 "migración B" serializa:mig prio:alta
flow_add_issue 12 "otro eje" serializa:otro entorno:nube
flow_add_issue 13 "mismo eje que 12" serializa:otro

# --- siguiente / reparto: an axis held by an en-curso issue keeps the others of that axis out
err="$(bash "$issue" siguiente "$r" 11 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "siguiente 11: exit $rc"
case "$err" in *"#11 su eje está ocupado: serializa:mig en #10"*) ;; *) fail "siguiente 11: '$err'";; esac
out="$(bash "$issue" siguiente "$r" 2>/dev/null)" || fail "siguiente: exit $?"
[ "$(last_line "$out")" = "FIN: 12" ] || fail "siguiente: debía dar 12 ('$out')"
out="$(bash "$issue" reparto "$r" 2>&1)" || fail "reparto: $out"
case "$out" in *"esperan a que se libere su eje: #11 (serializa:mig en #10)"*) ;; *) fail "reparto sin línea de eje: '$out'";; esac

# --- cloud: never an issue with an axis (no lock there), nor reclamar
err="$(CLAUDE_CODE_REMOTE=true bash "$issue" siguiente "$r" 12 2>&1 >/dev/null)"
case "$err" in *"#12 lleva serializa:otro y en la nube no se puede tomar su candado"*) ;; *) fail "nube siguiente 12: '$err'";; esac
out="$(CLAUDE_CODE_REMOTE=true bash "$issue" reparto "$r" 2>&1)"
case "$out" in *"solo en el Mac (con eje serializa:*, sin candado en la nube): #12"*) ;; *) fail "nube reparto: '$out'";; esac
err="$(CLAUDE_CODE_REMOTE=true bash "$issue" reclamar "$r" 12 kit-nube 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "nube reclamar: exit $rc"
[ "$(flow_issue 12 '.comments | length')" = 0 ] || fail "nube reclamar: publicó comentario"

# --- reclamar takes the lock once the claim is won
out="$(bash "$issue" reclamar "$r" 12 kit-aaaa 2>&1)" || fail "reclamar 12: $out"
case "$out" in *"candado: refs/locks/otro"*"FIN: reclamado #12") ;; *) fail "reclamar 12: '$out'";; esac
[ "$(lock_msg otro)" = "agente:kit-aaaa issue:12 eje:otro" ] || fail "candado de 12: '$(lock_msg otro)'"

# --- reclamar loses the axis (lock taken in between by another flow): claim undone, lock untouched
flow_add_issue 14 "tercer eje" serializa:tres
take_as tres agente-ajeno 99
err="$(bash "$issue" reclamar "$r" 14 kit-aaaa 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "reclamar 14 con eje ajeno: exit $rc ($err)"
case "$err" in *"el eje serializa:tres lo tiene otro (agente:agente-ajeno issue:99 eje:tres)"*"reclamación deshecha"*) ;;
  *) fail "reclamar 14: '$err'";; esac
[ "$(flow_issue 14 '[.labels[].name] | index("en-curso") != null')" = false ] || fail "reclamar 14: dejó en-curso"
flow_issue 14 '.comments[-1].body' | grep -q '^<!-- kit-soltado: kit-aaaa -->' || fail "reclamar 14: sin kit-soltado"
[ "$(lock_msg tres)" = "agente:agente-ajeno issue:99 eje:tres" ] || fail "reclamar 14: tocó el candado ajeno"

# --- soltar releases the own lock (and only it)
out="$(bash "$issue" soltar "$r" 12 kit-aaaa 2>&1)" || fail "soltar 12: $out"
[ -z "$(git -C "$o" for-each-ref refs/locks/otro)" ] || fail "soltar 12: el candado sigue"
case "$out" in *"candado soltado: refs/locks/otro"*) ;; *) fail "soltar 12 no dice que soltó el candado: $out";; esac
[ "$(flow_issue 12 '[.labels[].name] | index("en-curso") != null')" = false ] || fail "soltar 12: dejó en-curso"
# reclamar que pierde el eje deshace su reclamación sin liberar el candado ajeno
flow_add_issue 15 "pierde el eje" serializa:tres
out="$(bash "$issue" reclamar "$r" 15 kit-bbbb 2>&1)"; [ $? -eq 1 ] || fail "reclamar 15 debía perder el eje"
[ "$(lock_msg tres)" = "agente:agente-ajeno issue:99 eje:tres" ] || fail "reclamar perdido liberó el candado ajeno"
# soltar an issue whose axis is held for another issue: the other lock stays
flow_add_issue 16 "soltar sin candado propio" serializa:cuatro
out="$(bash "$issue" reclamar "$r" 16 kit-dddd 2>&1)" || fail "reclamar 16: $out"
git -C "$r" push -q origin ":refs/locks/cuatro" && take_as cuatro agente-ajeno 98
out="$(bash "$issue" soltar "$r" 16 kit-dddd 2>&1)" || fail "soltar 16: $out"
[ "$(lock_msg cuatro)" = "agente:agente-ajeno issue:98 eje:cuatro" ] || fail "soltar liberó un candado de otro issue"
git -C "$r" push -q origin ":refs/locks/cuatro"

# two axes, the second held by someone else: the first is released, the other untouched
flow_add_issue 20 "dos ejes" serializa:a1 serializa:b1
take_as b1 agente-ajeno 97
err="$(bash "$issue" reclamar "$r" 20 kit-eeee 2>&1 >/dev/null)"; [ $? -eq 1 ] || fail "dos ejes: debía perder ($err)"
[ -z "$(git -C "$o" for-each-ref refs/locks/a1)" ] || fail "dos ejes: quedó el candado del primer eje"
[ "$(lock_msg b1)" = "agente:agente-ajeno issue:97 eje:b1" ] || fail "dos ejes: tocó el candado ajeno"
git -C "$r" push -q origin ":refs/locks/b1"

# a lock left for this same issue by a dead session: the new claim takes it over
flow_add_issue 21 "candado viejo propio" serializa:c1
take_as c1 agente-muerto 21
out="$(bash "$issue" reclamar "$r" 21 kit-ffff 2>&1)" || fail "candado viejo propio: $out"
case "$out" in *"candado: refs/locks/c1 (ya era de #21: agente:agente-muerto issue:21 eje:c1)"*"FIN: reclamado #21") ;; *) fail "candado viejo propio: '$out'";; esac
bash "$issue" soltar "$r" 21 kit-ffff >/dev/null 2>&1 || fail "soltar 21"
[ -z "$(git -C "$o" for-each-ref refs/locks/c1)" ] || fail "soltar 21 no liberó el candado viejo"

# labels with spaces or that cannot be refs: rejected before claiming, never split into other axes
flow_add_issue 22 "eje con espacio" "serializa:db mig"
flow_add_issue 23 "eje inválido" "serializa:a..b"
for x in 22 23; do
  err="$(bash "$issue" reclamar "$r" $x kit-gggg 2>&1 >/dev/null)"; rc=$?
  [ $rc -eq 1 ] || fail "eje inválido #$x: exit $rc ($err)"
  case "$err" in *"no es un eje válido"*) ;; *) fail "eje inválido #$x: '$err'";; esac
  [ "$(flow_issue $x '.comments | length')" = 0 ] || fail "eje inválido #$x: publicó comentario"
done
[ -z "$(git -C "$o" for-each-ref refs/locks/db refs/locks/mig)" ] || fail "eje con espacio: creó candados partidos"

# --- bloquear releases too
out="$(bash "$issue" reclamar "$r" 13 kit-cccc 2>&1)" || fail "reclamar 13: $out"
echo "motivo" > "$HOME/m"
out="$(bash "$issue" bloquear "$r" 13 kit-cccc "$HOME/m" 2>&1)" || fail "bloquear 13: $out"
[ -z "$(git -C "$o" for-each-ref refs/locks/otro)" ] || fail "bloquear 13: el candado sigue"

# --- liberar-eje: a dead session's lock, whoever holds it
out="$(bash "$issue" liberar-eje "$r" serializa:tres 2>&1)" || fail "liberar-eje: $out"
case "$out" in *"liberado refs/locks/tres (era: agente:agente-ajeno issue:99 eje:tres)"*"FIN: liberado tres") ;; *) fail "liberar-eje: '$out'";; esac
[ -z "$(git -C "$o" for-each-ref refs/locks/tres)" ] || fail "liberar-eje: sigue"
bash "$issue" liberar-eje "$r" tres >/dev/null 2>&1; [ $? -eq 1 ] || fail "liberar-eje sin candado debe dar 1"
bash "$issue" liberar-eje "$r" "../x" >/dev/null 2>&1; [ $? -eq 1 ] || fail "liberar-eje con eje inválido debe dar 1"

# --- lock_release (what kit-pr.sh fusionar calls): only the issue that holds it
take_as mig agente-x 10
(cd "$r" && source "$REPO_ROOT/scripts/lib/locks.sh" && lock_release serializa:mig 11) || fail "lock_release ajeno falló"
[ -n "$(git -C "$o" for-each-ref refs/locks/mig)" ] || fail "lock_release liberó el candado de otro issue"
(cd "$r" && source "$REPO_ROOT/scripts/lib/locks.sh" && lock_release serializa:mig 10) || fail "lock_release propio falló"
[ -z "$(git -C "$o" for-each-ref refs/locks/mig)" ] || fail "lock_release no liberó el propio"
# tomar-eje: an issue already claimed needs an axis midway
flow_add_issue 30 "descubre una migración" prio:media
bash "$issue" reclamar "$r" 30 kit-hhhh >/dev/null 2>&1 || fail "reclamar 30"
out="$(bash "$issue" tomar-eje "$r" 30 kit-hhhh serializa:d1 2>&1)" || fail "tomar-eje: $out"
case "$out" in *"candado: refs/locks/d1"*"FIN: eje serializa:d1 tomado para #30") ;; *) fail "tomar-eje: '$out'";; esac
[ "$(lock_msg d1)" = "agente:kit-hhhh issue:30 eje:d1" ] || fail "tomar-eje: candado '$(lock_msg d1)'"
[ "$(flow_issue 30 '[.labels[].name] | index("serializa:d1") != null')" = true ] || fail "tomar-eje: sin etiqueta"
grep -q '^label create serializa:d1 --repo dru/demo' "$GH_LOG" || fail "tomar-eje no crea la etiqueta del eje"
out="$(bash "$issue" soltar "$r" 30 kit-hhhh 2>&1)" || fail "soltar 30: $out"
[ -z "$(git -C "$o" for-each-ref refs/locks/d1)" ] || fail "soltar no liberó el candado tomado a mitad"
# axis held by another issue: exit 1, the label stays so the issue waits for the axis
flow_add_issue 31 "otra migración" prio:media
bash "$issue" reclamar "$r" 31 kit-iiii >/dev/null 2>&1 || fail "reclamar 31"
take_as d1 agente-ajeno 96
err="$(bash "$issue" tomar-eje "$r" 31 kit-iiii d1 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "tomar-eje ocupado: exit $rc ($err)"
case "$err" in *"el eje serializa:d1 lo tiene otro (agente:agente-ajeno issue:96 eje:d1)"*) ;; *) fail "tomar-eje ocupado: '$err'";; esac
[ "$(flow_issue 31 '[.labels[].name] | index("serializa:d1") != null')" = true ] || fail "tomar-eje ocupado: quitó la etiqueta"
[ "$(lock_msg d1)" = "agente:agente-ajeno issue:96 eje:d1" ] || fail "tomar-eje ocupado: tocó el candado ajeno"
git -C "$r" push -q origin ":refs/locks/d1"
# not the claimant, cloud, invalid axis
bash "$issue" tomar-eje "$r" 31 kit-otro d1 >/dev/null 2>&1; [ $? -eq 1 ] || fail "tomar-eje sin ser el que reclamó debe dar 1"
CLAUDE_CODE_REMOTE=true bash "$issue" tomar-eje "$r" 31 kit-iiii d1 >/dev/null 2>&1; [ $? -eq 1 ] || fail "tomar-eje en la nube debe dar 1"
bash "$issue" tomar-eje "$r" 31 kit-iiii "d1 x" >/dev/null 2>&1; [ $? -eq 1 ] || fail "tomar-eje con eje inválido debe dar 1"
[ -z "$(git -C "$o" for-each-ref refs/locks/d1)" ] || fail "tomar-eje rechazado creó un candado"
# a lock left by an issue that is already closed (merged by hand with autoMerge false): reclamar recovers it
flow_add_issue 40 "cerrado con candado" serializa:e1
st_close() { local t; t="$(mktemp)"; jq --argjson n "$1" '(.issues[] | select(.number == $n)).state = "CLOSED"' "$GH_STATE/state.json" > "$t" && mv "$t" "$GH_STATE/state.json"; }
take_as e1 agente-viejo 40; st_close 40
flow_add_issue 41 "mismo eje, después" serializa:e1
out="$(bash "$issue" reclamar "$r" 41 kit-jjjj 2>&1)" || fail "candado de issue cerrado: $out"
case "$out" in *"candado: refs/locks/e1 (era de #40, ya cerrado)"*"FIN: reclamado #41") ;; *) fail "candado de issue cerrado: $out";; esac
[ "$(lock_msg e1)" = "agente:kit-jjjj issue:41 eje:e1" ] || fail "candado de issue cerrado: $(lock_msg e1)"
echo "OK test_locks"
