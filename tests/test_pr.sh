#!/usr/bin/env bash
# Tests for scripts/kit-pr.sh (local bare origin, stateful gh stub).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
pr="$REPO_ROOT/scripts/kit-pr.sh"
use_flow_gh
export KIT_CI_POLL=0
unset KIT_CI_TIMEOUT KIT_CI_GRACE GH_CHECKS_SEQ GH_USER
last_line() { printf '%s\n' "$1" | sed -n '$p'; }
tmp="$(mktemp -d)"

# repo with tracked marker, bare origin seen as github.com/dru/demo, worktree on issue-3-foo
r="$(mk_repo)"; o="$(mktemp -d)"
git init -q --bare "$o"
echo '{}' > "$r/.agents-kit.json"
(cd "$r" && git add .agents-kit.json && git commit -q -m marker \
  && git remote add origin https://github.com/dru/demo.git \
  && git config "url.$o.insteadOf" "https://github.com/dru/demo.git" \
  && git push -q -u origin main) >/dev/null 2>&1 || fail "setup remoto"
git -C "$o" symbolic-ref HEAD refs/heads/main
wt="$(mktemp -d)/wt"
git -C "$r" worktree add -q -b issue-3-foo --no-track "$wt" origin/main || fail "setup worktree"
flow_add_issue 3 "Foo" en-curso

st() { # <jq-filter>: update the stub state
  local t; t="$(mktemp)"
  jq "$1" "$GH_STATE/state.json" > "$t" && mv "$t" "$GH_STATE/state.json" || fail "st $1"
}
seq_checks() { # <json-array>...: check-runs answers, one per call, the last repeating
  printf '%s\n' "$@" > "$GH_STATE/checks.seq"
  rm -f "$GH_STATE/.checks_idx"
  export GH_CHECKS_SEQ="$GH_STATE/checks.seq"
}
pr_q() { jq -r ".prs[0] | $1" "$GH_STATE/state.json"; }
IP='[{"status":"in_progress","conclusion":null}]'
OK='[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"skipped"}]'
KO='[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"failure"}]'

# no marker
m="$(mk_repo)"; bash "$pr" historial "$m" 1 >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin marcador debe dar 1"

# abrir: no commits over origin/main
printf 'Cuerpo\n' > "$tmp/body"
bash "$pr" abrir "$wt" 3 "Foo" "$tmp/body" >/dev/null 2>&1; [ $? -eq 1 ] || fail "abrir sin commits debe dar 1"
# abrir: dirty tree
(cd "$wt" && echo a > a.txt && git add a.txt && git commit -q -m a) || fail "commit a"
echo x > "$wt/sucio.txt"
bash "$pr" abrir "$wt" 3 "Foo" "$tmp/body" >/dev/null 2>&1; [ $? -eq 1 ] || fail "abrir sucio debe dar 1"
rm "$wt/sucio.txt"
[ "$(jq '.prs | length' "$GH_STATE/state.json")" -eq 0 ] || fail "abrir rechazado creó PR"

