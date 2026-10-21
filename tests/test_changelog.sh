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
echo "OK test_changelog"
