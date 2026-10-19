#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1

S="$REPO_ROOT/scripts/kit-deactivate.sh"
dirs=()
trap 'rm -rf "${dirs[@]}"' EXIT
new_repo() { local d; d="$(mk_repo)"; dirs+=("$d"); echo "$d"; }
last_line() { tail -n 1 <<<"$1"; }

# 1. with marker: removed, nothing else touched, FIN: ok
r="$(new_repo)"
bash "$REPO_ROOT/scripts/kit-activate.sh" "$r" >/dev/null 2>&1 || fail "activate failed"
before="$(cd "$r" && cat AGENTS.md CHANGELOG.md CLAUDE.md | shasum)"
out="$(bash "$S" "$r" 2>/dev/null)" || fail "deactivate with marker should exit 0"
[ ! -e "$r/.agents-kit.json" ] || fail "marker not removed"
[ "$(last_line "$out")" = "FIN: ok" ] || fail "expected FIN: ok, got: $(last_line "$out")"
after="$(cd "$r" && cat AGENTS.md CHANGELOG.md CLAUDE.md | shasum)"
[ "$before" = "$after" ] || fail "deactivate touched other files"
[ -d "$r/.agents/skills" ] || fail ".agents/skills removed"
[ -L "$r/.claude/skills" ] || fail ".claude/skills symlink removed"

# 2. without marker: exit 1, message
err="$(bash "$S" "$r" 2>&1 >/dev/null)"; code=$?
[ $code -eq 1 ] || fail "no marker should exit 1, got $code"
grep -q "no está activado" <<<"$err" || fail "stderr should say 'no está activado'"

# 3. usage and environment errors
bash "$S" >/dev/null 2>&1; [ $? -eq 1 ] || fail "no args should exit 1"
bash "$S" "/nonexistent-dir-xyz" >/dev/null 2>&1; [ $? -eq 2 ] || fail "missing dir should exit 2"
nd="$(mktemp -d)"; dirs+=("$nd")
bash "$S" "$nd" >/dev/null 2>&1; [ $? -eq 2 ] || fail "non-git dir should exit 2"
echo "ok"