# abrir: adds "Cierra #3"
out="$(bash "$pr" abrir "$wt" 3 "Foo" "$tmp/body" 2>&1)" || fail "abrir: $out"
url="https://github.com/dru/demo/pull/4"
[ "$(last_line "$out")" = "FIN: $url" ] || fail "abrir FIN: $out"
printf '%s\n' "$out" | grep -qx 4 || fail "abrir no imprime el número: $out"
case "$(pr_q .body)" in "Cuerpo"*"Cierra #3") ;; *) fail "falta Cierra #3: $(pr_q .body)";; esac
[ "$(pr_q .baseRefName)/$(pr_q .headRefName)" = "main/issue-3-foo" ] || fail "base/head"
[ "$(git -C "$o" rev-parse issue-3-foo)" = "$(git -C "$wt" rev-parse HEAD)" ] || fail "abrir no empujó"
grep -n "push" "$GH_LOG" >/dev/null && fail "push por gh"
# body that already closes the issue is kept as is
printf 'Algo\n\nCierra #3\n' > "$tmp/body2"
st '.prs = []'
bash "$pr" abrir "$wt" 3 "Foo" "$tmp/body2" >/dev/null 2>&1 || fail "abrir 2"
[ "$(pr_q .body | grep -c 'Cierra #3')" -eq 1 ] || fail "duplica Cierra #3"
p=4
[ "$(pr_q .number)" = 4 ] || fail "número de PR"
# abrir again with an open PR for the branch: pushes, reuses it, creates nothing
(cd "$wt" && echo c > c.txt && git add c.txt && git commit -q -m c) || fail "commit c"
out="$(bash "$pr" abrir "$wt" 3 "Foo" "$tmp/body" 2>&1)" || fail "abrir idempotente: $out"
[ "$(jq '.prs | length' "$GH_STATE/state.json")" -eq 1 ] || fail "abrir idempotente creó otra PR"
[ "$(last_line "$out")" = "FIN: $url" ] || fail "abrir idempotente FIN: $out"
printf '%s\n' "$out" | grep -qx 4 || fail "abrir idempotente no imprime el número: $out"
[ "$(git -C "$o" rev-parse issue-3-foo)" = "$(git -C "$wt" rev-parse HEAD)" ] || fail "abrir idempotente no empujó"
grep -q -- "pr list --repo dru/demo --head issue-3-foo --state open" "$GH_LOG" || fail "abrir no busca la PR abierta"

# esperar-ci: no workflows
out="$(bash "$pr" esperar-ci "$wt" $p 2>&1)" || fail "sin-ci: $out"
[ "$(last_line "$out")" = "FIN: sin-ci" ] || fail "sin-ci FIN: $out"
# in_progress then success
st '.workflows = 1'
seq_checks "$IP" "$OK"
out="$(bash "$pr" esperar-ci "$wt" $p 2>&1)" || fail "verde: $out"
[ "$(last_line "$out")" = "FIN: verde" ] || fail "verde FIN: $out"
grep -q "commits/$(git -C "$wt" rev-parse HEAD)/check-runs" "$GH_LOG" || fail "esperar-ci no consulta el SHA de HEAD"
# a failed attempt re-run successfully: latest id per check name wins, whatever the array order
seq_checks '[{"name":"ci","id":2,"status":"completed","conclusion":"success"},{"name":"ci","id":1,"status":"completed","conclusion":"failure"}]'
out="$(bash "$pr" esperar-ci "$wt" $p 2>&1)" || fail "re-run: $out"
[ "$(last_line "$out")" = "FIN: verde" ] || fail "re-run FIN: $out"
seq_checks '[{"name":"ci","id":1,"status":"completed","conclusion":"success"},{"name":"ci","id":2,"status":"completed","conclusion":"failure"}]'
bash "$pr" esperar-ci "$wt" $p >/dev/null 2>&1; [ $? -eq 1 ] || fail "re-run fallido debe dar 1"
# same check name from two apps: a success of one app never masks a failure of the other
seq_checks '[{"name":"ci","id":5,"app":{"id":1},"status":"completed","conclusion":"failure"},{"name":"ci","id":6,"app":{"id":2},"status":"completed","conclusion":"success"}]'
err="$(bash "$pr" esperar-ci "$wt" $p 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "dos apps: exit $rc"
case "$err" in *"el CI terminó en 'failure'"*) ;; *) fail "dos apps msg: $err";; esac
# workflows but no check run for the SHA after the grace period: no CI for this PR
seq_checks '[]'
out="$(KIT_CI_GRACE=0 KIT_CI_TIMEOUT=2 bash "$pr" esperar-ci "$wt" $p 2>&1)" || fail "sin checks: $out"
[ "$(last_line "$out")" = "FIN: sin-ci" ] || fail "sin checks FIN: $out"
KIT_CI_GRACE=x bash "$pr" esperar-ci "$wt" $p >/dev/null 2>&1; [ $? -eq 2 ] || fail "KIT_CI_GRACE inválido debe dar 2"
# Review Focus 2: no checks yet right after the push, then success
seq_checks '[]' '[]' "$OK"
out="$(bash "$pr" esperar-ci "$wt" $p 2>&1)" || fail "lag: $out"
[ "$(last_line "$out")" = "FIN: verde" ] || fail "lag FIN: $out"
[ "$(cat "$GH_STATE/.checks_idx")" -eq 3 ] || fail "lag no siguió esperando"
# failure
seq_checks "$IP" "$KO"
err="$(bash "$pr" esperar-ci "$wt" $p 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "failure: exit $rc"
case "$err" in *"el CI terminó en 'failure'"*) ;; *) fail "failure msg: $err";; esac
# completed without conclusion is not green
seq_checks '[{"status":"completed","conclusion":null}]'
bash "$pr" esperar-ci "$wt" $p >/dev/null 2>&1; [ $? -eq 1 ] || fail "conclusión nula debe dar 1"
# timeout
seq_checks "$IP"
err="$(KIT_CI_TIMEOUT=0 bash "$pr" esperar-ci "$wt" $p 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "timeout: exit $rc"
sha="$(git -C "$wt" rev-parse HEAD)"
case "$err" in *"el CI de ${sha:0:8} no concluyó en 0s"*) ;; *) fail "timeout msg: $err";; esac
# gh failure -> 2
GH_FAIL_ON="check-runs" bash "$pr" esperar-ci "$wt" $p >/dev/null 2>&1; [ $? -eq 2 ] || fail "fallo de gh debe dar 2"
# local SHA differs from the PR
(cd "$wt" && echo b > b.txt && git add b.txt && git commit -q -m b) || fail "commit b"
seq_checks "$OK"
err="$(bash "$pr" esperar-ci "$wt" $p 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 2 ] || fail "sha distinto: exit $rc"
case "$err" in *"la PR apunta a $sha y aquí estás en $(git -C "$wt" rev-parse HEAD): empuja o espera"*) ;; *) fail "sha msg: $err";; esac
git -C "$wt" push -q origin HEAD 2>/dev/null || fail "push b"
sha="$(git -C "$wt" rev-parse HEAD)"
unset GH_CHECKS_SEQ

