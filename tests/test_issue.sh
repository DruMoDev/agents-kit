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

# --- siguiente: any open issue outside the excluded labels; prio:alta, prio:media, none, prio:baja; oldest first
use_flow_gh
flow_add_issue 1 "prop" propuesta
flow_add_issue 2 "cogido" en-curso
flow_add_issue 3 "duda" necesita-respuesta
flow_add_issue 4 "bloq" bloqueado
flow_add_issue 5 "algún día" someday
flow_add_issue 6 "registro" registro
flow_add_issue 7 "duda v2" listo necesita-decision
flow_add_issue 8 "📦 Changelog"
flow_add_issue 9 "baja vieja" prio:baja
flow_add_issue 12 "sin prio nueva" area
flow_add_issue 11 "sin prio vieja v2" listo
flow_add_issue 14 "media nueva" prio:media
flow_add_issue 13 "media vieja" prio:media
flow_add_issue 16 "alta cogida" prio:alta en-curso
# an issue opened by someone else never enters the pool (prompt injection into an unattended agent)
FLOW_AUTHOR=desconocido flow_add_issue 17 "alta ajena" prio:alta
out="$(bash "$issue" siguiente "$r" 2>&1)" || fail "siguiente: exit $? ($out)"
[ "$out" = "$(printf '13\nFIN: 13')" ] || fail "siguiente media: salida '$out'"
grep -q -- '--repo dru/demo' "$GH_LOG" || fail "siguiente: gh sin --repo"
grep -q -- '--label' "$GH_LOG" && fail "siguiente: filtra por etiqueta en gh (debe ser cualquier issue abierto)"
lim="$(sed -n 's/.*--limit \([0-9]*\).*/\1/p' "$GH_LOG")"
[ -n "$lim" ] && [ "$lim" -ge 300 ] || fail "siguiente: --limit '$lim' (mínimo 300)"
flow_add_issue 20 "alta" prio:alta
out="$(bash "$issue" siguiente "$r" 2>/dev/null)"
[ "$(last_line "$out")" = "FIN: 20" ] || fail "siguiente alta: '$out'"
use_flow_gh
flow_add_issue 9 "baja vieja" prio:baja
flow_add_issue 12 "sin prio nueva"
flow_add_issue 11 "sin prio vieja v2" listo
out="$(bash "$issue" siguiente "$r" 2>/dev/null)"
[ "$(last_line "$out")" = "FIN: 11" ] || fail "siguiente sin prio antes que baja: '$out'"
use_flow_gh
flow_add_issue 9 "baja" prio:baja
out="$(bash "$issue" siguiente "$r" 2>/dev/null)"
[ "$(last_line "$out")" = "FIN: 9" ] || fail "siguiente solo baja: '$out'"

use_flow_gh
flow_add_issue 2 "cogido" en-curso
flow_add_issue 3 "v2" listo necesita-decision
err="$(bash "$issue" siguiente "$r" 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "siguiente sin candidatos: exit $rc"
case "$err" in *"no hay issues disponibles"*) ;; *) fail "siguiente sin candidatos: '$err'";; esac

use_flow_gh; export GH_FAIL_ON="issue list"
bash "$issue" siguiente "$r" >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] || fail "siguiente con gh roto: exit $rc"
unset GH_FAIL_ON

# --- reclamar: en-curso without any kit marker (another flow) -> exit 1, nothing published
use_flow_gh
flow_add_issue 7 "tarea" en-curso
err="$(bash "$issue" reclamar "$r" 7 kit-aaaa1111 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "reclamar en-curso ajeno: exit $rc ($err)"
case "$err" in *"#7 ya tiene en-curso"*) ;; *) fail "reclamar en-curso ajeno: '$err'";; esac
[ "$(flow_issue 7 '.comments | length')" = 0 ] || fail "reclamar en-curso ajeno: publicó comentario"
grep -q '^issue edit' "$GH_LOG" && fail "reclamar en-curso ajeno: tocó etiquetas"

