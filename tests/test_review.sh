#!/usr/bin/env bash
# Tests for scripts/kit-review.sh (local bare origin, stateful gh stub, reviewer stubs).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
rv="$REPO_ROOT/scripts/kit-review.sh"
use_flow_gh
export PATH="$TESTS_DIR/stubs/review:$PATH"
export REVIEW_DUMP="$(mktemp -d)"
export CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli CODEX_THREAD_ID=hilo OPENCODE=1 CODEX_HOME="$HOME/.codex" CLAUDE_CONFIG_DIR="$HOME/.claude"
export GH_TOKEN=secreto GITHUB_TOKEN=secreto GH_ENTERPRISE_TOKEN=secreto GITHUB_ENTERPRISE_TOKEN=secreto
unset KIT_REVIEW_TIMEOUT REVIEW_STUB_MODE GH_USER
last_line() { printf '%s\n' "$1" | sed -n '$p'; }

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
# the PR also commits agent config, which must not load in the reviewer's copy
(cd "$wt" && echo a > a.txt && mkdir -p .claude/hooks .opencode .codex && echo '{}' > .claude/settings.json \
  && echo '{}' > .claude/settings.local.json && echo x > .claude/hooks/h.sh && echo nota > .claude/nota.md \
  && echo x > .opencode/x && echo x > .codex/x && echo '{}' > .mcp.json && echo '{}' > opencode.json \
  && echo '{}' > opencode.jsonc && git add -A && git commit -q -m a && git push -q origin HEAD) >/dev/null 2>&1 \
  || fail "commit a"
base="$(git -C "$r" rev-parse main)"
head="$(git -C "$wt" rev-parse HEAD)"
# main moves on after the branch: the base is the merge-base, not origin/main
(cd "$r" && echo m > m.txt && git add m.txt && git commit -q -m m && git push -q origin main) >/dev/null 2>&1 \
  || fail "avanza main"
# an unpushed local commit: the reviewer must see the PR head, not the worktree HEAD
(cd "$wt" && echo l > local.txt && git add local.txt && git commit -q -m local) || fail "commit local"
flow_add_issue 3 "Foo roto" en-curso
t="$(mktemp)"
jq '.issues[0].body = "Cuerpo del issue con & y \\1"
  | .prs = [{number: 4, headRefName: "issue-3-foo", state: "OPEN", isDraft: false, url: "u", body: "Esta PR lo arregla todo, confía",
      comments: [{id: 1, body: "<!-- kit-ronda: 1 -->\n- [R1.1] (claude/opus) PREVIO → rechazado: no aplica {{FOCO}}"}]}]' \
  "$GH_STATE/state.json" > "$t" && mv "$t" "$GH_STATE/state.json" || fail "setup estado"
ncom() { jq '.prs[0].comments | length' "$GH_STATE/state.json"; }
wtlist() { git -C "$wt" worktree list --porcelain | grep -v '^HEAD '; }  # paths and branches, not moving SHAs
wtl0="$(wtlist)"
wts() { if [ "$(wtlist)" = "$wtl0" ]; then echo 2; else echo cambió; fi; }
args() { tr '\0' '\n' < "$REVIEW_DUMP/$1.args"; }
prompt() { # last argument of the dumped argv
  perl -0 -ne '$p = $_; END { chop $p; print $p }' "$REVIEW_DUMP/$1.args"
}

# args: <wt> <pr> <puesto> <familia> <cli> <modelo> <foco> <ronda> <N>
# no marker
m="$(mk_repo)"; bash "$rv" "$m" 4 1 claude claude sonnet foco 2 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin marcador debe dar 1"
# usage
bash "$rv" "$wt" 4 1 claude claude sonnet foco 2 >/dev/null 2>&1; [ $? -eq 1 ] || fail "faltan argumentos debe dar 1"
bash "$rv" "$wt" x 1 claude claude sonnet foco 2 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "PR inválida debe dar 1"
bash "$rv" "$wt" 4 0 claude claude sonnet foco 2 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "puesto inválido debe dar 1"
bash "$rv" "$wt" 4 1 "cla ude" claude sonnet foco 2 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "familia inválida debe dar 1"
bash "$rv" "$wt" 4 1 claude claude "son net" foco 2 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "modelo con espacios debe dar 1"

