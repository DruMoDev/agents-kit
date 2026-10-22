#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1

S="$REPO_ROOT/scripts/kit-activate.sh"
dirs=()
trap 'rm -rf "${dirs[@]}"' EXIT
new_repo() { local d; d="$(mk_repo)"; dirs+=("$d"); echo "$d"; }
last_line() { tail -n 1 <<<"$1"; }

# 1. empty repo: everything created
r="$(new_repo)"
out="$(bash "$S" "$r" 2>/dev/null)" || fail "activate on empty repo should exit 0"
for f in .agents-kit.json CHANGELOG.md AGENTS.md CLAUDE.md; do [ -f "$r/$f" ] || fail "missing $f"; done
[ -d "$r/.agents/skills" ] || fail "missing .agents/skills"
[ -f "$r/.agents/skills/.gitkeep" ] || fail "missing .agents/skills/.gitkeep"
git -C "$r" status --porcelain -uall | grep -q '\.agents/skills/\.gitkeep' || fail ".gitkeep must be visible to git"
[ -L "$r/.claude/skills" ] || fail "missing .claude/skills symlink"
[ "$(cat "$r/CLAUDE.md")" = "@AGENTS.md" ] || fail "CLAUDE.md should be exactly @AGENTS.md"
[ "$(readlink "$r/.claude/skills")" = "../.agents/skills" ] || fail "wrong symlink target"
[ "$(jq .maxReviewRounds "$r/.agents-kit.json")" = "10" ] || fail "maxReviewRounds != 10"
[ "$(jq -r .notify "$r/.agents-kit.json")" = "ntfy" ] || fail "notify"
[ "$(jq -r '.reviewers.claude | length' "$r/.agents-kit.json")" = "2" ] || fail "reviewers.claude"
[ "$(last_line "$out")" = "FIN: 7" ] || fail "expected FIN: 7, got: $(last_line "$out")"
grep -q "^# Changelog" "$r/CHANGELOG.md" || fail "CHANGELOG title"
grep -qi "regla" "$r/AGENTS.md" && fail "AGENTS.md template must not contain kit rules"

# 2. idempotent
before="$(cd "$r" && cat .agents-kit.json CHANGELOG.md AGENTS.md CLAUDE.md | shasum)"
out="$(bash "$S" "$r" 2>/dev/null)" || fail "second run should exit 0"
[ "$(last_line "$out")" = "FIN: 0" ] || fail "second run expected FIN: 0, got: $(last_line "$out")"
after="$(cd "$r" && cat .agents-kit.json CHANGELOG.md AGENTS.md CLAUDE.md | shasum)"
[ "$before" = "$after" ] || fail "files changed on second run"

# 2b. existing empty .agents/skills dir gets a .gitkeep; non-empty dir does not
r="$(new_repo)"; mkdir -p "$r/.agents/skills"
bash "$S" "$r" >/dev/null 2>&1; [ -f "$r/.agents/skills/.gitkeep" ] || fail "empty dir should get .gitkeep"
r="$(new_repo)"; mkdir -p "$r/.agents/skills/x"; echo s > "$r/.agents/skills/x/SKILL.md"
bash "$S" "$r" >/dev/null 2>&1; [ ! -e "$r/.agents/skills/.gitkeep" ] || fail "non-empty dir must not get .gitkeep"

# 3. existing AGENTS.md and CLAUDE.md preserved
r="$(new_repo)"
echo "Mi contenido" > "$r/AGENTS.md"
echo "Notas" > "$r/CLAUDE.md"
bash "$S" "$r" >/dev/null 2>&1 || fail "activate with existing files should exit 0"
[ "$(cat "$r/AGENTS.md")" = "Mi contenido" ] || fail "AGENTS.md was modified"
[ "$(head -n 1 "$r/CLAUDE.md")" = "@AGENTS.md" ] || fail "CLAUDE.md should start with @AGENTS.md"
grep -qx "Notas" "$r/CLAUDE.md" || fail "CLAUDE.md lost its content"
out="$(bash "$S" "$r" 2>/dev/null)"
[ "$(last_line "$out")" = "FIN: 0" ] || fail "rerun should be FIN: 0"
[ "$(grep -cx '@AGENTS.md' "$r/CLAUDE.md")" = "1" ] || fail "@AGENTS.md duplicated"

