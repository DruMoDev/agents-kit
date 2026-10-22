#!/usr/bin/env bash
# Tests for scripts/kit-review-all.sh and lib/review-seats.sh (kit-review.sh replaced by a stub through KIT_REVIEW_BIN;
# the PATH holds fake reviewer CLIs only, so availability never depends on this machine).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
all="$REPO_ROOT/scripts/kit-review-all.sh"
use_flow_gh
unset CLAUDECODE CODEX_THREAD_ID OPENCODE GH_USER
stub="$(mktemp -d)/review"
cat > "$stub" <<'EOF'
#!/usr/bin/env bash
# args: wt pr puesto familia cli modelo foco ronda N. STUB_FAIL: "<cli>/<modelo>=<motivo> ..." fails those with exit 2.
echo "args: $*"
echo "$5/$6" >> "$STUB_CALLS"
for f in ${STUB_FAIL:-}; do
  if [ "${f%%=*}" = "$5/$6" ]; then
    echo "el revisor no entregó" >&2
    echo "sin confirmar (${f#*=}): detalle de $5/$6" >&2
    exit 2
  fi
done
echo "Informe del puesto $3"
echo "FIN: 0 hallazgos"
EOF
chmod +x "$stub"
export KIT_REVIEW_BIN="$stub" STUB_CALLS="$(mktemp)"
fake="$(mktemp -d)"; sysbin="$(mktemp -d)"
for c in jq git; do ln -s "$(command -v "$c")" "$sysbin/$c"; done
export PATH="$fake:$TESTS_DIR/stubs/flow:$sysbin:/usr/bin:/bin"
clis() { # <cli>...: the reviewer CLIs "installed"
  rm -f "$fake"/*
  for c in "$@"; do printf '#!/bin/sh\nexit 0\n' > "$fake/$c"; chmod +x "$fake/$c"; done
}
clis claude opencode codex

r="$(mk_repo)"
(cd "$r" && git remote add origin https://github.com/dru/demo.git) || fail "setup remoto"
echo '{}' > "$r/.agents-kit.json"
st() { local t; t="$(mktemp)"; jq "$1" "$GH_STATE/state.json" > "$t" && mv "$t" "$GH_STATE/state.json" || fail "st $1"; }
st '.prs = [{number: 7, headRefName: "issue-3-foo", state: "OPEN", isDraft: false, url: "u", comments: []}]'
set_global '{"proveedores": {"claude": {"cli": "claude", "modelos": {"profundo": "opus", "rapido": "sonnet"}},
                             "gpt": {"cli": "opencode", "modelos": {"profundo": "openai/x", "rapido": "openai/y"}}}}'
run() { : > "$STUB_CALLS"; out="$(bash "$all" "$r" 7 2 3 "$@" 2>&1)"; rc=$?; }
has() { grep -qxF "$1" <<<"$out" || fail "${2:-salida} sin '$1': $out"; }
ncom() { jq '.prs[0].comments | length' "$GH_STATE/state.json"; }

# seats by family (plugin seats: otra, otra, misma); the implementer comes from the environment
out="$(CLAUDECODE=1 zsh -c '"$1" "$2" 7 2 3' _ "$all" "$r" 2>&1)"; rc=$?
[ $rc -eq 0 ] || fail "exit $rc ($out)"
has "puesto 1 (gpt/openai/x): ok"; has "puesto 2 (gpt/openai/x): ok"; has "puesto 3 (claude/sonnet): ok"
[ "$(printf '%s\n' "$out" | sed -n '$p')" = "FIN: 3 puestos, 0 sin confirmar" ] || fail "FIN: $out"
d="$(sed -n 's/^salidas: //p' <<<"$out")"
grep -qx "args: $r 7 1 gpt opencode openai/x corrección, casos límite y tests 2 3" "$d/rev-1.out" || fail "args 1: $(cat "$d/rev-1.out")"
grep -qx "args: $r 7 3 claude claude sonnet simplicidad, reutilización y scope 2 3" "$d/rev-3.out" || fail "args 3: $(cat "$d/rev-3.out")"
[ "$(cut -f1-4,6 "$d/puestos.tsv" | tr '\t\n' ' |')" = "1 gpt opencode openai/x ok|2 gpt opencode openai/x ok|3 claude claude sonnet ok|" ] \
  || fail "puestos.tsv: $(cat "$d/puestos.tsv")"
[ "$(ncom)" = 0 ] || fail "publicó con todo confirmado"
# Codex session -> gpt implements: the other family is claude
out="$(CODEX_THREAD_ID=x CLAUDECODE=1 bash "$all" "$r" 7 2 3 2>&1)" || fail "codex: $out"
has "puesto 1 (claude/opus): ok"; has "puesto 3 (gpt/openai/y): ok"
# explicit --implementador wins over the environment
out="$(CLAUDECODE=1 bash "$all" "$r" 7 2 3 --implementador gpt 2>&1)" || fail "explícito: $out"
has "puesto 2 (claude/opus): ok"; has "puesto 3 (gpt/openai/y): ok"
# unknown implementer: OpenCode (any model) or no harness at all -> 2 asking for --implementador
for e in "OPENCODE=1 CLAUDECODE=1" "X=1"; do
  err="$(env $e bash "$all" "$r" 7 2 3 2>&1)"; rc=$?
  [ $rc -eq 2 ] || fail "implementador desconocido ($e): exit $rc"
  case "$err" in *"--implementador <familia>"*) ;; *) fail "implementador desconocido msg: $err";; esac
done
CLAUDECODE=1 bash "$all" "$r" 7 2 3 --implementador marciano >/dev/null 2>&1; [ $? -eq 1 ] || fail "familia desconocida debe dar 1"
CLAUDECODE=1 bash "$all" "$r" 7 2 3 --implementador >/dev/null 2>&1; [ $? -eq 1 ] || fail "--implementador sin valor debe dar 1"
CLAUDECODE=1 bash "$all" "$r" 7 2 3 --otra >/dev/null 2>&1; [ $? -eq 1 ] || fail "opción desconocida debe dar 1"
export CLAUDECODE=1

# no other family available (opencode missing): "otra" seats fall to the implementer's family and say so
clis claude codex
run
[ $rc -eq 0 ] || fail "sin opencode: exit $rc ($out)"
has "puesto 1 (claude/opus): ok (misma familia: no hay otra familia disponible)"
has "puesto 3 (claude/sonnet): ok"
grep -q "opencode" "$STUB_CALLS" && fail "lanzó un CLI que no está en el PATH"
clis claude opencode codex

# changing a family's CLI is changing "cli": gpt through codex
set_global '{"proveedores": {"claude": {"cli": "claude", "modelos": {"profundo": "opus", "rapido": "sonnet"}},
                             "gpt": {"cli": "codex", "modelos": {"profundo": "gpt-x", "rapido": "gpt-x"}}}}'
run
has "puesto 1 (gpt/gpt-x): ok"
grep -qx "args: $r 7 1 gpt codex gpt-x corrección, casos límite y tests 2 3" "$(sed -n 's/^salidas: //p' <<<"$out")/rev-1.out" \
  || fail "codex args"
# a family whose CLI is no known adapter never runs; the seat falls back
set_global '{"proveedores": {"claude": {"cli": "claude", "modelos": {"profundo": "opus", "rapido": "sonnet"}},
                             "gpt": {"cli": "rm", "modelos": {"profundo": "x", "rapido": "x"}}}}'
run
has "puesto 1 (claude/opus): ok (misma familia: no hay otra familia disponible)"
grep -q "^rm/" "$STUB_CALLS" && fail "lanzó un adaptador desconocido"
set_global '{"proveedores": {"claude": {"cli": "claude", "modelos": {"profundo": "opus", "rapido": "sonnet"}},
                             "gpt": {"cli": "opencode", "modelos": {"profundo": "openai/x", "rapido": "openai/y"}}}}'

# runtime fallback: login/model failure of the other family -> the implementer's family, with a warning
STUB_FAIL="opencode/openai/x=acceso" run
[ $rc -eq 0 ] || fail "fallback: exit $rc ($out)"
has "puesto 1 (gpt/openai/x): fallback a claude/opus"
has "puesto 1 (claude/opus): ok (misma familia: no hay otra familia disponible)"
grep -q "^aviso: gpt/openai/x (opencode) no respondió.*login" <<<"$out" || fail "sin aviso de login: $out"
[ "$(grep -c '^aviso: gpt/openai/x' <<<"$out")" = 1 ] || fail "aviso repetido: $out"
[ "$(printf '%s\n' "$out" | sed -n '$p')" = "FIN: 3 puestos, 0 sin confirmar" ] || fail "fallback FIN: $out"
grep -q "^args: .* 1 claude claude opus " "$(sed -n 's/^salidas: //p' <<<"$out")/rev-1.out" || fail "rev-1.out no es el último intento"
# a timeout never falls back: the seat stays unconfirmed, posted on the PR so the round is not complete
STUB_FAIL="opencode/openai/x=tiempo" run
[ $rc -eq 0 ] || fail "tiempo: exit $rc ($out)"
has "puesto 1 (gpt/openai/x): sin-confirmar (tiempo: detalle de opencode/openai/x)"
[ "$(grep -c '^claude/opus$' "$STUB_CALLS")" = 0 ] || fail "tiempo: probó otro candidato"
[ "$(printf '%s\n' "$out" | sed -n '$p')" = "FIN: 3 puestos, 2 sin confirmar" ] || fail "tiempo FIN: $out"
[ "$(ncom)" = 2 ] || fail "tiempo: no publicó los puestos sin confirmar"
b="$(jq -r '.prs[0].comments[0].body' "$GH_STATE/state.json")"
case "$b" in "<!-- kit-revision: puesto 1 sin-confirmar ronda 2 -->"*"gpt/openai/x"*"tiempo"*) ;; *) fail "comentario sin confirmar: $b";; esac
grep -q "pr comment 7 --repo dru/demo" "$GH_LOG" || fail "comentario sin --repo"
# every candidate fails -> unconfirmed
st '.prs[0].comments = []'
STUB_FAIL="opencode/openai/x=acceso claude/opus=acceso" run
has "puesto 2 (gpt/openai/x): fallback a claude/opus"
has "puesto 2 (claude/opus): sin-confirmar (acceso: detalle de claude/opus)"
has "puesto 3 (claude/sonnet): ok"
[ "$(ncom)" = 2 ] || fail "acceso total: comentarios $(ncom)"
# a failed post is only a warning (fusionar needs a confirmed review per seat anyway)
st '.prs[0].comments = []'; rm -f "$GH_STATE/.failed"
GH_FAIL_ON="pr comment" STUB_FAIL="opencode/openai/x=salida" run
[ $rc -eq 0 ] || fail "post fallido: exit $rc"
grep -q "^aviso: no se pudo publicar" <<<"$out" || fail "post fallido sin aviso: $out"
# a seat without any available CLI
st '.prs[0].comments = []'
echo '{"revision": {"puestos": [{"foco": "f", "nivel": "rapido", "familia": "misma"}]}}' > "$r/.agents-kit.json"
clis opencode
run
has "puesto 1 (misma): sin-confirmar (ningún CLI de revisión disponible en el PATH para este puesto)"
[ "$(printf '%s\n' "$out" | sed -n '$p')" = "FIN: 1 puestos, 1 sin confirmar" ] || fail "sin candidatos FIN: $out"
[ ! -s "$STUB_CALLS" ] || fail "sin candidatos lanzó algo"
clis claude opencode codex
# misma seat on a family without that level: config error
echo '{"revision": {"puestos": [{"foco": "f", "nivel": "lento", "familia": "misma"}]}}' > "$r/.agents-kit.json"
run; [ $rc -eq 1 ] || fail "nivel desconocido: exit $rc"

# no seats
echo '{"revision": {"puestos": []}}' > "$r/.agents-kit.json"
run
[ $rc -eq 1 ] || fail "sin puestos: exit $rc"
grep -q "sin puestos de revisión" <<<"$out" || fail "sin puestos msg: $out"

# broken marker, no marker, usage
echo '[' > "$r/.agents-kit.json"
bash "$all" "$r" 7 2 3 >/dev/null 2>&1; [ $? -eq 2 ] || fail "marcador roto"
rm "$r/.agents-kit.json"
bash "$all" "$r" 7 2 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin marcador"
bash "$all" "$r" 7 >/dev/null 2>&1; [ $? -eq 1 ] || fail "uso"
echo '{}' > "$r/.agents-kit.json"
bash "$all" "$r" x 2 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "PR inválida"
echo "OK test_review_all"
