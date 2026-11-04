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
grep -qxF "la deuda crece: src/b.ts no-console (eslint-suppressions.json)" <<<"$out" || fail "motivo b.ts: $out"
echo '{"src/a.ts": {"no-explicit-any": {"count": 3}}}' > "$r/eslint-suppressions.json"
run trinquete "$r" origin/main; [ $rc -eq 1 ] && grep -qxF "la deuda crece: src/a.ts no-explicit-any (eslint-suppressions.json)" <<<"$out" || fail "count mayor: $out"
limpia
echo '{"src/c.ts": 2}' > "$r/.agents-kit/tsc-base.json"
run trinquete "$r" origin/main; [ $rc -eq 1 ] && grep -qxF "la deuda crece: src/c.ts tipos (.agents-kit/tsc-base.json)" <<<"$out" || fail "tsc mayor: $out"
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
pj '.scripts.prelint = "x" | .scripts.postcheck = "y" | .scripts["prelint:base"] = "z" | .scripts.preotro = "w"'
run blindado "$r" origin/main
for x in "package.json (scripts.prelint)" "package.json (scripts.postcheck)" "package.json (scripts.prelint:base)"; do
  grep -qxF "$x" <<<"$out" || fail "pre/post sin '$x': $out"
done
[ "$(last_line "$out")" = "FIN: 3" ] || fail "preotro no cuenta: $out"
h1="$(sed -n 's/^hash: //p' <<<"$out")"
pj '.scripts.prelint = "x2"'
run blindado "$r" origin/main; [ "$(sed -n 's/^hash: //p' <<<"$out")" != "$h1" ] || fail "pre/post deben entrar en el hash"
limpia
pj '.dependencies.eslint = .devDependencies.eslint | del(.devDependencies.eslint)'
run blindado "$r" origin/main; [ "$(last_line "$out")" = "FIN: 0" ] || fail "mover eslint de sección no cuenta: $out"
limpia
pj '.overrides = {"foo": {"eslint": "8"}, "react": "19"} | .resolutions = {"**/typescript": "5"} | .pnpm.overrides = {"knip@<5": "5"}'
run blindado "$r" origin/main
# pnpm.overrides is covered by the whole pnpm object: one line, no duplicate
for x in "package.json (overrides foo>eslint)" "package.json (overrides **/typescript)" "package.json (pnpm)"; do
  grep -qxF "$x" <<<"$out" || fail "overrides sin '$x': $out"
done
[ "$(last_line "$out")" = "FIN: 3" ] || fail "overrides de react no cuenta: $out"
h1="$(sed -n 's/^hash: //p' <<<"$out")"
pj '.overrides.foo.eslint = "9"'
run blindado "$r" origin/main; [ "$(sed -n 's/^hash: //p' <<<"$out")" != "$h1" ] || fail "los overrides deben entrar en el hash"
limpia
# claves de configuración de package.json, enteras
pj '.eslintConfig = {"rules": {}} | .knip = {"entry": []} | .patchedDependencies = {"x@1": "patches/x.patch"}
  | .pnpm.patchedDependencies = {"y@1": "patches/y.patch"} | .pnpm.packageExtensions = {"z": {}}
  | .eslintIgnore = ["dist"] | .packageManager = "pnpm@9.0.0"'
run blindado "$r" origin/main
for x in "package.json (eslintConfig)" "package.json (knip)" "package.json (patchedDependencies)" "package.json (pnpm)" \
  "package.json (eslintIgnore)" "package.json (packageManager)"; do
  grep -qxF "$x" <<<"$out" || fail "claves de package.json sin '$x': $out"
done
[ "$(last_line "$out")" = "FIN: 6" ] || fail "pnpm debe salir una vez: $out"
h1="$(sed -n 's/^hash: //p' <<<"$out")"
pj '.pnpm.packageExtensions.z = {"a": 1}'
run blindado "$r" origin/main; [ "$(sed -n 's/^hash: //p' <<<"$out")" != "$h1" ] || fail "las claves deben entrar en el hash"
limpia
# cierre transitivo de los scripts: cadena, hooks que llaman a otros y ciclos
pj '.scripts.check = "pnpm run a" | .scripts.a = "bun run b" | .scripts.b = "x" | .scripts.prelint = "npm run c" | .scripts.c = "y"
  | .scripts.fmt = "npm run d" | .scripts.d = "npm run e" | .scripts.e = "yarn d" | .scripts.otro = "q"'
push_main cierre
pj '.scripts.b = "x2"'
run blindado "$r" origin/main; grep -qxF "package.json (scripts.b)" <<<"$out" && [ "$(last_line "$out")" = "FIN: 1" ] || fail "cadena lint>check>a>b: $out"
limpia
pj '.scripts.c = "y2" | .scripts.postc = "nuevo"'
run blindado "$r" origin/main
grep -qxF "package.json (scripts.c)" <<<"$out" && grep -qxF "package.json (scripts.postc)" <<<"$out" && [ "$(last_line "$out")" = "FIN: 2" ] \
  || fail "prelint llama a c: $out"