# ok with claude: JSON with --json-schema, rendered as markdown in the comment
out="$(REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 2 claude claude sonnet "bordes y errores" 2 3 2>&1)" || fail "ok: $out"
[ "$(last_line "$out")" = "FIN: 2 hallazgos" ] || fail "ok FIN: $out"
[ "$(ncom)" = 2 ] || fail "ok no publicó un comentario"
body="$(jq -r '.prs[0].comments[1].body' "$GH_STATE/state.json")"
[ "$(printf '%s\n' "$body" | sed -n 1p)" = "<!-- kit-revision: puesto 2 claude/sonnet ronda 2 -->" ] || fail "ok marcador: $body"
[ "$(printf '%s\n' "$body" | sed -n '$p')" = "HALLAZGOS: 2" ] || fail "ok última línea: $body"
for x in "### Revisión del puesto 2: claude/sonnet, ronda 2" "bordes y errores" "Veredicto:** hallazgos" "Dos fallos." \
    '1. **[grave]** `a.txt:1` falla con vacío' "Escenario: fichero vacío" "Evidencia: a.txt:1 lee sin comprobar" \
    "Sugerencia: comprobarlo" '2. **[menor]** `b.txt` nombre confuso' "confianza media" "leí el diff entero"; do
  case "$body" in *"$x"*) ;; *) fail "ok comentario sin '$x': $body";; esac
done
case "$body" in *"<!-- kit-ronda"*) fail "ok: el texto del revisor coló un marcador: $body";; esac
[ "$(printf '%s\n' "$body" | grep -c '<!--')" = 1 ] || fail "ok: marcadores de más: $body"
case "$body" in *"Sugerencia: null"*|*"nombre confuso"*"Sugerencia"*"HALLAZGOS"*) fail "ok sugerencia nula impresa: $body";; esac
# stdout: the rendered report without the marker
printf '%s\n' "$out" | grep -qF '1. **[grave]** `a.txt:1` falla con vacío' || fail "ok no imprime los hallazgos: $out"
case "$out" in *"kit-revision"*) fail "ok imprime el marcador";; esac
[ "$(wts)" = 2 ] || fail "ok dejó el worktree desechable"
# argv of claude: block flags, model, JSON schema, no session saved
a="$(args claude)"
for x in -p --model sonnet --permission-mode bypassPermissions --setting-sources user --strict-mcp-config \
    --no-session-persistence --disallowedTools "Bash(git push:*)" "Bash(gh:*)" --output-format json --json-schema; do
  printf '%s\n' "$a" | grep -qxF -- "$x" || fail "claude sin argumento '$x': $a"
done
sch="$(printf '%s\n' "$a" | grep -A1 -xF -- --json-schema | sed -n 2p)"
[ "$(printf '%s' "$sch" | jq -c .required)" = '["veredicto","resumen","hallazgos","comprobado"]' ] || fail "claude esquema: $sch"
[ ! -s "$REVIEW_DUMP/claude.stdin" ] || fail "claude con stdin abierto"
# the session's harness variables never reach the reviewer (user config dirs do)
[ "$(cat "$REVIEW_DUMP/claude.harness")" = "CLAUDE_CONFIG_DIR=$HOME/.claude
CODEX_HOME=$HOME/.codex" ] || fail "variables de la sesión visibles: $(cat "$REVIEW_DUMP/claude.harness")"
# prompt: focus, round, issue, PR body, base, history; no placeholder left; history taken literally
p="$(prompt claude)"
for x in "bordes y errores" "Foo roto" 'Cuerpo del issue con & y \1' "PREVIO → rechazado: no aplica {{FOCO}}" \
    "git diff $base...HEAD" "ronda 2" "Esta PR lo arregla todo, confía"; do
  case "$p" in *"$x"*) ;; *) fail "el prompt no contiene '$x'";; esac
