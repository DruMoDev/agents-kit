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
printf '%s' "$out" | jq -e '.exports == ["id","server","setup"]
  and .hooks == ["session.context","tool.execute.after","tool.execute.before"]' >/dev/null \
  || fail "v2 export (no permission hook: an ask in V2 is always the user's rule): $out"
# kit skills added from disk without frontmatter; a user skill with the same id wins
printf '%s' "$out" | jq -e --arg s "$REPO_ROOT/skills" '([.skills[].id] | sort) == ["kit-off","kit-on","kit-plan","kit-reglas","kit-revisar","kit-run","kit-scout"]
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
# a tool.hook that fails to register does not take the rules down
out="$(HARNESS_TOOL_HOOK_FALLA=1 run2 "$plugin" "$v2repo" 2>/dev/null)" || fail "v2 harness con tool.hook roto: $out"
printf '%s' "$out" | jq -e '.hooks == ["session.context"] and (.system | length) == 2' >/dev/null \
  || fail "v2 con tool.hook roto sigue inyectando las reglas: $out"

# rule hooks around the edit tools (hooks/pre-edit and hooks/post-edit): V1 args use filePath, V2 input path;
# patch/apply_patch go as Codex's apply_patch
hrepo="$(mk_repo)"; hbin="$(mktemp -d)"
cat > "$hbin/lint" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$(dirname "$0")/log"
grep -q MALO "$@" && { echo "MALO en $*"; exit 1; }
exit 0
EOF
chmod +x "$hbin/lint"
mkdir -p "$hrepo/src"; echo 'export const a = 1;' > "$hrepo/src/a.ts"
ev1='[{"tool":"write","args":{"filePath":"src/b.ts","content":"const x = 1 as any"}},
  {"tool":"edit","args":{"filePath":"src/a.ts","oldString":"1","newString":"2"}},
  {"tool":"apply_patch","args":{"patchText":"*** Begin Patch\n*** Add File: eslint.config.mjs\n+x\n*** End Patch\n"}},
  {"tool":"read","args":{"filePath":"src/a.ts"}}]'
# without the marker: nothing runs
out="$(run "$plugin" "$hrepo" '{}' - "$ev1")" || fail "harness tools sin marcador: $out"
printf '%s' "$out" | jq -e '[.tools[] | .before == null and .output == "hecho"] | all' >/dev/null || fail "sin marcador las herramientas no se tocan: $out"
[ ! -s "$hbin/log" ] || fail "sin marcador no se lanza el lint"
printf '{"lint": {"fichero": {"ts": "%s"}}}\n' "$hbin/lint" > "$hrepo/.agents-kit.json"
out="$(run "$plugin" "$hrepo/src/.." '{}' - "$ev1")" || fail "harness tools: $out"
printf '%s' "$out" | jq -e '(.tools[0].before | contains("No desactives reglas ni tipos"))
  and .tools[1].before == null and .tools[1].output == "hecho"
  and (.tools[2].before | contains("eslint.config.mjs: Fichero de reglas"))
  and .tools[3].before == null and .tools[3].output == "hecho"' >/dev/null || fail "v1 pre-edit por herramienta: $out"
grep -qx './src/a.ts' "$hbin/log" || fail "v1 post-edit lanza el lint del fichero editado: $(cat "$hbin/log")"
echo 'export const a = "MALO";' > "$hrepo/src/a.ts"
out="$(run "$plugin" "$hrepo" '{}' - '[{"tool":"multiedit","args":{"filePath":"src/a.ts","edits":[{"oldString":"1","newString":"2"}]}}]')" \
  || fail "harness multiedit: $out"
printf '%s' "$out" | jq -e '.tools[0].before == null and (.tools[0].output | startswith("hecho\n\n") and contains("MALO en ./src/a.ts"))' >/dev/null \
  || fail "v1 post-edit con el lint roto añade el fallo a la salida: $out"
out="$(run2 "$plugin" "$hrepo" '[{"tool":"write","input":{"path":"src/b.ts","content":"// @ts-ignore"}},
  {"tool":"edit","input":{"path":"src/a.ts","oldString":"a","newString":"b"}},
  {"tool":"patch","input":{"patchText":"*** Begin Patch\n*** Update File: src/a.ts\n@@\n-export const a = \"MALO\";\n+export const a = x as any;\n*** End Patch\n"}}]')" \
  || fail "v2 harness tools: $out"
printf '%s' "$out" | jq -e '(.tools[0].before | contains("No desactives reglas"))
  and .tools[1].before == null and .tools[1].content[0] == "hecho" and (.tools[1].content[1] | contains("MALO en ./src/a.ts"))
  and (.tools[2].before | contains("src/a.ts: No desactives reglas"))' >/dev/null || fail "v2 pre-edit y post-edit por herramienta: $out"
# bash tool: hooks/pre-bash blocks skipping git hooks (V1 args and V2 input carry command)
out="$(run "$plugin" "$hrepo" '{}' - '[{"tool":"bash","args":{"command":"git commit --no-verify -m x"}},
  {"tool":"bash","args":{"command":"git status"}}]')" || fail "harness bash: $out"
printf '%s' "$out" | jq -e '(.tools[0].before | contains("No te saltes los hooks de git"))
  and .tools[1].before == null and .tools[1].output == "hecho"' >/dev/null || fail "v1 pre-bash en la herramienta bash: $out"
out="$(run2 "$plugin" "$hrepo" '[{"tool":"bash","input":{"command":"HUSKY=0 git push"}}]')" || fail "v2 harness bash: $out"
printf '%s' "$out" | jq -e '(.tools[0].before | contains("No te saltes los hooks de git"))' >/dev/null \
  || fail "v2 pre-bash en la herramienta bash: $out"

echo ok
