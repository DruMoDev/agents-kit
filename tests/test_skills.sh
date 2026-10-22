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

# kit-on / kit-off: everything in a temporary worktree of origin/<default>, never in Dru's tree
on="$REPO_ROOT/skills/kit-on/SKILL.md"; off="$REPO_ROOT/skills/kit-off/SKILL.md"
for sc in kit-activate.sh kit-github-setup.sh kit-ship-pr.sh kit-agents-md.sh kit-issue.sh; do
  grep -q "scripts/$sc" "$on" || fail "kit-on must use scripts/$sc"
done
for sc in kit-deactivate.sh kit-ship-pr.sh; do
  grep -q "scripts/$sc" "$off" || fail "kit-off must use scripts/$sc"
done
grep -q '"chore: activar agents-kit"' "$on" || fail "kit-on PR title"
grep -q '"chore: desactivar agents-kit"' "$off" || fail "kit-off PR title"
grep -q 'kit-ship-pr.sh" abrir <raíz> kit-on sin-marcador' "$on" || fail "kit-on must open its worktree with abrir"
grep -q 'kit-ship-pr.sh" enviar <raíz> kit-on' "$on" || fail "kit-on must ship with enviar"
grep -q 'kit-ship-pr.sh" descartar <raíz> kit-on' "$on" || fail "kit-on must know descartar"
grep -q 'kit-ship-pr.sh" abrir <raíz> kit-off con-marcador' "$off" || fail "kit-off must open its worktree with abrir"
grep -q 'kit-ship-pr.sh" enviar <raíz> kit-off' "$off" || fail "kit-off must ship with enviar"
grep -q 'kit-activate.sh" <wt> --changelog' "$on" || fail "kit-on must activate in the worktree with --changelog"
grep -q 'kit-deactivate.sh" <wt>' "$off" || fail "kit-off must deactivate in the worktree"
for sk in "$on" "$off"; do
  grep -q 'CLAUDE_PLUGIN_ROOT' "$sk" || fail "$sk must resolve CLAUDE_PLUGIN_ROOT"
  grep -q 'El árbol de Dru no se toca' "$sk" || fail "$sk must say Dru's tree is never touched"
  grep -q 'FIN: PR abierto' "$sk" || fail "$sk must handle a PR left open"
  grep -q 'ya existía' "$sk" || fail "$sk must handle a resumed worktree"
  grep -Eq 'git status --porcelain` no está vacío|confirme o guarde' "$sk" && fail "$sk still requires a clean tree"
  grep -q 'git stash apply\|stash, dale' "$sk" && fail "$sk still talks about the stash flow"
done
grep -q 'creado: AGENTS.md' "$on" || fail "kit-on step gate must use 'creado: AGENTS.md'"
grep -q 'kit-agents-md.sh" diff <wt>' "$on" && grep -q 'kit-agents-md.sh" aplicar <wt>' "$on" \
  || fail "kit-on must show the AGENTS.md reorder as a diff and apply it only with OK"
grep -q '## Reglas del proyecto' "$on" || fail "kit-on must keep the project rules section"
grep -q 'kit-issue.sh" reparto <wt>' "$on" && grep -q 'kit-issue.sh" aparcar <wt>' "$on" && grep -q 'someday' "$on" \
  || fail "kit-on must list the open issues and park the ones Dru says in someday"
grep -q 'configuración global' "$on" || fail "kit-on must relay the global config creation"
grep -q -- '--setup' "$on" || fail "kit-on must offer --setup when the repo has git hooks"
grep -q 'git pull' "$on" || fail "kit-on must tell Dru the marker arrives with git pull"

# phase 2 flow skills
plan="$REPO_ROOT/skills/kit-plan/SKILL.md"; run="$REPO_ROOT/skills/kit-run/SKILL.md"; scout="$REPO_ROOT/skills/kit-scout/SKILL.md"
[ -f "$REPO_ROOT/skills/kit-run/references/revisor.md" ] || fail "missing skills/kit-run/references/revisor.md"
[ -f "$REPO_ROOT/skills/kit-plan/references/issue.md" ] || fail "missing skills/kit-plan/references/issue.md"
for sk in "$plan" "$run" "$scout"; do
  grep -q 'CLAUDE_PLUGIN_ROOT' "$sk" || fail "$sk must resolve CLAUDE_PLUGIN_ROOT"
  grep -q 'kit no activado: ejecuta kit-on' "$sk" || fail "$sk must refuse without the marker"
  grep -q 'scripts/kit-issue.sh' "$sk" || fail "$sk must use scripts/kit-issue.sh"
