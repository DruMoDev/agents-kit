#!/usr/bin/env bash
# Tests for templates/reglas/turno.sh (lint.turno: tsc baseline of the changed files plus typed ESLint), with fake
# tsc and eslint passed in KIT_TSC and KIT_ESLINT.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
command -v node >/dev/null 2>&1 || fail "falta node"
T="$REPO_ROOT/templates/reglas/turno.sh"
[ -f "$T" ] || fail "missing templates/reglas/turno.sh"

d="$(mktemp -d)"
trap 'rm -rf "$d" "$repo"' EXIT
cat > "$d/fake-tsc" <<EOS
#!/usr/bin/env bash
echo x >> "$d/tsc-calls"
cat "$d/tsc-out" 2>/dev/null
[ -s "$d/tsc-out" ] && exit 2
exit 0
EOS
cat > "$d/fake-eslint" <<EOS
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$d/eslint-args"
[ -f "$d/eslint-falla" ] && { echo "src/a.ts: 1:1 error no-floating-promises"; exit 1; }
exit 0
EOS
chmod +x "$d/fake-tsc" "$d/fake-eslint"

repo="$(mk_repo)"
mkdir -p "$repo/.agents-kit" "$repo/src"
cp "$REPO_ROOT/templates/reglas/tsc-base.mjs" "$repo/.agents-kit/tsc-base.mjs"
cp "$T" "$repo/.agents-kit/turno.sh"
echo '{"src/a.ts": 1}' > "$repo/.agents-kit/tsc-base.json"
cd "$repo" || fail "cd"
reset() { rm -f "$d/tsc-calls" "$d/eslint-args" "$d/eslint-falla" "$d/tsc-out"; }
run() { out="$(KIT_TSC="$d/fake-tsc" KIT_ESLINT="$d/fake-eslint" bash .agents-kit/turno.sh "$@" 2>&1)"; rc=$?; }

# nothing of code changed: neither tsc nor eslint run
reset; run ./README.md ./docs/x.md
[ "$rc" = 0 ] || fail "sin código rc=$rc: $out"
[ ! -e "$d/tsc-calls" ] && [ ! -e "$d/eslint-args" ] || fail "sin código no debe lanzar tsc ni eslint"
[ "$(tail -n 1 <<<"$out")" = "FIN: nada que comprobar" ] || fail "FIN sin código: $out"

# debt of a.ts is in the baseline: a change in b.ts passes; eslint gets only the lint extensions, with cache
reset; echo 'src/a.ts(1,1): error TS1: x' > "$d/tsc-out"
run ./src/b.ts ./README.md ./src/c.TSX ./src/d.css
[ "$rc" = 0 ] || fail "deuda de otro fichero rc=$rc: $out"
[ -s "$d/tsc-calls" ] || fail "debe lanzar tsc"
[ "$(tail -n 1 <<<"$out")" = "FIN: ok" ] || fail "FIN ok: $out"
grep -qx -- '--cache' "$d/eslint-args" || fail "eslint sin --cache: $(cat "$d/eslint-args")"
grep -qx './src/b.ts' "$d/eslint-args" && grep -qx './src/c.TSX' "$d/eslint-args" || fail "eslint no recibe los .ts/.tsx: $(cat "$d/eslint-args")"
grep -q 'README.md\|d.css' "$d/eslint-args" && fail "eslint recibe ficheros sin extensión de lint: $(cat "$d/eslint-args")"

# the changed file with debt (a.ts) goes in --cambiados: it must be left at zero
reset; echo 'src/a.ts(1,1): error TS1: x' > "$d/tsc-out"
run ./src/a.ts
[ "$rc" = 1 ] || fail "fichero cambiado con deuda debe dar 1 (rc=$rc): $out"
grep -q 'src/a.ts' <<<"$out" || fail "no nombra src/a.ts: $out"

# eslint fails: exit 1 with its output
reset; touch "$d/eslint-falla"
run ./src/b.ts
[ "$rc" = 1 ] || fail "eslint falla debe dar 1 (rc=$rc)"
grep -q 'no-floating-promises' <<<"$out" || fail "sin la salida de eslint: $out"

# only a .js changed: eslint runs, tsc too (types of the project), without --cambiados .js
reset; run ./src/e.mjs
[ "$rc" = 0 ] && [ -s "$d/tsc-calls" ] && grep -qx './src/e.mjs' "$d/eslint-args" || fail ".mjs: rc=$rc $out"

