#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Value of a frontmatter key (first --- block) in a SKILL.md.
fm() { awk -v k="$2" 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} NR>1&&index($0,k": ")==1{print substr($0,length(k)+3); exit}' "$1"; }

for s in kit-on kit-off; do
  [ -f "$REPO_ROOT/skills/$s/SKILL.md" ] || fail "missing skills/$s/SKILL.md"
done

n=0
for f in "$REPO_ROOT"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  dir="$(basename "$(dirname "$f")")"
  [ "$(head -n 1 "$f")" = "---" ] || fail "$dir: SKILL.md must start with frontmatter"
  [ "$(fm "$f" name)" = "$dir" ] || fail "$dir: name '$(fm "$f" name)' != folder name"
  d="$(fm "$f" description)"
  [ -n "$d" ] || fail "$dir: empty description"
  len="$(printf '%s' "$d" | wc -m | tr -d ' ')"
  [ "$len" -le 200 ] || fail "$dir: description has $len chars (> 200)"
  grep -q "—" "$f" && fail "$dir: em dash found"
  grep -Eq '\| *(head|tail)\b' "$f" && fail "$dir: pipes output through head/tail"
  for sc in $(grep -oE 'scripts/[A-Za-z0-9_.-]+' "$f" | sort -u); do
    [ -x "$REPO_ROOT/$sc" ] || fail "$dir: names $sc, which does not exist or is not executable"
  done
  n=$((n + 1))
done
[ "$n" -ge 2 ] || fail "expected at least 2 skills, found $n"

# kit-on / kit-off specifics from the brief
on="$REPO_ROOT/skills/kit-on/SKILL.md"; off="$REPO_ROOT/skills/kit-off/SKILL.md"
for sc in kit-activate.sh kit-github-setup.sh kit-ship-pr.sh; do
  grep -q "scripts/$sc" "$on" || fail "kit-on must use scripts/$sc"
done
for sc in kit-deactivate.sh kit-ship-pr.sh; do
  grep -q "scripts/$sc" "$off" || fail "kit-off must use scripts/$sc"
done
grep -q '"chore: activar agents-kit"' "$on" || fail "kit-on PR title"
grep -q '"chore: desactivar agents-kit"' "$off" || fail "kit-off PR title"
grep -q 'CLAUDE_PLUGIN_ROOT' "$on" || fail "kit-on must resolve CLAUDE_PLUGIN_ROOT"
grep -q 'CLAUDE_PLUGIN_ROOT' "$off" || fail "kit-off must resolve CLAUDE_PLUGIN_ROOT"
grep -q 'git status --porcelain' "$on" || fail "kit-on must define dirty tree"
grep -q 'git status --porcelain' "$off" || fail "kit-off must define dirty tree"
echo "ok"