# historial without rounds
out="$(bash "$pr" historial "$wt" $p 2>&1)" || fail "historial vacío: $out"
[ "$out" = "(sin rondas previas)
FIN: 0 rondas" ] || fail "historial vacío: $out"

# ronda: a finding without decision
printf -- '- [R1.1] (claude/opus) uno → aplicado\n- [R1.2] (claude/opus) dos\n' > "$tmp/r1bad"
err="$(bash "$pr" ronda "$wt" $p 1 "$tmp/r1bad" 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "ronda sin decisión: exit $rc"
case "$err" in *"[R1.2]"*) ;; *) fail "ronda no indica la línea: $err";; esac
printf -- '- [R1.1] (claude/opus) uno → rechazado:\n' > "$tmp/r1bad2"
bash "$pr" ronda "$wt" $p 1 "$tmp/r1bad2" >/dev/null 2>&1; [ $? -eq 1 ] || fail "rechazado sin motivo debe dar 1"
[ "$(pr_q '.comments | length')" -eq 0 ] || fail "ronda inválida publicó"

# ronda ok x2, then historial in order
printf -- 'Ronda 1\n- [R1.1] (claude/opus) uno → aplicado\n- [R1.2] (claude/opus) dos → rechazado: no aplica\n' > "$tmp/r1"
printf -- 'Ronda 2\n- [R2.1] (opencode/x) tres → aplicado\n' > "$tmp/r2"
st '.prs[0].comments += [{"id": 50, "body": "<!-- kit-revision: claude/opus ronda 1 -->\nhallazgos"}]'
out="$(bash "$pr" ronda "$wt" $p 1 "$tmp/r1" 2>&1)" || fail "ronda 1: $out"
[ "$(last_line "$out")" = "FIN: ronda 1" ] || fail "ronda 1 FIN: $out"
bash "$pr" ronda "$wt" $p 2 "$tmp/r2" >/dev/null 2>&1 || fail "ronda 2"
[ "$(pr_q '.comments[1].body' | sed -n 1p)" = "<!-- kit-ronda: 1 -->" ] || fail "marcador ronda"
out="$(bash "$pr" historial "$wt" $p 2>&1)" || fail "historial: $out"
exp="<!-- kit-ronda: 1 -->
$(cat "$tmp/r1")
-----
<!-- kit-ronda: 2 -->
$(cat "$tmp/r2")
FIN: 2 rondas"
[ "$out" = "$exp" ] || fail "historial: $out"
# a kit-ronda written by someone else is not part of the history
st '.prs[0].comments += [{"id": 60, "body": "<!-- kit-ronda: 9 -->\najena", "author": {"login": "otro"}}]'
out="$(bash "$pr" historial "$wt" $p 2>&1)" || fail "historial ajeno: $out"
[ "$out" = "$exp" ] || fail "historial con ronda ajena: $out"
grep -q "^api user" "$GH_LOG" || fail "historial no lee el usuario de gh"
st '.prs[0].comments |= map(select(.id != 60))'
# own login unreadable -> 2
rm -f "$GH_STATE/.failed"
GH_FAIL_ON="api user" bash "$pr" historial "$wt" $p >/dev/null 2>&1; [ $? -eq 2 ] || fail "usuario ilegible debe dar 2"