# a changed tsconfig runs tsc even without .ts files (no eslint), and a new error then fails
reset; run ./tsconfig.json ./README.md
[ "$rc" = 0 ] && [ -s "$d/tsc-calls" ] && [ ! -e "$d/eslint-args" ] || fail "tsconfig.json: rc=$rc tsc=$(cat "$d/tsc-calls" 2>/dev/null) $out"
reset; echo 'src/n.ts(1,1): error TS1: nuevo' > "$d/tsc-out"
run ./config/TSConfig.base.json
[ "$rc" = 1 ] && grep -q 'src/n.ts' <<<"$out" || fail "tsconfig con error nuevo debe dar 1 (rc=$rc): $out"

# names with spaces and shell metacharacters reach tsc-base and eslint as they are, and nothing is run
reset; raro='./src/a b;$(touch PWNED) `x` "q" *.ts'
run "$raro"
[ "$rc" = 0 ] || fail "nombre raro rc=$rc: $out"
[ "$(grep -c '' "$d/eslint-args")" -gt 0 ] && grep -qxF -- "$raro" "$d/eslint-args" || fail "eslint no recibe el nombre tal cual: $(cat "$d/eslint-args")"
[ ! -e PWNED ] && [ ! -e src/PWNED ] || fail "un nombre de fichero ejecutó código"
reset; echo "src/a b;\$(touch PWNED) \`x\` \"q\" *.ts(1,1): error TS1: x" > "$d/tsc-out"
run "$raro"
[ "$rc" = 1 ] || fail "el nombre raro debe ir en --cambiados (rc=$rc): $out"

# without .agents-kit/tsc-base.mjs: exit 1 saying how to fix it
reset; mv .agents-kit/tsc-base.mjs "$d/tsc-base.mjs"
run ./src/b.ts
[ "$rc" = 1 ] && grep -qF 'falta .agents-kit/tsc-base.mjs: cópialo con kit-reglas' <<<"$out" || fail "sin tsc-base.mjs: rc=$rc $out"
mv "$d/tsc-base.mjs" .agents-kit/tsc-base.mjs

# worktree without node_modules: 127 (the Stop hook does not block) and never a download
reset
out="$(bash .agents-kit/turno.sh ./src/b.ts 2>&1)"; rc=$?
[ "$rc" = 127 ] || fail "sin node_modules debe salir 127 (rc=$rc): $out"
grep -q 'node_modules' <<<"$out" || fail "sin node_modules debe decir qué falta: $out"
[ ! -e "$d/tsc-calls" ] || fail "sin node_modules no debe lanzar tsc"
grep -q 'npx' "$T" && ! grep -q 'npx --no-install' "$T" && fail "turno.sh no puede usar npx sin --no-install"

# TSC and ANTES_TSC, set by kit-reglas in the copy (TypeScript 7 next to TS 6, Astro): ANTES_TSC runs before the types,
# its failure stops with exit 1 and its output
reset; mkdir -p node_modules/typescript7/bin; cp "$d/fake-tsc" node_modules/typescript7/bin/tsc
cat > "$d/antes" <<EOS
#!/usr/bin/env bash
echo antes >> "$d/tsc-calls"
[ -f "$d/antes-falla" ] && { echo "sync roto"; exit 3; }
exit 0
EOS
chmod +x "$d/antes"
sed -e 's#^TSC=.*#TSC="node_modules/typescript7/bin/tsc"#' -e "s#^ANTES_TSC=.*#ANTES_TSC=\"$d/antes\"#" "$T" > .agents-kit/turno.sh
out="$(KIT_ESLINT="$d/fake-eslint" bash .agents-kit/turno.sh ./src/b.ts 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$d/tsc-calls")" = $'antes\nx' ] || fail "ANTES_TSC y TSC: rc=$rc $(cat "$d/tsc-calls" 2>/dev/null) $out"
reset; touch "$d/antes-falla"
out="$(KIT_ESLINT="$d/fake-eslint" bash .agents-kit/turno.sh ./src/b.ts 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -qF 'sync roto' <<<"$out" && [ "$(cat "$d/tsc-calls")" = antes ] || fail "ANTES_TSC que falla: rc=$rc $out"
rm -rf node_modules; cp "$T" .agents-kit/turno.sh
echo "ok"