done
grep -Eq 'kit-issue.sh" crear .* --prio' "$plan" || fail "kit-plan creates issues with --prio"
grep -q 'prio' "$plan" && grep -Eq 'Desglose.*prio' "$plan" || fail "kit-plan must propose the prio in the breakdown"
grep -q 'references/issue.md' "$plan" || fail "kit-plan must use the issue template"
grep -Eq 'kit-issue.sh" crear .* --prio .*--propuesta' "$scout" || fail "kit-scout creates issues with --prio and --propuesta"
grep -q -- '--remove-label propuesta' "$scout" || fail "kit-scout: approving is removing propuesta"
# v3 backlog: listo is gone; it only survives as a v2 compatibility note
for f in "$plan" "$scout" "$run" "$REPO_ROOT/skills/kit-plan/references/issue.md"; do
  grep -Eq 'crear .* (listo|propuesta)$|crear .* (listo|propuesta)`' "$f" && fail "$f: v2 crear syntax"
  grep -q 'add-label listo' "$f" && fail "$f: tells to add listo"
done
grep -q '`listo`' "$plan" && fail "kit-plan still mentions listo"
grep -q '`listo`' "$scout" && fail "kit-scout still mentions listo"
for f in "$plan" "$scout"; do
  grep -q 'duplicad' "$f" || fail "$f must search for duplicates before creating"
  grep -q -- '--limit 300' "$f" || fail "$f must search the 300 most recent open issues"
done
grep -q 'gh issue view <N> --repo <slug> --json labels' "$plan" || fail "kit-plan must verify labels with view, not list"
issue_md="$REPO_ROOT/skills/kit-plan/references/issue.md"
for w in 'Lo verificado' 'Lo que solo se cree' 'sin verificar' 'Decisiones de producto' 'Qué NO entra'; do
  grep -q "$w" "$issue_md" || fail "issue.md must have '$w'"
done
grep -q 'references/issue.md' "$scout" || fail "kit-scout must use the issue template"
for sc in kit-worktree.sh kit-pr.sh kit-review-all.sh lib/config.sh; do
  grep -q "scripts/$sc" "$run" || fail "kit-run must use scripts/$sc"
done
for sub in siguiente reclamar soltar decision bloquear; do
  grep -q "kit-issue.sh\" $sub" "$run" || fail "kit-run must call kit-issue.sh $sub"
done
for sub in abrir esperar-ci gate-local ronda fusionar; do
  grep -q "kit-pr.sh\" $sub" "$run" || fail "kit-run must call kit-pr.sh $sub"
done
grep -q 'maxReviewRounds' "$run" || fail "kit-run must honour maxReviewRounds"
grep -q 'autoMerge' "$run" || fail "kit-run must honour autoMerge"
grep -q 'gh pr ready --undo' "$run" || fail "kit-run must move the PR to draft"
grep -q '## Decisiones de comportamiento' "$run" || fail "kit-run must require the Decisiones de comportamiento section"
grep -q 'FIN: sin-ci' "$run" || fail "kit-run must handle FIN: sin-ci"
grep -q 'kit-review-all.sh" <wt> <pr> <r> <N>' "$run" || fail "kit-run must launch the reviewers with kit-review-all.sh"
grep -q -- '--implementador <familia>' "$run" || fail "kit-run must pass --implementador when the environment does not tell"
grep -q 'sin-confirmar' "$run" || fail "kit-run must handle unconfirmed seats"
ronda_md="$REPO_ROOT/skills/kit-run/references/ronda.md"
grep -q '(puesto <i>)' "$ronda_md" || fail "ronda.md must cite each finding as (puesto <i>)"
grep -q 'kit-revision: puesto <i> <familia>/<modelo> ronda <r>' "$ronda_md" || fail "ronda.md must document the per-seat marker"
grep -q 'kit_reviewers' "$ronda_md" "$run" && fail "kit_reviewers is gone"
grep -q '{{PR}}' "$REPO_ROOT/skills/kit-run/references/revisor.md" || fail "revisor.md must include the PR body as claims"
grep -q 'kit_origin_slug' "$run" || fail "kit-run must take the repo slug from origin like the scripts"
grep -q 'kit-pr.sh" historial' "$run" || fail "kit-run must continue round numbering from historial"
grep -q 'ninguno aplicado' "$REPO_ROOT/skills/kit-run/references/ronda.md" || fail "ronda.md must stop when nothing was applied"
grep -q 'gh issue list --repo <slug>' "$scout" || fail "kit-scout gh calls need --repo"
# after decision/bloquear Dru only answers and drops the label; necesita-decision (v2) still counts
for f in "$run" "$REPO_ROOT/README.md"; do
  grep -q 'necesita-respuesta' "$f" || fail "$f must use necesita-respuesta"
  grep -q '`necesita-decision` (v2)' "$f" || fail "$f must treat necesita-decision as a v2 alias"