# --- reclamar: wins
use_flow_gh
flow_add_issue 7 "tarea"
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
flow_add_issue 7 "tarea"
flow_add_comment 7 '<!-- kit-reclamado: otro -->'
err="$(bash "$issue" reclamar "$r" 7 kit-aaaa1111 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "reclamar perdido: exit $rc ($err)"
[ "$(flow_issue 7 '.comments[-1].body')" = 'El agente `kit-aaaa1111` suelta este issue: lo había cogido antes `otro`.' ] \
  || fail "reclamar perdido: comentario '$(flow_issue 7 '.comments[-1].body')'"
[ "$(flow_issue 7 '[.labels[].name] | index("en-curso") != null')" = true ] || fail "reclamar perdido: quitó en-curso ajeno"
# --- reclamar: en-curso of another kit agent -> exit 1 before publishing anything
use_flow_gh
flow_add_issue 7 "tarea" en-curso
flow_add_comment 7 '<!-- kit-reclamado: otro -->'
bash "$issue" reclamar "$r" 7 kit-aaaa1111 >/dev/null 2>&1; rc=$?
[ $rc -eq 1 ] || fail "reclamar con en-curso del kit: exit $rc"
[ "$(flow_issue 7 '.comments | length')" = 1 ] || fail "reclamar con en-curso del kit: publicó comentario"

# --- reclamar: earlier claim released -> wins
use_flow_gh
flow_add_issue 7 "tarea"
flow_add_comment 7 '<!-- kit-reclamado: otro -->'
flow_add_comment 7 '<!-- kit-soltado: otro -->'
flow_add_comment 7 '<!-- kit-reclamado: otro2 -->'
flow_add_comment 7 '<!-- kit-soltado: otro2 -->'
out="$(bash "$issue" reclamar "$r" 7 kit-aaaa1111 2>&1)" || fail "reclamar tras soltado: exit $? ($out)"
[ "$(last_line "$out")" = "FIN: reclamado #7" ] || fail "reclamar tras soltado: '$out'"

# --- reclamar: label edit fails -> exit 2 and own kit-soltado published
use_flow_gh; export GH_FAIL_ON="issue edit"
flow_add_issue 7 "tarea"
bash "$issue" reclamar "$r" 7 kit-aaaa1111 >/dev/null 2>&1; rc=$?
unset GH_FAIL_ON
[ $rc -eq 2 ] || fail "reclamar con fallo: exit $rc"
flow_issue 7 '.comments[-1].body' | grep -q '^<!-- kit-soltado: kit-aaaa1111 -->' \
  || fail "reclamar con fallo: sin kit-soltado propio ('$(flow_issue 7 '.comments[-1].body')')"
[ "$(flow_issue 7 '[.labels[].name] | index("en-curso") != null')" = false ] || fail "reclamar con fallo: queda en-curso"

# --- soltar: someone else's claim -> exit 1
use_flow_gh
flow_add_issue 7 "tarea" en-curso
flow_add_comment 7 '<!-- kit-reclamado: otro -->'
err="$(bash "$issue" soltar "$r" 7 kit-aaaa1111 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "soltar ajeno: exit $rc"
case "$err" in *"la reclamación de #7 es de 'otro', no tuya"*) ;; *) fail "soltar ajeno: '$err'";; esac
[ "$(flow_issue 7 '.comments | length')" = 1 ] || fail "soltar ajeno: publicó comentario"

# --- soltar: own claim -> marker before label removal
use_flow_gh
flow_add_issue 7 "tarea" en-curso
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
flow_add_issue 7 "tarea" en-curso
flow_add_comment 7 '<!-- kit-reclamado: kit-aaaa1111 -->'
out="$(bash "$issue" decision "$r" 7 kit-aaaa1111 "$qfile" 2>&1)" || fail "decision: exit $? ($out)"
[ "$(last_line "$out")" = "FIN: necesita-respuesta #7" ] || fail "decision: '$out'"
flow_issue 7 '.comments[].body' | grep -q '^<!-- kit-decision -->' || fail "decision: sin marcador"
flow_issue 7 '.comments[].body' | grep -q '¿Rojo o azul?' || fail "decision: sin pregunta"
[ "$(flow_issue 7 '[.labels[].name] | index("necesita-respuesta") != null')" = true ] || fail "decision: sin etiqueta"
[ "$(flow_issue 7 '[.labels[].name] | index("necesita-decision") != null')" = false ] || fail "decision: pone la etiqueta v2"
[ "$(flow_issue 7 '[.labels[].name] | index("en-curso") != null')" = false ] || fail "decision: queda en-curso"
[ "$(flow_issue 7 '.assignees | length')" = 1 ] || fail "decision: sin asignado"
grep -q -- '--add-assignee @me' "$GH_LOG" || fail "decision: no asigna @me"
flow_issue 7 '.comments[-1].body' | grep -q '^<!-- kit-soltado: kit-aaaa1111 -->' || fail "decision: no suelta"
flow_issue 7 '.comments[-1].body' | grep -q 'Motivo: necesita respuesta de Dru' || fail "decision: motivo"

