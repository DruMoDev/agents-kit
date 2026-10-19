#!/usr/bin/env bash
# Tests for scripts/kit-review.sh (local bare origin, stateful gh stub, reviewer stubs).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
rv="$REPO_ROOT/scripts/kit-review.sh"
use_flow_gh
export PATH="$TESTS_DIR/stubs/review:$PATH"
export REVIEW_DUMP="$(mktemp -d)"
export GH_TOKEN=secreto GITHUB_TOKEN=secreto GH_ENTERPRISE_TOKEN=secreto GITHUB_ENTERPRISE_TOKEN=secreto
unset KIT_REVIEW_TIMEOUT REVIEW_STUB_MODE
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
  | .prs = [{number: 4, headRefName: "issue-3-foo", state: "OPEN", isDraft: false, url: "u",
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

# no marker
m="$(mk_repo)"; bash "$rv" "$m" 4 claude sonnet foco 2 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin marcador debe dar 1"
# usage
bash "$rv" "$wt" 4 claude sonnet foco 2 >/dev/null 2>&1; [ $? -eq 1 ] || fail "faltan argumentos debe dar 1"
bash "$rv" "$wt" x claude sonnet foco 2 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "PR inválida debe dar 1"

# ok with claude
out="$(REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 claude sonnet "bordes y errores" 2 3 2>&1)" || fail "ok: $out"
[ "$(last_line "$out")" = "FIN: 2 hallazgos" ] || fail "ok FIN: $out"
[ "$(ncom)" = 2 ] || fail "ok no publicó un comentario"
body="$(jq -r '.prs[0].comments[1].body' "$GH_STATE/state.json")"
exp="<!-- kit-revision: claude/sonnet ronda 2 -->
1. [grave] a.txt:1: falla con vacío. Escenario: fichero vacío. Arreglo: comprobarlo
2. [menor] b.txt:2: nombre confuso. Escenario: lectura. Arreglo: renombrar
HALLAZGOS: 2"
[ "$body" = "$exp" ] || fail "ok comentario: $body"
printf '%s\n' "$out" | grep -qx "2. \[menor\] b.txt:2: nombre confuso. Escenario: lectura. Arreglo: renombrar" \
  || fail "ok no imprime los hallazgos: $out"
printf '%s\n' "$out" | grep -q "Revisé el diff" && fail "ok imprime el preámbulo"
[ "$(wts)" = 2 ] || fail "ok dejó el worktree desechable"
# argv of claude: block flags, model, stdin-free headless mode
a="$(args claude)"
for x in -p --model sonnet --permission-mode bypassPermissions --setting-sources user --strict-mcp-config \
    --disallowedTools "Bash(git push:*)" "Bash(gh:*)" --output-format text; do
  printf '%s\n' "$a" | grep -qxF -- "$x" || fail "claude sin argumento '$x': $a"
done
# prompt: focus, round, issue, base, history; no placeholder left; history taken literally
p="$(prompt claude)"
for x in "bordes y errores" "Foo roto" 'Cuerpo del issue con & y \1' "PREVIO → rechazado: no aplica {{FOCO}}" \
    "git diff $base...HEAD" "ronda 2"; do
  case "$p" in *"$x"*) ;; *) fail "el prompt no contiene '$x'";; esac
