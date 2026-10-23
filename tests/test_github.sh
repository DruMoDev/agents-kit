#!/usr/bin/env bash
# Tests for kit-github-setup.sh and kit-ship-pr.sh (gh stubbed, git real).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
setup="$REPO_ROOT/scripts/kit-github-setup.sh"
ship="$REPO_ROOT/scripts/kit-ship-pr.sh"
use_gh_stub

# repo with a local bare origin whose default branch is $1
mk_with_origin() {
  local b="$1" r o
  r="$(mk_repo)"; o="$(mktemp -d)"
  git init -q --bare "$o"
  # origin looks like a GitHub URL; insteadOf routes the real traffic to the local bare repo
  (cd "$r" && git branch -m "$b" && git remote add origin "https://github.com/dru/demo.git" \
    && git config "url.$o.insteadOf" "https://github.com/dru/demo.git" && git push -q -u origin "$b") >/dev/null 2>&1 || fail "mk_with_origin"
  echo "$r"
}

# --- setup: no remote
r="$(mk_repo)"; : > "$GH_LOG"
err="$(GH_STUB_MODE=no-remote bash "$setup" "$r" 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "no-remote: exit $rc, esperado 1"
case "$err" in *"sin remoto de GitHub"*) ;; *) fail "no-remote: stderr '$err'";; esac

# --- setup: non-GitHub origin -> exit 1
(cd "$r" && git remote add origin https://example.com/x/y.git)
err="$(bash "$setup" "$r" 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "origin no GitHub: exit $rc"
case "$err" in *"sin remoto de GitHub"*) ;; *) fail "origin no GitHub: stderr '$err'";; esac

# --- setup: ok (ssh origin parsed, --repo passed to every gh call)
(cd "$r" && git remote set-url origin git@github.com:dru/demo.git)
: > "$GH_LOG"
out="$(GH_STUB_MODE=ok bash "$setup" "$r" 2>&1)" || fail "setup ok: exit $?"
grep -q -- '--force' "$GH_LOG" && fail "setup: usa --force (pisaría etiquetas existentes)"
grep -q '^label list .*--repo dru/demo' "$GH_LOG" || fail "setup: no lista las etiquetas existentes"
kit_labels="en-curso necesita-respuesta bloqueado propuesta someday registro prio:alta prio:media prio:baja entorno:nube entorno:mac"
n="$(grep -c '^label create ' "$GH_LOG")"
[ "$n" -eq 11 ] || fail "esperadas 11 etiquetas creadas, hay $n"
for l in $kit_labels; do
  grep -q "^label create $l " "$GH_LOG" || fail "falta label $l"
done
for l in listo necesita-decision; do
  grep -q "^label create $l " "$GH_LOG" && fail "crea la etiqueta v2 $l"
done
grep -q '^repo edit .*--enable-squash-merge' "$GH_LOG" || fail "repo edit sin squash"
grep -q '^repo edit .*--delete-branch-on-merge' "$GH_LOG" || fail "repo edit sin delete-branch"
grep -q '^issue create .*📦 Changelog.*--label registro' "$GH_LOG" || fail "no crea issue Changelog con registro"
grep -q '^issue pin' "$GH_LOG" || fail "no fija issue"
case "$out" in *"FIN: ok"*) ;; *) fail "setup sin FIN: ok";; esac
while IFS= read -r line; do
  case "$line" in "auth status"*) continue;; esac
  case "$line" in *"dru/demo"*) ;; *) fail "gh sin repo explícito: $line";; esac
done < "$GH_LOG"

# --- setup: existing labels are kept (never recreated); only the missing ones are created
: > "$GH_LOG"
out="$(GH_STUB_MODE=labels-exist bash "$setup" "$r" 2>&1)" || fail "setup labels-exist: exit $? ($out)"
for l in en-curso prio:alta; do
  grep -q "^label create $l " "$GH_LOG" && fail "recrea la etiqueta existente $l"
done
n="$(grep -c '^label create ' "$GH_LOG")"
[ "$n" -eq 9 ] || fail "labels-exist: esperadas 9 creadas, hay $n"
case "$out" in *"etiqueta: en-curso (ya existía)"*"etiqueta: necesita-respuesta (creada)"*) ;; *) fail "labels-exist: salida '$out'";; esac

