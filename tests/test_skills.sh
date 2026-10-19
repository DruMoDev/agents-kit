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
  grep -Ewq '(él|ella)' "$f" && fail "$dir: gendered wording (él/ella)"
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
grep -q 'git ls-files --error-unmatch .agents-kit.json' "$on" || fail "kit-on must detect an uncommitted marker (interrupted run)"
grep -q 'git ls-files --error-unmatch .agents-kit.json' "$off" || fail "kit-off must detect an interrupted run"
grep -q 'rama `kit-on`' "$on" || fail "kit-on must mention a leftover kit-on branch"
grep -q 'rama `kit-off`' "$off" || fail "kit-off must mention a leftover kit-off branch"
for pth in .agents-kit.json CHANGELOG.md AGENTS.md CLAUDE.md .agents/ .claude/; do
  grep -qF "\`$pth\`" "$on" || fail "kit-on resume guard must list $pth"
done
grep -q 'no relacionad' "$on" || fail "kit-on must stop on unrelated changes when resuming"
grep -q 'creado: AGENTS.md' "$on" || fail "kit-on step 4 gate must use 'creado: AGENTS.md'"
grep -q 'borrado del marcador pendiente' "$off" || fail "kit-off must report dirty tree + pending marker deletion"
for sk in "$on" "$off"; do
  grep -q 'sin el prefijo `origin/`' "$sk" || fail "$sk: falta aclarar que la rama por defecto va sin origin/"
done
grep -q 'interrumpida: haz solo la comprobación de al día' "$off" || fail "kit-off retomado debe comprobar al día"
echo "ok"
