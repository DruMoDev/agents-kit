#!/usr/bin/env bash
# Tests for kit-github-setup.sh and kit-ship-pr.sh (gh stubbed, git real).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
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
n="$(grep -c '^label create .*--force' "$GH_LOG")"
[ "$n" -eq 5 ] || fail "esperadas 5 labels con --force, hay $n"
for l in listo propuesta en-curso necesita-decision bloqueado; do
  grep -q "^label create $l " "$GH_LOG" || fail "falta label $l"
done
grep -q '^repo edit .*--enable-squash-merge' "$GH_LOG" || fail "repo edit sin squash"
grep -q '^repo edit .*--delete-branch-on-merge' "$GH_LOG" || fail "repo edit sin delete-branch"
grep -q '^issue create .*📦 Changelog' "$GH_LOG" || fail "no crea issue Changelog"
grep -q '^issue pin' "$GH_LOG" || fail "no fija issue"
case "$out" in *"FIN: ok"*) ;; *) fail "setup sin FIN: ok";; esac
while IFS= read -r line; do
  case "$line" in "auth status"*) continue;; esac
  case "$line" in *"dru/demo"*) ;; *) fail "gh sin repo explícito: $line";; esac
done < "$GH_LOG"

# --- setup: idempotent with existing issue (fuzzy neighbour must not match)
: > "$GH_LOG"
GH_STUB_MODE=issue-exists bash "$setup" "$r" >/dev/null 2>&1 || fail "setup rerun: exit $?"
grep -q '^issue create' "$GH_LOG" && fail "vuelve a crear el issue existente"
grep -q '^issue pin 7' "$GH_LOG" || fail "no fija el issue existente"

# --- ship: trunk default
r="$(mk_with_origin trunk)"; : > "$GH_LOG"
echo change > "$r/new.txt"; echo more >> "$r/README.md"
out="$(GH_STUB_MODE=default-branch-trunk bash "$ship" "$r" kit/cambio "feat: algo" "cuerpo" 2>&1)" || fail "ship: exit $? ($out)"
grep -q '^pr create .*--base trunk' "$GH_LOG" || fail "pr create sin --base trunk"
grep -q '^pr merge .*--squash' "$GH_LOG" || fail "pr merge sin --squash"
[ "$(git -C "$r" rev-parse --abbrev-ref HEAD)" = trunk ] || fail "no termina en trunk"
git -C "$r" show-ref --verify -q refs/heads/kit/cambio && fail "rama local no borrada"
git -C "$r" ls-remote --exit-code --heads origin kit/cambio >/dev/null 2>&1 && fail "rama remota no borrada tras el merge"
git -C "$r" show-ref --verify -q refs/remotes/origin/kit/cambio && fail "queda ref de seguimiento obsoleto"
case "$out" in *"PR fusionado: https://github.com/dru/demo/pull/1"*"FIN: ok"*) ;; *) fail "salida sin URL/FIN: $out";; esac

grep -q '^pr create .*--repo dru/demo' "$GH_LOG" || fail "pr create sin --repo"
grep -q '^pr merge .*--repo dru/demo' "$GH_LOG" || fail "pr merge sin --repo"

# --- ship: merge exits 1 but PR is MERGED -> success
r="$(mk_with_origin main)"; echo c > "$r/f.txt"
out="$(GH_STUB_MODE=merge-fails-merged bash "$ship" "$r" kit/mf t b 2>&1)" || fail "merge falla pero MERGED: exit $? ($out)"
case "$out" in *"PR fusionado"*"FIN: ok"*) ;; *) fail "merge falla pero MERGED: salida '$out'";; esac

# --- ship: non-GitHub origin -> exit 1
r="$(mk_with_origin main)"; echo c > "$r/f.txt"
git -C "$r" config remote.origin.url https://example.com/x/y.git
err="$(bash "$ship" "$r" kit/ng t b 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "origin no GitHub: exit $rc"
case "$err" in *"sin remoto de GitHub"*) ;; *) fail "origin no GitHub: stderr '$err'";; esac