# --- setup: label list fails -> exit 2, nothing created
: > "$GH_LOG"
GH_STUB_MODE=label-list-fails bash "$setup" "$r" >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] || fail "label list roto: exit $rc"
grep -q '^label create' "$GH_LOG" && fail "label list roto: creó etiquetas"

# --- setup: idempotent with existing issue (fuzzy neighbour must not match); registro is added to it
: > "$GH_LOG"
GH_STUB_MODE=issue-exists bash "$setup" "$r" >/dev/null 2>&1 || fail "setup rerun: exit $?"
grep -q '^issue create' "$GH_LOG" && fail "vuelve a crear el issue existente"
grep -q '^issue edit 7 .*--add-label registro' "$GH_LOG" || fail "no añade registro al issue existente"
grep -q '^issue pin 7' "$GH_LOG" || fail "no fija el issue existente"

# --- setup: "changelog": false in the marker -> no changelog issue at all
echo '{"changelog": false}' > "$r/.agents-kit.json"
: > "$GH_LOG"
out="$(GH_STUB_MODE=ok bash "$setup" "$r" 2>&1)" || fail "changelog false: exit $? ($out)"
grep -Eq '^issue (list|create|pin|edit)' "$GH_LOG" && fail "changelog false: toca el issue de changelog"
grep -q '^label create registro ' "$GH_LOG" || fail "changelog false: la etiqueta registro se crea igual"
case "$out" in *"sin changelog"*"FIN: ok"*) ;; *) fail "changelog false: salida '$out'";; esac
echo '{"changelog": true}' > "$r/.agents-kit.json"
: > "$GH_LOG"
GH_STUB_MODE=ok bash "$setup" "$r" >/dev/null 2>&1 || fail "changelog true: exit $?"
grep -q '^issue create' "$GH_LOG" || fail "changelog true: no crea el issue"
echo '{' > "$r/.agents-kit.json"
GH_STUB_MODE=ok bash "$setup" "$r" >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] || fail "marcador roto: exit $rc"
rm "$r/.agents-kit.json"

export KIT_WORKTREES="$(mktemp -d)"
bare_of() { git -C "$1" config --get-regexp '^url\..*\.insteadof$' | sed -E 's/^url\.(.*)\.insteadof .*/\1/'; }
snap() { git -C "$1" rev-parse HEAD; git -C "$1" symbolic-ref -q HEAD; git -C "$1" status --porcelain -uall; git -C "$1" stash list; }
# dirty_main <repo>: Dru's tree with edits, untracked files and an unpublished commit on a feature branch
dirty_main() {
  (cd "$1" && git checkout -q -b feature && echo wip > wip.txt && git add wip.txt && git commit -q -m wip \
    && echo mine >> README.md && echo nuevo > suelto.txt) || fail "dirty_main"
}

