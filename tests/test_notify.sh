#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
N="$REPO_ROOT/scripts/kit-notify.sh"

export PATH="$TESTS_DIR/stubs/notify:$PATH"
export HOME="$(mktemp -d)"
export CURL_LOG="$(mktemp)"
unset CURL_FAIL KIT_NTFY_SERVER CLAUDE_CODE_REMOTE

sent() { # sent <jq>: field of the JSON body of the last curl call
  local b; b="$(awk '$0 == "--data-raw" {getline; b = $0} END {print b}' "$CURL_LOG")"
  printf '%s' "$b" | jq -r "$1"
}
mk() { # mk <json>: repo with marker {} and <json> as the global config
  local r; r="$(mk_repo)"; echo '{}' > "$r/.agents-kit.json"; set_global "$1"; echo "$r"
}

# sin marcador
r="$(mk_repo)"
out="$(bash "$N" "$r" accion T M 2>&1)"; rc=$?
[ $rc -eq 1 ] || fail "sin marcador rc=$rc"
grep -q "kit no activado" <<<"$out" || fail "sin marcador msg"

# none
r="$(mk '{"notify":"none"}')"; : > "$CURL_LOG"
out="$(bash "$N" "$r" accion T M)"; rc=$?
[ $rc -eq 0 ] || fail "none rc"
[ "$(tail -n1 <<<"$out")" = "FIN: sin-aviso" ] || fail "none fin: $out"
[ ! -s "$CURL_LOG" ] || fail "none llamó a curl"

# claude-push
r="$(mk '{"notify":"claude-push"}')"
out="$(bash "$N" "$r" accion T M https://x)"; rc=$?
[ $rc -eq 0 ] || fail "push rc"
grep -qx "AVISO-CLAUDE: ✋ T: M https://x" <<<"$out" || fail "push línea: $out"
out="$(bash "$N" "$r" info T $'uno\ndos')"
grep -qx "AVISO-CLAUDE: ✅ T: uno dos" <<<"$out" || fail "push info sin url: $out"
[ "$(tail -n1 <<<"$out")" = "FIN: claude-push" ] || fail "push fin"

# ntfy sin tema
r="$(mk '{"notify":"ntfy"}')"; : > "$CURL_LOG"
out="$(bash "$N" "$r" accion T M https://x)"; rc=$?
[ $rc -eq 0 ] || fail "ntfy rc=$rc $out"
f="$HOME/.agents-kit/ntfy-topic"
[ -f "$f" ] || fail "no creó tema"
[ "$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")" = 600 ] || fail "modo tema"
topic="$(cat "$f")"
[[ $topic =~ ^agents-kit-[0-9a-f]{24}$ ]] || fail "formato tema: $topic"
grep -q "^tema ntfy nuevo: $topic" <<<"$out" || fail "sin línea de tema nuevo"
[ "$(tail -n1 <<<"$out")" = "FIN: ntfy" ] || fail "ntfy fin"
[ "$(sent .title)" = "✋ T" ] || fail "title"
[ "$(sent .click)" = "https://x" ] || fail "click"
[ "$(sent .message)" = "M" ] || fail "mensaje"
[ "$(sent .priority)" = 4 ] || fail "prioridad accion"
[ "$(sent .topic)" = "$topic" ] || fail "topic"
grep -qx -- "--data-raw" "$CURL_LOG" || fail "--data-raw (un mensaje con @ no debe leer ficheros)"
grep -qx "https://ntfy.sh" "$CURL_LOG" || fail "URL"
# segunda llamada
: > "$CURL_LOG"; out="$(bash "$N" "$r" accion T M)"
grep -q "tema ntfy nuevo" <<<"$out" && fail "repite tema nuevo"
[ "$(sent 'has("click")')" = false ] || fail "click sin url"
[ "$(cat "$f")" = "$topic" ] || fail "tema cambió"

# tema por variable de entorno; el marcador del repo no puede desviarlo
r="$(mk '{"notify":"ntfy"}')"; echo '{"ntfyTopic":"del-repo"}' > "$r/.agents-kit.json"; : > "$CURL_LOG"
KIT_NTFY_TOPIC=mi-tema bash "$N" "$r" accion T M >/dev/null || fail "mi-tema rc"
[ "$(sent .topic)" = mi-tema ] || fail "URL mi-tema"
: > "$CURL_LOG"; bash "$N" "$r" accion T M >/dev/null || fail "repo rc"
grep -q "del-repo" "$CURL_LOG" && fail "el marcador desvió el tema"

# tema inválido
KIT_NTFY_TOPIC=a/b bash "$N" "$r" accion T M >/dev/null 2>&1; [ $? -eq 2 ] || fail "tema inválido rc"

# url con salto de línea queda en una línea
: > "$CURL_LOG"; bash "$N" "$r" accion T M "$(printf 'https://x\nX-Evil: 1')" >/dev/null || fail "url rc"
[ "$(sent .click)" = "https://x X-Evil: 1" ] || fail "url nl"