# --- bloquear
use_flow_gh
flow_add_issue 7 "tarea" en-curso
flow_add_comment 7 '<!-- kit-reclamado: kit-aaaa1111 -->'
out="$(bash "$issue" bloquear "$r" 7 kit-aaaa1111 "$qfile" 2>&1)" || fail "bloquear: exit $? ($out)"
[ "$(last_line "$out")" = "FIN: bloqueado #7" ] || fail "bloquear: '$out'"
flow_issue 7 '.comments[].body' | grep -q '^<!-- kit-bloqueado -->' || fail "bloquear: sin marcador"
[ "$(flow_issue 7 '[.labels[].name] | index("bloqueado") != null')" = true ] || fail "bloquear: sin etiqueta"
[ "$(flow_issue 7 '[.labels[].name] | index("en-curso") != null')" = false ] || fail "bloquear: queda en-curso"

# --- avisos tras decision/bloquear
seed7() { use_flow_gh; flow_add_issue 7 "tarea: rojo" en-curso; flow_add_comment 7 '<!-- kit-reclamado: kit-aaaa1111 -->'; }
set_global '{"notify":"none"}'
seed7; : > "$CURL_LOG"
out="$(bash "$issue" decision "$r" 7 kit-aaaa1111 "$qfile" 2>&1)" || fail "aviso none: exit $? ($out)"
[ "$(last_line "$out")" = "FIN: necesita-respuesta #7" ] || fail "aviso none: '$out'"
[ -s "$CURL_LOG" ] && fail "aviso none: llamó a curl"
set_global '{"notify":"ntfy"}'
seed7; : > "$CURL_LOG"
out="$(bash "$issue" decision "$r" 7 kit-aaaa1111 "$qfile" 2>/dev/null)" || fail "aviso ntfy: exit $?"
[ "$(last_line "$out")" = "FIN: necesita-respuesta #7" ] || fail "aviso ntfy: '$out'"
grep -qx "Title: demo: necesita respuesta" "$CURL_LOG" || fail "aviso ntfy: título ($(cat "$CURL_LOG"))"
grep -qx "#7 tarea: rojo" "$CURL_LOG" || fail "aviso ntfy: mensaje"
grep -qx "Click: https://github.com/dru/demo/issues/7" "$CURL_LOG" || fail "aviso ntfy: url"
seed7; : > "$CURL_LOG"
out="$(bash "$issue" bloquear "$r" 7 kit-aaaa1111 "$qfile" 2>/dev/null)" || fail "aviso bloquear: exit $?"
grep -qx "Title: demo: bloqueado" "$CURL_LOG" || fail "aviso bloquear: título"
seed7
err="$(CURL_FAIL=1 bash "$issue" decision "$r" 7 kit-aaaa1111 "$qfile" 2>&1 >"$HOME/out")"; rc=$?
[ $rc -eq 0 ] || fail "aviso fallido: exit $rc"
case "$err" in *"aviso: no se pudo avisar (error: no se pudo enviar el aviso por ntfy)"*) ;; *) fail "aviso fallido: stderr '$err'";; esac
[ "$(sed -n '$p' "$HOME/out")" = "FIN: necesita-respuesta #7" ] || fail "aviso fallido: FIN '$(cat "$HOME/out")'"
# tema nuevo y envío fallido: la línea del tema no se pierde
seed7
out="$(HOME="$(mktemp -d)" CURL_FAIL=1 KIT_NTFY_TOPIC= bash "$issue" decision "$r" 7 kit-aaaa1111 "$qfile" 2>/dev/null)"; rc=$?
[ $rc -eq 0 ] || fail "tema nuevo con fallo: exit $rc"
printf '%s\n' "$out" | grep -q '^tema ntfy nuevo: agents-kit-' || fail "tema nuevo con fallo: se perdió la línea ($out)"
[ "$(last_line "$out")" = "FIN: necesita-respuesta #7" ] || fail "tema nuevo con fallo: FIN '$out'"
set_global '{"notify":"claude-push"}'
seed7
out="$(bash "$issue" bloquear "$r" 7 kit-aaaa1111 "$qfile" 2>/dev/null)" || fail "aviso push: exit $?"
[ "$out" = "$(printf 'AVISO-CLAUDE: demo: bloqueado: #7 tarea: rojo https://github.com/dru/demo/issues/7\nFIN: bloqueado #7')" ] \
  || fail "aviso push: '$out'"