# --- ship: abrir + enviar from a dirty main tree (trunk default): Dru's tree is never touched
r="$(mk_with_origin trunk)"; dirty_main "$r"; : > "$GH_LOG"
before="$(snap "$r")"
out="$(GH_STUB_MODE=default-branch-trunk bash "$ship" abrir "$r" kit-on sin-marcador 2>&1)" || fail "abrir: exit $? ($out)"
wt="$KIT_WORKTREES/$(basename "$r")/kit-on"
case "$out" in *"worktree: $wt"*"base: trunk"*"FIN: $wt") ;; *) fail "abrir: salida '$out'";; esac
[ "$(git -C "$wt" rev-parse HEAD)" = "$(git -C "$r" rev-parse origin/trunk)" ] || fail "abrir: el worktree no sale de origin/trunk"
[ "$(git -C "$wt" symbolic-ref --short HEAD)" = kit-on ] || fail "abrir: rama del worktree"
[ ! -e "$wt/wip.txt" ] && [ ! -e "$wt/suelto.txt" ] || fail "abrir: el worktree arrastra cambios de Dru"
bash "$REPO_ROOT/scripts/kit-activate.sh" "$wt" >/dev/null 2>&1 || fail "activate en el worktree"
[ "$(snap "$r")" = "$before" ] || fail "abrir/activar tocó el árbol de Dru"
out="$(GH_STUB_MODE=default-branch-trunk bash "$ship" enviar "$r" kit-on "chore: activar agents-kit" "cuerpo" 2>&1)" || fail "enviar: exit $? ($out)"
grep -q '^pr create .*--base trunk.*--head kit-on' "$GH_LOG" || fail "pr create sin --base trunk --head kit-on"
grep -q '^pr merge .*--squash' "$GH_LOG" || fail "pr merge sin --squash"
grep -q '^pr merge .*--delete-branch' "$GH_LOG" && fail "pr merge con --delete-branch (gh tocaría ramas locales)"
case "$out" in *"PR fusionado: https://github.com/dru/demo/pull/1"*"FIN: ok") ;; *) fail "enviar: salida '$out'";; esac
[ ! -e "$wt" ] || fail "enviar: el worktree no se borró"
git -C "$r" show-ref --verify -q refs/heads/kit-on && fail "enviar: rama local no borrada"
git -C "$r" ls-remote --exit-code --heads origin kit-on >/dev/null 2>&1 && fail "enviar: rama remota no borrada"
[ "$(snap "$r")" = "$before" ] || fail "enviar tocó el árbol de Dru"
grep -q '^pr create .*--repo dru/demo' "$GH_LOG" || fail "pr create sin --repo"
grep -q '^pr merge .*--repo dru/demo' "$GH_LOG" || fail "pr merge sin --repo"
while IFS= read -r line; do
  case "$line" in "auth status"*) continue;; esac
  case "$line" in *"dru/demo"*) ;; *) fail "gh sin repo explícito: $line";; esac
done < "$GH_LOG"


# --- ship: the PR merges only after its CI (green); red or timed out leaves it open
ship_ci() { # <GH_CI>: abrir + activar + enviar on a fresh repo; prints enviar's output, returns its exit code
  local r w
  r="$(mk_with_origin main)"
  bash "$ship" abrir "$r" kit-on sin-marcador >/dev/null 2>&1 || { echo "abrir falló"; return 9; }
  w="$KIT_WORKTREES/$(basename "$r")/kit-on"
  bash "$REPO_ROOT/scripts/kit-activate.sh" "$w" >/dev/null 2>&1 || { echo "activate falló"; return 9; }
  : > "$GH_LOG"
  GH_CI="$1" KIT_CI_POLL=0 KIT_CI_TIMEOUT=1 bash "$ship" enviar "$r" kit-on "chore: activar agents-kit" "cuerpo" 2>&1
}
out="$(ship_ci verde)" || fail "ship CI verde: exit $? ($out)"
case "$out" in *"CI: verde"*"FIN: ok") ;; *) fail "ship CI verde: '$out'";; esac
grep -q '^api repos/dru/demo/commits/.*/check-runs' "$GH_LOG" || fail "ship CI verde: no miró los checks"
for c in rojo esperando; do
  out="$(ship_ci "$c")"; rc=$?
  [ $rc -eq 2 ] || fail "ship CI $c: exit $rc ($out)"
  grep -q '^pr merge' "$GH_LOG" && fail "ship CI $c: fusionó sin CI verde"
  case "$out" in *"FIN: PR abierto") ;; *) fail "ship CI $c: '$out'";; esac
  case "$out" in *"gh pr merge falló"*) fail "ship CI $c: culpa a la fusión, que no se intentó ('$out')";; esac
done
case "$(ship_ci esperando)" in *"el CI sigue en marcha"*"kit-ship-pr.sh fusionar "*" kit-on"*) ;;
  *) fail "ship CI esperando: no dice cómo relanzar solo la fusión";; esac
case "$(ship_ci rojo)" in *"sigue en marcha"*) fail "ship CI rojo: lo trata como CI en marcha";; esac

