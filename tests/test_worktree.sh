#!/usr/bin/env bash
# Tests for scripts/kit-worktree.sh (local bare origin, stateful gh stub).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
wt="$REPO_ROOT/scripts/kit-worktree.sh"
use_flow_gh
export KIT_WORKTREES; KIT_WORKTREES="$(mktemp -d)"
tmpe="$(mktemp)"
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

# branch only on origin (issue resumed elsewhere): the local branch starts from it, without upstream
git -C "$r" worktree add -q -b issue-5-remota --no-track "$(mktemp -d)/w5" origin/main || fail "setup rama remota"
w5="$(git -C "$r" worktree list --porcelain | sed -n 's|^worktree \(.*/w5\)$|\1|p')"
(cd "$w5" && echo r > r.txt && git add r.txt && git commit -q -m remota && git push -q origin HEAD) >/dev/null 2>&1 || fail "push rama remota"
tip5="$(git -C "$w5" rev-parse HEAD)"
git -C "$r" worktree remove "$w5" && git -C "$r" branch -q -D issue-5-remota || fail "borrar rama local"
git -C "$r" update-ref -d refs/remotes/origin/issue-5-remota 2>/dev/null
out="$(bash "$wt" abrir "$r" 5 remota 2>&1)" || fail "abrir rama remota: $out"
p5="$KIT_WORKTREES/$name/issue-5-remota"
[ "$(git -C "$p5" rev-parse HEAD)" = "$tip5" ] || fail "abrir no parte de origin/issue-5-remota"
[ -z "$(git -C "$p5" config --get branch.issue-5-remota.remote)" ] || fail "la rama remota quedó con upstream"
git -C "$r" worktree remove "$p5" || fail "quitar worktree 5"

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
# setup: runs once in the new worktree; failure -> exit 2 with the output; unsafe path -> exit 2
mkdir -p "$r/tools"
printf '#!/bin/sh\necho "preparado" >> "$SETUP_LOG"\n[ -e "$SETUP_OK" ] || { echo "no hay entorno"; exit 1; }\n' > "$r/tools/setup.sh"
echo '{"setup":"tools/setup.sh"}' > "$r/.agents-kit.json"
(cd "$r" && git add -A && git commit -q -m setup && git push -q origin main) >/dev/null 2>&1 || fail "push setup"
export SETUP_LOG; SETUP_LOG="$(mktemp)"; export SETUP_OK="$(mktemp -d)/ok"
err="$(bash "$wt" abrir "$r" 40 uno 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 2 ] || fail "setup fallido debe dar 2: $rc"
case "$err" in *"setup falló (exit 1)"*"no hay entorno"*) ;; *) fail "setup msg: $err";; esac
[ -d "$KIT_WORKTREES/$name/issue-40-uno" ] || fail "el worktree debe quedarse tras setup fallido"
touch "$SETUP_OK"
out="$(bash "$wt" abrir "$r" 40 uno 2>&1)" || fail "reintento con setup: $out"
[ "$(last_line "$out")" = "FIN: $KIT_WORKTREES/$name/issue-40-uno" ] || fail "reintento sin FIN"
bash "$wt" abrir "$r" 40 uno >/dev/null 2>&1 || fail "tercera apertura"
[ "$(grep -c preparado "$SETUP_LOG")" -eq 2 ] || fail "setup debe correr hasta tener éxito y una sola vez: $(cat "$SETUP_LOG")"
echo '{"setup":"../x.sh"}' > "$r/.agents-kit.json"
bash "$wt" abrir "$r" 41 dos >/dev/null 2>"$tmpe"; rc=$?
[ $rc -eq 2 ] && grep -q "'\.\.'" "$tmpe" || fail "setup con .. debe dar 2: $rc"
git -C "$r" worktree remove --force "$KIT_WORKTREES/$name/issue-41-dos" 2>/dev/null; git -C "$r" branch -q -D issue-41-dos 2>/dev/null
echo '{"setup":"/bin/true"}' > "$r/.agents-kit.json"
bash "$wt" abrir "$r" 42 tres >/dev/null 2>"$tmpe"; rc=$?
[ $rc -eq 2 ] && grep -q absoluta "$tmpe" || fail "setup absoluto debe dar 2: $rc"
git -C "$r" worktree remove --force "$KIT_WORKTREES/$name/issue-42-tres" 2>/dev/null; git -C "$r" branch -q -D issue-42-tres 2>/dev/null
echo '{}' > "$r/.agents-kit.json"