rm -f "$KIT_CONFIG"

# --- crear
use_flow_gh
flow_add_issue 3 "Arreglar Login" prio:media
bfile="$(mktemp)"; echo "cuerpo" > "$bfile"
err="$(bash "$issue" crear "$r" "arreglar login" "$bfile" --prio alta 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "crear duplicado: exit $rc"
case "$err" in *"ya existe #3 con ese título"*) ;; *) fail "crear duplicado: '$err'";; esac
out="$(bash "$issue" crear "$r" "Nuevo" "$bfile" --prio alta 2>&1)" || fail "crear: exit $? ($out)"
[ "$out" = "$(printf 'https://github.com/dru/demo/issues/4\nFIN: https://github.com/dru/demo/issues/4')" ] || fail "crear: '$out'"
[ "$(flow_issue 4 '[.labels[].name] | join(",")')" = prio:alta ] || fail "crear: etiquetas '$(flow_issue 4 '[.labels[].name] | join(",")')'"
[ "$(flow_issue 4 '.body')" = cuerpo ] || fail "crear: cuerpo"
out="$(bash "$issue" crear "$r" "Propuesto" "$bfile" --etiqueta audio --prio baja --propuesta --etiqueta "editor panel" 2>&1)" \
  || fail "crear propuesta: exit $? ($out)"
[ "$(flow_issue 5 '[.labels[].name] | sort | join(",")')" = "audio,editor panel,prio:baja,propuesta" ] \
  || fail "crear propuesta: etiquetas '$(flow_issue 5 '[.labels[].name] | sort | join(",")')'"
for bad in "" "--prio urgente" "--prio" "--prio alta --etiqueta" "--prio alta --etiqueta a,b" "--prio alta --etiqueta listo" \
           "--prio alta --etiqueta en-curso" "--prio alta --etiqueta prio:alta" "--prio alta --etiqueta propuesta" \
           "--prio alta --etiqueta registro" "--prio alta --otra" "listo" "propuesta" "--prio alta extra"; do
  : > "$GH_LOG"
  bash "$issue" crear "$r" "Otro" "$bfile" $bad >/dev/null 2>&1; rc=$?
  [ $rc -eq 1 ] || fail "crear '$bad': exit $rc (esperado 1)"
  grep -q '^issue create' "$GH_LOG" && fail "crear '$bad': creó el issue"
done
err="$(bash "$issue" crear "$r" "Otro" "$bfile" listo 2>&1 >/dev/null)"
case "$err" in *"--prio"*) ;; *) fail "crear v2 sin --prio: mensaje '$err'";; esac

# --- no marker: every subcommand refuses
nr="$(mk_repo)"; git -C "$nr" remote add origin https://github.com/dru/demo.git
use_flow_gh
for args in "siguiente" "reclamar 7 kit-a" "soltar 7 kit-a" "decision 7 kit-a $qfile" \
            "bloquear 7 kit-a $qfile" "crear x $qfile --prio alta"; do
  set -- $args
  sub="$1"; shift
  err="$(bash "$issue" "$sub" "$nr" "$@" 2>&1 >/dev/null)"; rc=$?
  [ $rc -eq 1 ] || fail "sin marcador ($sub): exit $rc"
  [ "$err" = "kit no activado: ejecuta kit-on" ] || fail "sin marcador ($sub): '$err'"
done
[ -s "$GH_LOG" ] && fail "sin marcador: se llamó a gh"

echo "OK test_issue"