# gate-local
printf 'tests ok\nlint ok\n' > "$tmp/gate"
out="$(bash "$pr" gate-local "$wt" $p "$tmp/gate" 2>&1)" || fail "gate-local: $out"
[ "$(last_line "$out")" = "FIN: gate-local ${sha:0:8}" ] || fail "gate-local FIN: $out"
gate_body="$(pr_q '.comments[-1].body')"
case "$gate_body" in "<!-- kit-gate-local: $sha -->"*"tests ok"*"lint ok"*) ;; *) fail "gate body: $gate_body";; esac
st '.prs[0].comments |= map(select(.body | startswith("<!-- kit-gate-local") | not))'

# fusionar: kit-revision after the last kit-ronda (Review Focus 4), CI green
st '.workflows = 1 | .checks = [{"status":"completed","conclusion":"success"}]'
st '.prs[0].comments += [{"id": 90, "body": "\n  <!-- kit-revision: claude/opus ronda 3 -->\nnuevo"}]'
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "revisión posterior: exit $rc"
case "$err" in "no se puede fusionar:"*"  - "*"posterior"*) ;; *) fail "revisión msg: $err";; esac
[ "$(pr_q .state)" = OPEN ] || fail "fusionó con revisión pendiente"
# a later kit-ronda by someone else does not settle the review
st '.prs[0].comments += [{"id": 95, "body": "<!-- kit-ronda: 3 -->\nRonda 3", "author": {"login": "otro"}}]'
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "ronda ajena: exit $rc"
case "$err" in *"posterior"*) ;; *) fail "ronda ajena msg: $err";; esac
[ "$(pr_q .state)" = OPEN ] || fail "fusionó con una ronda ajena"
st '.prs[0].comments |= map(select(.id != 90 and .id != 95))'