# tipo inválido o ausente
out="$(bash "$N" "$r" urgente T M 2>&1)"; [ $? -eq 1 ] || fail "tipo inválido rc"
grep -q "uso:" <<<"$out" || fail "tipo inválido msg"
bash "$N" "$r" T M >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin tipo rc"

# fallo de curl
r="$(mk '{"notify":"ntfy"}')"
out="$(CURL_FAIL=1 bash "$N" "$r" accion T M 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "curl falla rc=$rc"
grep -q "error: no se pudo enviar el aviso por ntfy" <<<"$out" || fail "curl falla msg"

# saltos de línea
: > "$CURL_LOG"
bash "$N" "$r" info $'ti\ntulo' $'uno\r\ndos' >/dev/null || fail "nl rc"
[ "$(sent .message)" = $'uno\ndos' ] || fail "mensaje nl (ntfy conserva los saltos)"
[ "$(sent .title)" = "✅ ti tulo" ] || fail "título nl"
[ "$(sent .priority)" = 2 ] || fail "prioridad info"
# mensaje largo: recortado
: > "$CURL_LOG"; bash "$N" "$r" info T "$(printf 'x%.0s' $(seq 2000))" >/dev/null || fail "largo rc"
[ "$(sent '.message | length')" = 1500 ] || fail "largo: $(sent '.message | length')"
[ "$(sent '.message | endswith("...")')" = true ] || fail "largo sin ..."

# canal desconocido
r="$(mk '{"notify":"sms"}')"
out="$(bash "$N" "$r" accion T M 2>&1)"; rc=$?
[ $rc -eq 1 ] || fail "sms rc"
grep -q "canal de aviso desconocido: sms" <<<"$out" || fail "sms msg"

# HOME no escribible
r="$(mk '{"notify":"ntfy"}')"
out="$(HOME=/dev/null/x bash "$N" "$r" accion T M 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "home rc=$rc"

# en la nube sin KIT_NTFY_TOPIC ni tema guardado: no inventa un tema
r="$(mk '{"notify":"ntfy"}')"; h="$(mktemp -d)"; : > "$CURL_LOG"
out="$(HOME="$h" CLAUDE_CODE_REMOTE=true bash "$N" "$r" accion T M 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "nube sin tema rc=$rc $out"
grep -qx "error: en la nube define KIT_NTFY_TOPIC (el tema de tu app ntfy)" <<<"$out" || fail "nube sin tema msg: $out"
[ -e "$h/.agents-kit/ntfy-topic" ] && fail "nube sin tema: creó un tema"
[ -s "$CURL_LOG" ] && fail "nube sin tema: llamó a curl"
# en la nube con KIT_NTFY_TOPIC o con tema guardado sí envía
HOME="$h" CLAUDE_CODE_REMOTE=true KIT_NTFY_TOPIC=nube-tema bash "$N" "$r" accion T M >/dev/null || fail "nube con variable"
[ "$(sent .topic)" = nube-tema ] || fail "nube con variable: URL"
mkdir -p "$h/.agents-kit"; echo guardado > "$h/.agents-kit/ntfy-topic"; : > "$CURL_LOG"
HOME="$h" CLAUDE_CODE_REMOTE=true bash "$N" "$r" accion T M >/dev/null || fail "nube con tema guardado"
[ "$(sent .topic)" = guardado ] || fail "nube con tema guardado: URL"

# kit_transport
source "$REPO_ROOT/scripts/lib/transport.sh"
[ "$(CLAUDE_CODE_REMOTE=true kit_transport)" = nube ] || fail "transporte nube"
[ "$(kit_transport)" = local ] || fail "transporte local"

# el canal del repo se ignora con aviso: manda el global
r="$(mk '{"notify":"none"}')"; echo '{"notify":"claude-push"}' > "$r/.agents-kit.json"
out="$(bash "$N" "$r" accion T M 2>&1)"; rc=$?
[ $rc -eq 0 ] || fail "notify del repo rc=$rc"
[ "$(tail -n1 <<<"$out")" = "FIN: sin-aviso" ] || fail "notify del repo no se ignora: $out"
grep -q "aviso: .agents-kit.json: 'notify'" <<<"$out" || fail "notify del repo sin aviso: $out"
# global ausente: el canal de la plantilla
r="$(mk_repo)"; echo '{}' > "$r/.agents-kit.json"; rm -f "$KIT_CONFIG"; : > "$CURL_LOG"
KIT_NTFY_TOPIC=t bash "$N" "$r" accion T M >/dev/null || fail "plantilla rc"
[ "$(sent .topic)" = t ] || fail "plantilla: no usó ntfy"
[ "$(jq -r .notify "$REPO_ROOT/templates/config.json")" = ntfy ] || fail "plantilla"
echo "OK test_notify"