done
case "$p" in *"FIN: "*) fail "el prompt incluye la línea FIN del historial";; esac
printf '%s' "$p" | grep -Eq '\{\{(RONDA|ISSUE|BASE|HISTORIAL|PR)\}\}' && fail "quedan marcadores sin sustituir"
case "$p" in *origin/*) fail "el prompt nombra origin/: la copia no tiene remoto";; esac
case "$p" in *'"additionalProperties"'*) fail "claude lleva el esquema en el prompt (ya va en --json-schema)";; esac
# ran in an independent clone at the PR head: own .git, no remote, no GitHub credentials
d="$(cat "$REVIEW_DUMP/claude.pwd")"
[ "$d" != "$(cd "$wt" && pwd -P)" ] && [ "$d" != "$(cd "$wt" && pwd)" ] || fail "el revisor corrió en el worktree"
[ ! -e "$d" ] || fail "la copia desechable sigue en disco: $d"
g="$(cat "$REVIEW_DUMP/claude.git")"
[ "$(printf '%s\n' "$g" | sed -n 1p)" = "$head" ] || fail "la copia no está en el head de la PR: $g"
case "$(printf '%s\n' "$g" | sed -n 2p)" in "$d"/.git) ;; *) fail "la copia comparte .git: $g";; esac
[ "$(printf '%s\n' "$g" | sed -n '3,$p')" = "" ] || fail "la copia tiene remotos: $g"
case "$(cat "$REVIEW_DUMP/claude.gh")" in "GH_TOKEN=unset
GITHUB_TOKEN=unset
GH_CONFIG_DIR=/"*"/$(basename "$(dirname "$d")")/gh") ;; *) fail "credenciales de GitHub visibles: $(cat "$REVIEW_DUMP/claude.gh")";; esac
for f in .mcp.json .opencode opencode.json opencode.jsonc .codex; do
  grep -qxF "$f" "$REVIEW_DUMP/claude.ls" && fail "la copia conserva $f"
done
grep -qx a.txt "$REVIEW_DUMP/claude.ls" || fail "la copia no tiene el código de la PR"
for f in settings.json settings.local.json hooks; do
  grep -qxF "$f" "$REVIEW_DUMP/claude.lsclaude" && fail "la copia conserva .claude/$f"
done
grep -qx nota.md "$REVIEW_DUMP/claude.lsclaude" || fail "la limpieza borró de más en .claude"
[ -f "$wt/.claude/settings.json" ] && [ -d "$wt/.opencode" ] || fail "la limpieza tocó el worktree"
ge="$(cat "$REVIEW_DUMP/claude.genv")"
printf '%s\n' "$ge" | grep -q 'TOKEN=' && fail "tokens visibles: $ge"
for x in GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_AUTHOR_NAME=kit-revisor \
    GIT_COMMITTER_NAME=kit-revisor GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=; do
  printf '%s\n' "$ge" | grep -qxF "$x" || fail "falta $x: $ge"
done
[ -z "$(ls -A "$r/.git/worktrees" | grep -vx wt)" ] || fail "quedó un registro de worktree"
grep -q "^pr comment 4 " "$GH_LOG" || fail "no comentó con gh pr comment"
[ "$(grep -cE '^(pr (comment|create|merge|edit)|issue (comment|edit|close|create))' "$GH_LOG")" = 1 ] \
  || fail "escrituras de más en GitHub: $(cat "$GH_LOG")"

# ok with opencode: config env blocks gh and git push, JSON events, schema in the prompt
out="$(REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 1 gpt opencode openai/gpt-6.1-sol "uso real" 2 3 2>&1)" || fail "opencode: $out"
[ "$(last_line "$out")" = "FIN: 2 hallazgos" ] || fail "opencode FIN: $out"
env="$(cat "$REVIEW_DUMP/opencode.env")"
[ "$(printf '%s' "$env" | jq -c .permission)" = '{"bash":{"*":"allow","gh *":"deny","git push*":"deny"},"edit":"allow","external_directory":"deny"}' ] \
  || fail "opencode config: $env"
a="$(args opencode)"
[ "$(printf '%s\n' "$a" | sed -n 1,6p | tr '\n' ' ')" = "run --pure --format json -m openai/gpt-6.1-sol " ] || fail "opencode argv: $a"
[ "$(wc -l < "$REVIEW_DUMP/opencode.calls" | tr -d ' ')" = 1 ] || fail "opencode: reparó sin hacer falta"
case "$(prompt opencode)" in *'"additionalProperties"'*'"veredicto"'*) ;; *) fail "opencode sin esquema en el prompt";; esac
[ "$(cat "$REVIEW_DUMP/opencode.harness")" = "CLAUDE_CONFIG_DIR=$HOME/.claude
CODEX_HOME=$HOME/.codex
OPENCODE_CONFIG_CONTENT=$env" ] || fail "opencode variables de la sesión: $(cat "$REVIEW_DUMP/opencode.harness")"
body="$(jq -r '.prs[0].comments[2].body' "$GH_STATE/state.json")"
[ "$(printf '%s\n' "$body" | sed -n 1p)" = "<!-- kit-revision: puesto 1 gpt/openai/gpt-6.1-sol ronda 2 -->" ] || fail "opencode marcador: $body"
case "$body" in *$'\x1b'*|*"> build"*|*"Voy a revisar"*) fail "opencode comentario con ruido: $body";; esac
[ "$(wts)" = 2 ] || fail "opencode dejó el worktree desechable"

# ok with codex: --output-schema, last message file, sandbox without network
rm -f "$REVIEW_DUMP"/codex.*
out="$(REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 3 gpt codex gpt-6.1-sol "scope" 2 3 2>&1)" || fail "codex: $out"
[ "$(last_line "$out")" = "FIN: 2 hallazgos" ] || fail "codex FIN: $out"
a="$(args codex)"
[ "$(printf '%s\n' "$a" | sed -n 1p)" = exec ] || fail "codex argv: $a"
for x in --ephemeral --ignore-user-config --ignore-rules --sandbox workspace-write 'approval_policy="never"' \
    sandbox_workspace_write.network_access=false --color never -m gpt-6.1-sol --output-schema -o -C; do
  printf '%s\n' "$a" | grep -qxF -- "$x" || fail "codex sin argumento '$x': $a"
done
sf="$(printf '%s\n' "$a" | grep -A1 -xF -- --output-schema | sed -n 2p)"
[ "$(jq -c .required "$sf")" = '["veredicto","resumen","hallazgos","comprobado"]' ] || fail "codex esquema: $sf"
cdir="$(printf '%s\n' "$a" | grep -A1 -xF -- -C | sed -n 2p)"
case "$(cat "$REVIEW_DUMP/codex.pwd")" in *"/$(basename "$(dirname "$cdir")")/$(basename "$cdir")") ;; *) fail "codex -C no es la copia: $cdir";; esac
[ ! -s "$REVIEW_DUMP/codex.stdin" ] || fail "codex con stdin abierto"
[ "$(cat "$REVIEW_DUMP/codex.harness")" = "CLAUDE_CONFIG_DIR=$HOME/.claude
CODEX_HOME=$HOME/.codex" ] || fail "codex variables de la sesión: $(cat "$REVIEW_DUMP/codex.harness")"
[ "$(jq -r '.prs[0].comments[-1].body' "$GH_STATE/state.json" | sed -n 1p)" = "<!-- kit-revision: puesto 3 gpt/gpt-6.1-sol ronda 2 -->" ] \
  || fail "codex marcador"

# zero findings
out="$(REVIEW_STUB_MODE=cero bash "$rv" "$wt" 4 1 claude claude opus foco 3 3 2>&1)" || fail "cero: $out"
[ "$(last_line "$out")" = "FIN: 0 hallazgos" ] || fail "cero FIN: $out"
cb="$(jq -r '.prs[0].comments[-1].body' "$GH_STATE/state.json")"
case "$cb" in "<!-- kit-revision: puesto 1 claude/opus ronda 3 -->"*"Veredicto:** sin hallazgos"*"tests en verde"*"HALLAZGOS: 0") ;; *) fail "cero comentario: $cb";; esac
# idempotent per marker: same args again prints the stored report, posts nothing, does not run the reviewer
nc="$(ncom)"; rm -f "$REVIEW_DUMP/claude.args"
out2="$(REVIEW_STUB_MODE=cero bash "$rv" "$wt" 4 1 claude claude opus foco 3 3 2>&1)" || fail "idem: $out2"
[ "$(last_line "$out2")" = "FIN: 0 hallazgos" ] || fail "idem FIN: $out2"
case "$out2" in *"Veredicto:** sin hallazgos"*"HALLAZGOS: 0"*) ;; *) fail "idem cuerpo: $out2";; esac
[ "$(ncom)" = "$nc" ] || fail "idem volvió a comentar"
[ ! -e "$REVIEW_DUMP/claude.args" ] || fail "idem lanzó el revisor"
# a stored report with findings is printed back with its count
out2="$(bash "$rv" "$wt" 4 2 claude claude sonnet "bordes y errores" 2 3 2>&1)" || fail "idem2: $out2"
[ "$(last_line "$out2")" = "FIN: 2 hallazgos" ] || fail "idem2 FIN: $out2"
case "$out2" in *"kit-revision"*) fail "idem2 imprime el marcador";; esac
[ "$(ncom)" = "$nc" ] || fail "idem2 volvió a comentar"
[ ! -e "$REVIEW_DUMP/claude.args" ] || fail "idem2 lanzó el revisor"
# another seat, model or round still runs (two seats with the same model never collide)
REVIEW_STUB_MODE=cero bash "$rv" "$wt" 4 2 claude claude opus foco 3 3 >/dev/null 2>&1 || fail "otro puesto"
[ -e "$REVIEW_DUMP/claude.args" ] && [ "$(ncom)" = "$((nc + 1))" ] || fail "otro puesto no corrió o no comentó"
REVIEW_STUB_MODE=cero bash "$rv" "$wt" 4 1 claude claude haiku foco 3 3 >/dev/null 2>&1 || fail "otro modelo"
REVIEW_STUB_MODE=cero bash "$rv" "$wt" 4 1 claude claude opus foco 9 3 >/dev/null 2>&1 || fail "otra ronda"
[ "$(ncom)" = "$((nc + 3))" ] || fail "otro modelo u otra ronda no comentó"
lastc() { jq -r '.prs[0].comments[-1].body' "$GH_STATE/state.json"; }

# opencode: invalid JSON gets one repair call in the same session
rm -f "$REVIEW_DUMP"/opencode.*
out="$(REVIEW_STUB_MODE=invalido bash "$rv" "$wt" 4 1 gpt opencode openai/x foco 6 3 2>&1)" || fail "reparación: $out"
[ "$(last_line "$out")" = "FIN: 2 hallazgos" ] || fail "reparación FIN: $out"
[ "$(wc -l < "$REVIEW_DUMP/opencode.calls" | tr -d ' ')" = 2 ] || fail "reparación: no hizo 2 llamadas"
a2="$(tr '\0' '\n' < "$REVIEW_DUMP/opencode.args.2")"
printf '%s\n' "$a2" | grep -A1 -xF -- -s | sed -n 2p | grep -qx ses_1 || fail "reparación sin la sesión: $a2"
case "$(prompt opencode)" in *"no cumple el esquema"*) ;; *) fail "reparación sin los errores";; esac
n0="$(ncom)"

# failures: exit 2, a "sin confirmar (<motivo>)" line, nothing posted, no worktree left
expect_fail() { # <mode> <cli> <motivo> <msg-fragment> [env...]
  local mode="$1" cli="$2" motivo="$3" msg="$4" err rc fam=claude; shift 4
  [ "$cli" = claude ] || fam=gpt
  err="$(env REVIEW_STUB_MODE="$mode" "$@" bash "$rv" "$wt" 4 1 "$fam" "$cli" mod foco 4 3 2>&1 >/dev/null)"; rc=$?
  [ $rc -eq 2 ] || fail "$mode/$cli: exit $rc ($err)"
  case "$err" in *"$msg"*) ;; *) fail "$mode/$cli mensaje: $err";; esac
  [ "$(printf '%s\n' "$err" | grep '^sin confirmar (' | sed -n '$p' | sed 's/^sin confirmar (\([a-z]*\)).*/\1/')" = "$motivo" ] \
    || fail "$mode/$cli motivo (esperado $motivo): $err"
  [ "$(ncom)" = "$n0" ] || fail "$mode/$cli publicó un comentario"
  [ "$(wts)" = 2 ] || fail "$mode/$cli dejó el worktree desechable"
}
expect_fail mudo claude salida "no entregó"
expect_fail mudo opencode salida "no entregó"
expect_fail mudo codex salida "no entregó"
expect_fail invalido claude salida "no entregó"
expect_fail invalido codex salida "no cumple el esquema"
rm -f "$REVIEW_DUMP"/opencode.*
expect_fail invalido2 opencode salida "no cumple el esquema"
[ "$(wc -l < "$REVIEW_DUMP/opencode.calls" | tr -d ' ')" = 2 ] || fail "invalido2: más de un reintento"
expect_fail bloqueado claude bloqueado "No pude leer el diff."
expect_fail login claude acceso "Invalid API key"
expect_fail login opencode acceso "not logged in"
expect_fail login codex acceso "not logged in"
expect_fail evento opencode acceso "ProviderModelNotFoundError"
expect_fail falla opencode acceso "terminó con código 3"
# the reviewer writes into the real worktree: integrity check
expect_fail toca claude integridad "el worktree" REVIEW_STUB_TOUCH="$wt/toque.txt"
rm -f "$wt/toque.txt"
start=$SECONDS
expect_fail lento claude tiempo "agotó el tiempo (1s)" KIT_REVIEW_TIMEOUT=1
[ $((SECONDS - start)) -lt 10 ] || fail "el tope de tiempo no cortó al revisor"
# the timeout kills the reviewer's whole process group, children included
rm -f "$REVIEW_DUMP/hijo.pid"
expect_fail hijo claude tiempo "agotó el tiempo (1s)" KIT_REVIEW_TIMEOUT=1
hp="$(cat "$REVIEW_DUMP/hijo.pid")" || fail "hijo sin pid"
kill -0 "$hp" 2>/dev/null && { kill "$hp"; fail "el hijo del revisor sigue vivo tras el tope"; }
# INT on kit-review stops the reviewer group too
rm -f "$REVIEW_DUMP/hijo.pid"
REVIEW_STUB_MODE=hijo bash "$rv" "$wt" 4 1 claude claude mod foco 4 3 >/dev/null 2>&1 &
kp=$!
for _ in $(seq 50); do [ -s "$REVIEW_DUMP/hijo.pid" ] && break; sleep 0.1; done
hp="$(cat "$REVIEW_DUMP/hijo.pid")" || fail "hijo sin pid (INT)"
kill -TERM "$kp"; wait "$kp"; rc=$?
[ $rc -ne 0 ] || fail "TERM: exit 0"
kill -0 "$hp" 2>/dev/null && { kill "$hp"; fail "el hijo del revisor sigue vivo tras TERM"; }
[ "$(ncom)" = "$n0" ] || fail "TERM publicó un comentario"
[ "$(wts)" = 2 ] || fail "TERM dejó el worktree desechable"
# unknown adapter or CLI missing from the PATH
expect_fail ok foo acceso "revisor no disponible: foo"
# (a PATH with only the system tools, jq and the gh stub: never the real reviewer CLIs)
sysbin="$(mktemp -d)"; ln -s "$(command -v jq)" "$sysbin/jq"
expect_fail ok codex acceso "revisor no disponible: codex" PATH="$TESTS_DIR/stubs/flow:$sysbin:/usr/bin:/bin"
GH_FAIL_ON="pr comment" expect_fail ok claude entorno "no se pudo comentar"
# a PR that commits .claude as a symlink out of the copy: the link goes, its target is untouched
fuera="$(mktemp -d)"; echo '{"mio": true}' > "$fuera/settings.json"; mkdir "$fuera/hooks"; echo x > "$fuera/hooks/h"
(cd "$wt" && git rm -q -r .claude .opencode && rm -rf .claude .opencode && ln -s "$fuera" .claude && ln -s "$fuera" .opencode \
  && git add -A && git commit -q -m enlace && git push -q origin HEAD) >/dev/null 2>&1 || fail "commit enlace"