# fusionar: no CI green and no gate-local
st '.checks = [{"status":"completed","conclusion":"failure"}]'
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "CI rojo: exit $rc"
case "$err" in *"el CI terminó en 'failure'"*) ;; *) fail "CI rojo msg: $err";; esac
st '.workflows = 0 | .checks = []'
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "sin gate: exit $rc"
case "$err" in *"gate local"*) ;; *) fail "sin gate msg: $err";; esac
# a gate-local for another SHA does not count
st ".prs[0].comments += [{\"id\": 91, \"body\": \"<!-- kit-gate-local: $(git -C "$wt" rev-parse HEAD~1) -->\"}]"
bash "$pr" fusionar "$wt" $p 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "gate de otro sha debe dar 1"
# the gate-local rules, with a dirty tree so nothing merges
echo x > "$wt/sucio.txt"
# a gate-local for the SHA written by someone else does not count
st ".prs[0].comments += [{\"id\": 92, \"body\": \"<!-- kit-gate-local: $sha -->\", \"author\": {\"login\": \"otro\"}}]"
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"
case "$err" in *"gate local"*) ;; *) fail "gate ajeno aceptado: $err";; esac
st '.prs[0].comments |= map(select(.id != 92))'
bash "$pr" gate-local "$wt" $p "$tmp/gate" >/dev/null 2>&1 || fail "gate-local propio"
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"
case "$err" in *"gate local"*|*"CI"*) fail "gate propio rechazado: $err";; esac
# workflows that never ran for the SHA (no check run): the own gate-local is accepted
st '.workflows = 1 | .checks = []'
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"
case "$err" in *"gate local"*|*"CI"*) fail "gate con workflows sin checks rechazado: $err";; esac
# any check run for the SHA wins over the gate-local, even without workflows
st '.workflows = 0 | .checks = [{"name":"x","id":1,"status":"in_progress","conclusion":null}]'
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"
case "$err" in *"el CI de ${sha:0:8} no ha concluido"*) ;; *) fail "gate aceptado con checks: $err";; esac
st '.checks = [{"name":"x","id":1,"status":"completed","conclusion":"failure"}]'
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"
case "$err" in *"el CI terminó en 'failure'"*) ;; *) fail "gate aceptado con check rojo: $err";; esac
rm "$wt/sucio.txt"
st '.checks = [] | .prs[0].comments |= map(select(.body | startswith("<!-- kit-gate-local") | not))'

# fusionar: draft + dirty + no rounds -> the 3 reasons together
saved="$(jq -c '.prs[0].comments' "$GH_STATE/state.json")"
st '.prs[0].isDraft = true | .prs[0].comments = []'
bash "$pr" gate-local "$wt" $p "$tmp/gate" >/dev/null 2>&1 || fail "gate-local 2"
echo x > "$wt/sucio.txt"
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "3 motivos: exit $rc"
[ "$(printf '%s\n' "$err" | grep -c '^  - ')" -eq 3 ] || fail "no lista 3 motivos: $err"
case "$err" in *borrador*cambios*ronda*) ;; *) fail "3 motivos msg: $err";; esac
rm "$wt/sucio.txt"
st ".prs[0].isDraft = false | .prs[0].comments = $saved"
bash "$pr" gate-local "$wt" $p "$tmp/gate" >/dev/null 2>&1 || fail "gate-local 3"

# fusionar: origin/main moved -> rebase, push, ask to wait for CI again
(cd "$r" && echo m > m.txt && git add m.txt && git commit -q -m m && git push -q origin main) 2>/dev/null || fail "avanzar main"
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "rebase: exit $rc"
case "$err" in *"rebasada sobre main: vuelve a esperar el CI"*) ;; *) fail "rebase msg: $err";; esac
git -C "$wt" merge-base --is-ancestor "$(git -C "$r" rev-parse main)" HEAD || fail "no rebasó"
[ "$(git -C "$o" rev-parse issue-3-foo)" = "$(git -C "$wt" rev-parse HEAD)" ] || fail "no empujó el rebase"
[ "$(pr_q .state)" = OPEN ] || fail "fusionó tras rebasar"
sha="$(git -C "$wt" rev-parse HEAD)"
bash "$pr" gate-local "$wt" $p "$tmp/gate" >/dev/null 2>&1 || fail "gate-local 4"

# fusionar: rebase conflict -> abort
(cd "$r" && echo main > b.txt && git add b.txt && git commit -q -m conflicto && git push -q origin main) 2>/dev/null || fail "conflicto main"
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "conflicto: exit $rc"
case "$err" in *"conflicto con main: resuélvelo"*) ;; *) fail "conflicto msg: $err";; esac
[ "$(git -C "$wt" rev-parse HEAD)" = "$sha" ] && [ -z "$(git -C "$wt" status --porcelain)" ] || fail "conflicto no abortó"
[ ! -d "$(git -C "$wt" rev-parse --git-path rebase-merge)" ] || fail "rebase a medias"
(cd "$r" && git reset -q --hard HEAD~1 && git push -q -f origin main) 2>/dev/null || fail "deshacer conflicto"