# --- ship: stale local default, origin edited a file / added a colliding one -> exit 2, clean tree, stash kept
for kind in edit collide; do
  r="$(mk_with_origin main)"
  o="$(git -C "$r" config --get-regexp '^url\..*\.insteadof$' | sed -E 's/^url\.(.*)\.insteadof .*/\1/')"
  w="$(mktemp -d)"; git clone -q "$o" "$w" 2>/dev/null
  (cd "$w" && git config user.name T && git config user.email t@e.c \
    && if [ $kind = edit ]; then echo upstream > README.md; else echo upstream > CHANGELOG.md; fi \
    && git add -A && git commit -q -m up && git push -q origin main) || fail "stale: setup upstream"
  if [ $kind = edit ]; then echo mine > "$r/README.md"; else echo mine > "$r/CHANGELOG.md"; fi
  echo extra > "$r/extra.txt"
  out="$(bash "$ship" "$r" kit/stale t b 2>&1)"; rc=$?
  [ $rc -eq 2 ] || fail "stale $kind: exit $rc ($out)"
  [ "$(git -C "$r" rev-parse --abbrev-ref HEAD)" = main ] || fail "stale $kind: debe volver a main"
  [ -z "$(git -C "$r" status --porcelain)" ] || fail "stale $kind: árbol sucio: $(git -C "$r" status --porcelain)"
  sha="$(git -C "$r" rev-parse refs/stash)"
  case "$out" in *"$sha"*"git pull"*) ;; *) fail "stale $kind: mensaje sin sha/pull: $out";; esac
  git -C "$r" show "$sha^3:extra.txt" >/dev/null 2>&1 || fail "stale $kind: stash sin los cambios"
  git -C "$r" show-ref --verify -q refs/heads/kit/stale && fail "stale $kind: rama no borrada"
done

# --- ship: nothing to ship
r="$(mk_with_origin main)"
err="$(bash "$ship" "$r" kit/x t b 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "sin cambios: exit $rc"
case "$err" in *"nada que enviar"*) ;; *) fail "sin cambios: stderr '$err'";; esac

# --- ship: branch exists -> exit 1, no clobber
echo c > "$r/f.txt"; git -C "$r" branch kit/dup
err="$(bash "$ship" "$r" kit/dup t b 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "rama existente: exit $rc"
[ -f "$r/f.txt" ] || fail "rama existente: cambios perdidos"

# --- ship: remote branch exists -> exit 1
r="$(mk_with_origin main)"; echo c > "$r/f.txt"
(cd "$r" && git branch kit/rem && git push -q origin kit/rem && git branch -q -D kit/rem) >/dev/null 2>&1
err="$(bash "$ship" "$r" kit/rem t b 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "rama remota existente: exit $rc"
case "$err" in *origin*) ;; *) fail "rama remota: stderr '$err'";; esac
[ -f "$r/f.txt" ] || fail "rama remota: cambios perdidos"

# --- ship: stale tracking ref (branch deleted on remote) -> not refused
r="$(mk_with_origin main)"; echo c > "$r/f.txt"
(cd "$r" && git branch kit/old && git push -q origin kit/old && git branch -q -D kit/old) >/dev/null 2>&1
git -C "$r" show-ref --verify -q refs/remotes/origin/kit/old || fail "stale: falta el ref de seguimiento"
git -C "$(git -C "$r" remote get-url origin)" branch -q -D kit/old 2>/dev/null || git --git-dir="$(git -C "$r" remote get-url origin)" branch -q -D kit/old || fail "stale: no se pudo borrar en el remoto"
out="$(bash "$ship" "$r" kit/old t b 2>&1)" || fail "stale: debe aceptarse (exit $?, $out)"
git -C "$r" show-ref --verify -q refs/remotes/origin/kit/old && fail "stale: queda ref de seguimiento tras el merge"

# --- ship: PR not merged -> exit 2, says it remains open
r="$(mk_with_origin main)"; echo c > "$r/f.txt"
out="$(GH_STUB_MODE=merge-open bash "$ship" "$r" kit/open t b 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "no fusionado: exit $rc"
case "$out" in *"sigue abierto"*"github.com/dru/demo/pull/1"*) ;; *) fail "no fusionado: salida '$out'";; esac
case "$out" in *"PR fusionado"*) fail "no fusionado: no debe decir fusionado";; esac

