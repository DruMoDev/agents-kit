#!/usr/bin/env bash
# Tests for scripts/kit-changelog.sh validar.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
cl="$REPO_ROOT/scripts/kit-changelog.sh"
fx="$TESTS_DIR/fixtures/changelog"
last_line() { printf '%s\n' "$1" | sed -n '$p'; }

r="$(mk_repo)"; echo '{}' > "$r/.agents-kit.json"
run() { # <fixture>: copy it as CHANGELOG.md in $r and validate; sets out/rc
  cp "$fx/$1" "$r/CHANGELOG.md"
  out="$(bash "$cl" validar "$r" 2>&1)"; rc=$?
}

# sin marcador
m="$(mk_repo)"; bash "$cl" validar "$m" >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin marcador debe dar 1"
# sin changelog
out="$(bash "$cl" validar "$r" 2>&1)" || fail "sin changelog: $out"
[ "$out" = "FIN: sin-changelog" ] || fail "sin-changelog: $out"

# válidos
run valido-vacio.md; [ $rc -eq 0 ] && [ "$out" = "FIN: valido 0 entradas" ] || fail "vacío: $rc $out"
mkdir -p "$r/docs/changelog"; echo png > "$r/docs/changelog/12-login.png"
run valido-completo.md; [ $rc -eq 0 ] && [ "$(last_line "$out")" = "FIN: valido 4 entradas" ] || fail "completo: $rc $out"
cp "$REPO_ROOT/templates/CHANGELOG.md" "$r/CHANGELOG.md"
out="$(bash "$cl" validar "$r" 2>&1)"; [ $? -eq 0 ] && [ "$out" = "FIN: valido 0 entradas" ] || fail "plantilla: $out"

# inválidos: exit 1 y error en la línea correcta
chk() { # <fixture> <línea> <texto>
  run "$1"; [ $rc -eq 1 ] || fail "$1 debe dar 1: $rc $out"
  case "$out" in *"CHANGELOG.md:$2: "*"$3"*) ;; *) fail "$1: esperaba línea $2 con '$3': $out";; esac
  [ "$(printf '%s\n' "$out" | grep -c '^CHANGELOG.md:')" -eq 1 ] || fail "$1: un solo error: $out"
  case "$out" in *FIN:*) fail "$1: no debe imprimir FIN";; esac
}
chk invalido-tipo.md 5 "tipo inválido"
chk invalido-orden.md 7 "descendente"
chk invalido-enlace.md 5 "no coincide"
chk invalido-imagen.md 6 "no existe"

# imagen grande: aviso, exit 0
cp "$fx/invalido-imagen.md" "$r/CHANGELOG.md"
head -c 614400 /dev/zero > "$r/docs/changelog/no-existe.png"
out="$(bash "$cl" validar "$r" 2>&1)"; rc=$?
[ $rc -eq 0 ] || fail "imagen grande: $rc $out"
case "$out" in *"aviso: "*"500 KB"*) ;; *) fail "sin aviso: $out";; esac
[ "$(last_line "$out")" = "FIN: valido 1 entradas" ] || fail "imagen grande FIN: $out"
# imagen http no se comprueba
printf '## 2026-10-18\n\n### Nuevo: A · [#1](https://github.com/a/b/pull/1)\n![x](https://example.com/x.png)\n' > "$r/CHANGELOG.md"
out="$(bash "$cl" validar "$r" 2>&1)" || fail "imagen http: $out"
# fecha repetida
printf '## 2026-10-18\n## 2026-10-18\n' > "$r/CHANGELOG.md"
bash "$cl" validar "$r" >/dev/null 2>&1; [ $? -eq 1 ] || fail "fecha repetida"
# fecha inexistente
printf '## 2026-02-30\n' > "$r/CHANGELOG.md"
bash "$cl" validar "$r" >/dev/null 2>&1; [ $? -eq 1 ] || fail "fecha inexistente"
# entrada sin fecha
printf '### Nuevo: A · [#1](https://github.com/a/b/pull/1)\n' > "$r/CHANGELOG.md"
bash "$cl" validar "$r" >/dev/null 2>&1; [ $? -eq 1 ] || fail "entrada sin fecha"
# título vacío
printf '## 2026-10-18\n### Nuevo:  · [#1](https://github.com/a/b/pull/1)\n' > "$r/CHANGELOG.md"
bash "$cl" validar "$r" >/dev/null 2>&1; [ $? -eq 1 ] || fail "título vacío"

