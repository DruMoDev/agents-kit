#!/usr/bin/env bash
# Tests for scripts/kit-reglas.sh (estado, trinquete, blindado, abrir, cerrar), git real with a local bare origin.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
k="$REPO_ROOT/scripts/kit-reglas.sh"
last_line() { printf '%s\n' "$1" | sed -n '$p'; }

r="$(mk_repo)"; o="$(mktemp -d)"
git init -q --bare "$o"
(cd "$r" && git remote add origin https://github.com/dru/demo.git && git config "url.$o.insteadOf" "https://github.com/dru/demo.git" \
  && echo '{}' > .agents-kit.json && git add .agents-kit.json && git commit -q -m kit && git push -q -u origin main) >/dev/null 2>&1 \
  || fail "setup remoto"
git -C "$o" symbolic-ref HEAD refs/heads/main
# push_main: commit everything in the scratch repo to main and push it (the new base of origin/main).
push_main() { (cd "$r" && git add -A && git commit -q -m "$1" && git push -q origin main) >/dev/null 2>&1 || fail "push_main $1"; }
# limpia: back to origin/main, nothing local.
limpia() { git -C "$r" checkout -q main && git -C "$r" reset -q --hard origin/main && git -C "$r" clean -qfd; }
run() { out="$(bash "$k" "$@" 2>&1)"; rc=$?; }

# --- uso
run; [ $rc -eq 1 ] || fail "sin argumentos: exit $rc"
run trinquete "$r"; [ $rc -eq 1 ] || fail "trinquete sin ref: exit $rc"
run otro "$r"; [ $rc -eq 1 ] || fail "subcomando desconocido: exit $rc"
s="$(mktemp -d)"; run estado "$s"; [ $rc -eq 1 ] || fail "sin marcador: exit $rc"

# --- estado
printf 'echo hola\n' > "$r/x.sh"; push_main sh
run estado "$r"; [ $rc -eq 0 ] || fail "estado sin TS: $out"
[ "$(last_line "$out")" = "FIN: base completa" ] || fail "sin TS debe ser completa: $out"
for x in "lenguajes: sh" "lint: sin declarar" "deuda-lint: ninguna" "deuda-tsc: ninguna"; do
  grep -qxF "$x" <<<"$out" || fail "estado sin '$x': $out"
done
echo '{"lint": {"fichero": {"ts": "eslint"}}}' > "$r/.agents-kit.json"
cat > "$r/tsconfig.json" <<'EOF'
{ "compilerOptions": { "strict": true, "exactOptionalPropertyTypes" : true, "verbatimModuleSyntax": true,
  "noImplicitOverride": true, "noFallthroughCasesInSwitch": true, "strictNullChecks": true } }
EOF
run estado "$r"; [ $rc -eq 0 ] || fail "estado TS: $out"
[ "$(last_line "$out")" = "FIN: base incompleta" ] || fail "sin noUncheckedIndexedAccess debe ser incompleta: $out"
for x in "lenguajes: ts,sh" "lint: declarado" "tsconfig: strict sí" "tsconfig: noUncheckedIndexedAccess no" \
  "eslint: strictTypeChecked no" "eslint: noInlineConfig no" "knip: no"; do
  grep -qxF "$x" <<<"$out" || fail "estado TS sin '$x': $out"
done
sed -i.bak 's/"strict": true,/"strict": true, "noUncheckedIndexedAccess": true,/' "$r/tsconfig.json"; rm -f "$r/tsconfig.json.bak"
printf 'export default [tseslint.configs.strictTypeChecked, { linterOptions: { noInlineConfig: true } }];\n' > "$r/eslint.config.mjs"
echo '{}' > "$r/knip.json"
mkdir -p "$r/.agents-kit"
echo '{"src/a.ts": {"no-explicit-any": {"count": 2}, "no-floating-promises": {"count": 1}}, "src/b.ts": {"x": {"count": 1}}}' > "$r/eslint-suppressions.json"
echo '{"src/a.ts": 3}' > "$r/.agents-kit/tsc-base.json"
run estado "$r"
[ "$(last_line "$out")" = "FIN: base completa" ] || fail "base entera debe ser completa: $out"
for x in "tsconfig: noUncheckedIndexedAccess sí" "eslint: strictTypeChecked sí" "eslint: noInlineConfig sí" "knip: sí" \
  "deuda-lint: 3 entradas" "deuda-tsc: 1 ficheros"; do
  grep -qxF "$x" <<<"$out" || fail "estado completo sin '$x': $out"
