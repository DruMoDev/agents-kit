#!/usr/bin/env bash
# Tests for scripts/kit-worktree.sh (local bare origin, stateful gh stub).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
wt="$REPO_ROOT/scripts/kit-worktree.sh"
use_flow_gh
export KIT_WORKTREES; KIT_WORKTREES="$(mktemp -d)"
last_line() { printf '%s\n' "$1" | sed -n '$p'; }

r="$(mk_repo)"; o="$(mktemp -d)"
git init -q --bare "$o"
echo '{}' > "$r/.agents-kit.json"
(cd "$r" && git remote add origin https://github.com/dru/demo.git \
  && git config "url.$o.insteadOf" "https://github.com/dru/demo.git" \
  && git push -q -u origin main) >/dev/null 2>&1 || fail "setup remoto"
git -C "$o" symbolic-ref HEAD refs/heads/main
name="$(basename "$r")"
path="$KIT_WORKTREES/$name/issue-3-foo"
set_pr() { # <state> [oid]: seed a PR for issue-3-foo (oid defaults to the branch tip)
  local oid="${2:-$(git -C "$r" rev-parse issue-3-foo)}"
  echo "{\"issues\":[],\"prs\":[{\"number\":9,\"headRefName\":\"issue-3-foo\",\"state\":\"$1\",\"headRefOid\":\"$oid\"}]}" > "$GH_STATE/state.json"
}

# invalid args
bash "$wt" abrir "$r" 3 "Foo_bar" >/dev/null 2>&1; [ $? -eq 1 ] || fail "slug inválido debe dar 1"
bash "$wt" abrir "$r" x foo >/dev/null 2>&1; [ $? -eq 1 ] || fail "N inválido debe dar 1"
# no marker
m="$(mk_repo)"; bash "$wt" abrir "$m" 3 foo >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin marcador debe dar 1"

# abrir
out="$(bash "$wt" abrir "$r" 3 foo 2>&1)" || fail "abrir: $out"
[ -d "$path" ] || fail "no crea $path"
case "$out" in *"worktree: $path"*"rama: issue-3-foo"*) ;; *) fail "abrir salida: $out";; esac
[ "$(last_line "$out")" = "FIN: $path" ] || fail "abrir sin FIN"
[ -z "$(git -C "$path" config --get branch.issue-3-foo.remote)" ] || fail "la rama tiene upstream"
[ "$(git -C "$path" rev-parse HEAD)" = "$(git -C "$r" rev-parse origin/main)" ] || fail "no parte de origin/main"

# idempotent
out="$(bash "$wt" abrir "$r" 3 foo 2>&1)" || fail "abrir 2: $out"
case "$out" in *"ya existía"*) ;; *) fail "falta 'ya existía': $out";; esac
[ "$(last_line "$out")" = "FIN: $path" ] || fail "abrir 2 sin FIN"

# branch exists without worktree
git -C "$r" worktree remove "$path" && out="$(bash "$wt" abrir "$r" 3 foo 2>&1)" || fail "re-añadir: $out"
[ -d "$path" ] || fail "no re-añade el worktree"

# path exists and is not that worktree
mkdir -p "$KIT_WORKTREES/$name/issue-4-bar"
bash "$wt" abrir "$r" 4 bar >/dev/null 2>&1; [ $? -eq 1 ] || fail "ruta ocupada debe dar 1"
rmdir "$KIT_WORKTREES/$name/issue-4-bar"

# limpiar: PR open
set_pr OPEN
err="$(bash "$wt" limpiar "$r" 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "limpiar OPEN: exit $rc"
case "$err" in *"la PR de issue-3-foo no está fusionada"*) ;; *) fail "limpiar OPEN msg: $err";; esac
[ -d "$path" ] || fail "OPEN borró el worktree"
# no PR at all
echo '{"issues":[],"prs":[]}' > "$GH_STATE/state.json"
bash "$wt" limpiar "$r" 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin PR debe dar 1"

# MERGED but dirty
set_pr MERGED
echo x > "$path/dirty.txt"
err="$(bash "$wt" limpiar "$r" 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "limpiar sucio: exit $rc"
case "$err" in *"el worktree tiene cambios; no se borra nada"*) ;; *) fail "sucio msg: $err";; esac
[ -d "$path" ] && git -C "$r" rev-parse -q --verify issue-3-foo >/dev/null || fail "sucio borró algo"

# gh failure -> 2
rm "$path/dirty.txt"
GH_FAIL_ON="pr list" bash "$wt" limpiar "$r" 3 >/dev/null 2>&1; [ $? -eq 2 ] || fail "fallo de gh debe dar 2"
[ -d "$path" ] || fail "fallo de gh borró"

# commit made after the merge (PR oid differs from the tip)
set_pr MERGED
(cd "$path" && echo y > late.txt && git add late.txt && git commit -q -m late) || fail "commit tardío"
err="$(bash "$wt" limpiar "$r" 3 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "commit tardío: exit $rc"
case "$err" in *"la rama tiene commits que no están en la PR fusionada; no se borra nada"*) ;; *) fail "commit tardío msg: $err";; esac
[ -d "$path" ] && git -C "$r" rev-parse -q --verify issue-3-foo >/dev/null || fail "commit tardío borró algo"

# issue 31 coexists: limpiar 3 must touch only issue 3
bash "$wt" abrir "$r" 31 bar >/dev/null 2>&1 || fail "abrir 31"
path31="$KIT_WORKTREES/$name/issue-31-bar"
git -C "$path" reset -q --hard HEAD~1
set_pr MERGED

# MERGED and clean
out="$(bash "$wt" limpiar "$r" 3 2>&1)" || fail "limpiar: $out"
[ "$(last_line "$out")" = "FIN: limpio" ] || fail "limpiar sin FIN"
[ ! -e "$path" ] || fail "queda el worktree"
git -C "$r" rev-parse -q --verify issue-3-foo >/dev/null && fail "queda la rama"
while IFS= read -r line; do case "$line" in *"dru/demo"*) ;; *) fail "gh sin repo: $line";; esac; done < "$GH_LOG"

[ -d "$path31" ] && git -C "$r" rev-parse -q --verify issue-31-bar >/dev/null || fail "limpiar 3 tocó el issue 31"

# nothing to clean
bash "$wt" limpiar "$r" 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin worktree debe dar 1"
echo "OK test_worktree"