# --- ship: diverged local default -> exit 1
r="$(mk_with_origin main)"
(cd "$r" && echo x > local.txt && git add local.txt && git commit -q -m local-only) || fail setup
echo c > "$r/f.txt"
bash "$ship" "$r" kit/div t b >/dev/null 2>&1; [ $? -eq 1 ] || fail "default divergida debe salir 1"
[ -f "$r/f.txt" ] || fail "default divergida: cambios perdidos"

# --- ship: non-default branch with unpublished commits -> exit 1
r="$(mk_with_origin main)"
(cd "$r" && git checkout -q -b feature && echo x > a.txt && git add a.txt && git commit -q -m wip) || fail setup
echo c > "$r/f.txt"
err="$(bash "$ship" "$r" kit/nb t b 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "rama con commits sin publicar: exit $rc"
[ "$(git -C "$r" rev-parse --abbrev-ref HEAD)" = feature ] || fail "debe quedarse en feature"

# --- ship: stash that captures nothing must never apply an older stash
r="$(mk_with_origin main)"
sub="$(mktemp -d)"; (cd "$sub" && git init -q -b main && git config user.name T && git config user.email t@e.c && echo s > s && git add s && git commit -q -m s)
(cd "$r" && git -c protocol.file.allow=always submodule add -q "$sub" sub && git commit -q -m addsub && git push -q origin main) >/dev/null 2>&1 || fail "submodule setup"
(cd "$r" && echo old > old.txt && git stash push -u -q -m older) || fail "older stash"
old_sha="$(git -C "$r" rev-parse refs/stash)"
echo dirty >> "$r/sub/s"
[ -n "$(git -C "$r" status --porcelain)" ] || fail "el submódulo debería estar sucio"
bash "$ship" "$r" kit/subm t b >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] || fail "stash vacío debe fallar"
[ "$(git -C "$r" rev-parse refs/stash)" = "$old_sha" ] || fail "el stash antiguo fue tocado"
[ ! -e "$r/old.txt" ] || fail "se aplicó el stash antiguo"
git -C "$r" ls-remote --exit-code --heads origin kit/subm >/dev/null 2>&1 && fail "se subió una rama"

# --- ship: commit failure leaves changes in tree and no branch
r="$(mk_with_origin main)"; echo c > "$r/f.txt"
printf '#!/bin/sh\nexit 1\n' > "$r/.git/hooks/pre-commit"; chmod +x "$r/.git/hooks/pre-commit"
err="$(bash "$ship" "$r" kit/hook t b 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 2 ] || fail "commit fallido: exit $rc"
[ -f "$r/f.txt" ] || fail "commit fallido: cambios perdidos"
git -C "$r" show-ref --verify -q refs/heads/kit/hook && fail "rama vacía no borrada"
case "$err" in *"árbol de trabajo"*) ;; *) fail "commit fallido: mensaje '$err'";; esac

# --- ship: detached HEAD at origin/main works
r="$(mk_with_origin main)"; git -C "$r" checkout -q --detach; echo c > "$r/f.txt"
GH_STUB_MODE=ok bash "$ship" "$r" kit/det "t" b >/dev/null 2>&1 || fail "detached: exit $?"
[ "$(git -C "$r" rev-parse --abbrev-ref HEAD)" = main ] || fail "detached: debe terminar en main"

# --- auth / no origin -> 2
r="$(mk_repo)"
GH_STUB_MODE=no-auth bash "$setup" "$r" >/dev/null 2>&1; [ $? -eq 2 ] || fail "setup sin auth debe salir 2"
echo c > "$r/f.txt"
bash "$ship" "$r" kit/x t b >/dev/null 2>&1; [ $? -eq 2 ] || fail "sin origin debe salir 2"

# --- ship: not a git repo -> 2
bash "$ship" "$(mktemp -d)" kit/x t b >/dev/null 2>&1; [ $? -eq 2 ] || fail "no-repo debe salir 2"

echo "OK test_github"