done
rm "$r/tsconfig.json" "$r/knip.json"
echo '{"devDependencies": {"typescript": "x"}, "knip": {}}' > "$r/package.json"
run estado "$r"
grep -qxF "lenguajes: ts,sh" <<<"$out" && grep -qxF "knip: sí" <<<"$out" || fail "ts y knip por package.json: $out"
limpia

# --- trinquete
mkdir -p "$r/src" "$r/.agents-kit"
for f in a b c; do echo "export const $f = 1;" > "$r/src/$f.ts"; done
echo '{"src/a.ts": {"no-explicit-any": {"count": 2}}}' > "$r/eslint-suppressions.json"
echo '{"src/c.ts": 1}' > "$r/.agents-kit/tsc-base.json"
push_main deuda
run trinquete "$r" origin/main; [ $rc -eq 0 ] && [ "$(last_line "$out")" = "FIN: ok" ] || fail "sin cambios: $out"
git -C "$r" checkout -q -b pr
echo "// cambio" >> "$r/src/a.ts"
run trinquete "$r" origin/main; [ $rc -eq 1 ] || fail "tocar a.ts con deuda debe fallar: $out"
grep -qxF "deuda en fichero tocado: src/a.ts (lint)" <<<"$out" || fail "motivo a.ts: $out"
echo '{}' > "$r/eslint-suppressions.json"
run trinquete "$r" origin/main; [ $rc -eq 0 ] || fail "quitar sus entradas debe pasar: $out"
(cd "$r" && git add -A && git commit -q -m limpia) >/dev/null || fail "commit limpia"
run trinquete "$r" origin/main; [ $rc -eq 0 ] || fail "lo mismo confirmado debe pasar: $out"
echo "// cambio" >> "$r/src/c.ts"
run trinquete "$r" origin/main; [ $rc -eq 1 ] && grep -qxF "deuda en fichero tocado: src/c.ts (tipos)" <<<"$out" || fail "c.ts tipos: $out"
limpia; git -C "$r" branch -qD pr
echo '{"src/a.ts": {"no-explicit-any": {"count": 2}}, "src/b.ts": {"no-console": {"count": 1}}}' > "$r/eslint-suppressions.json"
run trinquete "$r" origin/main; [ $rc -eq 1 ] || fail "entrada nueva en b.ts debe fallar: $out"
grep -qxF "la deuda crece: src/b.ts no-console" <<<"$out" || fail "motivo b.ts: $out"
echo '{"src/a.ts": {"no-explicit-any": {"count": 3}}}' > "$r/eslint-suppressions.json"
run trinquete "$r" origin/main; [ $rc -eq 1 ] && grep -qxF "la deuda crece: src/a.ts no-explicit-any" <<<"$out" || fail "count mayor: $out"
limpia
echo '{"src/c.ts": 2}' > "$r/.agents-kit/tsc-base.json"
run trinquete "$r" origin/main; [ $rc -eq 1 ] && grep -qxF "la deuda crece: src/c.ts tipos" <<<"$out" || fail "tsc mayor: $out"
limpia
git -C "$r" rm -q src/a.ts
run trinquete "$r" origin/main; [ $rc -eq 1 ] && grep -qxF "deuda en fichero tocado: src/a.ts (lint)" <<<"$out" || fail "borrado con deuda: $out"
echo '{}' > "$r/eslint-suppressions.json"
run trinquete "$r" origin/main; [ $rc -eq 0 ] || fail "borrado y podado debe pasar: $out"
limpia
git -C "$r" mv src/c.ts src/d.ts
run trinquete "$r" origin/main; [ $rc -eq 1 ] && grep -qxF "deuda en fichero tocado: src/c.ts (tipos)" <<<"$out" || fail "renombrar cuenta como tocar: $out"
limpia
echo 'no json' > "$r/eslint-suppressions.json"
run trinquete "$r" origin/main; [ $rc -eq 2 ] || fail "supresiones rotas deben dar 2: $out"
limpia
run trinquete "$r" no-existe; [ $rc -eq 2 ] || fail "ref inexistente debe dar 2: $out"