[ "$(git -C "$wt" ls-tree HEAD .claude .opencode | cut -c1-6 | sort -u)" = 120000 ] || fail "setup: .claude no es un enlace"
out="$(REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 1 claude claude opus foco 5 3 2>&1)" || fail "enlace: $out"
[ "$(cat "$fuera/settings.json")" = '{"mio": true}' ] && [ -f "$fuera/hooks/h" ] || fail "la limpieza siguió el enlace .claude"
grep -qxF .claude "$REVIEW_DUMP/claude.ls" && fail "la copia conserva el enlace .claude"
grep -qxF .opencode "$REVIEW_DUMP/claude.ls" && fail "la copia conserva el enlace .opencode"
grep -qx local.txt "$REVIEW_DUMP/claude.ls" || fail "la copia no está en el nuevo head"
[ "$(wts)" = 2 ] || fail "worktrees al final"
# a kit-revision for the same marker written by someone else is never replayed: the reviewer runs
t="$(mktemp)"
jq '.prs[0].comments += [{id: 900, body: "<!-- kit-revision: puesto 1 claude/opus ronda 8 -->\nHALLAZGOS: 0", author: {login: "otro"}}]' \
  "$GH_STATE/state.json" > "$t" && mv "$t" "$GH_STATE/state.json" || fail "setup revisión ajena"
