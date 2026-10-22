#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
N="$REPO_ROOT/scripts/kit-notify.sh"

export PATH="$TESTS_DIR/stubs/notify:$PATH"
export HOME="$(mktemp -d)"
export CURL_LOG="$(mktemp)"
unset CURL_FAIL KIT_NTFY_SERVER CLAUDE_CODE_REMOTE

mk() { # mk <json>: repo with marker
  local r; r="$(mk_repo)"; echo "$1" > "$r/.agents-kit.json"; echo "$r"
}

# sin marcador
r="$(mk_repo)"
out="$(bash "$N" "$r" T M 2>&1)"; rc=$?
[ $rc -eq 1 ] || fail "sin marcador rc=$rc"
grep -q "kit no activado" <<<"$out" || fail "sin marcador msg"

# none
r="$(mk '{"notify":"none"}')"; : > "$CURL_LOG"
out="$(bash "$N" "$r" T M)"; rc=$?
[ $rc -eq 0 ] || fail "none rc"
[ "$(tail -n1 <<<"$out")" = "FIN: sin-aviso" ] || fail "none fin: $out"
[ ! -s "$CURL_LOG" ] || fail "none llamó a curl"

# claude-push
r="$(mk '{"notify":"claude-push"}')"
out="$(bash "$N" "$r" T M https://x)"; rc=$?
[ $rc -eq 0 ] || fail "push rc"
grep -qx "AVISO-CLAUDE: T: M https://x" <<<"$out" || fail "push línea: $out"
[ "$(tail -n1 <<<"$out")" = "FIN: claude-push" ] || fail "push fin"

# ntfy sin tema
r="$(mk '{"notify":"ntfy"}')"; : > "$CURL_LOG"
out="$(bash "$N" "$r" T M https://x)"; rc=$?
[ $rc -eq 0 ] || fail "ntfy rc=$rc $out"
f="$HOME/.agents-kit/ntfy-topic"
[ -f "$f" ] || fail "no creó tema"
[ "$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")" = 600 ] || fail "modo tema"
topic="$(cat "$f")"
[[ $topic =~ ^agents-kit-[0-9a-f]{24}$ ]] || fail "formato tema: $topic"
grep -q "^tema ntfy nuevo: $topic" <<<"$out" || fail "sin línea de tema nuevo"
[ "$(tail -n1 <<<"$out")" = "FIN: ntfy" ] || fail "ntfy fin"
grep -qx "Title: T" "$CURL_LOG" || fail "Title"
grep -qx "Click: https://x" "$CURL_LOG" || fail "Click"
grep -qx "M" "$CURL_LOG" || fail "mensaje"
grep -qx -- "--data-raw" "$CURL_LOG" || fail "--data-raw (un mensaje con @ no debe leer ficheros)"
grep -qx "https://ntfy.sh/$topic" "$CURL_LOG" || fail "URL"
# segunda llamada
: > "$CURL_LOG"; out="$(bash "$N" "$r" T M)"
grep -q "tema ntfy nuevo" <<<"$out" && fail "repite tema nuevo"
grep -q "^Click:" "$CURL_LOG" && fail "Click sin url"
[ "$(cat "$f")" = "$topic" ] || fail "tema cambió"

# tema por variable de entorno; el marcador del repo no puede desviarlo
r="$(mk '{"notify":"ntfy","ntfyTopic":"del-repo"}')"; : > "$CURL_LOG"
KIT_NTFY_TOPIC=mi-tema bash "$N" "$r" T M >/dev/null || fail "mi-tema rc"
grep -qx "https://ntfy.sh/mi-tema" "$CURL_LOG" || fail "URL mi-tema"
: > "$CURL_LOG"; bash "$N" "$r" T M >/dev/null || fail "repo rc"
grep -q "del-repo" "$CURL_LOG" && fail "el marcador desvió el tema"

# tema inválido
KIT_NTFY_TOPIC=a/b bash "$N" "$r" T M >/dev/null 2>&1; [ $? -eq 2 ] || fail "tema inválido rc"

# url con salto de línea no inyecta cabeceras
: > "$CURL_LOG"; bash "$N" "$r" T M "$(printf 'https://x\nX-Evil: 1')" >/dev/null || fail "url rc"
grep -q "^X-Evil" "$CURL_LOG" && fail "cabecera inyectada"

# fallo de curl
r="$(mk '{"notify":"ntfy"}')"
out="$(CURL_FAIL=1 bash "$N" "$r" T M 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "curl falla rc=$rc"
grep -q "error: no se pudo enviar el aviso por ntfy" <<<"$out" || fail "curl falla msg"

# saltos de línea
: > "$CURL_LOG"
bash "$N" "$r" $'ti\ntulo' $'uno\ndos' >/dev/null || fail "nl rc"
grep -qx "uno dos" "$CURL_LOG" || fail "mensaje nl"
grep -qx "Title: ti tulo" "$CURL_LOG" || fail "título nl"

# canal desconocido
r="$(mk '{"notify":"sms"}')"
out="$(bash "$N" "$r" T M 2>&1)"; rc=$?
[ $rc -eq 1 ] || fail "sms rc"
grep -q "canal de aviso desconocido: sms" <<<"$out" || fail "sms msg"

# HOME no escribible
r="$(mk '{"notify":"ntfy"}')"
out="$(HOME=/dev/null/x bash "$N" "$r" T M 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "home rc=$rc"

# en la nube sin KIT_NTFY_TOPIC ni tema guardado: no inventa un tema
r="$(mk '{"notify":"ntfy"}')"; h="$(mktemp -d)"; : > "$CURL_LOG"
out="$(HOME="$h" CLAUDE_CODE_REMOTE=true bash "$N" "$r" T M 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "nube sin tema rc=$rc $out"
grep -qx "error: en la nube define KIT_NTFY_TOPIC (el tema de tu app ntfy)" <<<"$out" || fail "nube sin tema msg: $out"
[ -e "$h/.agents-kit/ntfy-topic" ] && fail "nube sin tema: creó un tema"
[ -s "$CURL_LOG" ] && fail "nube sin tema: llamó a curl"
# en la nube con KIT_NTFY_TOPIC o con tema guardado sí envía
HOME="$h" CLAUDE_CODE_REMOTE=true KIT_NTFY_TOPIC=nube-tema bash "$N" "$r" T M >/dev/null || fail "nube con variable"
grep -qx "https://ntfy.sh/nube-tema" "$CURL_LOG" || fail "nube con variable: URL"
mkdir -p "$h/.agents-kit"; echo guardado > "$h/.agents-kit/ntfy-topic"; : > "$CURL_LOG"
HOME="$h" CLAUDE_CODE_REMOTE=true bash "$N" "$r" T M >/dev/null || fail "nube con tema guardado"
grep -qx "https://ntfy.sh/guardado" "$CURL_LOG" || fail "nube con tema guardado: URL"

# kit_transport
source "$REPO_ROOT/scripts/lib/transport.sh"
[ "$(CLAUDE_CODE_REMOTE=true kit_transport)" = nube ] || fail "transporte nube"
[ "$(kit_transport)" = local ] || fail "transporte local"

# plantilla
[ "$(jq -r .notify "$REPO_ROOT/templates/agents-kit.json")" = ntfy ] || fail "plantilla"
echo "OK test_notify"
