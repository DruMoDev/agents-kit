#!/usr/bin/env bash
# Tests for scripts/kit-issue.sh (stateful gh stub, git real).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
issue="$REPO_ROOT/scripts/kit-issue.sh"
# avisos: nunca a la red (curl con stub, tema y HOME temporales)
export PATH="$TESTS_DIR/stubs/notify:$PATH"
export HOME="$(mktemp -d)" CURL_LOG="$(mktemp)" KIT_NTFY_TOPIC=tema-test
unset CURL_FAIL KIT_NTFY_SERVER

mk_kit_repo() {
  local r; r="$(mk_repo)"
  git -C "$r" remote add origin https://github.com/dru/demo.git
  echo '{}' > "$r/.agents-kit.json"
  echo "$r"
}
last_line() { printf '%s\n' "$1" | sed -n '$p'; }

r="$(mk_kit_repo)"
qfile="$(mktemp)"; echo "¿Rojo o azul?" > "$qfile"

# --- siguiente: oldest listo without en-curso/necesita-decision/bloqueado
use_flow_gh
flow_add_issue 1 "sin listo" propuesta
flow_add_issue 2 "cogido" listo en-curso
flow_add_issue 3 "duda" listo necesita-decision
flow_add_issue 4 "bloq" listo bloqueado
flow_add_issue 6 "bueno nuevo" listo
flow_add_issue 5 "bueno viejo" listo
out="$(bash "$issue" siguiente "$r" 2>&1)" || fail "siguiente: exit $? ($out)"
[ "$out" = "$(printf '5\nFIN: 5')" ] || fail "siguiente: salida '$out'"
grep -q -- '--repo dru/demo' "$GH_LOG" || fail "siguiente: gh sin --repo"

use_flow_gh
flow_add_issue 2 "cogido" listo en-curso
err="$(bash "$issue" siguiente "$r" 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "siguiente sin candidatos: exit $rc"
case "$err" in *"no hay issues listos"*) ;; *) fail "siguiente sin candidatos: '$err'";; esac

use_flow_gh; export GH_FAIL_ON="issue list"
bash "$issue" siguiente "$r" >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] || fail "siguiente con gh roto: exit $rc"
unset GH_FAIL_ON

# --- reclamar: wins
use_flow_gh
flow_add_issue 7 "tarea" listo
out="$(bash "$issue" reclamar "$r" 7 kit-aaaa1111 2>&1)" || fail "reclamar: exit $? ($out)"
[ "$(last_line "$out")" = "FIN: reclamado #7" ] || fail "reclamar: salida '$out'"
[ "$(flow_issue 7 '[.labels[].name] | index("en-curso") != null')" = true ] || fail "reclamar: sin en-curso"
[ "$(flow_issue 7 '.comments[0].body')" = "$(printf '<!-- kit-reclamado: kit-aaaa1111 -->\nCogido por el agente `kit-aaaa1111`.')" ] \
  || fail "reclamar: comentario '$(flow_issue 7 '.comments[0].body')'"
while IFS= read -r line; do
  case "$line" in *"--repo dru/demo"*) ;; *) fail "gh sin --repo: $line";; esac
done < "$GH_LOG"
grep -q -- '--body-file' "$GH_LOG" || fail "reclamar: comentario sin --body-file"

# --- reclamar: loses against an earlier claim
use_flow_gh
flow_add_issue 7 "tarea" listo en-curso
flow_add_comment 7 '<!-- kit-reclamado: otro -->'
err="$(bash "$issue" reclamar "$r" 7 kit-aaaa1111 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "reclamar perdido: exit $rc ($err)"
[ "$(flow_issue 7 '.comments[-1].body')" = 'El agente `kit-aaaa1111` suelta este issue: lo había cogido antes `otro`.' ] \
  || fail "reclamar perdido: comentario '$(flow_issue 7 '.comments[-1].body')'"
[ "$(flow_issue 7 '[.labels[].name] | index("en-curso") != null')" = true ] || fail "reclamar perdido: quitó en-curso ajeno"

# --- reclamar: earlier claim released -> wins
use_flow_gh
flow_add_issue 7 "tarea" listo
flow_add_comment 7 '<!-- kit-reclamado: otro -->'
flow_add_comment 7 '<!-- kit-soltado: otro -->'
flow_add_comment 7 '<!-- kit-reclamado: otro2 -->'
flow_add_comment 7 '<!-- kit-soltado: otro2 -->'
out="$(bash "$issue" reclamar "$r" 7 kit-aaaa1111 2>&1)" || fail "reclamar tras soltado: exit $? ($out)"
[ "$(last_line "$out")" = "FIN: reclamado #7" ] || fail "reclamar tras soltado: '$out'"

# --- reclamar: label edit fails -> exit 2 and own kit-soltado published
use_flow_gh; export GH_FAIL_ON="issue edit"
flow_add_issue 7 "tarea" listo
bash "$issue" reclamar "$r" 7 kit-aaaa1111 >/dev/null 2>&1; rc=$?
unset GH_FAIL_ON
[ $rc -eq 2 ] || fail "reclamar con fallo: exit $rc"
flow_issue 7 '.comments[-1].body' | grep -q '^<!-- kit-soltado: kit-aaaa1111 -->' \
  || fail "reclamar con fallo: sin kit-soltado propio ('$(flow_issue 7 '.comments[-1].body')')"