# --- a transient GraphQL error in gh pr merge is retried; the output says so and ends in FIN: ok
rm -f "$GH_LOG.flaky"
out="$(GH_MERGE_FLAKY=1 KIT_GH_RETRY_WAIT=0 ship_ci verde)" || fail "merge con fallo transitorio: exit $? ($out)"
case "$out" in *"aviso: fallo transitorio de GitHub"*"FIN: ok") ;; *) fail "merge con fallo transitorio: '$out'";; esac
[ "$(grep -c '^pr merge' "$GH_LOG")" = 2 ] || fail "merge transitorio: $(grep -c '^pr merge' "$GH_LOG") intentos"
case "$out" in *"esperando al CI del PR (hasta "*" min)"*) ;; *) fail "enviar no avisa de la espera al CI: '$out'";; esac
rm -f "$GH_LOG.flaky"

# --- ship fusionar: only the merge of the open PR, after its CI
r="$(mk_with_origin main)"
: > "$GH_LOG"
out="$(GH_STUB_MODE=pr-open GH_CI=verde KIT_CI_POLL=0 bash "$ship" fusionar "$r" kit-on 2>&1)" || fail "fusionar verde: $out"
case "$out" in *"CI: verde"*"PR fusionado: https://github.com/dru/demo/pull/5"*"FIN: ok") ;; *) fail "fusionar verde: '$out'";; esac
grep -q '^api repos/dru/demo/commits/abc123/check-runs' "$GH_LOG" || fail "fusionar: no miró el CI del head del PR"
grep -q '^pr merge https://github.com/dru/demo/pull/5 .*--squash --match-head-commit abc123' "$GH_LOG" \
  || fail "fusionar: no fusionó el PR 5 atado al commit comprobado"
grep -q 'pull/6\|f0f0f0' "$GH_LOG" && fail "fusionar: tocó el PR de un fork"
: > "$GH_LOG"
out="$(GH_STUB_MODE=pr-open GH_CI=esperando KIT_CI_POLL=0 KIT_CI_TIMEOUT=0 bash "$ship" fusionar "$r" kit-on 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "fusionar esperando: exit $rc ($out)"
grep -q '^pr merge' "$GH_LOG" && fail "fusionar esperando: fusionó sin CI verde"
case "$out" in *"FIN: PR abierto") ;; *) fail "fusionar esperando: '$out'";; esac
err="$(bash "$ship" fusionar "$r" kit-on 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "fusionar sin PR: exit $rc"
case "$err" in *"no hay un PR abierto desde 'kit-on'"*) ;; *) fail "fusionar sin PR: '$err'";; esac


# --- real repo shape (tiktok-editor): CLAUDE.md -> AGENTS.md, .claude/skills symlink, core.hooksPath, dirty main tree
r="$(mk_with_origin main)"
(cd "$r" && printf '# proyecto\n\n## Reglas duras\n\n- no tocar lib/\n' > AGENTS.md && ln -s AGENTS.md CLAUDE.md \
  && mkdir -p .agents/skills/x .claude tools/hooks && echo s > .agents/skills/x/SKILL.md && ln -s ../.agents/skills .claude/skills \
  && printf '#!/bin/sh\nexit 1\n' > tools/hooks/pre-commit && chmod +x tools/hooks/pre-commit \
  && echo '{}' > .claude/settings.json && git add -A && git commit -q -m base && git push -q origin main \
  && git config core.hooksPath tools/hooks) || fail "repo real: setup"
(cd "$r" && echo "cambio de Dru" >> AGENTS.md && echo x > notas.txt)
before="$(snap "$r")"; agents_before="$(cat "$r/AGENTS.md")"
out="$(bash "$ship" abrir "$r" kit-on sin-marcador 2>&1)" || fail "repo real abrir: $out"
wt="$KIT_WORKTREES/$(basename "$r")/kit-on"
err="$(bash "$REPO_ROOT/scripts/kit-activate.sh" "$wt" --changelog false 2>&1 >/dev/null)" || fail "repo real activar: $err"
case "$err" in *core.hooksPath=tools/hooks*) ;; *) fail "repo real: sin aviso de hooks ($err)";; esac
[ -L "$wt/CLAUDE.md" ] && [ -L "$wt/.claude/skills" ] || fail "repo real: symlinks tocados"
grep -qx '## Reglas del proyecto' "$wt/AGENTS.md" && grep -q 'no tocar lib/' "$wt/AGENTS.md" || fail "repo real: AGENTS.md mínimo"
grep -q 'cambio de Dru' "$wt/AGENTS.md" && fail "repo real: el worktree arrastra cambios de Dru"
[ ! -e "$wt/CHANGELOG.md" ] || fail "repo real: changelog false creó CHANGELOG.md"
GH_STUB_MODE=labels-exist bash "$setup" "$wt" >/dev/null 2>&1 || fail "repo real: github setup"
out="$(bash "$ship" enviar "$r" kit-on "chore: activar agents-kit" b 2>&1)" || fail "repo real enviar: $out"
[ "$(snap "$r")" = "$before" ] && [ "$(cat "$r/AGENTS.md")" = "$agents_before" ] || fail "repo real: se tocó el árbol de Dru"
[ ! -e "$wt" ] || fail "repo real: worktree no borrado"