# fusionar: the last own round applied changes -> a new round is missing
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "ronda con aplicados: exit $rc"
case "$err" in *"la última ronda aplicó cambios: falta una ronda nueva"*) ;; *) fail "aplicado msg: $err";; esac
# a later round by someone else does not count
st '.prs[0].comments += [{"id": 96, "body": "<!-- kit-ronda: 3 -->\nRonda 3: 0 hallazgos.", "author": {"login": "otro"}}]'
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"
case "$err" in *"la última ronda aplicó cambios"*) ;; *) fail "ronda ajena sin aplicados aceptada: $err";; esac
st '.prs[0].comments |= map(select(.id != 96))'
printf 'Ronda 3: 0 hallazgos de todos los revisores.\n' > "$tmp/r3"
bash "$pr" ronda "$wt" $p 3 "$tmp/r3" >/dev/null 2>&1 || fail "ronda 3"

# fusionar: a push lands between the gates and the merge -> merge refused (all gates passed, round 3 included)
GH_RACE_OID=0123456789abcdef0123456789abcdef01234567 bash "$pr" fusionar "$wt" $p 3 >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] || fail "carrera: exit $rc"
[ "$(pr_q .state)" = OPEN ] || fail "fusionó otro head"
grep -q -- "--match-head-commit $sha" "$GH_LOG" || fail "merge sin --match-head-commit"

# fusionar: everything fine with green CI (no gate-local) -> merge and close the issue
st '.workflows = 1 | .checks = [{"name":"ci","id":7,"status":"completed","conclusion":"success"}]
  | .prs[0].comments |= map(select(.body | startswith("<!-- kit-gate-local") | not))
  | (.issues[] | select(.number == 3) | .labels) += [{name: "listo"}, {name: "otra"}]'
: > "$GH_LOG"
out="$(bash "$pr" fusionar "$wt" $p 3 2>&1)" || fail "fusionar: $out"
grep -q "commits/$sha/check-runs" "$GH_LOG" || fail "fusionar no consulta el SHA de la PR"
[ "$(last_line "$out")" = "FIN: ok" ] || fail "fusionar FIN: $out"
case "$out" in *"PR fusionado: $url"*) ;; *) fail "fusionar msg: $out";; esac
[ "$(pr_q .state)" = MERGED ] || fail "no fusionó"
[ "$(flow_issue 3 .state)" = CLOSED ] || fail "no cerró el issue"
[ "$(flow_issue 3 '.comments[-1].body')" = "Resuelto en #$p." ] || fail "comentario de cierre"
[ "$(flow_issue 3 '[.labels[].name] | sort | join(",")')" = otra ] || fail "no quitó en-curso y listo: $(flow_issue 3 '.labels')"
grep -q -- "issue edit 3 --repo dru/demo --remove-label en-curso --remove-label listo" "$GH_LOG" || fail "issue edit sin las etiquetas"
grep -q -- "pr merge $p.*--squash" "$GH_LOG" || fail "merge sin --squash"
grep -q -- "--delete-branch" "$GH_LOG" && fail "merge con --delete-branch"
while IFS= read -r line; do case "$line" in *"dru/demo"*|"api user --jq .login") ;; *) fail "gh sin repo: $line";; esac; done < "$GH_LOG"

# fusionar: a failing label cleanup is only a warning, the merge still counts
st '.prs[0].state = "OPEN" | .prs[0].comments |= map(select(.body | startswith("<!-- kit-gate-local") | not))
  | (.issues[] | select(.number == 3)) |= (.state = "OPEN" | .labels = [{name: "listo"}, {name: "en-curso"}])'
