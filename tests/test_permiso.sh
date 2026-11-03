#!/usr/bin/env bash
# kit-activate.sh / kit-deactivate.sh: the Claude Code permission rule for kit-fusionar in .claude/settings.json.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1

A="$REPO_ROOT/scripts/kit-activate.sh"
D="$REPO_ROOT/scripts/kit-deactivate.sh"
RULE='Bash(kit-fusionar *)'
dirs=()
trap 'rm -rf "${dirs[@]}"' EXIT
new_repo() { local d; d="$(mk_repo)"; dirs+=("$d"); echo "$d"; }
n_rule() { jq --arg r "$RULE" '[.permissions.allow[]? | select(. == $r)] | length' "$1/.claude/settings.json"; }

# 1. no settings file: activate creates it with only the rule
r="$(new_repo)"
out="$(bash "$A" "$r" 2>/dev/null)" || fail "activate failed"
grep -qx 'creado: .claude/settings.json' <<<"$out" || fail "expected 'creado: .claude/settings.json', got: $out"
[ "$(jq -c . "$r/.claude/settings.json")" = "{\"permissions\":{\"allow\":[\"$RULE\"]}}" ] || fail "unexpected settings: $(cat "$r/.claude/settings.json")"
[ -x "$REPO_ROOT/bin/kit-fusionar" ] || fail "bin/kit-fusionar missing or not executable"

# 2. rerun: idempotent, no duplicate, no change line
out="$(bash "$A" "$r" 2>/dev/null)" || fail "second activate failed"
grep -q 'settings.json' <<<"$out" && fail "second run should not touch settings: $out"
[ "$(n_rule "$r")" = 1 ] || fail "rule duplicated"

# 3. deactivate: rule removed; file left empty is deleted
out="$(bash "$D" "$r" 2>/dev/null)" || fail "deactivate failed"
grep -qx 'borrado: .claude/settings.json' <<<"$out" || fail "expected 'borrado: .claude/settings.json', got: $out"
[ ! -e "$r/.claude/settings.json" ] || fail "empty settings should be deleted"
[ -L "$r/.claude/skills" ] || fail ".claude/skills symlink removed"

# 4. existing settings with other keys and rules: merged, kept; deactivate keeps them
r="$(new_repo)"; mkdir -p "$r/.claude"
printf '{"model":"x","permissions":{"allow":["Bash(npm test)"],"deny":["Bash(rm *)"]}}\n' > "$r/.claude/settings.json"
out="$(bash "$A" "$r" 2>/dev/null)" || fail "activate over existing settings failed"
grep -qx 'cambiado: .claude/settings.json' <<<"$out" || fail "expected 'cambiado: .claude/settings.json', got: $out"
[ "$(jq -c '[.model, .permissions.allow, .permissions.deny]' "$r/.claude/settings.json")" = "[\"x\",[\"Bash(npm test)\",\"$RULE\"],[\"Bash(rm *)\"]]" ] \
  || fail "existing keys not kept: $(cat "$r/.claude/settings.json")"
out="$(bash "$D" "$r" 2>/dev/null)" || fail "deactivate over merged settings failed"
grep -qx 'cambiado: .claude/settings.json' <<<"$out" || fail "deactivate should say cambiado, got: $out"
[ "$(jq -c . "$r/.claude/settings.json")" = '{"model":"x","permissions":{"allow":["Bash(npm test)"],"deny":["Bash(rm *)"]}}' ] \
  || fail "deactivate touched other keys: $(cat "$r/.claude/settings.json")"

# 5. "flujo": false: no rule (and an existing one is removed)
r="$(new_repo)"
bash "$A" "$r" >/dev/null 2>&1 || fail "activate failed"
out="$(bash "$A" "$r" --flujo false 2>/dev/null)" || fail "activate --flujo false failed"
grep -qx 'borrado: .claude/settings.json' <<<"$out" || fail "flujo false should remove the rule, got: $out"
r="$(new_repo)"
out="$(bash "$A" "$r" --flujo false 2>/dev/null)" || fail "activate --flujo false failed"
[ ! -e "$r/.claude/settings.json" ] || fail "flujo false should not create settings"