# --- abrir: marker state on origin/<base> must match
r="$(mk_with_origin main)"
err="$(bash "$ship" abrir "$r" kit-off con-marcador 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "con-marcador sin marcador: exit $rc"
case "$err" in *"no está activo"*) ;; *) fail "con-marcador: '$err'";; esac
(cd "$r" && echo '{}' > .agents-kit.json && git add . && git commit -q -m on && git push -q origin main) || fail setup
err="$(bash "$ship" abrir "$r" kit-on sin-marcador 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "sin-marcador con marcador: exit $rc"
case "$err" in *"ya está activo"*) ;; *) fail "sin-marcador: '$err'";; esac
[ ! -e "$KIT_WORKTREES/$(basename "$r")/kit-on" ] || fail "rechazo: creó el worktree"
bash "$ship" abrir "$r" kit-on otra-cosa >/dev/null 2>&1; [ $? -eq 1 ] || fail "estado inválido debe salir 1"

# --- kit-off from a dirty tree: deactivation in the worktree, marker gone from origin
dirty_main "$r"; before="$(snap "$r")"
out="$(bash "$ship" abrir "$r" kit-off con-marcador 2>&1)" || fail "kit-off abrir: $out"
wt="$KIT_WORKTREES/$(basename "$r")/kit-off"
bash "$REPO_ROOT/scripts/kit-deactivate.sh" "$wt" >/dev/null || fail "kit-off deactivate"
out="$(bash "$ship" enviar "$r" kit-off "chore: desactivar agents-kit" b 2>&1)" || fail "kit-off enviar: $out"
[ "$(snap "$r")" = "$before" ] || fail "kit-off tocó el árbol de Dru"
[ ! -e "$wt" ] || fail "kit-off: worktree no borrado"

# --- abrir: open PR for the branch -> exit 1 with its URL
r="$(mk_with_origin main)"
err="$(GH_STUB_MODE=pr-open bash "$ship" abrir "$r" kit-on sin-marcador 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "PR abierto: exit $rc"
case "$err" in *"https://github.com/dru/demo/pull/5"*) ;; *) fail "PR abierto: '$err'";; esac

# --- abrir: leftover local branch or remote branch without a worktree -> exit 1
git -C "$r" branch kit-on
err="$(bash "$ship" abrir "$r" kit-on sin-marcador 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "rama local vieja: exit $rc"
case "$err" in *"git branch -D kit-on"*) ;; *) fail "rama local vieja: '$err'";; esac
(cd "$r" && git push -q origin kit-on && git branch -q -D kit-on) >/dev/null 2>&1
err="$(bash "$ship" abrir "$r" kit-on sin-marcador 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "rama remota vieja: exit $rc"
case "$err" in *"git push origin --delete kit-on"*) ;; *) fail "rama remota vieja: '$err'";; esac