done
case "$p" in *"FIN: "*) fail "el prompt incluye la línea FIN del historial";; esac
printf '%s' "$p" | grep -Eq '\{\{(RONDA|ISSUE|BASE|HISTORIAL)\}\}' && fail "quedan marcadores sin sustituir"
case "$p" in *origin/*) fail "el prompt nombra origin/: la copia no tiene remoto";; esac
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

# ok with opencode: config env blocks gh and git push, ANSI and noise stripped
out="$(REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 opencode openai/gpt-6.1-sol "uso real" 2 3 2>&1)" || fail "opencode: $out"
[ "$(last_line "$out")" = "FIN: 2 hallazgos" ] || fail "opencode FIN: $out"
env="$(cat "$REVIEW_DUMP/opencode.env")"
[ "$(printf '%s' "$env" | jq -c .permission)" = '{"bash":{"*":"allow","gh *":"deny","git push*":"deny"},"edit":"allow","external_directory":"deny"}' ] \
  || fail "opencode config: $env"
a="$(args opencode)"
[ "$(printf '%s\n' "$a" | sed -n 1,3p | tr '\n' ' ')" = "run -m openai/gpt-6.1-sol " ] || fail "opencode argv: $a"
body="$(jq -r '.prs[0].comments[2].body' "$GH_STATE/state.json")"
[ "$(printf '%s\n' "$body" | sed -n 1p)" = "<!-- kit-revision: opencode/openai/gpt-6.1-sol ronda 2 -->" ] || fail "opencode marcador: $body"
case "$body" in *$'\x1b'*|*"> build"*|*"| Bash"*) fail "opencode comentario con ruido: $body";; esac
case "$out" in *$'\x1b'*) fail "opencode imprime ANSI";; esac
[ "$(wts)" = 2 ] || fail "opencode dejó el worktree desechable"

# zero findings
out="$(REVIEW_STUB_MODE=cero bash "$rv" "$wt" 4 claude opus foco 3 3 2>&1)" || fail "cero: $out"
[ "$(last_line "$out")" = "FIN: 0 hallazgos" ] || fail "cero FIN: $out"
[ "$(jq -r '.prs[0].comments[3].body' "$GH_STATE/state.json")" = "<!-- kit-revision: claude/opus ronda 3 -->
HALLAZGOS: 0" ] || fail "cero comentario"
lastc() { jq -r '.prs[0].comments[-1].body' "$GH_STATE/state.json"; }

# a total > 0 with no recognisable finding keeps everything before HALLAZGOS
out="$(REVIEW_STUB_MODE=negrita bash "$rv" "$wt" 4 claude opus foco 3 3 2>&1)" || fail "negrita: $out"
[ "$(last_line "$out")" = "FIN: 1 hallazgos" ] || fail "negrita FIN: $out"
case "$(lastc)" in *"1. **[grave]** a:1: x"*"HALLAZGOS: 1") ;; *) fail "negrita perdió el hallazgo: $(lastc)";; esac
# HALLAZGOS line wrapped in markdown still delivers
out="$(REVIEW_STUB_MODE=envuelto bash "$rv" "$wt" 4 claude opus foco 3 3 2>&1)" || fail "envuelto: $out"
[ "$(last_line "$out")" = "FIN: 1 hallazgos" ] || fail "envuelto FIN: $out"
case "$(lastc)" in *"1. [medio] a.txt:1: y."*'HALLAZGOS: 1`**') ;; *) fail "envuelto comentario: $(lastc)";; esac
n0="$(ncom)"

# failures: exit 2, nothing posted, no worktree left
expect_fail() { # <mode> <tool> <msg-fragment> [env...]
  local mode="$1" tool="$2" msg="$3" err rc; shift 3
  err="$(env REVIEW_STUB_MODE="$mode" "$@" bash "$rv" "$wt" 4 "$tool" mod foco 4 3 2>&1 >/dev/null)"; rc=$?
  [ $rc -eq 2 ] || fail "$mode/$tool: exit $rc ($err)"
  case "$err" in *"$msg"*) ;; *) fail "$mode/$tool mensaje: $err";; esac
  [ "$(ncom)" = "$n0" ] || fail "$mode/$tool publicó un comentario"
  [ "$(wts)" = 2 ] || fail "$mode/$tool dejó el worktree desechable"
}
expect_fail mudo claude "el revisor claude/mod no entregó: "
expect_fail falla opencode "el revisor opencode/mod no entregó: "
start=$SECONDS
expect_fail lento claude "el revisor claude/mod no entregó: " KIT_REVIEW_TIMEOUT=1
[ $((SECONDS - start)) -lt 10 ] || fail "el tope de tiempo no cortó al revisor"
# the timeout kills the reviewer's whole process group, children included
rm -f "$REVIEW_DUMP/hijo.pid"
expect_fail hijo claude "agotó el tiempo (1s)" KIT_REVIEW_TIMEOUT=1
hp="$(cat "$REVIEW_DUMP/hijo.pid")" || fail "hijo sin pid"
kill -0 "$hp" 2>/dev/null && { kill "$hp"; fail "el hijo del revisor sigue vivo tras el tope"; }
# INT on kit-review stops the reviewer group too
rm -f "$REVIEW_DUMP/hijo.pid"
REVIEW_STUB_MODE=hijo bash "$rv" "$wt" 4 claude mod foco 4 3 >/dev/null 2>&1 &
kp=$!
for _ in $(seq 50); do [ -s "$REVIEW_DUMP/hijo.pid" ] && break; sleep 0.1; done
hp="$(cat "$REVIEW_DUMP/hijo.pid")" || fail "hijo sin pid (INT)"
kill -TERM "$kp"; wait "$kp"; rc=$?
[ $rc -ne 0 ] || fail "TERM: exit 0"
kill -0 "$hp" 2>/dev/null && { kill "$hp"; fail "el hijo del revisor sigue vivo tras TERM"; }
[ "$(ncom)" = "$n0" ] || fail "TERM publicó un comentario"
[ "$(wts)" = 2 ] || fail "TERM dejó el worktree desechable"
expect_fail ok foo "revisor no disponible: foo"
GH_FAIL_ON="pr comment" expect_fail ok claude "no se pudo comentar"
# a PR that commits .claude as a symlink out of the copy: the link goes, its target is untouched
fuera="$(mktemp -d)"; echo '{"mio": true}' > "$fuera/settings.json"; mkdir "$fuera/hooks"; echo x > "$fuera/hooks/h"
(cd "$wt" && git rm -q -r .claude .opencode && rm -rf .claude .opencode && ln -s "$fuera" .claude && ln -s "$fuera" .opencode \
  && git add -A && git commit -q -m enlace && git push -q origin HEAD) >/dev/null 2>&1 || fail "commit enlace"
[ "$(git -C "$wt" ls-tree HEAD .claude .opencode | cut -c1-6 | sort -u)" = 120000 ] || fail "setup: .claude no es un enlace"
out="$(REVIEW_STUB_MODE=ok bash "$rv" "$wt" 4 claude opus foco 5 3 2>&1)" || fail "enlace: $out"
[ "$(cat "$fuera/settings.json")" = '{"mio": true}' ] && [ -f "$fuera/hooks/h" ] || fail "la limpieza siguió el enlace .claude"
grep -qxF .claude "$REVIEW_DUMP/claude.ls" && fail "la copia conserva el enlace .claude"
grep -qxF .opencode "$REVIEW_DUMP/claude.ls" && fail "la copia conserva el enlace .opencode"
grep -qx local.txt "$REVIEW_DUMP/claude.ls" || fail "la copia no está en el nuevo head"
[ "$(wts)" = 2 ] || fail "worktrees al final"
echo "test_review OK"