limpia
pj '.scripts.e = "yarn d && echo"'
run blindado "$r" origin/main; grep -qxF "package.json (scripts.e)" <<<"$out" || fail "ciclo d>e>d: $out"
limpia
pj '.scripts.otro = "q2"'
run blindado "$r" origin/main; [ "$(last_line "$out")" = "FIN: 0" ] || fail "script ajeno no cuenta: $out"
limpia
# un script del árbol que entra en el cierre también cuenta (la unión de base y árbol)
pj '.scripts.b = "npm run nuevo" | .scripts.nuevo = "z"'
run blindado "$r" origin/main
grep -qxF "package.json (scripts.b)" <<<"$out" && grep -qxF "package.json (scripts.nuevo)" <<<"$out" || fail "cierre del árbol: $out"
limpia
# package.json anidados: la misma comparación, con su ruta delante; fuera de node_modules
mkdir -p "$r/web"
echo '{"scripts": {"lint": "eslint ."}, "devDependencies": {"eslint": "9"}}' > "$r/web/package.json"
run blindado "$r" origin/main
grep -qxF "web/package.json (scripts.lint)" <<<"$out" && [ "$(last_line "$out")" = "FIN: 1" ] || fail "package.json anidado nuevo: $out"
mkdir -p "$r/app"; cp "$r/web/package.json" "$r/app/package.json"
push_main anidado
pjw() { jq "$1" "$r/web/package.json" > "$r/p" && mv "$r/p" "$r/web/package.json" || fail "pjw $1"; }
pjw '.scripts.lint = "true"'
run blindado "$r" origin/main
grep -qxF "web/package.json (scripts.lint)" <<<"$out" && [ "$(last_line "$out")" = "FIN: 1" ] || fail "scripts.lint anidado: $out"
h1="$(sed -n 's/^hash: //p' <<<"$out")"; [ ${#h1} -eq 64 ] || fail "hash del anidado: $out"
run blindado "$r" origin/main; [ "$(sed -n 's/^hash: //p' <<<"$out")" = "$h1" ] || fail "hash del anidado no determinista: $out"
git -C "$r" checkout -q -- web/package.json
jq '.scripts.lint = "true"' "$r/app/package.json" > "$r/p" && mv "$r/p" "$r/app/package.json"
run blindado "$r" origin/main; h2="$(sed -n 's/^hash: //p' <<<"$out")"
grep -qxF "app/package.json (scripts.lint)" <<<"$out" && [ -n "$h2" ] && [ "$h2" != "$h1" ] || fail "la ruta debe entrar en el hash: $out"
limpia
pjw '.dependencies.left = "1"'
run blindado "$r" origin/main; [ "$(last_line "$out")" = "FIN: 0" ] || fail "dependencia normal en el anidado no cuenta: $out"
limpia
rm "$r/web/package.json"
run blindado "$r" origin/main
grep -qxF "web/package.json (scripts.lint)" <<<"$out" && grep -qxF "web/package.json (quitada eslint)" <<<"$out" \
  && [ "$(last_line "$out")" = "FIN: 2" ] || fail "package.json anidado borrado: $out"
limpia
mkdir -p "$r/node_modules/x"; echo '{"scripts": {"lint": "true"}}' > "$r/node_modules/x/package.json"
run blindado "$r" origin/main; [ "$(last_line "$out")" = "FIN: 0" ] || fail "node_modules no cuenta: $out"
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

mkdir -p "$r/packages/web" "$r/packages/a" "$r/src"
echo 'export default [];' > "$r/packages/web/eslint.config.mjs"; echo '{}' > "$r/packages/a/knip.json"
echo 'registry=x' > "$r/.npmrc"; echo x > "$r/src/myknip.ts"; echo x > "$r/src/noteslint.config.js"
run blindado "$r" origin/main
for x in "packages/web/eslint.config.mjs" "packages/a/knip.json" ".npmrc"; do grep -qxF "$x" <<<"$out" || fail "glob sin '$x': $out"; done
[ "$(last_line "$out")" = "FIN: 3" ] || fail "myknip.ts y noteslint.config.js no son blindados: $out"
limpia
mkdir -p "$r/packages/a" "$r/patches" "$r/.yarn/plugins" "$r/src"
echo x > "$r/packages/a/.eslintignore"; echo x > "$r/src/foo.eslintignore"; echo x > "$r/packages/a/.npmrc"
mkdir -p "$r/.yarn/cache"; echo x > "$r/.yarn/cache/x.zip"
echo x > "$r/patches/x.patch"; echo x > "$r/.yarn/plugins/p.cjs"; echo '{}' > "$r/.knip.jsonc"; echo x > "$r/.pnpmfile.cjs"
echo x > "$r/.yarnrc"; echo x > "$r/packages/a/bunfig.toml"
run blindado "$r" origin/main
for x in "packages/a/.eslintignore" "packages/a/.npmrc" "patches/x.patch" ".yarn/plugins/p.cjs" ".knip.jsonc" ".pnpmfile.cjs" \
  ".yarnrc" "packages/a/bunfig.toml"; do
  grep -qxF "$x" <<<"$out" || fail "glob sin '$x': $out"
done
[ "$(last_line "$out")" = "FIN: 8" ] || fail "foo.eslintignore y .yarn/cache no son blindados: $out"
limpia

# --- estado por proyecto TS (monorepos): cada directorio con package.json y tsconfig.json, fuera de node_modules
m="$(mk_repo)"; echo '{}' > "$m/.agents-kit.json"
# base_ts <dir>: the whole base in <dir> (tsconfig with the six flags, eslint config, knip)
base_ts() {
  mkdir -p "$1"; echo '{}' > "$1/package.json"
  printf '{"compilerOptions": {%s}}\n' '"strict": true, "noUncheckedIndexedAccess": true, "exactOptionalPropertyTypes": true, "verbatimModuleSyntax": true, "noImplicitOverride": true, "noFallthroughCasesInSwitch": true' > "$1/tsconfig.json"
  printf 'export default [strictTypeChecked, { linterOptions: { noInlineConfig: true } }];\n' > "$1/eslint.config.mjs"
  echo '{}' > "$1/knip.json"
}
mkdir -p "$m/web"; echo '{}' > "$m/web/package.json"; echo '{}' > "$m/web/tsconfig.json"
run estado "$m"; [ $rc -eq 0 ] || fail "estado web: $out"
[ "$(last_line "$out")" = "FIN: base incompleta" ] || fail "web sin base debe ser incompleta: $out"
for x in "lenguajes: ts" "proyecto: web (ts, base incompleta)" "tsconfig: strict no" "knip: no"; do
  grep -qxF "$x" <<<"$out" || fail "estado web sin '$x': $out"
done
[ "$(grep -c '^deuda-lint:' <<<"$out")" = 2 ] || fail "deuda de la raíz y de web: $out"
grep -q '^proyecto: \.' <<<"$out" && fail "la raíz sin TS no es proyecto: $out"
rm -rf "$m/web"; base_ts "$m/web"
run estado "$m"; [ "$(last_line "$out")" = "FIN: base incompleta" ] || fail "sin lint declarado debe ser incompleta: $out"
grep -qxF "proyecto: web (ts, base incompleta)" <<<"$out" || fail "sin lint, web incompleta: $out"
echo '{"lint": {"fichero": {"ts": "eslint"}}}' > "$m/.agents-kit.json"
run estado "$m"; [ "$(last_line "$out")" = "FIN: base completa" ] && grep -qxF "proyecto: web (ts, base completa)" <<<"$out" \
  || fail "web con base debe ser completa: $out"
mkdir -p "$m/web/.agents-kit"; echo '{"src/a.ts": 2}' > "$m/web/.agents-kit/tsc-base.json"
run estado "$m"; grep -qxF "deuda-tsc: 1 ficheros" <<<"$out" || fail "deuda de web: $out"
# two packages, one without the base; a directory name with repeated spaces and a tab
base_ts "$m/packages/a  b"; base_ts "$m/packages/t	u"; mkdir -p "$m/packages/c"; echo '{}' > "$m/packages/c/package.json"; echo '{}' > "$m/packages/c/tsconfig.json"
run estado "$m"; [ "$(last_line "$out")" = "FIN: base incompleta" ] || fail "un paquete sin base: $out"
for x in "proyecto: packages/a  b (ts, base completa)" "proyecto: packages/c (ts, base incompleta)" "proyecto: web (ts, base completa)" \
  "proyecto: packages/t"$'\t'"u (ts, base completa)"; do
  grep -qxF "$x" <<<"$out" || fail "monorepo sin '$x': $out"
done
rm -rf "$m/packages/c"
# a name that starts with - is a directory, never an option
base_ts "$m/-app"; run estado "$m"; [ $rc -eq 0 ] && grep -qxF "proyecto: -app (ts, base completa)" <<<"$out" || fail "proyecto -app: $rc $out"
mkdir -p "$m/-app/.agents-kit"; echo '{"src/a.ts": 1}' > "$m/-app/.agents-kit/tsc-base.json"
run estado "$m"; [ $rc -eq 0 ] || fail "deuda de -app: $rc $out"
rm -rf "$m/-app"
# not projects: a tsconfig.*.json alone, a tsconfig.json without package.json, node_modules, ignored directories
mkdir -p "$m/tools" "$m/lib" "$m/node_modules/x" "$m/web/node_modules/y" "$m/gen"
echo '{}' > "$m/tools/package.json"; echo '{}' > "$m/tools/tsconfig.build.json"; echo '{}' > "$m/lib/tsconfig.json"
for d in node_modules/x web/node_modules/y gen; do echo '{}' > "$m/$d/package.json"; echo '{}' > "$m/$d/tsconfig.json"; done
echo 'gen/' > "$m/.gitignore"
run estado "$m"; [ "$(last_line "$out")" = "FIN: base completa" ] || fail "nada de eso es un proyecto: $out"
[ "$(grep -c '^proyecto:' <<<"$out")" = 3 ] || fail "solo web, packages/a  b y packages/t u: $out"
# git failing is an environment error, never "no projects"
mv "$m/.git" "$m/.git-off"; run estado "$m"; [ $rc -eq 2 ] || fail "estado con git roto debe dar 2: $rc $out"; mv "$m/.git-off" "$m/.git"
# a single app in the root: the root is the project, its debt lines once
s1="$(mk_repo)"; echo '{"lint": {"fichero": {"ts": "eslint"}}}' > "$s1/.agents-kit.json"; base_ts "$s1"
run estado "$s1"; [ "$(last_line "$out")" = "FIN: base completa" ] && grep -qxF "proyecto: . (ts, base completa)" <<<"$out" \
  || fail "app en la raíz: $out"
[ "$(grep -c '^deuda-lint:' <<<"$out")" = 1 ] || fail "deuda de la raíz una vez: $out"

# --- estado: proyecto JS (tsconfig con allowJs solo para que typescript-eslint infiera tipos) frente a uno TS
j="$(mk_repo)"; echo '{"lint": {"fichero": {"ts,mjs": "eslint"}}}' > "$j/.agents-kit.json"
base_ts "$j/web"; mkdir -p "$j/web/src"; echo 'export const a: number = 1;' > "$j/web/src/main.ts"
mkdir -p "$j/social-apps/api/src" "$j/social-apps/scripts" "$j/social-apps/test" "$j/social-apps/types"
echo '{"type": "module", "devDependencies": {"eslint": "x", "typescript": "x", "typescript-eslint": "x"}}' > "$j/social-apps/package.json"
cat > "$j/social-apps/tsconfig.json" <<'EOF2'
{
  "//": ["Solo para que typescript-eslint infiera tipos: no compila nada."],
  "compilerOptions": { "allowJs": true, "checkJs": false, "noEmit": true, "module": "esnext", "target": "esnext" },
  "include": ["**/*.mjs", "**/*.js"]
}
EOF2
echo 'export default { fetch: async () => new Response("ok") };' > "$j/social-apps/api/src/index.mjs"
echo 'await fetch("http://localhost");' > "$j/social-apps/scripts/smoke.mjs"
echo 'import { test } from "node:test"; test("x", () => {});' > "$j/social-apps/test/api.test.mjs"
echo 'declare const ENV: string;' > "$j/social-apps/types/env.d.ts"
run estado "$j"; [ $rc -eq 0 ] || fail "estado JS: $out"
[ "$(last_line "$out")" = "FIN: base incompleta" ] || fail "JS sin base debe ser incompleta: $out"
for x in "lenguajes: ts,js" "proyecto: social-apps (js, base incompleta)" "proyecto: web (ts, base completa)" \
  "tsconfig: checkJs no (opcional)" "eslint: strictTypeChecked no" "knip: no"; do
  grep -qxF "$x" <<<"$out" || fail "estado JS sin '$x': $out"
done
[ "$(grep -c '^tsconfig: strict ' <<<"$out")" = 1 ] || fail "las opciones estrictas solo en el proyecto TS: $out"
# the JS base: strictNullChecks (by strict or by itself), strictTypeChecked, noInlineConfig and knip, without the other
# strict tsconfig flags
printf 'export default [tseslint.configs.strictTypeChecked, { linterOptions: { noInlineConfig: true } }];\n' > "$j/social-apps/eslint.config.js"
echo '{}' > "$j/social-apps/knip.json"
run estado "$j"; [ "$(last_line "$out")" = "FIN: base incompleta" ] && grep -qxF "proyecto: social-apps (js, base incompleta)" <<<"$out" \
  && grep -qxF "tsconfig: strictNullChecks no" <<<"$out" || fail "JS sin strictNullChecks debe ser incompleta: $out"
# js_tsc <opciones>: the tsconfig of social-apps with these extra compilerOptions
js_tsc() {
  printf '{\n  "compilerOptions": { "allowJs": true, "checkJs": false, "noEmit": true, %s },\n  "include": ["**/*.mjs", "**/*.js"]\n}\n' "$1" \
    > "$j/social-apps/tsconfig.json"
}
js_tsc '"strict": true, "strictNullChecks": false'
run estado "$j"; grep -qxF "proyecto: social-apps (js, base incompleta)" <<<"$out" && grep -qxF "tsconfig: strictNullChecks no" <<<"$out" \
  || fail "strict con strictNullChecks false no cuenta: $out"
# tsconfig.json is JSONC: a commented out option does not count, a // inside a string is not a comment
js_tsc '"strict": false, "x": "http://a", // "strictNullChecks": true
    /* "strict": true */ "y": 1'
run estado "$j"; grep -qxF "proyecto: social-apps (js, base incompleta)" <<<"$out" && grep -qxF "tsconfig: strictNullChecks no" <<<"$out" \
  || fail "una opción comentada no cuenta: $out"
js_tsc '"strictNullChecks": true'
run estado "$j"; [ "$(last_line "$out")" = "FIN: base completa" ] && grep -qxF "proyecto: social-apps (js, base completa)" <<<"$out" \
  && grep -qxF "tsconfig: strictNullChecks sí" <<<"$out" || fail "JS con strictNullChecks debe ser completa: $out"
js_tsc '"strict":true'
run estado "$j"; [ "$(last_line "$out")" = "FIN: base completa" ] && grep -qxF "proyecto: social-apps (js, base completa)" <<<"$out" \
  && grep -qxF "tsconfig: strictNullChecks sí" <<<"$out" || fail "JS con strict debe ser completa: $out"
[ "$(grep -c '^tsconfig: strictNullChecks ' <<<"$out")" = 1 ] || fail "strictNullChecks solo en el proyecto JS: $out"
sed -i.bak 's/"checkJs": false/"checkJs": true/' "$j/social-apps/tsconfig.json"; rm -f "$j/social-apps/tsconfig.json.bak"
run estado "$j"; grep -qxF "tsconfig: checkJs sí (opcional)" <<<"$out" && [ "$(last_line "$out")" = "FIN: base completa" ] \
  || fail "checkJs es opcional: $out"
# inline directives: counted per project (TS and JS), only its own files, not node_modules nor a nested project's
grep -qxF "directivas-en-linea: 0" <<<"$out" && [ "$(grep -c '^directivas-en-linea: 0$' <<<"$out")" = 2 ] || fail "sin directivas: $out"
cat > "$j/social-apps/api/src/viejo.mjs" <<'EOF2'
/* eslint-disable no-control-regex */
// eslint-disable-next-line no-console
console.log(1); // eslint-disable-line no-console
/*eslint no-alert: "off"*/
// antes había un eslint-disable aquí: esto no es una directiva
export const re = /\x00/; /* eslint-enable no-control-regex */
/*
  eslint-disable no-alert
*/
EOF2
mkdir -p "$j/social-apps/node_modules/x" "$j/social-apps/sub"
echo '// eslint-disable-next-line' > "$j/social-apps/node_modules/x/i.js"
echo '{}' > "$j/social-apps/sub/package.json"; echo '{"compilerOptions": {"allowJs": true}}' > "$j/social-apps/sub/tsconfig.json"
echo '// eslint-disable-next-line no-console' > "$j/social-apps/sub/a.mjs"
echo '// eslint-disable-next-line' > "$j/web/src/b.ts"
echo '// eslint-disable-next-line' > "$j/social-apps/notas.md"
run estado "$j"
blk() { awk -v p="proyecto: $1 (" 'index($0, p) == 1 { on = 1; next } /^proyecto: |^FIN: / { on = 0 } on' <<<"$out"; }
grep -qxF "directivas-en-linea: 6" <<<"$(blk social-apps)" || fail "directivas de social-apps: $out"
grep -qxF "directivas-en-linea: 1" <<<"$(blk social-apps/sub)" || fail "directivas del proyecto anidado: $out"
grep -qxF "directivas-en-linea: 1" <<<"$(blk web)" || fail "directivas del proyecto TS: $out"
grep -qxF "proyecto: social-apps (js, base completa)" <<<"$out" || fail "las directivas no cambian la base: $out"
rm -rf "$j/social-apps/api/src/viejo.mjs" "$j/social-apps/node_modules" "$j/social-apps/sub" "$j/social-apps/notas.md" "$j/web/src/b.ts"
# the kit templates: up to date, with the four variables adjusted, or out of date; no line when the file is not there
t="$REPO_ROOT/templates/reglas"
run estado "$j"; grep -q '^plantilla: ' <<<"$out" && fail "sin plantillas no hay línea: $out"
mkdir -p "$j/social-apps/.agents-kit"; cp "$t/turno.sh" "$j/social-apps/.agents-kit/turno.sh"
cp "$t/tsc-base.mjs" "$j/social-apps/.agents-kit/tsc-base.mjs"
run estado "$j"; grep -qxF "plantilla: .agents-kit/turno.sh al día" <<<"$(blk social-apps)" \
  && grep -qxF "plantilla: .agents-kit/tsc-base.mjs al día" <<<"$(blk social-apps)" || fail "plantillas al día: $out"
sed -i.bak -e 's#^TSC_EXT=.*#TSC_EXT=""#' -e 's#^LINT_EXT=.*#LINT_EXT="js mjs astro"#' -e 's#^TSC=.*#TSC="node_modules/typescript7/bin/tsc"#' \
  -e 's#^ANTES_TSC=.*#ANTES_TSC="node_modules/.bin/astro sync"#' "$j/social-apps/.agents-kit/turno.sh"; rm -f "$j/social-apps/.agents-kit/turno.sh.bak"
grep -qx 'TSC_EXT=""' "$j/social-apps/.agents-kit/turno.sh" || fail "fixture de turno.sh"
run estado "$j"; grep -qxF "plantilla: .agents-kit/turno.sh al día" <<<"$(blk social-apps)" || fail "las cuatro variables no desfasan: $out"
sed -i.bak 's#^rc=0$#rc=0; true#' "$j/social-apps/.agents-kit/turno.sh"; rm -f "$j/social-apps/.agents-kit/turno.sh.bak"
echo '// otra versión' >> "$j/social-apps/.agents-kit/tsc-base.mjs"
run estado "$j"
grep -qxF "plantilla: .agents-kit/turno.sh desfasada: vuelve a copiar templates/reglas/turno.sh del kit (conserva TSC_EXT, LINT_EXT, TSC y ANTES_TSC)" <<<"$(blk social-apps)" \
  && grep -qxF "plantilla: .agents-kit/tsc-base.mjs desfasada: vuelve a copiar templates/reglas/tsc-base.mjs del kit" <<<"$(blk social-apps)" \
  || fail "plantillas desfasadas: $out"
grep -qxF "proyecto: social-apps (js, base completa)" <<<"$out" || fail "una plantilla desfasada no cambia la base: $out"
rm -rf "$j/social-apps/.agents-kit"
# a nested project's .ts does not make its parent TS; a .ts of its own does
mkdir -p "$j/social-apps/tools"; echo '{}' > "$j/social-apps/tools/package.json"; echo '{}' > "$j/social-apps/tools/tsconfig.json"
echo 'export const t = 1;' > "$j/social-apps/tools/gen.ts"
run estado "$j"; grep -qxF "proyecto: social-apps (js, base completa)" <<<"$out" && grep -qxF "proyecto: social-apps/tools (ts, base incompleta)" <<<"$out" \
  || fail "el .ts de un proyecto anidado no cuenta: $out"
rm -rf "$j/social-apps/tools"; echo 'export const x = 1;' > "$j/social-apps/api/src/x.ts"
run estado "$j"; grep -qxF "proyecto: social-apps (ts, base incompleta)" <<<"$out" && grep -qxF "tsconfig: noUncheckedIndexedAccess no" <<<"$out" \
  || fail "allowJs con un .ts propio es TS: $out"
rm "$j/social-apps/api/src/x.ts"
# a versioned .ts deleted but not staged no longer counts
echo 'export const x = 1;' > "$j/social-apps/api/src/old.ts"; git -C "$j" add social-apps/api/src/old.ts; rm "$j/social-apps/api/src/old.ts"
run estado "$j"; grep -qxF "proyecto: social-apps (js, base completa)" <<<"$out" || fail "un .ts borrado sin preparar no cuenta: $out"
# a JS project whose name starts with - is a directory, never a grep option
cp -R "$j/social-apps" "$j/-js"
run estado "$j"; grep -qxF "proyecto: -js (js, base completa)" <<<"$out" || fail "proyecto JS -js: $out"
rm -rf "$j/-js"
# the root as a JS project: the .ts of web/ are not its own
cp "$j/social-apps/tsconfig.json" "$j/tsconfig.json"; echo '{}' > "$j/package.json"; echo 'export {};' > "$j/index.mjs"
run estado "$j"; grep -qxF "proyecto: . (js, base incompleta)" <<<"$out" || fail "raíz JS: $out"

# --- trinquete y blindado con la deuda de un proyecto (claves relativas a su directorio)
limpia
mkdir -p "$r/web/src" "$r/web/.agents-kit"
for f in a b c; do echo "export const $f = 1;" > "$r/web/src/$f.ts"; done
echo '{}' > "$r/web/package.json"; echo '{}' > "$r/web/tsconfig.json"
echo '{"src/a.ts": {"no-explicit-any": {"count": 1}}}' > "$r/web/eslint-suppressions.json"
echo '{"src/b.ts": 1}' > "$r/web/.agents-kit/tsc-base.json"
push_main web
run trinquete "$r" origin/main; [ $rc -eq 0 ] || fail "web sin cambios: $out"
echo "// cambio" >> "$r/web/src/a.ts"; echo "// cambio" >> "$r/web/src/b.ts"
run trinquete "$r" origin/main; [ $rc -eq 1 ] || fail "tocar la deuda de web debe fallar: $out"
grep -qxF "deuda en fichero tocado: web/src/a.ts (lint)" <<<"$out" && grep -qxF "deuda en fichero tocado: web/src/b.ts (tipos)" <<<"$out" \
  || fail "motivos de web: $out"
grep -q 'src/c.ts\|^deuda en fichero tocado: src/' <<<"$out" && fail "web/src/a.ts no es src/a.ts de la raíz: $out"
limpia
echo '{"src/a.ts": {"no-explicit-any": {"count": 1}}, "src/c.ts": {"no-console": {"count": 1}}}' > "$r/web/eslint-suppressions.json"
echo '{"src/b.ts": 2}' > "$r/web/.agents-kit/tsc-base.json"
run trinquete "$r" origin/main; [ $rc -eq 1 ] || fail "la deuda de web crece: $out"
grep -qxF "la deuda crece: web/src/c.ts no-console (web/eslint-suppressions.json)" <<<"$out" \
  && grep -qxF "la deuda crece: web/src/b.ts tipos (web/.agents-kit/tsc-base.json)" <<<"$out" || fail "crece en web: $out"
run blindado "$r" origin/main
grep -qxF "web/eslint-suppressions.json" <<<"$out" && grep -qxF "web/.agents-kit/tsc-base.json" <<<"$out" || fail "blindado de la deuda de web: $out"
limpia
echo '{}' > "$r/web/eslint-suppressions.json"; echo '{}' > "$r/web/.agents-kit/tsc-base.json"
run blindado "$r" origin/main; [ "$(last_line "$out")" = "FIN: 0" ] || fail "la deuda de web que encoge no cuenta: $out"
run trinquete "$r" origin/main; [ $rc -eq 0 ] || fail "encoger la deuda de web pasa: $out"
limpia; git -C "$r" rm -q web/eslint-suppressions.json
run trinquete "$r" origin/main; [ $rc -eq 0 ] || fail "borrar la deuda de web pasa: $out"
limpia
# a debt directory whose name has sed metacharacters (# and &) keeps its name in the reason
mkdir -p "$r/w#&"; echo '{"src/x.ts": 1}' > "$r/w#&/eslint-suppressions.json.x"; mv "$r/w#&/eslint-suppressions.json.x" "$r/w#&/eslint-suppressions.json"
printf '{"src/x.ts": {"r": {"count": 1}}}\n' > "$r/w#&/eslint-suppressions.json"
run trinquete "$r" origin/main; [ $rc -eq 1 ] && grep -qxF "la deuda crece: w#&/src/x.ts r (w#&/eslint-suppressions.json)" <<<"$out" \
  || fail "directorio con # y &: $out"
limpia

# --- estado: Python, detectado por sus ficheros, con sus líneas informativas
py="$(mk_repo)"; echo '{}' > "$py/.agents-kit.json"
echo 'line-length = 100' > "$py/ruff.toml"; echo 'print(1)' > "$py/app.py"; git -C "$py" add -A
run estado "$py"; [ $rc -eq 0 ] || fail "estado py: $out"
for x in "lenguajes: py" "ruff: sí" "ruff select: por defecto" "pyright: no"; do grep -qxF "$x" <<<"$out" || fail "py con ruff.toml sin '$x': $out"; done
[ "$(last_line "$out")" = "FIN: base completa" ] || fail "Python no cambia la base: $out"
# only requirements.txt, only setup.py, only setup.cfg, only .ruff.toml: py; nothing of that, not py
for f in requirements-dev.txt setup.py setup.cfg .ruff.toml; do
  p2="$(mk_repo)"; echo '{}' > "$p2/.agents-kit.json"; echo 'x' > "$p2/$f"
  run estado "$p2"; grep -qxF "lenguajes: py" <<<"$out" || fail "py por $f: $out"
done
p2="$(mk_repo)"; echo '{}' > "$p2/.agents-kit.json"; mkdir -p "$p2/src"; echo 'x = 1' > "$p2/src/m.py"
run estado "$p2"; grep -qxF "lenguajes: ninguno" <<<"$out" || fail "un .py sin versionar no es py: $out"
git -C "$p2" add src/m.py; run estado "$p2"; grep -qxF "lenguajes: py" <<<"$out" && grep -qxF "ruff: no" <<<"$out" || fail "py por .py versionado: $out"
# ruff and pyright in pyproject.toml; select in one line or several, in [lint] or at the top
cat > "$py/pyproject.toml" <<'EOF2'
[project]
name = "x"
select = ["NO"]

[tool.ruff.lint]
select = [
  "E", "F",
  "B",  # bugbear
]

[tool.pyright]
typeCheckingMode = "strict"
EOF2
rm "$py/ruff.toml"
run estado "$py"; for x in "ruff: sí" "ruff select: E,F,B" "pyright: sí"; do grep -qxF "$x" <<<"$out" || fail "pyproject sin '$x': $out"; done
rm "$py/pyproject.toml"; printf '[lint]\nselect = ["E", "UP"]\n' > "$py/ruff.toml"; echo '{}' > "$py/pyrightconfig.json"
run estado "$py"; for x in "ruff: sí" "ruff select: E,UP" "pyright: sí"; do grep -qxF "$x" <<<"$out" || fail "ruff.toml [lint] sin '$x': $out"; done
printf 'select = ["I"]\n' > "$py/ruff.toml"
run estado "$py"; grep -qxF "ruff select: I" <<<"$out" || fail "select arriba del todo: $out"
printf '[lint]\nselect = []\n' > "$py/.ruff.toml"
run estado "$py"; grep -qxF "ruff select: ninguna" <<<"$out" || fail ".ruff.toml antes que ruff.toml, y select vacío: $out"
rm "$py/.ruff.toml"
echo '[tool.black]' > "$py/pyproject.toml"; rm "$py/ruff.toml" "$py/pyrightconfig.json"
run estado "$py"; grep -qxF "ruff: no" <<<"$out" && grep -qxF "pyright: no" <<<"$out" || fail "pyproject sin ruff ni pyright: $out"
grep -q '^ruff select' <<<"$out" && fail "sin ruff no hay select: $out"
run estado "$r"; grep -q '^ruff:' <<<"$out" && fail "sin py no hay líneas de Python: $out"

# --- marcador: los flags exactos de kit-activate.sh
ESL='KIT_LINT_RAPIDO=1 node_modules/.bin/eslint --cache --cache-location node_modules/.cache/agents-kit/eslint-rapido --no-warn-ignored --pass-on-unpruned-suppressions'
run marcador; [ $rc -eq 1 ] || fail "marcador sin wt: exit $rc"
# a TS project in the root
mt="$(mk_repo)"; echo '{}' > "$mt/.agents-kit.json"; echo '{}' > "$mt/package.json"; echo '{}' > "$mt/tsconfig.json"
mkdir -p "$mt/src"; echo 'export {};' > "$mt/src/a.ts"
run marcador "$mt"; [ $rc -eq 0 ] || fail "marcador TS: $out"
[ "$out" = "--lint-fichero 'ts,tsx,mts,cts,js,jsx,mjs,cjs=$ESL'"$'\n'"--lint-turno 'bash .agents-kit/turno.sh'"$'\n'"FIN: 2" ] \
  || fail "marcador TS en la raíz: $out"
# a monorepo: a JS project in a subdirectory (with .astro files), the root without turno.sh, plus bash
mj="$(mk_repo)"; echo '{}' > "$mj/.agents-kit.json"; mkdir -p "$mj/app/src"
echo '{}' > "$mj/app/package.json"; echo '{"compilerOptions": {"allowJs": true}}' > "$mj/app/tsconfig.json"
echo 'export {};' > "$mj/app/src/a.mjs"; echo '---' > "$mj/app/src/p.astro"; echo 'echo' > "$mj/x.sh"; git -C "$mj" add -A
run marcador "$mj"
[ "$out" = "--lint-fichero 'js,jsx,mjs,cjs,astro=$ESL'"$'\n'"--lint-fichero 'sh,bash=shellcheck'"$'\n'"--lint-turno '[ ! -f .agents-kit/turno.sh ] || bash .agents-kit/turno.sh'"$'\n'"FIN: 3" ] \
  || fail "marcador monorepo JS: $out"
# the root with its own turno.sh: no guard
mkdir -p "$mj/.agents-kit"; echo 'x' > "$mj/.agents-kit/turno.sh"
run marcador "$mj"; grep -qxF -- "--lint-turno 'bash .agents-kit/turno.sh'" <<<"$out" || fail "raíz con turno.sh: $out"
# Python: ruff of the PATH, of .venv, or through the interpreter given with --python
run marcador "$py"; [ "$out" = "--lint-fichero 'py=ruff check --quiet'"$'\n'"FIN: 1" ] || fail "marcador py: $out"
mkdir -p "$py/.venv/bin"; printf '#!/bin/sh\n' > "$py/.venv/bin/ruff"; chmod +x "$py/.venv/bin/ruff"
run marcador "$py"; grep -qxF -- "--lint-fichero 'py=.venv/bin/ruff check --quiet'" <<<"$out" || fail "marcador py con .venv: $out"
run marcador "$py" --python "tools/python 3.sh"
grep -qxF -- "--lint-fichero 'py=\"tools/python 3.sh\" -m ruff check --quiet'" <<<"$out" || fail "marcador py con --python: $out"
run marcador "$py" --python 'a"b'; [ $rc -eq 1 ] && grep -q 'valor de --python inválido' <<<"$out" || fail "--python con comillas: exit $rc $out"
# an interpreter decided by a script of the repo, evaluated when the hook runs
run marcador "$py" --python '$(tools/python.sh)'
grep -qxF -- "--lint-fichero 'py=\"\$(tools/python.sh)\" -m ruff check --quiet'" <<<"$out" || fail "marcador py con \$(...): $out"
run marcador "$py" --otra x; [ $rc -eq 1 ] || fail "opción desconocida: exit $rc"
# a project in a subdirectory: the hooks run lint.fichero from there, so the paths relative to the root go from it
mkdir -p "$mj/.venv/bin"; printf '#!/bin/sh\n' > "$mj/.venv/bin/ruff"; chmod +x "$mj/.venv/bin/ruff"; echo 'x = 1' > "$mj/app/h.py"
git -C "$mj" add app/h.py
run marcador "$mj"; grep -qxF -- "--lint-fichero 'py=\"\$(git rev-parse --show-toplevel)/.venv/bin/ruff\" check --quiet'" <<<"$out" || fail "ruff de .venv en monorepo: $out"
run marcador "$mj" --python '$(tools/python.sh)'
grep -qxF -- "--lint-fichero 'py=\"\$(\"\$(git rev-parse --show-toplevel)\"/tools/python.sh)\" -m ruff check --quiet'" <<<"$out" || fail "--python \$(...) en monorepo: $out"
run marcador "$mj" --python 'tools/py.sh'
grep -qxF -- "--lint-fichero 'py=\"\$(git rev-parse --show-toplevel)/tools/py.sh\" -m ruff check --quiet'" <<<"$out" || fail "--python ruta en monorepo: $out"
run marcador "$mj" --python 'python3'; grep -qxF -- "--lint-fichero 'py=\"python3\" -m ruff check --quiet'" <<<"$out" || fail "--python del PATH en monorepo: $out"
# and it really runs from the project directory: the fake interpreter of tools/ is found
mkdir -p "$mj/tools"; printf '#!/bin/sh\necho /bin/echo\n' > "$mj/tools/python.sh"; chmod +x "$mj/tools/python.sh"
run marcador "$mj" --python '$(tools/python.sh)'; c="$(sed -n "s/^--lint-fichero 'py=\(.*\)'\$/\1/p" <<<"$out")"
o="$(cd "$mj/app" && /bin/sh -c "$c \"\$@\"" kit-lint ./h.py)" && [ "$o" = "-m ruff check --quiet ./h.py" ] || fail "el comando desde el proyecto: '$o' ($c)"
rm -rf "$mj/.venv" "$mj/tools" "$mj/app/h.py"; git -C "$mj" rm -q --cached app/h.py
# nothing to lint
mn="$(mk_repo)"; echo '{}' > "$mn/.agents-kit.json"; run marcador "$mn"; [ "$out" = "FIN: 0" ] || fail "marcador vacío: $out"
# what it prints works as it is with kit-activate.sh
cp -R "$mj" "$mj-act"; run marcador "$mj-act"
flags="$(sed '$d' <<<"$out" | tr '\n' ' ')"
eval "bash \"$REPO_ROOT/scripts/kit-activate.sh\" \"$mj-act\" $flags" >/dev/null 2>&1 || fail "kit-activate con los flags: exit $?"
[ "$(jq -c '.lint' "$mj-act/.agents-kit.json")" = "$(jq -cn --arg e "$ESL" '{fichero: {"js,jsx,mjs,cjs,astro": $e, "sh,bash": "shellcheck"}, turno: "bash .agents-kit/turno.sh"}')" ] \
  || fail "marcador escrito por kit-activate: $(jq -c .lint "$mj-act/.agents-kit.json")"
cp -R "$py" "$py-act"; run marcador "$py-act" --python '$(tools/python.sh)'; flags="$(sed '$d' <<<"$out" | tr '\n' ' ')"
eval "bash \"$REPO_ROOT/scripts/kit-activate.sh\" \"$py-act\" $flags" >/dev/null 2>&1 || fail "kit-activate con --python: exit $?"
[ "$(jq -r '.lint.fichero.py' "$py-act/.agents-kit.json")" = '"$(tools/python.sh)" -m ruff check --quiet' ] || fail "py escrito: $(cat "$py-act/.agents-kit.json")"

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
