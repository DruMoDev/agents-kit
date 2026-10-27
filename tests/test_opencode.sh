#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1

command -v node >/dev/null || fail "node no está instalado"
plugin="$REPO_ROOT/.opencode/plugins/agents-kit.js"
[ -f "$plugin" ] || fail ".opencode/plugins/agents-kit.js missing"
NODE="$(command -v node)"
run() { "$NODE" --no-warnings "$TESTS_DIR/opencode_harness.mjs" "$@"; }
export KIT_WORKTREES="$(mktemp -d)/wt" KIT_TMP="$(mktemp -d)/tmp"
allowed='(["scripts","skills","rules","templates"] | map($r + "/" + . + "/**")) + [$wt + "/" + $name + "/**", $tmp + "/**"]'

repo="$(mk_repo)"

# repo without marker: skills registered, no permission rule, nothing injected
out="$(run "$plugin" "$repo")" || fail "harness failed: $out"
printf '%s' "$out" | jq -e --arg s "$REPO_ROOT/skills" '.skills == [$s] and .permission == null and .texts == ["hola"]' >/dev/null \
  || fail "unmarked repo must only register skills: $out"

# outside git: same as unmarked
nogit="$(mktemp -d)"
out="$(run "$plugin" "$nogit")" || fail "harness failed outside git: $out"
printf '%s' "$out" | jq -e '.permission == null and .texts == ["hola"]' >/dev/null \
  || fail "non-git dir must be inert: $out"

# kit-on mid-process: rules load on the next session without restarting
out="$(run "$plugin" "$repo" '{}' "$repo/.agents-kit.json")" || fail "harness failed: $out"
printf '%s' "$out" | jq -e '.texts == ["hola"] and (.textsAfter | length) == 2 and .textsAfter[1] == "hola"' >/dev/null \
  || fail "marker created mid-process must take effect: $out"

# repo with marker, from a subdir: rules injected once, before the user text,
# and only the plugin's scripts/skills/rules/templates are allowed
mkdir -p "$repo/src"
out="$(run "$plugin" "$repo/src")" || fail "harness failed: $out"
printf '%s' "$out" | jq -e '(.texts | length) == 2 and .texts[1] == "hola"
  and (.texts[0] | contains("agents-kit está activo"))
  and (.texts[0] | contains("## Escribe menos código"))' >/dev/null \
  || fail "marked repo must inject rules once: $out"
printf '%s' "$out" | jq -e --arg r "$REPO_ROOT" --arg wt "$KIT_WORKTREES" --arg tmp "$KIT_TMP" --arg name "$(basename "$repo")" "(.permission.external_directory | keys | sort) == ($allowed | sort)
  and ([.permission.external_directory[]] | all(. == \"allow\"))" >/dev/null \
  || fail "marked repo must allow only the plugin's scripts/skills/rules/templates, its issue worktrees and the kit tmp: $out"

# a user rule wins; a global string rule is left alone
out="$(run "$plugin" "$repo" "{\"permission\":{\"external_directory\":{\"$REPO_ROOT/scripts/**\":\"deny\"}}}")" || fail "harness failed: $out"
printf '%s' "$out" | jq -e --arg p "$REPO_ROOT/scripts/**" '.permission.external_directory[$p] == "deny"' >/dev/null \
  || fail "user rule for a plugin dir must win: $out"
out="$(run "$plugin" "$repo" '{"permission":{"external_directory":"ask"}}')" || fail "harness failed: $out"
printf '%s' "$out" | jq -e '.permission.external_directory == "ask"' >/dev/null \
  || fail "a global external_directory rule must be left alone: $out"

# hook without jq: no injection, a Spanish warning, no crash
nojq="$(mktemp -d)"
for b in git bash cat dirname env; do ln -s "$(command -v $b)" "$nojq/$b"; done
out="$(PATH="$nojq" run "$plugin" "$repo" 2>"$nojq/err")" || fail "harness failed without jq: $out"
printf '%s' "$out" | jq -e '.texts == ["hola"]' >/dev/null || fail "missing jq must not inject: $out"
grep -q "falta jq" "$nojq/err" || fail "missing jq must warn in Spanish: $(cat "$nojq/err")"

# loaded through a symlink (how it is installed): paths resolve to the real repo
link="$(mktemp -d)/agents-kit.js"
ln -s "$plugin" "$link"
out="$(run "$link" "$repo")" || fail "harness failed via symlink: $out"
printf '%s' "$out" | jq -e --arg s "$REPO_ROOT/skills" '.skills == [$s] and (.texts | length) == 2' >/dev/null \
  || fail "symlinked plugin must resolve the real plugin root: $out"

# V2 (opencode 2.x): default export with id, setup and the V1 server
run2() { "$NODE" --no-warnings "$TESTS_DIR/opencode_v2_harness.mjs" "$@"; }
v2repo="$(mk_repo)"
out="$(run2 "$plugin" "$v2repo")" || fail "v2 harness failed: $out"
printf '%s' "$out" | jq -e '.exports == ["id","server","setup"] and .hooks == ["session.context"]' >/dev/null \
  || fail "v2 export (no permission hook: an ask in V2 is always the user's rule): $out"
# kit skills added from disk without frontmatter; a user skill with the same id wins
printf '%s' "$out" | jq -e --arg s "$REPO_ROOT/skills" '([.skills[].id] | sort) == ["kit-off","kit-on","kit-plan","kit-run","kit-scout"]
  and (.skills[] | select(.id == "kit-on") | .path == "/user/kit-on/SKILL.md")
  and (.skills[] | select(.id == "kit-run") | .path == ($s + "/kit-run/SKILL.md") and (.description | startswith("Lleva"))
       and (.start | startswith("---") | not))' >/dev/null || fail "v2 skills: $out"
printf '%s' "$out" | jq -e '.system == ["base"]' >/dev/null || fail "v2 unmarked repo must not inject: $out"
# marked, from a subdir and through a symlink: rules on every model call, after the base system
echo '{}' > "$v2repo/.agents-kit.json"
mkdir -p "$v2repo/src"
out="$(run2 "$link" "$v2repo/src")" || fail "v2 harness failed: $out"
printf '%s' "$out" | jq -e --arg r "$REPO_ROOT/rules/testing.md" '(.system | length) == 2 and .system[0] == "base"
  and (.system[1] | contains("agents-kit está activo") and contains($r)) and .systemAgain == .system' >/dev/null \
  || fail "v2 marked repo must add the rules to every model call: $out"

echo ok