# 6. invalid JSON, non-array allow or a symlinked settings: left untouched, with a warning, exit 0
r="$(new_repo)"; mkdir -p "$r/.claude"
printf '{ roto\n' > "$r/.claude/settings.json"
err="$(bash "$A" "$r" 2>&1 >/dev/null)" || fail "activate should not fail on broken settings"
grep -q 'aviso: .claude/settings.json' <<<"$err" || fail "expected a warning, got: $err"
[ "$(cat "$r/.claude/settings.json")" = '{ roto' ] || fail "broken settings was modified"
err="$(bash "$D" "$r" 2>&1 >/dev/null)" || fail "deactivate should not fail on broken settings"
[ "$(cat "$r/.claude/settings.json")" = '{ roto' ] || fail "deactivate modified broken settings"
r="$(new_repo)"; mkdir -p "$r/.claude"
printf '{"permissions":{"allow":"Bash(x)"}}\n' > "$r/.claude/settings.json"
err="$(bash "$A" "$r" 2>&1 >/dev/null)" || fail "activate should not fail on non-array allow"
grep -q 'aviso: .claude/settings.json' <<<"$err" || fail "expected a warning for non-array allow, got: $err"
[ "$(jq -c . "$r/.claude/settings.json")" = '{"permissions":{"allow":"Bash(x)"}}' ] || fail "non-array allow was modified"
r="$(new_repo)"; mkdir -p "$r/.claude"; t="$(mktemp)"; dirs+=("$t"); echo '{}' > "$t"
ln -s "$t" "$r/.claude/settings.json"
err="$(bash "$A" "$r" 2>&1 >/dev/null)" || fail "activate should not fail on symlinked settings"
grep -q 'aviso: .claude/settings.json' <<<"$err" || fail "expected a warning for symlinked settings, got: $err"
[ "$(cat "$t")" = '{}' ] || fail "symlink target was modified"

# 6b. a valid object followed by broken JSON: untouched (jq would print the first object before failing)
r="$(new_repo)"; mkdir -p "$r/.claude"
printf '{"model":"x"}\n{ roto\n' > "$r/.claude/settings.json"; before="$(cat "$r/.claude/settings.json")"
err="$(bash "$A" "$r" 2>&1 >/dev/null)" || fail "activate should not fail on trailing garbage"
grep -q 'aviso: .claude/settings.json' <<<"$err" || fail "expected a warning for trailing garbage, got: $err"
[ "$(cat "$r/.claude/settings.json")" = "$before" ] || fail "settings with trailing garbage was modified"

# 6c. deactivate: a failed write of settings keeps the marker, so a retry removes the rule
r="$(new_repo)"; bash "$A" "$r" >/dev/null 2>&1 || fail "activate failed"
jq '.model = "x"' "$r/.claude/settings.json" > "$r/s.tmp" && mv "$r/s.tmp" "$r/.claude/settings.json"
stub="$(mktemp -d)"; dirs+=("$stub"); printf '#!/bin/sh\nexit 1\n' > "$stub/mv"; chmod +x "$stub/mv"
PATH="$stub:$PATH" bash "$D" "$r" >/dev/null 2>&1; [ $? -eq 2 ] || fail "deactivate with a failing write should exit 2"
[ -e "$r/.agents-kit.json" ] || fail "marker removed although the rule could not be removed"
bash "$D" "$r" >/dev/null 2>&1 || fail "deactivate retry failed"
[ "$(n_rule "$r")" = 0 ] || fail "retry did not remove the rule"
[ ! -e "$r/.agents-kit.json" ] || fail "retry did not remove the marker"

# 7. bin/kit-fusionar runs kit-pr.sh fusionar with the same arguments (usage error reaches through)
err="$(bash "$REPO_ROOT/bin/kit-fusionar" 2>&1)"; code=$?
[ $code -eq 1 ] || fail "kit-fusionar without args should exit 1 (kit-pr.sh usage), got $code"
grep -q 'fusionar' <<<"$err" || fail "kit-fusionar usage should come from kit-pr.sh fusionar, got: $err"
echo "ok"
