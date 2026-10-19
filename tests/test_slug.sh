#!/usr/bin/env bash
# Table-driven tests for scripts/lib/github-slug.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
source "$REPO_ROOT/scripts/lib/github-slug.sh"

check() { # url expected ("" = rejected)
  local got; got="$(kit_parse_github_url "$1")"
  [ "$got" = "$2" ] || fail "parse '$1': got '$got', esperado '$2'"
}
check https://github.com/o/r o/r
check https://github.com/o/r.git o/r
check https://github.com/o/r/ o/r
check https://github.com/o/r.git/ o/r
check https://user:tok@github.com/o/r.git o/r
check https://GitHub.COM/o/r o/r
check https://github.com:443/o/r o/r
check git@github.com:o/r.git o/r
check git@github.com:o/r o/r
check git@GITHUB.com:o/r.git/ o/r
check ssh://git@github.com/o/r.git o/r
check ssh://git@github.com:22/o/r.git o/r
check ssh://git@GitHub.com:22/o/r.git/ o/r
check https://github.com.evil.com/o/r ""
check https://evilgithub.com/o/r ""
check https://github.com@evil.com/o/r ""
check git@github.com.evil.com:o/r.git ""
check git@notgithub.com:o/r.git ""
check ssh://git@github.com.evil.com:22/o/r ""
check https://example.com/github.com/o/r ""
check https://github.com/o ""
check https://github.com/o/r/extra ""
check "" ""
check o/r ""

# insteadOf alias: raw url does not parse, resolved one does
r="$(mk_repo)"
(cd "$r" && git remote add origin gh:o/r.git && git config url.https://github.com/.insteadOf gh:) || fail "setup alias"
got="$(cd "$r" && kit_origin_slug)"
[ "$got" = o/r ] || fail "insteadOf: got '$got'"
(cd "$r" && git remote set-url origin https://example.com/o/r.git)
got="$(cd "$r" && kit_origin_slug)"
[ -z "$got" ] || fail "no GitHub: got '$got'"

echo "OK test_slug"