[ "$(flow_issue 7 '[.labels[].name] | index("en-curso") != null')" = false ] || fail "reclamar con fallo: queda en-curso"

# --- soltar: someone else's claim -> exit 1
use_flow_gh
flow_add_issue 7 "tarea" listo en-curso
flow_add_comment 7 '<!-- kit-reclamado: otro -->'
err="$(bash "$issue" soltar "$r" 7 kit-aaaa1111 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "soltar ajeno: exit $rc"
case "$err" in *"la reclamación de #7 es de 'otro', no tuya"*) ;; *) fail "soltar ajeno: '$err'";; esac
[ "$(flow_issue 7 '.comments | length')" = 1 ] || fail "soltar ajeno: publicó comentario"

# --- soltar: own claim -> marker before label removal
use_flow_gh
flow_add_issue 7 "tarea" listo en-curso
flow_add_comment 7 '<!-- kit-reclamado: kit-aaaa1111 -->'
out="$(bash "$issue" soltar "$r" 7 kit-aaaa1111 "me rindo" 2>&1)" || fail "soltar: exit $? ($out)"
[ "$(last_line "$out")" = "FIN: soltado #7" ] || fail "soltar: '$out'"
body="$(flow_issue 7 '.comments[-1].body')"
case "$body" in "<!-- kit-soltado: kit-aaaa1111 -->"*"Motivo: me rindo"*) ;; *) fail "soltar: comentario '$body'";; esac
[ "$(flow_issue 7 '[.labels[].name] | index("en-curso") != null')" = false ] || fail "soltar: queda en-curso"
c="$(grep -n '^issue comment' "$GH_LOG" | cut -d: -f1)"
e="$(grep -n '^issue edit .*--remove-label en-curso' "$GH_LOG" | cut -d: -f1)"
[ -n "$c" ] && [ -n "$e" ] && [ "$c" -lt "$e" ] || fail "soltar: orden comentario/etiqueta ($c, $e)"

# --- decision
use_flow_gh
flow_add_issue 7 "tarea" listo en-curso
flow_add_comment 7 '<!-- kit-reclamado: kit-aaaa1111 -->'
out="$(bash "$issue" decision "$r" 7 kit-aaaa1111 "$qfile" 2>&1)" || fail "decision: exit $? ($out)"
[ "$(last_line "$out")" = "FIN: necesita-decision #7" ] || fail "decision: '$out'"
flow_issue 7 '.comments[].body' | grep -q '^<!-- kit-decision -->' || fail "decision: sin marcador"
flow_issue 7 '.comments[].body' | grep -q '¿Rojo o azul?' || fail "decision: sin pregunta"
[ "$(flow_issue 7 '[.labels[].name] | index("necesita-decision") != null')" = true ] || fail "decision: sin etiqueta"
[ "$(flow_issue 7 '[.labels[].name] | index("en-curso") != null')" = false ] || fail "decision: queda en-curso"
[ "$(flow_issue 7 '.assignees | length')" = 1 ] || fail "decision: sin asignado"
grep -q -- '--add-assignee @me' "$GH_LOG" || fail "decision: no asigna @me"
flow_issue 7 '.comments[-1].body' | grep -q '^<!-- kit-soltado: kit-aaaa1111 -->' || fail "decision: no suelta"
flow_issue 7 '.comments[-1].body' | grep -q 'Motivo: necesita decisión de producto' || fail "decision: motivo"

# --- bloquear
use_flow_gh
flow_add_issue 7 "tarea" listo en-curso
flow_add_comment 7 '<!-- kit-reclamado: kit-aaaa1111 -->'
out="$(bash "$issue" bloquear "$r" 7 kit-aaaa1111 "$qfile" 2>&1)" || fail "bloquear: exit $? ($out)"
[ "$(last_line "$out")" = "FIN: bloqueado #7" ] || fail "bloquear: '$out'"
flow_issue 7 '.comments[].body' | grep -q '^<!-- kit-bloqueado -->' || fail "bloquear: sin marcador"
[ "$(flow_issue 7 '[.labels[].name] | index("bloqueado") != null')" = true ] || fail "bloquear: sin etiqueta"
[ "$(flow_issue 7 '[.labels[].name] | index("en-curso") != null')" = false ] || fail "bloquear: queda en-curso"

