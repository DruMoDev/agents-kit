#!/usr/bin/env bash
# Usage: scripts/release.sh <semver>
# Writes the version into both plugin manifests and the Claude marketplace entry.
set -euo pipefail

v="${1:-}"
if ! [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "usage: $0 <semver>  (e.g. 2.1.0)" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

update() { # file jq-filter
  local tmp
  tmp="$(mktemp)"
  jq --arg v "$v" "$2" "$1" > "$tmp" && mv "$tmp" "$1"
}

update "$root/.claude-plugin/plugin.json" '.version = $v'
update "$root/.codex-plugin/plugin.json" '.version = $v'
update "$root/.claude-plugin/marketplace.json" '(.plugins[] | select(.name == "agents-kit") | .version) = $v'
# skills that compare their version with the scripts' (kit-issue.sh comprobar prints "kit: <version>")
for f in "$root"/skills/*/SKILL.md; do
  grep -q '^Versión de esta skill: ' "$f" || continue
  V="$v" perl -pi -e 's/^(Versión de esta skill: )[0-9][0-9A-Za-z.+-]*?\.(\s|$)/$1$ENV{V}.$2/' "$f"
done
echo "version set to $v"
