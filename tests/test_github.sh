#!/usr/bin/env bash
# Tests for kit-github-setup.sh and kit-ship-pr.sh (gh stubbed, git real).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
setup="$REPO_ROOT/scripts/kit-github-setup.sh"
ship="$REPO_ROOT/scripts/kit-ship-pr.sh"
use_gh_stub

# repo with a local bare origin whose default branch is $1
mk_with_origin() {
  local b="$1" r o
  r="$(mk_repo)"; o="$(mktemp -d)"
  git init -q --bare "$o"
  (cd "$r" && git branch -m "$b" && git remote add origin "$o" && git push -q -u origin "$b") >/dev/null 2>&1 || fail "mk_with_origin"
  echo "$r"
}

# --- setup: no remote
r="$(mk_repo)"; : > "$GH_LOG"
err="$(GH_STUB_MODE=no-remote bash "$setup" "$r" 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "no-remote: exit $rc, esperado 1"
case "$err" in *"sin remoto de GitHub"*) ;; *) fail "no-remote: stderr '$err'";; esac

# --- setup: ok
: > "$GH_LOG"
out="$(GH_STUB_MODE=ok bash "$setup" "$r" 2>&1)" || fail "setup ok: exit $?"
n="$(grep -c '^label create .*--force' "$GH_LOG")"
[ "$n" -eq 5 ] || fail "esperadas 5 labels con --force, hay $n"
for l in listo propuesta en-curso necesita-decision bloqueado; do
  grep -q "^label create $l " "$GH_LOG" || fail "falta label $l"
done
grep -q '^repo edit .*--enable-squash-merge' "$GH_LOG" || fail "repo edit sin squash"
grep -q '^repo edit .*--delete-branch-on-merge' "$GH_LOG" || fail "repo edit sin delete-branch"
grep -q '^issue create .*📦 Changelog' "$GH_LOG" || fail "no crea issue Changelog"
grep -q '^issue pin' "$GH_LOG" || fail "no fija issue"
case "$out" in *"FIN: ok"*) ;; *) fail "setup sin FIN: ok";; esac

# --- setup: idempotent with existing issue (fuzzy neighbour must not match)
: > "$GH_LOG"
GH_STUB_MODE=issue-exists bash "$setup" "$r" >/dev/null 2>&1 || fail "setup rerun: exit $?"
grep -q '^issue create' "$GH_LOG" && fail "vuelve a crear el issue existente"
grep -q '^issue pin 7' "$GH_LOG" || fail "no fija el issue existente"

# --- ship: trunk default
r="$(mk_with_origin trunk)"; : > "$GH_LOG"
echo change > "$r/new.txt"; echo more >> "$r/README.md"
out="$(GH_STUB_MODE=default-branch-trunk bash "$ship" "$r" kit/cambio "feat: algo" "cuerpo" 2>&1)" || fail "ship: exit $? ($out)"
grep -q '^pr create .*--base trunk' "$GH_LOG" || fail "pr create sin --base trunk"
grep -q '^pr merge .*--squash' "$GH_LOG" || fail "pr merge sin --squash"
[ "$(git -C "$r" rev-parse --abbrev-ref HEAD)" = trunk ] || fail "no termina en trunk"
git -C "$r" show-ref --verify -q refs/heads/kit/cambio && fail "rama local no borrada"
git -C "$r" ls-remote --exit-code --heads origin kit/cambio >/dev/null 2>&1 || fail "rama no se subió"
[ "$(git -C "$r" log -1 --format=%s kit/cambio 2>/dev/null)" != "" ] || true
case "$out" in *"github.com/dru/demo/pull/1"*"FIN: ok"*) ;; *) fail "salida sin URL/FIN: $out";; esac

# --- ship: nothing to ship
r="$(mk_with_origin main)"
err="$(bash "$ship" "$r" kit/x t b 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "sin cambios: exit $rc"
case "$err" in *"nada que enviar"*) ;; *) fail "sin cambios: stderr '$err'";; esac

# --- ship: branch exists -> exit 1, no clobber
echo c > "$r/f.txt"; git -C "$r" branch kit/dup
err="$(bash "$ship" "$r" kit/dup t b 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "rama existente: exit $rc"
[ -f "$r/f.txt" ] || fail "rama existente: cambios perdidos"

# --- ship: not a git repo -> 2
bash "$ship" "$(mktemp -d)" kit/x t b >/dev/null 2>&1; [ $? -eq 2 ] || fail "no-repo debe salir 2"

echo "OK test_github"
