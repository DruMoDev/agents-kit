#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1

hook="$REPO_ROOT/hooks/session-start"
[ -x "$hook" ] || fail "hooks/session-start missing or not executable"
jq -e '.hooks.SessionStart[0].matcher == "startup|resume|clear|compact|fork"' "$REPO_ROOT/hooks/hooks.json" >/dev/null \
  || fail "hooks/hooks.json missing or wrong matcher"

# run_hook <hook> <cwd> <stdin-json|-> : prints stdout; exit status in $RC_FILE
RC_FILE="$(mktemp)"
run_hook() {
  local h="$1" cwd="$2" input="$3"
  if [ "$input" = "-" ]; then
    (cd "$cwd" && "$h" </dev/null)
  else
    (cd "$cwd" && printf '%s' "$input" | "$h")
  fi
  echo $? > "$RC_FILE"
}
rc() { cat "$RC_FILE"; }

repo="$(mk_repo)"
nogit="$(mktemp -d)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

# repo without marker: inert
out="$(run_hook "$hook" "$repo" "{\"cwd\":\"$repo\"}")"
[ "$(rc)" -eq 0 ] && [ -z "$out" ] || fail "repo without marker must be silent (rc=$(rc) out=$out)"

# outside git: inert
out="$(run_hook "$hook" "$nogit" "{\"cwd\":\"$nogit\"}")"
[ "$(rc)" -eq 0 ] && [ -z "$out" ] || fail "non-git dir must be silent (rc=$(rc) out=$out)"

# repo with marker, cwd = subdir
echo '{}' > "$repo/.agents-kit.json"
mkdir -p "$repo/src"
check_json() {
  printf '%s' "$1" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"
    and (.hookSpecificOutput.additionalContext | contains("## Escribe menos código"))
    and (.hookSpecificOutput.additionalContext | contains("rules/testing.md"))
    and (.hookSpecificOutput.additionalContext | contains("rules/docs-discipline.md"))' >/dev/null \
    || fail "$2: invalid output: $1"
}
out="$(run_hook "$hook" "$repo/src" "{\"cwd\":\"$repo/src\"}")"
[ "$(rc)" -eq 0 ] || fail "marker case rc=$(rc)"
check_json "$out" "with CLAUDE_PLUGIN_ROOT"

# same without CLAUDE_PLUGIN_ROOT (root resolved from $0)
out="$(unset CLAUDE_PLUGIN_ROOT; run_hook "$hook" "$repo/src" "{\"cwd\":\"$repo/src\"}")"
check_json "$out" "without CLAUDE_PLUGIN_ROOT"

# empty stdin: falls back to $PWD, does not block
out="$(run_hook "$hook" "$repo/src" -)"
check_json "$out" "empty stdin"

# malformed stdin: falls back to $PWD
out="$(run_hook "$hook" "$repo/src" "not json{")"
[ "$(rc)" -eq 0 ] || fail "malformed stdin rc=$(rc)"
check_json "$out" "malformed stdin"

# flags of the marker: the kit flow section by default, the repo's own with "flujo": false, nothing with "reglas": false
ctx() { run_hook "$hook" "$repo" "{\"cwd\":\"$repo\"}" | jq -r '.hookSpecificOutput.additionalContext'; }
c="$(ctx)"
case "$c" in *"## Flujo del kit: issues y PR"*) ;; *) fail "default marker must carry the kit flow";; esac
case "$c" in *"## Flujo del repo"*) fail "default marker must not carry sin-flujo";; esac
echo '{"flujo": false}' > "$repo/.agents-kit.json"
c="$(ctx)"
case "$c" in *"## Escribe menos código"*"## Flujo del repo (el del kit está desactivado)"*"kit-revisar"*) ;;
  *) fail "flujo false must carry the core rules and sin-flujo: $c";; esac
case "$c" in *"por PR con squash merge"*) fail "flujo false must not say code goes through the kit's PRs";; esac
echo '{"reglas": false}' > "$repo/.agents-kit.json"
out="$(run_hook "$hook" "$repo" "{\"cwd\":\"$repo\"}")"
[ "$(rc)" -eq 0 ] && [ -z "$out" ] || fail "reglas false must be silent (rc=$(rc) out=$out)"
echo 'no es json' > "$repo/.agents-kit.json"
case "$(ctx)" in *"## Flujo del kit: issues y PR"*) ;; *) fail "an unreadable marker counts as the defaults";; esac
echo '{}' > "$repo/.agents-kit.json"

# core.md with quotes, backslashes and tabs (temporary plugin copy)
tmp="$(mktemp -d)"
mkdir "$tmp/hooks" "$tmp/rules"
cp "$hook" "$tmp/hooks/"
cp "$REPO_ROOT"/rules/*.md "$tmp/rules/"
printf '## Escribe menos código\nquote " backslash \\ tab\there \\n literal\n' > "$tmp/rules/core.md"
out="$(unset CLAUDE_PLUGIN_ROOT; run_hook "$tmp/hooks/session-start" "$repo" "{\"cwd\":\"$repo\"}")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("quote \" backslash \\ tab\there \\n literal")' >/dev/null \
  || fail "special characters not preserved: $out"
echo "ok"