# barrer: only clean worktrees of the kit dir that are finished (merged PR at the tip, or closed issue without commits)
bash "$wt" barrer "$r" extra >/dev/null 2>&1; [ $? -eq 1 ] || fail "barrer con argumentos debe dar 1"
for spec in "50 abierto" "51 cerrado" "52 fusionado" "53 sucio" "54 conpr" "55 ajeno"; do
  bash "$wt" abrir "$r" ${spec% *} ${spec#* } >/dev/null 2>&1 || fail "abrir $spec"
done
kw() { echo "$KIT_WORKTREES/$name/issue-$1"; }
(cd "$(kw 52-fusionado)" && echo m > m.txt && git add m.txt && git commit -q -m m) || fail "commit 52"
(cd "$(kw 54-conpr)" && echo c > c.txt && git add c.txt && git commit -q -m c) || fail "commit 54"
echo x > "$(kw 53-sucio)/sucio.txt"
outside="$(mktemp -d)/fuera"
git -C "$r" worktree add -q -b fuera --no-track "$outside" origin/main || fail "worktree fuera"
tip52="$(git -C "$(kw 52-fusionado)" rev-parse HEAD)"
cat > "$GH_STATE/state.json" <<JSON
{"issues":[{"number":50,"state":"OPEN","labels":[],"comments":[]},{"number":51,"state":"CLOSED","labels":[],"comments":[]},
  {"number":52,"state":"CLOSED","labels":[],"comments":[]},{"number":53,"state":"CLOSED","labels":[],"comments":[]},
  {"number":54,"state":"CLOSED","labels":[],"comments":[]},{"number":55,"state":"OPEN","labels":[],"comments":[]}],
 "prs":[{"number":8,"headRefName":"issue-52-fusionado","state":"MERGED","headRefOid":"$tip52"}]}
JSON
# gh failure: nothing is deleted
ghd="$(mktemp -d)"; realgh="$(command -v gh)"
printf '#!/bin/sh\n[ "$1 $2" = "pr list" ] && exit 1\nexec "%s" "$@"\n' "$realgh" > "$ghd/gh"; chmod +x "$ghd/gh"
PATH="$ghd:$PATH" bash "$wt" barrer "$r" >"$tmpe.o" 2>"$tmpe"; rc=$?
[ $rc -eq 0 ] && [ "$(last_line "$(cat "$tmpe.o")")" = "FIN: 0 borrados" ] || fail "barrer con gh roto: $rc $(cat "$tmpe.o")"
grep -q "^aviso:" "$tmpe" || fail "sin aviso con gh roto"
[ -d "$(kw 51-cerrado)" ] || fail "gh roto borró algo"
out="$(bash "$wt" barrer "$r" 2>"$tmpe")" || fail "barrer: $out"
[ "$(last_line "$out")" = "FIN: 2 borrados" ] || fail "barrer FIN: $out"
[ ! -e "$(kw 51-cerrado)" ] && ! git -C "$r" rev-parse -q --verify issue-51-cerrado >/dev/null || fail "issue cerrado sin commits debe borrarse"
[ ! -e "$(kw 52-fusionado)" ] && ! git -C "$r" rev-parse -q --verify issue-52-fusionado >/dev/null || fail "PR fusionada debe borrarse"
[ -d "$(kw 50-abierto)" ] || fail "barrer borró un worktree vivo de un issue abierto sin commits"
[ -d "$(kw 53-sucio)" ] || fail "barrer borró uno sucio"
[ -d "$(kw 54-conpr)" ] || fail "barrer borró uno con commits y sin PR fusionada"
[ -d "$(kw 55-ajeno)" ] || fail "barrer borró otro issue abierto"
[ -d "$outside" ] && git -C "$r" rev-parse -q --verify fuera >/dev/null || fail "barrer tocó un worktree ajeno al kit"
[ -d "$r" ] || fail "barrer tocó el árbol principal"
echo "OK test_worktree"
