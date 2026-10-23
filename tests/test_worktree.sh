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

# MERGED and clean; origin/main moved meanwhile (the merge): the main clone fast-forwards
other="$(mktemp -d)"
(git clone -q "$o" "$other" && cd "$other" && git config user.email t@e && git config user.name t \
  && echo m > merged.txt && git add merged.txt && git commit -q -m merged && git push -q origin main) >/dev/null 2>&1 \
  || fail "mover origin/main"
echo local > "$r/notas-de-dru.txt"
out="$(bash "$wt" limpiar "$r" 3 2>&1)" || fail "limpiar: $out"
[ "$(last_line "$out")" = "FIN: limpio" ] || fail "limpiar sin FIN"
case "$out" in *"principal al día con origin/main ($(git -C "$r" rev-parse --short HEAD))"*) ;; *) fail "sin principal al día: $out";; esac
[ "$(git -C "$r" rev-parse HEAD)" = "$(git -C "$other" rev-parse HEAD)" ] || fail "el principal no avanzó"
[ "$(cat "$r/notas-de-dru.txt")" = local ] || fail "avanzar el principal tocó trabajo sin confirmar"
rm "$r/notas-de-dru.txt"
[ ! -e "$path" ] || fail "queda el worktree"
git -C "$r" rev-parse -q --verify issue-3-foo >/dev/null && fail "queda la rama"
while IFS= read -r line; do case "$line" in *"dru/demo"*) ;; *) fail "gh sin repo: $line";; esac; done < "$GH_LOG"

[ -d "$path31" ] && git -C "$r" rev-parse -q --verify issue-31-bar >/dev/null || fail "limpiar 3 tocó el issue 31"

# nothing to clean
bash "$wt" limpiar "$r" 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin worktree debe dar 1"
# a modified tracked file that the advance would overwrite: git refuses, the file is kept and it says why
(cd "$other" && git pull -q && echo nuevo > README.md && git commit -q -am readme && git push -q origin main) >/dev/null 2>&1 || fail "mover main 3"
echo "edición de Dru" > "$r/README.md"
bash "$wt" abrir "$r" 32 baz >/dev/null 2>&1 || fail "abrir 32"
jq --arg oid "$(git -C "$r" rev-parse issue-32-baz)" \
  '.prs = [{number: 4, headRefName: "issue-32-baz", state: "MERGED", headRefOid: $oid, body: "", comments: []}]' \
  "$GH_STATE/state.json" > "$GH_STATE/s" && mv "$GH_STATE/s" "$GH_STATE/state.json"
before="$(git -C "$r" rev-parse HEAD)"
out="$(bash "$wt" limpiar "$r" 32 2>&1)" || fail "limpiar con README editado: $out"
case "$out" in *"AVISO: el principal NO se pudo avanzar a origin/main"*) ;; *) fail "sin AVISO de avance rechazado: $out";; esac
[ "$(cat "$r/README.md")" = "edición de Dru" ] && [ "$(git -C "$r" rev-parse HEAD)" = "$before" ] || fail "el avance pisó la edición de Dru"
git -C "$r" checkout -q README.md && git -C "$r" merge -q --ff-only origin/main || fail "restaurar README"

# main clone on another branch: limpiar still cleans, the main clone is not moved and it says why
(cd "$other" && echo n > n.txt && git add n.txt && git commit -q -m n && git push -q origin main) >/dev/null 2>&1 || fail "mover main 2"
git -C "$r" checkout -q -b trabajo-de-dru || fail "rama de Dru"
before="$(git -C "$r" rev-parse main)"
jq --arg oid "$(git -C "$r" rev-parse issue-31-bar)" \
  '.prs = [{number: 2, headRefName: "issue-31-bar", state: "MERGED", headRefOid: $oid, body: "", comments: []}]' \
  "$GH_STATE/state.json" > "$GH_STATE/s" && mv "$GH_STATE/s" "$GH_STATE/state.json"
out="$(bash "$wt" limpiar "$r" 31 2>&1)" || fail "limpiar en otra rama: $out"
[ "$(last_line "$out")" = "FIN: limpio" ] || fail "limpiar en otra rama sin FIN"
case "$out" in *"AVISO: el repo principal está en 'trabajo-de-dru', no en 'main': no se actualiza."*) ;; *) fail "sin AVISO de rama: $out";; esac
[ "$(git -C "$r" rev-parse main)" = "$before" ] && [ "$(git -C "$r" branch --show-current)" = trabajo-de-dru ] || fail "tocó la rama de Dru"
git -C "$r" checkout -q main && git -C "$r" merge -q --ff-only origin/main || fail "volver a main"
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

# abrir an issue that went on in another clone (or the cloud): the local branch catches up by fast-forward
bash "$wt" abrir "$r" 60 viejo >/dev/null 2>&1 || fail "abrir 60"
p60="$KIT_WORKTREES/$name/issue-60-viejo"
(cd "$p60" && echo a > a60.txt && git add a60.txt && git commit -q -m a60 && git push -q origin HEAD) >/dev/null 2>&1 || fail "push 60"
o60="$(mktemp -d)"
(git clone -q "$o" "$o60" && cd "$o60" && git config user.email t@e && git config user.name t && git checkout -q issue-60-viejo \
  && echo b > b60.txt && git add b60.txt && git commit -q -m b60 && git push -q origin issue-60-viejo) >/dev/null 2>&1 || fail "avance remoto 60"
out="$(bash "$wt" abrir "$r" 60 viejo 2>&1)" || fail "abrir 60 retomado: $out"
case "$out" in *"ya existía"*"rama al día con origin/issue-60-viejo"*) ;; *) fail "abrir 60 retomado: $out";; esac
[ "$(git -C "$p60" rev-parse HEAD)" = "$(git -C "$o60" rev-parse HEAD)" ] || fail "la rama local no avanzó a origin"
# diverged: never merged here, exit 1 saying both tips
(cd "$p60" && echo c > c60.txt && git add c60.txt && git commit -q -m c60) || fail "commit local 60"
(cd "$o60" && echo d > d60.txt && git add d60.txt && git commit -q -m d60 && git push -q origin issue-60-viejo) >/dev/null 2>&1 || fail "avance remoto 60 bis"
err="$(bash "$wt" abrir "$r" 60 viejo 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "rama divergida: exit $rc ($err)"
case "$err" in *"han divergido"*) ;; *) fail "rama divergida: $err";; esac
git -C "$r" worktree remove --force "$p60" && git -C "$r" branch -q -D issue-60-viejo || fail "quitar 60"
git -C "$r" push -q origin --delete issue-60-viejo 2>/dev/null

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