# --- blindado
echo '{"scripts": {"lint": "eslint .", "test": "vitest"}, "devDependencies": {"eslint": "9", "vitest": "3"}}' > "$r/package.json"
echo 'export default [];' > "$r/eslint.config.mjs"
push_main blindado-base
run blindado "$r" origin/main; [ $rc -eq 0 ] && [ "$(last_line "$out")" = "FIN: 0" ] || fail "blindado sin cambios: $out"
grep -q '^hash:' <<<"$out" && fail "sin cambios no debe haber hash: $out"
echo 'export default [{}];' > "$r/eslint.config.mjs"
jq '.scripts.lint = "eslint src"' "$r/package.json" > "$r/p" && mv "$r/p" "$r/package.json"
run blindado "$r" origin/main; [ $rc -eq 0 ] || fail "blindado: $out"
[ "$(last_line "$out")" = "FIN: 2" ] || fail "FIN: 2: $out"
grep -qxF "eslint.config.mjs" <<<"$out" && grep -qxF "package.json (scripts.lint)" <<<"$out" || fail "lista blindado: $out"
h1="$(sed -n 's/^hash: //p' <<<"$out")"
[ ${#h1} -eq 64 ] || fail "hash sha256: '$h1'"
run blindado "$r" origin/main; [ "$(sed -n 's/^hash: //p' <<<"$out")" = "$h1" ] || fail "hash no determinista: $out"
echo 'export default [{ rules: {} }];' > "$r/eslint.config.mjs"
run blindado "$r" origin/main; h2="$(sed -n 's/^hash: //p' <<<"$out")"
[ -n "$h2" ] && [ "$h2" != "$h1" ] || fail "otro cambio debe dar otro hash: $h1 $h2"
jq '.scripts.lint = "eslint ."' "$r/package.json" > "$r/p" && mv "$r/p" "$r/package.json"
run blindado "$r" origin/main; h3="$(sed -n 's/^hash: //p' <<<"$out")"
[ "$h3" != "$h2" ] || fail "el cambio de package.json debe entrar en el hash"
limpia
jq '.dependencies.left = "1" | .scripts.test = "jest"' "$r/package.json" > "$r/p" && mv "$r/p" "$r/package.json"
run blindado "$r" origin/main; [ "$(last_line "$out")" = "FIN: 0" ] || fail "añadir dependencia no cuenta: $out"
jq 'del(.devDependencies.eslint)' "$r/package.json" > "$r/p" && mv "$r/p" "$r/package.json"
run blindado "$r" origin/main
grep -qxF "package.json (quitada eslint)" <<<"$out" && [ "$(last_line "$out")" = "FIN: 1" ] || fail "quitar eslint cuenta: $out"
limpia
echo '{}' > "$r/eslint-suppressions.json"; echo '{}' > "$r/.agents-kit/tsc-base.json"
run blindado "$r" origin/main; [ "$(last_line "$out")" = "FIN: 0" ] || fail "deuda que encoge no cuenta: $out"
echo '{"src/b.ts": {"x": {"count": 1}}}' > "$r/eslint-suppressions.json"
run blindado "$r" origin/main; grep -qxF "eslint-suppressions.json" <<<"$out" || fail "deuda que crece cuenta: $out"
limpia
# the worktree marker cannot weaken the list (it is read from <ref>)
echo '{"blindado": []}' > "$r/.agents-kit.json"; echo 'x' > "$r/tsconfig.base.json"; mkdir -p "$r/reglas"; echo x > "$r/reglas/r.mjs"
run blindado "$r" origin/main
for x in ".agents-kit.json" "tsconfig.base.json" "reglas/r.mjs"; do grep -qxF "$x" <<<"$out" || fail "blindado sin '$x': $out"; done
[ "$(last_line "$out")" = "FIN: 3" ] || fail "FIN con marcador y no versionados: $out"
limpia

# --- estado con un fichero de deuda roto: error de entorno, nunca "ninguna"
echo 'no json' > "$r/eslint-suppressions.json"
run estado "$r"; [ $rc -eq 2 ] || fail "estado con supresiones rotas debe dar 2: $out"
limpia
echo '[1' > "$r/.agents-kit/tsc-base.json"
run estado "$r"; [ $rc -eq 2 ] || fail "estado con tsc-base roto debe dar 2: $out"
limpia

# --- la puerta no falla abierta: si git diff falla, exit 2
realgit="$(command -v git)"; sb="$(mktemp -d)"
printf '#!/bin/sh\ncase " $* " in *" --name-only "*) echo "fallo simulado" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$realgit" > "$sb/git"
chmod +x "$sb/git"
echo "// cambio" >> "$r/src/a.ts"
out="$(PATH="$sb:$PATH" bash "$k" trinquete "$r" origin/main 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "trinquete con git diff roto debe dar 2: $rc $out"
echo x > "$r/eslint.config.mjs"
out="$(PATH="$sb:$PATH" bash "$k" blindado "$r" origin/main 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "blindado con git diff roto debe dar 2: $rc $out"
limpia

# --- package.json: versiones, overrides y scripts llamados por los de lint
pj() { jq "$1" "$r/package.json" > "$r/p" && mv "$r/p" "$r/package.json" || fail "pj $1"; }
pj '.scripts.lint = "npm run -s lint:base && pnpm check && yarn run fmt" | .scripts.check = "tsc" | .scripts.fmt = "prettier"
  | .scripts["lint:base"] = "eslint ." | .scripts.otro = "x" | .optionalDependencies = {"typescript": "5"}'
push_main pj-base
pj '.devDependencies.eslint = "10"'
run blindado "$r" origin/main
grep -qxF "package.json (cambiada eslint)" <<<"$out" && [ "$(last_line "$out")" = "FIN: 1" ] || fail "versión de eslint cambiada: $out"
h1="$(sed -n 's/^hash: //p' <<<"$out")"
pj '.devDependencies.eslint = "11"'
run blindado "$r" origin/main; [ "$(sed -n 's/^hash: //p' <<<"$out")" != "$h1" ] || fail "la versión debe entrar en el hash"
limpia
pj '.devDependencies.vitest = "4" | .scripts.otro = "y" | del(.optionalDependencies.typescript)'
run blindado "$r" origin/main
grep -qxF "package.json (quitada typescript)" <<<"$out" && [ "$(last_line "$out")" = "FIN: 1" ] || fail "quitada de optionalDependencies: $out"
limpia
pj '.scripts.check = "tsc -b" | .scripts.fmt = "prettier -w" | .scripts["lint:base"] = "eslint src"'
run blindado "$r" origin/main
for x in "package.json (scripts.check)" "package.json (scripts.fmt)" "package.json (scripts.lint:base)"; do
  grep -qxF "$x" <<<"$out" || fail "script llamado desde lint sin '$x': $out"
done
[ "$(last_line "$out")" = "FIN: 3" ] || fail "FIN scripts llamados: $out"
limpia
pj '.overrides = {"foo": {"eslint": "8"}, "react": "19"} | .resolutions = {"**/typescript": "5"} | .pnpm.overrides = {"knip@<5": "5"}'
run blindado "$r" origin/main
for x in "package.json (overrides foo>eslint)" "package.json (overrides **/typescript)" "package.json (overrides knip@<5)"; do
  grep -qxF "$x" <<<"$out" || fail "overrides sin '$x': $out"
done
[ "$(last_line "$out")" = "FIN: 3" ] || fail "overrides de react no cuenta: $out"
h1="$(sed -n 's/^hash: //p' <<<"$out")"
pj '.overrides.foo.eslint = "9"'
run blindado "$r" origin/main; [ "$(sed -n 's/^hash: //p' <<<"$out")" != "$h1" ] || fail "los overrides deben entrar en el hash"
limpia

# --- globs: * cruza /, prefijos y rutas con espacios
mkdir -p "$r/config" "$r/.github/workflows"
echo '{}' > "$r/config/tsconfig.base.json"; echo 'on: push' > "$r/.github/workflows/c i.yml"
run blindado "$r" origin/main
grep -qxF "config/tsconfig.base.json" <<<"$out" && grep -qxF ".github/workflows/c i.yml" <<<"$out" \
  && [ "$(last_line "$out")" = "FIN: 2" ] || fail "tsconfig en subdirectorio y workflow con espacios: $out"
push_main globs
echo 'on: pull_request' > "$r/.github/workflows/c i.yml"
run blindado "$r" origin/main
grep -qxF ".github/workflows/c i.yml" <<<"$out" && grep -q '^hash: ' <<<"$out" && [ "$(last_line "$out")" = "FIN: 1" ] \
  || fail "workflow versionado con espacios en el hash: $out"
limpia

# --- abrir y cerrar
w="$(mktemp -d)/wt"; git -C "$r" worktree add -q -b otra "$w" >/dev/null 2>&1 || fail "worktree"
f="$r/.git/agents-kit/reglas-abiertas"
run abrir "$w"; [ $rc -eq 1 ] || fail "abrir sin session_id: exit $rc"
run abrir "$w" sesion-123; [ $rc -eq 0 ] && [ "$(last_line "$out")" = "FIN: abierto" ] || fail "abrir: $out"
[ "$(cat "$f")" = "sesion-123" ] || fail "contenido de reglas-abiertas: $(cat "$f" 2>&1)"
run cerrar "$w"; [ $rc -eq 0 ] && [ "$(last_line "$out")" = "FIN: cerrado" ] || fail "cerrar: $out"
[ ! -e "$f" ] || fail "cerrar no borró el fichero"
run cerrar "$w"; [ $rc -eq 0 ] || fail "cerrar dos veces: $out"

echo ok