# --- enviar: nothing to send -> exit 1, worktree kept; descartar removes it
r="$(mk_with_origin main)"
bash "$ship" abrir "$r" kit-on sin-marcador >/dev/null 2>&1 || fail "abrir vacío"
wt="$KIT_WORKTREES/$(basename "$r")/kit-on"
err="$(bash "$ship" enviar "$r" kit-on t b 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "sin cambios: exit $rc"
case "$err" in *"nada que enviar"*) ;; *) fail "sin cambios: '$err'";; esac
[ -d "$wt" ] || fail "sin cambios: borró el worktree"
echo basura > "$wt/x.txt"
out="$(bash "$ship" descartar "$r" kit-on 2>&1)" || fail "descartar: $out"
[ ! -e "$wt" ] || fail "descartar: worktree sigue"
git -C "$r" show-ref --verify -q refs/heads/kit-on && fail "descartar: rama sigue"
case "$out" in *"FIN: descartado"*) ;; *) fail "descartar: '$out'";; esac
bash "$ship" descartar "$r" kit-on >/dev/null 2>&1; [ $? -eq 1 ] || fail "descartar sin worktree debe salir 1"
bash "$ship" enviar "$r" kit-on t b >/dev/null 2>&1; [ $? -eq 1 ] || fail "enviar sin worktree debe salir 1"

# --- enviar: push fails -> exit 2, worktree kept and named; a rerun resumes it
r="$(mk_with_origin main)"
bash "$ship" abrir "$r" kit-on sin-marcador >/dev/null 2>&1 || fail "abrir push"
wt="$KIT_WORKTREES/$(basename "$r")/kit-on"; echo a > "$wt/a.txt"
o="$(bare_of "$r")"; mv "$o" "$o.off"
err="$(bash "$ship" enviar "$r" kit-on t b 2>&1 >/dev/null)"; rc=$?
mv "$o.off" "$o"
[ $rc -eq 2 ] || fail "push roto: exit $rc"
case "$err" in *"$wt"*) ;; *) fail "push roto: no dice dónde está el worktree: '$err'";; esac
[ -f "$wt/a.txt" ] || fail "push roto: se perdió el trabajo"
out="$(bash "$ship" abrir "$r" kit-on sin-marcador 2>&1)" || fail "reabrir: $out"
case "$out" in *"ya existía"*"FIN: $wt") ;; *) fail "reabrir: '$out'";; esac
out="$(bash "$ship" enviar "$r" kit-on t b 2>&1)" || fail "reenviar: exit $? ($out)"
[ ! -e "$wt" ] || fail "reenviar: worktree sigue"

# --- enviar: gh pr create fails -> exit 2, worktree kept; rerun with the branch already on origin works
r="$(mk_with_origin main)"
bash "$ship" abrir "$r" kit-on sin-marcador >/dev/null 2>&1 || fail "abrir create"
wt="$KIT_WORKTREES/$(basename "$r")/kit-on"; echo a > "$wt/a.txt"
err="$(GH_STUB_MODE=pr-create-fails bash "$ship" enviar "$r" kit-on t b 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 2 ] || fail "pr create roto: exit $rc"
case "$err" in *"$wt"*) ;; *) fail "pr create roto: '$err'";; esac
[ -d "$wt" ] || fail "pr create roto: borró el worktree"
bash "$ship" abrir "$r" kit-on sin-marcador >/dev/null 2>&1 || fail "reabrir tras pr create roto"
bash "$ship" enviar "$r" kit-on t b >/dev/null 2>&1 || fail "reenviar tras pr create roto"

# --- enviar: PR left open -> exit 2, FIN: PR abierto, worktree removed (the work is in the PR)
r="$(mk_with_origin main)"
bash "$ship" abrir "$r" kit-on sin-marcador >/dev/null 2>&1; wt="$KIT_WORKTREES/$(basename "$r")/kit-on"; echo a > "$wt/a.txt"
out="$(GH_STUB_MODE=merge-open bash "$ship" enviar "$r" kit-on t b 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "no fusionado: exit $rc"
case "$out" in *"sigue abierto"*"github.com/dru/demo/pull/1"*"FIN: PR abierto") ;; *) fail "no fusionado: salida '$out'";; esac
case "$out" in *"PR fusionado"*) fail "no fusionado: no debe decir fusionado";; esac
[ ! -e "$wt" ] || fail "no fusionado: el worktree debe borrarse"
git -C "$r" ls-remote --exit-code --heads origin kit-on >/dev/null 2>&1 || fail "no fusionado: la rama remota del PR debe quedar"
[ "$(git --git-dir="$(bare_of "$r")" log -1 --format=%s kit-on)" = t ] || fail "no fusionado: el commit no lleva el título"
git --git-dir="$(bare_of "$r")" show kit-on:a.txt >/dev/null 2>&1 || fail "no fusionado: el commit no lleva los cambios"

