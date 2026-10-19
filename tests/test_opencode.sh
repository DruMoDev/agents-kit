#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v node >/dev/null || fail "node no está instalado"
plugin="$REPO_ROOT/.opencode/plugins/agents-kit.js"
[ -f "$plugin" ] || fail ".opencode/plugins/agents-kit.js missing"
run() { node "$TESTS_DIR/opencode_harness.mjs" "$@"; }

repo="$(mk_repo)"

# repo without marker: skills registered, nothing injected
out="$(run "$plugin" "$repo")" || fail "harness failed: $out"
printf '%s' "$out" | jq -e --arg s "$REPO_ROOT/skills" '.skills == [$s] and .texts == ["hola"]' >/dev/null \
  || fail "unmarked repo must only register skills: $out"

# repo with marker, from a subdir: rules injected once, before the user text
echo '{}' > "$repo/.agents-kit.json"
mkdir -p "$repo/src"
out="$(run "$plugin" "$repo/src")" || fail "harness failed: $out"
printf '%s' "$out" | jq -e '(.texts | length) == 2 and .texts[1] == "hola"
  and (.texts[0] | contains("agents-kit está activo"))
  and (.texts[0] | contains("## Escribe menos código"))' >/dev/null \
  || fail "marked repo must inject rules once: $out"

# loaded through a symlink (how it is installed): paths resolve to the real repo
link="$(mktemp -d)/agents-kit.js"
ln -s "$plugin" "$link"
out="$(run "$link" "$repo")" || fail "harness failed via symlink: $out"
printf '%s' "$out" | jq -e --arg s "$REPO_ROOT/skills" '.skills == [$s] and (.texts | length) == 2' >/dev/null \
  || fail "symlinked plugin must resolve the real plugin root: $out"

# the plugin root is allowed as an external directory, without overriding the user
out="$(run "$plugin" "$repo")" || fail "harness failed: $out"
printf '%s' "$out" | jq -e --arg p "$REPO_ROOT/**" '.permission.external_directory[$p] == "allow"' >/dev/null \
  || fail "plugin root must be an allowed external directory: $out"
out="$(run "$plugin" "$repo" "{\"permission\":{\"external_directory\":{\"$REPO_ROOT/**\":\"deny\",\"/x/**\":\"allow\"}}}")" || fail "harness failed: $out"
printf '%s' "$out" | jq -e --arg p "$REPO_ROOT/**" '.permission.external_directory == {($p): "deny", "/x/**": "allow"}' >/dev/null \
  || fail "user rule for the plugin root must win: $out"
out="$(run "$plugin" "$repo" '{"permission":{"external_directory":"ask"}}')" || fail "harness failed: $out"
printf '%s' "$out" | jq -e '.permission.external_directory == "ask"' >/dev/null \
  || fail "a global external_directory rule must be left alone: $out"

echo ok