# 3b. CLAUDE.md already has @AGENTS.md later in the file: untouched
r="$(new_repo)"
printf 'Notas\n@AGENTS.md\n' > "$r/CLAUDE.md"
bash "$S" "$r" >/dev/null 2>&1 || fail "exit 0 expected"
[ "$(head -n 1 "$r/CLAUDE.md")" = "Notas" ] || fail "CLAUDE.md with existing import was changed"

# 3c. CLAUDE.md symlink to AGENTS.md: satisfied, not modified
r="$(new_repo)"
echo "Mi contenido" > "$r/AGENTS.md"
ln -s AGENTS.md "$r/CLAUDE.md"
bash "$S" "$r" >/dev/null 2>&1 || fail "exit 0 expected for CLAUDE.md symlink"
[ -L "$r/CLAUDE.md" ] || fail "CLAUDE.md symlink was replaced"
[ "$(cat "$r/AGENTS.md")" = "Mi contenido" ] || fail "AGENTS.md modified through symlink"

# 4. real .claude/skills directory: untouched, warning, exit 0
r="$(new_repo)"
mkdir -p "$r/.claude/skills/x"
echo "skill" > "$r/.claude/skills/x/SKILL.md"
err="$(bash "$S" "$r" 2>&1 >/dev/null)" || fail "real skills dir should still exit 0"
[ -f "$r/.claude/skills/x/SKILL.md" ] || fail "real skills dir was touched"
[ ! -L "$r/.claude/skills" ] || fail "real dir replaced by symlink"
grep -q "\.claude/skills" <<<"$err" || fail "stderr should mention .claude/skills"

# 5. broken symlink is redone
r="$(new_repo)"
mkdir -p "$r/.claude"
ln -s ../nowhere "$r/.claude/skills"
bash "$S" "$r" >/dev/null 2>&1 || fail "broken symlink case should exit 0"
[ "$(readlink "$r/.claude/skills")" = "../.agents/skills" ] || fail "broken symlink not redone"

# 6. existing marker is not overwritten
r="$(new_repo)"
echo '{"maxReviewRounds":3}' > "$r/.agents-kit.json"
bash "$S" "$r" >/dev/null 2>&1
[ "$(jq .maxReviewRounds "$r/.agents-kit.json")" = "3" ] || fail "marker overwritten"

# 6b. CLAUDE.md symlink to another file: nothing written through it
r="$(new_repo)"
o="$(mktemp -d)"; dirs+=("$o")
echo "ajeno" > "$o/other.md"
ln -s "$o/other.md" "$r/CLAUDE.md"
err="$(bash "$S" "$r" 2>&1 >/dev/null)" || fail "CLAUDE.md foreign symlink should exit 0"
[ "$(cat "$o/other.md")" = "ajeno" ] || fail "wrote through CLAUDE.md symlink"
[ -L "$r/CLAUDE.md" ] || fail "CLAUDE.md symlink replaced"
grep -q "CLAUDE.md" <<<"$err" || fail "stderr should mention CLAUDE.md"

# 6c. .claude and .agents symlinked outside: outside dirs untouched
r="$(new_repo)"
o1="$(mktemp -d)"; o2="$(mktemp -d)"; dirs+=("$o1" "$o2")
ln -s "$o1" "$r/.claude"; ln -s "$o2" "$r/.agents"
err="$(bash "$S" "$r" 2>&1 >/dev/null)" || fail "symlinked dirs should exit 0"
[ -z "$(ls -A "$o1")" ] || fail "wrote into outside dir via .claude"
[ -z "$(ls -A "$o2")" ] || fail "wrote into outside dir via .agents"
grep -q "\.claude" <<<"$err" || fail "stderr should mention .claude"
grep -q "\.agents" <<<"$err" || fail "stderr should mention .agents"

# 7. environment errors exit 2
bash "$S" "/nonexistent-dir-xyz" >/dev/null 2>&1; [ $? -eq 2 ] || fail "missing dir should exit 2"
nd="$(mktemp -d)"; dirs+=("$nd")
bash "$S" "$nd" >/dev/null 2>&1; [ $? -eq 2 ] || fail "non-git dir should exit 2"
bash "$S" >/dev/null 2>&1; [ $? -eq 1 ] || fail "no args should exit 1"
echo "ok"