rm -f "$GH_STATE/.failed"
GH_FAIL_ON="issue edit" bash "$pr" fusionar "$wt" $p 3 >"$GH_STATE/o" 2>"$GH_STATE/e"; rc=$?
[ $rc -eq 0 ] || fail "etiquetas fallidas rompen la fusión: $rc $(cat "$GH_STATE/e")"
[ "$(last_line "$(cat "$GH_STATE/o")")" = "FIN: ok" ] || fail "FIN con aviso de etiquetas"
grep -q "etiquetas" "$GH_STATE/e" || fail "sin aviso de etiquetas: $(cat "$GH_STATE/e")"
# fusionar: malformed CHANGELOG.md blocks the merge before gh pr merge
st '.prs[0].state = "OPEN" | .prs[0].comments |= map(select(.body | startswith("<!-- kit-gate-local") | not))
  | (.issues[] | select(.number == 3)) |= (.state = "OPEN" | .labels = [{name: "listo"}, {name: "en-curso"}])'
printf '# Changelog\n\n## 2026-10-18\n\n### Novedad: Algo · [#1](https://github.com/dru/demo/pull/1)\n' > "$wt/CHANGELOG.md"
: > "$GH_LOG"
err="$(bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "changelog inválido debe dar 1: $rc $err"
case "$err" in *"CHANGELOG.md mal formado"*"CHANGELOG.md:5: tipo inválido"*) ;; *) fail "changelog msg: $err";; esac
grep -q "pr merge" "$GH_LOG" && fail "fusionó con el changelog inválido"
[ "$(pr_q .state)" = OPEN ] || fail "changelog inválido: PR no abierta"
rm "$wt/CHANGELOG.md"
# fusionar with a valid CHANGELOG.md (kept out of git status) merges
excl="$(git -C "$wt" rev-parse --git-common-dir)/info/exclude"; mkdir -p "$(dirname "$excl")"
cp "$excl" "$tmp/exclude.bak" 2>/dev/null || : > "$tmp/exclude.bak"
echo CHANGELOG.md >> "$excl"
printf '# Changelog\n\n## 2026-10-18\n\n### Nuevo: Algo · [#1](https://github.com/dru/demo/pull/1)\n' > "$wt/CHANGELOG.md"
reset_open() {
  st '.prs[0].state = "OPEN" | .prs[0].comments |= map(select(.body | startswith("<!-- kit-gate-local") | not))
    | (.issues[] | select(.number == 3)) |= (.state = "OPEN" | .labels = [{name: "listo"}, {name: "en-curso"}])'
}
reset_open; : > "$GH_LOG"
out="$(bash "$pr" fusionar "$wt" $p 3 2>&1)" || fail "fusionar con changelog válido: $out"
[ "$(last_line "$out")" = "FIN: ok" ] || fail "changelog válido FIN: $out"
[ "$(pr_q .state)" = MERGED ] || fail "changelog válido: no fusionó"
# kit-changelog exit 2 (awk roto) -> fusionar exit 2, sin fusionar
reset_open; : > "$GH_LOG"
awkd="$(mktemp -d)"; printf '#!/bin/sh\nexit 2\n' > "$awkd/awk"; chmod +x "$awkd/awk"
err="$(PATH="$awkd:$PATH" bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 2 ] || fail "kit-changelog exit 2 debe dar 2: $rc $err"
case "$err" in *"kit-changelog.sh falló"*) ;; *) fail "kit-changelog exit 2 msg: $err";; esac
grep -q "pr merge" "$GH_LOG" && fail "fusionó con kit-changelog roto"
# a marker that vanishes from the worktree is not reported as a malformed changelog
reset_open
realgit="$(command -v git)"; gitd="$(mktemp -d)"
printf '#!/bin/sh\n[ "$1" = status ] && rm -f "%s/.agents-kit.json"\nexec "%s" "$@"\n' "$wt" "$realgit" > "$gitd/git"; chmod +x "$gitd/git"
err="$(PATH="$gitd:$PATH" bash "$pr" fusionar "$wt" $p 3 2>&1 >/dev/null)"; rc=$?
case "$err" in *"mal formado"*) fail "marcador ausente informado como changelog mal formado: $err";; esac
git -C "$wt" checkout -q -- .agents-kit.json || fail "restaurar marcador"
rm "$wt/CHANGELOG.md"; cp "$tmp/exclude.bak" "$excl"
echo "OK test_pr"