# --- enviar: merge exits 1 but the PR is MERGED -> success
r="$(mk_with_origin main)"
bash "$ship" abrir "$r" kit-on sin-marcador >/dev/null 2>&1; echo a > "$KIT_WORKTREES/$(basename "$r")/kit-on/a.txt"
out="$(GH_STUB_MODE=merge-fails-merged bash "$ship" enviar "$r" kit-on t b 2>&1)" || fail "merge falla pero MERGED: exit $? ($out)"
case "$out" in *"PR fusionado"*"FIN: ok") ;; *) fail "merge falla pero MERGED: salida '$out'";; esac

# --- enviar: project hooks are skipped (the worktree has no setup); a failing git -> exit 2, changes kept
r="$(mk_with_origin main)"
bash "$ship" abrir "$r" kit-on sin-marcador >/dev/null 2>&1; wt="$KIT_WORKTREES/$(basename "$r")/kit-on"; echo a > "$wt/a.txt"
mkdir -p "$r/tools/hooks"; printf '#!/bin/sh\nexit 1\n' > "$r/tools/hooks/pre-commit"; chmod +x "$r/tools/hooks/pre-commit"
git -C "$r" config core.hooksPath tools/hooks
cp "$r/tools/hooks/pre-commit" "$r/.git/hooks/pre-commit"
mkdir -p "$wt/tools/hooks"; cp "$r/tools/hooks/pre-commit" "$wt/tools/hooks/"
GH_STUB_MODE=merge-open bash "$ship" enviar "$r" kit-on t b >/dev/null 2>&1
git --git-dir="$(bare_of "$r")" show kit-on:a.txt >/dev/null 2>&1 || fail "los hooks del proyecto bloquearon el commit"
r="$(mk_with_origin main)"
bash "$ship" abrir "$r" kit-on sin-marcador >/dev/null 2>&1; wt="$KIT_WORKTREES/$(basename "$r")/kit-on"; echo a > "$wt/a.txt"
: > "$(git -C "$wt" rev-parse --absolute-git-dir)/index.lock"
err="$(bash "$ship" enviar "$r" kit-on t b 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 2 ] || fail "commit fallido: exit $rc"
[ -f "$wt/a.txt" ] || fail "commit fallido: cambios perdidos"
case "$err" in *"$wt"*) ;; *) fail "commit fallido: mensaje '$err'";; esac

# --- ship: non-GitHub origin -> exit 1
r="$(mk_with_origin main)"
git -C "$r" config remote.origin.url https://example.com/x/y.git
err="$(bash "$ship" abrir "$r" kit-on sin-marcador 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "origin no GitHub: exit $rc"
case "$err" in *"sin remoto de GitHub"*) ;; *) fail "origin no GitHub: stderr '$err'";; esac
bash "$ship" >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin argumentos debe salir 1"
bash "$ship" abrir "$r" "rama mala" sin-marcador >/dev/null 2>&1; [ $? -eq 1 ] || fail "rama inválida debe salir 1"
r="$(mk_with_origin main)"
GH_STUB_MODE=no-auth bash "$ship" abrir "$r" kit-on sin-marcador >/dev/null 2>&1; [ $? -eq 2 ] || fail "ship sin auth debe salir 2"

# --- auth / no origin -> 2
r="$(mk_repo)"
GH_STUB_MODE=no-auth bash "$setup" "$r" >/dev/null 2>&1; [ $? -eq 2 ] || fail "setup sin auth debe salir 2"
bash "$ship" abrir "$r" kit-on sin-marcador >/dev/null 2>&1; [ $? -eq 2 ] || fail "sin origin debe salir 2"

# --- ship: not a git repo -> 2
bash "$ship" abrir "$(mktemp -d)" kit-on sin-marcador >/dev/null 2>&1; [ $? -eq 2 ] || fail "no-repo debe salir 2"

echo "OK test_github"