# --- resumen en el issue fijado "📦 Changelog"
rr="$(mk_repo)"; echo '{}' > "$rr/.agents-kit.json"
git -C "$rr" remote add origin https://github.com/dru/demo.git
sfile="$(mktemp)"; printf 'Fusionadas: #4\n' > "$sfile"
use_flow_gh
flow_add_issue 3 "📦 Changelog viejo"
flow_add_issue 9 "📦 Changelog"
out="$(bash "$cl" resumen "$rr" run-1 "$sfile" 2>&1)" || fail "resumen: exit $? ($out)"
[ "$(last_line "$out")" = "FIN: https://github.com/dru/demo/issues/9#issuecomment-IC_9_0" ] || fail "resumen FIN: $out"
[ "$(flow_issue 9 '.comments | length')" = 1 ] || fail "resumen: no comentó en #9"
[ "$(flow_issue 9 '.comments[0].body')" = "$(printf '<!-- kit-resumen: run-1 -->\nFusionadas: #4')" ] \
  || fail "resumen: cuerpo '$(flow_issue 9 '.comments[0].body')'"
[ "$(flow_issue 3 '.comments | length')" = 0 ] || fail "resumen: comentó en un título parecido"
while IFS= read -r line; do
  case "$line" in api\ user*|*"--repo dru/demo"*) ;; *) fail "resumen: gh sin --repo: $line";; esac
done < "$GH_LOG"
# segunda llamada: no duplica
out="$(bash "$cl" resumen "$rr" run-1 "$sfile" 2>&1)" || fail "resumen repetido: exit $? ($out)"
[ "$(flow_issue 9 '.comments | length')" = 1 ] || fail "resumen repetido: duplicó el comentario"
[ "$(last_line "$out")" = "FIN: https://github.com/dru/demo/issues/9#issuecomment-IC_9_0" ] || fail "resumen repetido FIN: $out"
# otro id sí publica
bash "$cl" resumen "$rr" run-2 "$sfile" >/dev/null 2>&1 || fail "resumen otro id"
[ "$(flow_issue 9 '.comments | length')" = 2 ] || fail "resumen otro id: no publicó"
# un comentario con el marcador de otro autor no cuenta
use_flow_gh
flow_add_issue 9 "📦 Changelog"
tmp="$(mktemp)"
jq '(.issues[0].comments) += [{id: "IC_x", body: "<!-- kit-resumen: run-1 -->\nfalso", author: {login: "intruso"}}]' \
  "$GH_STATE/state.json" > "$tmp" && mv "$tmp" "$GH_STATE/state.json"
out="$(bash "$cl" resumen "$rr" run-1 "$sfile" 2>&1)" || fail "resumen ajeno: exit $? ($out)"
[ "$(flow_issue 9 '.comments | length')" = 2 ] || fail "resumen ajeno: no publicó el suyo"
case "$(last_line "$out")" in *issuecomment-IC_x) fail "resumen ajeno: devolvió el comentario ajeno";; esac
# sin issue fijado
use_flow_gh
flow_add_issue 9 "Otra cosa"
err="$(bash "$cl" resumen "$rr" run-1 "$sfile" 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 2 ] || fail "sin issue fijado: exit $rc"
case "$err" in *'no hay issue "📦 Changelog": ejecuta kit-on'*) ;; *) fail "sin issue fijado: '$err'";; esac
# uso y marcador
bash "$cl" resumen "$rr" run-1 >/dev/null 2>&1; [ $? -eq 1 ] || fail "resumen sin fichero: uso"
bash "$cl" resumen "$rr" run-1 /no/existe >/dev/null 2>&1; [ $? -eq 1 ] || fail "resumen fichero inexistente"
bash "$cl" resumen "$rr" 'mal id' "$sfile" >/dev/null 2>&1; [ $? -eq 1 ] || fail "resumen id inválido"
use_flow_gh
bash "$cl" resumen "$m" run-1 "$sfile" >/dev/null 2>&1; [ $? -eq 1 ] || fail "resumen sin marcador"
[ -s "$GH_LOG" ] && fail "resumen sin marcador: llamó a gh"
echo "OK test_changelog"
