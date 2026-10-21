#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1

# Value of a frontmatter key (first --- block) in a SKILL.md.
fm() { awk -v k="$2" 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} NR>1&&index($0,k": ")==1{print substr($0,length(k)+3); exit}' "$1"; }

for s in kit-on kit-off kit-plan kit-run kit-scout; do
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
[ "$n" -ge 5 ] || fail "expected at least 5 skills, found $n"

# references follow the same writing rules
for f in "$REPO_ROOT"/skills/*/references/*.md; do
  [ -f "$f" ] || continue
  grep -q "—" "$f" && fail "$f: em dash found"
  grep -Ewq '(él|ella)' "$f" && fail "$f: gendered wording (él/ella)"
  grep -Eq '\| *(head|tail)\b' "$f" && fail "$f: pipes output through head/tail"
done

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
for sk in "$on" "$off"; do
  grep -q 'el árbol NO quedó limpio' "$sk" || fail "$sk: debe retransmitir el estado real del árbol"
  grep -q 'a salvo ahí y el árbol quedó limpio' "$sk" && fail "$sk: afirma árbol limpio sin condición"
done

# phase 2 flow skills
plan="$REPO_ROOT/skills/kit-plan/SKILL.md"; run="$REPO_ROOT/skills/kit-run/SKILL.md"; scout="$REPO_ROOT/skills/kit-scout/SKILL.md"
[ -f "$REPO_ROOT/skills/kit-run/references/revisor.md" ] || fail "missing skills/kit-run/references/revisor.md"
[ -f "$REPO_ROOT/skills/kit-plan/references/issue.md" ] || fail "missing skills/kit-plan/references/issue.md"
for sk in "$plan" "$run" "$scout"; do
  grep -q 'CLAUDE_PLUGIN_ROOT' "$sk" || fail "$sk must resolve CLAUDE_PLUGIN_ROOT"
  grep -q 'kit no activado: ejecuta kit-on' "$sk" || fail "$sk must refuse without the marker"
  grep -q 'scripts/kit-issue.sh' "$sk" || fail "$sk must use scripts/kit-issue.sh"
done
grep -Eq 'kit-issue.sh" crear .* listo' "$plan" || fail "kit-plan creates issues as listo"
grep -q 'references/issue.md' "$plan" || fail "kit-plan must use the issue template"
grep -Eq 'kit-issue.sh" crear .* propuesta' "$scout" || fail "kit-scout creates issues as propuesta"
grep -Eq 'crear .* listo' "$scout" && fail "kit-scout must never create listo issues"
grep -q 'references/issue.md' "$scout" || fail "kit-scout must use the issue template"
for sc in kit-worktree.sh kit-pr.sh kit-review.sh lib/config.sh; do
  grep -q "scripts/$sc" "$run" || fail "kit-run must use scripts/$sc"
done
for sub in siguiente reclamar soltar decision bloquear; do
  grep -q "kit-issue.sh\" $sub" "$run" || fail "kit-run must call kit-issue.sh $sub"
done
for sub in abrir esperar-ci gate-local ronda fusionar; do
  grep -q "kit-pr.sh\" $sub" "$run" || fail "kit-run must call kit-pr.sh $sub"
done
grep -q 'kit_reviewers' "$run" || fail "kit-run must read reviewers with kit_reviewers"
grep -q 'maxReviewRounds' "$run" || fail "kit-run must honour maxReviewRounds"
grep -q 'autoMerge' "$run" || fail "kit-run must honour autoMerge"
grep -q 'gh pr ready --undo' "$run" || fail "kit-run must move the PR to draft"
grep -q '## Decisiones de comportamiento' "$run" || fail "kit-run must require the Decisiones de comportamiento section"
grep -q 'FIN: sin-ci' "$run" || fail "kit-run must handle FIN: sin-ci"
grep -q 'kit-review.sh" .*&$' "$run" || fail "kit-run must launch each reviewer as a background job"
grep -q 'wait "${pids\[' "$run" || fail "kit-run must wait for each reviewer PID"
grep -q 'kit_origin_slug' "$run" || fail "kit-run must take the repo slug from origin like the scripts"
grep -q 'kit-pr.sh" historial' "$run" || fail "kit-run must continue round numbering from historial"
grep -q 'ninguno aplicado' "$REPO_ROOT/skills/kit-run/references/ronda.md" || fail "ronda.md must stop when nothing was applied"
grep -q 'gh issue list --repo <slug>' "$scout" || fail "kit-scout gh calls need --repo"
# after decision/bloquear Dru only answers and drops the label: listo stays on the issue
for f in "$run" "$REPO_ROOT/README.md"; do
  grep -q '`listo` sigue puesto, no hay que volver a ponerlo' "$f" || fail "$f must say listo stays after decision/bloquear"
done
grep -Eiq 'add-label listo|(vuelve|volver) a poner `listo`|(añade|pon|ponle) `listo`' "$run" && fail "kit-run tells Dru to re-add listo"
grep -q 'falta una ronda nueva' "$run" || fail "kit-run must handle the applied-round refusal of fusionar"
grep -q 'listo --label en-curso' "$run" || fail "kit-run summary must list possible stale claims"
grep -q 'kit-issue.sh" soltar <raíz> <N> <id> "reclamo colgado"' "$run" || fail "kit-run must give the exact soltar command for stale claims"
grep -q 'KIT_CI_GRACE' "$run" || fail "kit-run must explain sin-ci after the grace period"
grep -q 'no se ejecutan en PRs' "$run" && fail "kit-run keeps the obsolete workflows-never-run guidance"
grep -q 'autoMerge` falso' "$REPO_ROOT/README.md" && grep -q 'quítalas a mano' "$REPO_ROOT/README.md" \
  || fail "README must say labels stay after Dru merges with autoMerge false"
# phase 3: changelog and notifications
for w in 'kit-changelog.sh" validar' 'kit-changelog.sh" resumen' 'scripts/kit-notify.sh' 'AVISO-CLAUDE' 'docs/changelog/' 'PushNotification'; do
  grep -qF "$w" "$run" || fail "kit-run must mention $w"
done
grep -q 'llegan en la fase 3' "$run" && fail "kit-run keeps the phase 3 placeholder"
grep -q 'tema ntfy nuevo: <tema>' "$run" && grep -q 'suscríbete' "$run" \
  || fail "kit-run must pass a new ntfy topic to Dru with the subscribe instruction"
grep -q 'si `resumen` falla, avisa igual sin URL' "$run" || fail "kit-run must notify without URL when resumen fails"
grep -q 'pasaron a `necesita-decision` o `bloqueado` en esta ejecución' "$run" \
  || fail "kit-run summary trigger must be limited to this run"
# the reviewer launcher uses bash syntax: it must run under bash whatever the agent's shell is (zsh breaks it)
grep -qx "   bash <<'EOS'" "$run" && grep -qx '   EOS' "$run" || fail "kit-run reviewer launcher must run under bash"
grep -q 'ntfy' "$on" || fail "kit-on must mention ntfy"
grep -q 'scripts/kit-notify.sh' "$on" || fail "kit-on must send the activation notice"
grep -qF 'cat ~/.agents-kit/ntfy-topic' "$on" || fail "kit-on must show the ntfy topic"
# every suite stops if lib.sh cannot be sourced, never falling back to the real repo
for t in "$TESTS_DIR"/test_*.sh; do
  grep -qxF 'source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1' "$t" || fail "$(basename "$t") must guard its source of lib.sh"
done
echo "ok"
