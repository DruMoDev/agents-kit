#!/usr/bin/env bash
# Shared helpers for tests/test_*.sh. Source this file.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
# Global config never comes from the real ~/.agents-kit: a fresh path that does not exist (plugin defaults).
export KIT_CONFIG="$(mktemp -d)/config.json"
# Where kit_config remembers the warnings it already printed: fresh per test file.
export KIT_AVISOS_DIR="$(mktemp -d)"

# set_global <json>: write the global config read by kit_config.
set_global() {
  printf '%s\n' "$1" > "$KIT_CONFIG"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Create a temporary git repo with an initial commit on main; print its path.
mk_repo() {
  local d
  d="$(mktemp -d)"
  (
    cd "$d" || exit 1
    git init -q -b main
    git config user.name "Test"
    git config user.email "test@example.com"
    git config commit.gpgsign false
    echo "# test" > README.md
    git add README.md
    git commit -q -m "initial commit"
  ) || fail "mk_repo failed"
  echo "$d"
}

# Prepend tests/stubs to PATH so `gh` resolves to the stub.
# The stub logs each call to $GH_LOG and replies according to $GH_STUB_MODE.
use_gh_stub() {
  export PATH="$TESTS_DIR/stubs:$PATH"
  export GH_LOG="${GH_LOG:-$(mktemp)}"
  export GH_STUB_MODE="${GH_STUB_MODE:-ok}"
}

# Use the stateful gh stub (tests/stubs/flow/gh): fresh $GH_STATE/state.json and $GH_LOG.
use_flow_gh() {
  export PATH="$TESTS_DIR/stubs/flow:$PATH"
  export GH_STATE="$(mktemp -d)"
  export GH_LOG="$(mktemp)"
  unset GH_FAIL_ON
  echo '{"issues":[],"prs":[]}' > "$GH_STATE/state.json"
}

# flow_add_issue <number> <title> [label...]: seed an open issue in the stub state.
flow_add_issue() {
  local n="$1" t="$2"; shift 2
  local tmp; tmp="$(mktemp)"
  # FLOW_AUTHOR sets the issue author (default: the gh user, filled in by the stub); FLOW_BODY its body
  jq --argjson n "$n" --arg t "$t" --arg a "${FLOW_AUTHOR:-}" --arg b "${FLOW_BODY:-}" '.issues += [{number: $n, title: $t, body: $b, state: "OPEN",
      labels: [$ARGS.positional[] | {name: .}], assignees: [], comments: []}
      + (if $a == "" then {} else {author: {login: $a}} end)]' --args "$@" \
    < "$GH_STATE/state.json" > "$tmp" && mv "$tmp" "$GH_STATE/state.json" || fail "flow_add_issue"
}

# flow_add_comment <number> <body>: append a comment to an issue in the stub state.
# FLOW_AUTHOR sets the comment author (default: the gh user, filled in by the stub).
flow_add_comment() {
  local tmp; tmp="$(mktemp)"
  jq --argjson n "$1" --arg b "$2" --arg a "${FLOW_AUTHOR:-}" '(.issues[] | select(.number == $n) | .comments) |= . + [{id: "IC_seed\(length)", body: $b}
      + (if $a == "" then {} else {author: {login: $a}} end)]' \
    "$GH_STATE/state.json" > "$tmp" && mv "$tmp" "$GH_STATE/state.json" || fail "flow_add_comment"
}

# flow_issue <number> <jq-filter>: query one issue of the stub state.
flow_issue() {
  jq -r --argjson n "$1" ".issues[] | select(.number == \$n) | $2" "$GH_STATE/state.json"
}