nc="$(ncom)"; rm -f "$REVIEW_DUMP/claude.args"
out="$(REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 1 claude claude opus foco 8 3 2>&1)" || fail "revisión ajena: $out"
[ "$(last_line "$out")" = "FIN: 2 hallazgos" ] || fail "revisión ajena reproducida: $out"
[ -e "$REVIEW_DUMP/claude.args" ] || fail "revisión ajena: no lanzó el revisor"
[ "$(ncom)" = "$((nc + 1))" ] || fail "revisión ajena: no publicó"
# own login unreadable -> 2, nothing run
rm -f "$GH_STATE/.failed" "$REVIEW_DUMP/claude.args"
err="$(GH_FAIL_ON="api user" REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 1 claude claude opus foco 10 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 2 ] || fail "usuario ilegible: exit $rc ($err)"
[ ! -e "$REVIEW_DUMP/claude.args" ] || fail "usuario ilegible lanzó el revisor"
# KIT_REVIEW_BASE (kit-review-all fetched once for every seat): no fetch nor ls-remote here, so seats in parallel never
# race on refs/remotes (origin moves on, the local origin/main stays put); the base is the merge-base with that commit
before="$(git -C "$r" rev-parse refs/remotes/origin/main)"
c2="$(mktemp -d)/c"
{ git clone -q "$o" "$c2" && git -C "$c2" -c user.name=t -c user.email=t@t commit -q --allow-empty -m otra \
    && git -C "$c2" push -q origin HEAD:main; } >/dev/null 2>&1 || fail "setup avanza origin"