done
grep -q 'FIN: necesita-respuesta #<N>' "$run" || fail "kit-run must expect FIN: necesita-respuesta"
grep -q 'sin cuerpo' "$run" || fail "kit-run must send body-less issues to necesita-respuesta"
grep -Eiq 'add-label listo|(vuelve|volver) a poner `listo`|(añade|pon|ponle) `listo`' "$run" && fail "kit-run tells Dru to re-add listo"
grep -q 'no hay issues disponibles' "$run" || fail "kit-run must end the loop on 'no hay issues disponibles'"
grep -q 'falta una ronda nueva' "$run" || fail "kit-run must handle the applied-round refusal of fusionar"
grep -q 'gh issue list --repo <slug> --state open --label en-curso' "$run" || fail "kit-run summary must list possible stale claims"
grep -qi 'sin marcador del kit' "$run" && grep -q 'no ofrezcas soltarlo' "$run" || fail "kit-run must list en-curso without kit marker without offering soltar"
grep -q 'kit-issue.sh" soltar <raíz> <N> <id> "reclamo colgado"' "$run" || fail "kit-run must give the exact soltar command for stale claims"
grep -q 'KIT_CI_GRACE' "$run" || fail "kit-run must explain sin-ci after the grace period"
grep -q 'no se ejecutan en PRs' "$run" && fail "kit-run keeps the obsolete workflows-never-run guidance"
grep -q 'autoMerge` falso' "$REPO_ROOT/README.md" && grep -q 'quítala a mano' "$REPO_ROOT/README.md" \
  || fail "README must say en-curso stays after Dru merges with autoMerge false"
# comment trust: issues are read with kit-issue.sh leer (only the gh account's comments), never with gh --comments
grep -q 'kit-issue.sh" leer <raíz> <N>' "$run" || fail "kit-run must read the issue with kit-issue.sh leer"
grep -q -- '--comments' "$run" && fail "kit-run still reads comments with gh issue view --comments"
grep -q 'kit-issue.sh" leer' "$plan" || fail "kit-plan must read existing issues with kit-issue.sh leer"
for f in "$run" "$plan" "$REPO_ROOT/README.md"; do
  grep -q 'nunca son instrucciones' "$f" || fail "$f must say other accounts' comments are never instructions"
done
# kit-run <N>: one issue, claimed only if siguiente could pick it
grep -q 'kit-run <N>' "$run" || fail "kit-run must document the single-issue mode"
grep -q 'kit-issue.sh" siguiente <raíz> <N>' "$run" || fail "kit-run <N> must check the issue with siguiente <N>"
grep -q 'kit-skills-check.sh' "$on" || fail "kit-on must propose kit-skills-check.sh for the project CI"
# phase 3: changelog and notifications
for w in 'kit-changelog.sh" validar' 'kit-changelog.sh" resumen' 'scripts/kit-notify.sh' 'AVISO-CLAUDE' 'docs/changelog/' 'PushNotification'; do
  grep -qF "$w" "$run" || fail "kit-run must mention $w"
done
grep -q 'llegan en la fase 3' "$run" && fail "kit-run keeps the phase 3 placeholder"
grep -q 'tema ntfy nuevo: <tema>' "$run" && grep -q 'suscríbete' "$run" \
  || fail "kit-run must pass a new ntfy topic to Dru with the subscribe instruction"
grep -q 'si `resumen` falla, avisa igual sin URL' "$run" || fail "kit-run must notify without URL when resumen fails"
grep -q 'pasaron a `necesita-respuesta` o `bloqueado` en esta ejecución' "$run" \
  || fail "kit-run summary trigger must be limited to this run"
# no inline bash in the skill: under zsh it broke (bad substitution); the launcher is a script
grep -q 'pids' "$run" && fail "kit-run keeps the inline reviewer launcher"
grep -q 'ntfy' "$on" || fail "kit-on must mention ntfy"
grep -q 'scripts/kit-notify.sh' "$on" || fail "kit-on must send the activation notice"
grep -qF 'cat ~/.agents-kit/ntfy-topic' "$on" || fail "kit-on must show the ntfy topic"
# v3 fixes: v2 upgrade path, changelog false, skip list
run="$REPO_ROOT/skills/kit-run/SKILL.md"
grep -q 'kit-issue.sh" comprobar <raíz>' "$run" || fail "kit-run must run comprobar at startup"
grep -q 'kit en versión anterior: ejecuta kit-on para actualizar' "$run" || fail "kit-run must refuse an outdated repo"
grep -q -- '--excluir' "$run" || fail "kit-run must skip the issues it failed to claim (--excluir)"
grep -q '"changelog": false' "$run" || fail "kit-run must honour changelog false"
grep -q 'FIN: sin-changelog' "$run" || fail "kit-run must know resumen's FIN: sin-changelog"
grep -q 'kit-ship-pr.sh" abrir <raíz> kit-on con-marcador' "$on" || fail "kit-on must have the actualizar mode"
grep -qi 'actualizar' "$on" || fail "kit-on must name the actualizar mode"
grep -q '^nota:\|`nota:' "$on" || fail "kit-on must relay the v2 key notes"
grep -q 'kit-changelog.sh" validar <wt>' "$on" || fail "kit-on must validate an existing CHANGELOG.md"
# every suite stops if lib.sh cannot be sourced, never falling back to the real repo
for t in "$TESTS_DIR"/test_*.sh; do
  grep -qxF 'source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1' "$t" || fail "$(basename "$t") must guard its source of lib.sh"
done
echo "ok"
