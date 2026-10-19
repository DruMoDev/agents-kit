#!/usr/bin/env bash
# Shared helpers for tests/test_*.sh. Source this file.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

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
