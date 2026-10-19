#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar -C "$REPO_ROOT" --exclude=.git -cf - . | tar -C "$tmp" -xf -

(cd "$tmp" && bash scripts/release.sh 2.1.0) || fail "release.sh 2.1.0 should succeed"

for f in .claude-plugin/plugin.json .codex-plugin/plugin.json; do
  jq -e . "$tmp/$f" >/dev/null || fail "$f is not valid JSON"
  [ "$(jq -r .version "$tmp/$f")" = "2.1.0" ] || fail "$f version != 2.1.0"
done
jq -e . "$tmp/.claude-plugin/marketplace.json" >/dev/null || fail "marketplace.json invalid"
[ "$(jq -r '.plugins[] | select(.name=="agents-kit") | .version' "$tmp/.claude-plugin/marketplace.json")" = "2.1.0" ] \
  || fail "marketplace entry version != 2.1.0"

if (cd "$tmp" && bash scripts/release.sh foo 2>/dev/null); then fail "release.sh foo should fail"; fi
(cd "$tmp" && bash scripts/release.sh foo >/dev/null 2>&1); [ $? -eq 1 ] || fail "release.sh foo should exit 1"
echo "ok"
