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
[ "$(flow_issue 12 '[.labels[].name] | index("en-curso") != null')" = false ] || fail "soltar 12: dejó en-curso"
flow_add_issue 15 "suelta sin candado propio" serializa:tres
out="$(bash "$issue" reclamar "$r" 15 kit-bbbb 2>&1)"; [ $? -eq 1 ] || fail "reclamar 15 debía perder el eje"
[ "$(lock_msg tres)" = "agente:agente-ajeno issue:99 eje:tres" ] || fail "soltar sin candado propio liberó el ajeno"

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
echo "OK test_locks"
