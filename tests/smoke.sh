#!/usr/bin/env bash
set -euo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="node $KIT/bin/cli.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# 1. init --framework next on an empty project
cd "$TMP" && mkdir p1 && cd p1
$CLI init --framework next >out.txt
[ -f docs/agent/base.md ] || fail "base.md missing"
[ -f docs/agent/nextjs.md ] || fail "nextjs.md missing"
[ -f docs/agent/testing.md ] || fail "testing.md missing"
[ -f docs/agent/docs-discipline.md ] || fail "docs-discipline.md missing"
grep -q '^@docs/agent/base.md' AGENTS.md || fail "AGENTS.md missing base import"
grep -q '^@docs/agent/nextjs.md' AGENTS.md || fail "AGENTS.md missing framework import"
grep -q '^## Project' AGENTS.md || fail "AGENTS.md missing Project section"
[ "$(cat CLAUDE.md)" = "@AGENTS.md" ] || fail "CLAUDE.md shim wrong"
grep -q 'vercel-react-best-practices' out.txt || fail "next skill recommendations not logged"
grep -q 'mcp next-devtools' out.txt || fail "next MCP recommendations not logged"

# 2. re-running init changes nothing (idempotent)
sum_before=$(find . -type f ! -name out.txt -exec shasum {} + | sort | shasum)
$CLI init --framework next >/dev/null
sum_after=$(find . -type f ! -name out.txt -exec shasum {} + | sort | shasum)
[ "$sum_before" = "$sum_after" ] || fail "re-run not idempotent"

# 3. generic installs no framework file and leaks no placeholder
cd "$TMP" && mkdir p2 && cd p2
$CLI init --framework generic >/dev/null
[ ! -f docs/agent/nextjs.md ] || fail "generic must not install a framework file"
grep -q '{{FRAMEWORK_IMPORT}}' AGENTS.md && fail "placeholder leaked into AGENTS.md" || true

# 4. pre-existing AGENTS.md / CLAUDE.md: user content preserved, kit lines added
cd "$TMP" && mkdir p3 && cd p3
printf '# My project\nMy content\n' > AGENTS.md
printf '# Old claude notes\n' > CLAUDE.md
$CLI init --framework astro >/dev/null
grep -q 'My content' AGENTS.md || fail "user AGENTS.md content lost"
head -1 AGENTS.md | grep -q 'Mandatory reading' || fail "header not prepended to AGENTS.md"
grep -q '^@AGENTS.md' CLAUDE.md || fail "@AGENTS.md line not added to CLAUDE.md"
grep -q 'Old claude notes' CLAUDE.md || fail "user CLAUDE.md content lost"

# 5. update overwrites kit-owned edits and auto-detects the framework
cd "$TMP/p1"
echo 'LOCAL EDIT' >> docs/agent/base.md
$CLI update >upd.txt
grep -q 'LOCAL EDIT' docs/agent/base.md && fail "update did not overwrite base.md" || true
grep -q 'Framework: next' upd.txt || fail "update framework detection failed"
grep -q 'My content' "$TMP/p3/AGENTS.md" || fail "sanity: p3 user content"

# 6. mcp command: dual-write to .mcp.json + opencode.json, merge, idempotent
cd "$TMP/p1"
printf '{ "mcp": { "custom": { "type": "remote", "url": "https://example.com" } } }\n' > opencode.json
$CLI mcp next-devtools playwright supabase --project-ref testref >/dev/null
node -e "
const fs = require('fs');
const c = JSON.parse(fs.readFileSync('.mcp.json', 'utf8'));
const o = JSON.parse(fs.readFileSync('opencode.json', 'utf8'));
if (c.mcpServers['next-devtools'].args.join(' ') !== '-y next-devtools-mcp@latest') throw 'claude next-devtools wrong';
if (c.mcpServers.playwright.command !== 'npx') throw 'claude playwright wrong';
if (c.mcpServers.supabase.url !== 'https://mcp.supabase.com/mcp?project_ref=testref') throw 'claude supabase ref wrong';
if (o.mcp['next-devtools'].type !== 'local') throw 'opencode next-devtools wrong';
if (o.mcp.supabase.type !== 'remote') throw 'opencode supabase wrong';
if (o.mcp.custom.url !== 'https://example.com') throw 'existing opencode entry lost';
" || fail "mcp configs wrong"
before=$(shasum .mcp.json opencode.json)
$CLI mcp next-devtools playwright supabase --project-ref testref >/dev/null
after=$(shasum .mcp.json opencode.json)
[ "$before" = "$after" ] || fail "mcp re-run not idempotent"

echo "ALL SMOKE TESTS PASSED"