out="$(KIT_REVIEW_BASE="$before" REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 1 claude claude opus foco 11 3 2>&1)"; rc=$?
[ $rc -eq 0 ] || fail "KIT_REVIEW_BASE: exit $rc ($out)"
[ "$(git -C "$r" rev-parse refs/remotes/origin/main)" = "$before" ] || fail "KIT_REVIEW_BASE: hizo fetch"
case "$(prompt claude)" in *"git diff $base...HEAD"*) ;; *) fail "KIT_REVIEW_BASE: base del prompt";; esac
err="$(KIT_REVIEW_BASE=nope REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 1 claude claude opus foco 12 3 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "KIT_REVIEW_BASE inválido: exit $rc"
case "$err" in *"sin confirmar (entorno): KIT_REVIEW_BASE"*) ;; *) fail "KIT_REVIEW_BASE inválido msg: $err";; esac
# codex takes the model id without the OpenCode provider prefix; the marker keeps the configured id
rm -f "$REVIEW_DUMP"/codex.*
out="$(REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 3 gpt codex openai/gpt-6.1-sol "scope" 13 3 2>&1)" || fail "codex openai/: $out"
a="$(args codex)"
[ "$(printf '%s\n' "$a" | grep -A1 -xF -- -m | sed -n 2p)" = gpt-6.1-sol ] || fail "codex -m con prefijo: $a"
[ "$(jq -r '.prs[0].comments[-1].body' "$GH_STATE/state.json" | sed -n 1p)" = "<!-- kit-revision: puesto 3 gpt/openai/gpt-6.1-sol ronda 13 -->" ] \
  || fail "codex openai/ marcador"
echo "test_review OK"