# --- avisos tras decision/bloquear
seed7() { use_flow_gh; flow_add_issue 7 "tarea: rojo" listo en-curso; flow_add_comment 7 '<!-- kit-reclamado: kit-aaaa1111 -->'; }
echo '{"notify":"none"}' > "$r/.agents-kit.json"
seed7; : > "$CURL_LOG"
out="$(bash "$issue" decision "$r" 7 kit-aaaa1111 "$qfile" 2>&1)" || fail "aviso none: exit $? ($out)"
[ "$(last_line "$out")" = "FIN: necesita-decision #7" ] || fail "aviso none: '$out'"
[ -s "$CURL_LOG" ] && fail "aviso none: llamó a curl"
echo '{"notify":"ntfy"}' > "$r/.agents-kit.json"
seed7; : > "$CURL_LOG"
out="$(bash "$issue" decision "$r" 7 kit-aaaa1111 "$qfile" 2>/dev/null)" || fail "aviso ntfy: exit $?"
[ "$(last_line "$out")" = "FIN: necesita-decision #7" ] || fail "aviso ntfy: '$out'"
grep -qx "Title: demo: necesita decisión" "$CURL_LOG" || fail "aviso ntfy: título ($(cat "$CURL_LOG"))"
grep -qx "#7 tarea: rojo" "$CURL_LOG" || fail "aviso ntfy: mensaje"
grep -qx "Click: https://github.com/dru/demo/issues/7" "$CURL_LOG" || fail "aviso ntfy: url"
seed7; : > "$CURL_LOG"
out="$(bash "$issue" bloquear "$r" 7 kit-aaaa1111 "$qfile" 2>/dev/null)" || fail "aviso bloquear: exit $?"
grep -qx "Title: demo: bloqueado" "$CURL_LOG" || fail "aviso bloquear: título"
seed7
err="$(CURL_FAIL=1 bash "$issue" decision "$r" 7 kit-aaaa1111 "$qfile" 2>&1 >"$HOME/out")"; rc=$?
[ $rc -eq 0 ] || fail "aviso fallido: exit $rc"
case "$err" in *"aviso: no se pudo avisar (error: no se pudo enviar el aviso por ntfy)"*) ;; *) fail "aviso fallido: stderr '$err'";; esac
[ "$(sed -n '$p' "$HOME/out")" = "FIN: necesita-decision #7" ] || fail "aviso fallido: FIN '$(cat "$HOME/out")'"
# tema nuevo y envío fallido: la línea del tema no se pierde
seed7
out="$(HOME="$(mktemp -d)" CURL_FAIL=1 KIT_NTFY_TOPIC= bash "$issue" decision "$r" 7 kit-aaaa1111 "$qfile" 2>/dev/null)"; rc=$?
[ $rc -eq 0 ] || fail "tema nuevo con fallo: exit $rc"
printf '%s\n' "$out" | grep -q '^tema ntfy nuevo: agents-kit-' || fail "tema nuevo con fallo: se perdió la línea ($out)"
[ "$(last_line "$out")" = "FIN: necesita-decision #7" ] || fail "tema nuevo con fallo: FIN '$out'"
echo '{"notify":"claude-push"}' > "$r/.agents-kit.json"
seed7
out="$(bash "$issue" bloquear "$r" 7 kit-aaaa1111 "$qfile" 2>/dev/null)" || fail "aviso push: exit $?"
[ "$out" = "$(printf 'AVISO-CLAUDE: demo: bloqueado: #7 tarea: rojo https://github.com/dru/demo/issues/7\nFIN: bloqueado #7')" ] \
  || fail "aviso push: '$out'"
echo '{}' > "$r/.agents-kit.json"

# --- crear
use_flow_gh
flow_add_issue 3 "Arreglar Login" listo
bfile="$(mktemp)"; echo "cuerpo" > "$bfile"
err="$(bash "$issue" crear "$r" "arreglar login" "$bfile" listo 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "crear duplicado: exit $rc"
case "$err" in *"ya existe #3 con ese título"*) ;; *) fail "crear duplicado: '$err'";; esac
out="$(bash "$issue" crear "$r" "Nuevo" "$bfile" propuesta 2>&1)" || fail "crear: exit $? ($out)"
[ "$out" = "$(printf 'https://github.com/dru/demo/issues/4\nFIN: https://github.com/dru/demo/issues/4')" ] || fail "crear: '$out'"
[ "$(flow_issue 4 '[.labels[].name] | join(",")')" = propuesta ] || fail "crear: etiqueta"
[ "$(flow_issue 4 '.body')" = cuerpo ] || fail "crear: cuerpo"
bash "$issue" crear "$r" "Otro" "$bfile" en-curso >/dev/null 2>&1; [ $? -eq 1 ] || fail "crear con etiqueta inválida debe salir 1"

# --- no marker: every subcommand refuses
nr="$(mk_repo)"; git -C "$nr" remote add origin https://github.com/dru/demo.git
use_flow_gh
for args in "siguiente" "reclamar 7 kit-a" "soltar 7 kit-a" "decision 7 kit-a $qfile" \
            "bloquear 7 kit-a $qfile" "crear x $qfile listo"; do
  set -- $args
  sub="$1"; shift
  err="$(bash "$issue" "$sub" "$nr" "$@" 2>&1 >/dev/null)"; rc=$?
  [ $rc -eq 1 ] || fail "sin marcador ($sub): exit $rc"
  [ "$err" = "kit no activado: ejecuta kit-on" ] || fail "sin marcador ($sub): '$err'"
done
[ -s "$GH_LOG" ] && fail "sin marcador: se llamó a gh"

echo "OK test_issue"
