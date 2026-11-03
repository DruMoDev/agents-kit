#!/usr/bin/env bash
# Tests for templates/reglas/tsc-base.mjs (tsc error baseline), with a fake tsc passed in KIT_TSC.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
SCRIPT="$REPO_ROOT/templates/reglas/tsc-base.mjs"

d="$(mktemp -d)"
tsc_out="$d/tsc-out.txt"
cat > "$d/fake-tsc" <<EOS
#!/usr/bin/env bash
cat "$tsc_out"
[ -s "$tsc_out" ] && exit 2
exit 0
EOS
chmod +x "$d/fake-tsc"
export KIT_TSC="$d/fake-tsc"

repo="$(mk_repo)"
cd "$repo" || fail "cd"
run() { out="$(node "$SCRIPT" "$@" 2>&1)"; rc=$?; }

printf '%s\n' 'src/a.ts(1,1): error TS1: x' 'src/a.ts(1,1): error TS1: x' 'src/b.ts(3,4): error TS2: y' > "$tsc_out"

run comprobar; [ "$rc" = 1 ] || fail "sin base y con errores deberia rechazar (rc=$rc)"
run generar; [ "$rc" = 0 ] || fail "generar rc=$rc: $out"
[ "$(tail -n 1 <<<"$out")" = "FIN: 2 ficheros con deuda" ] || fail "FIN de generar: $out"
[ "$(jq -c . .agents-kit/tsc-base.json)" = '{"src/a.ts":2,"src/b.ts":1}' ] || fail "base: $(cat .agents-kit/tsc-base.json)"

run comprobar; [ "$rc" = 0 ] || fail "comprobar igual a la base rc=$rc: $out"
[ "$(tail -n 1 <<<"$out")" = "FIN: ok" ] || fail "FIN de comprobar: $out"

# rutas con ./ y absolutas cuentan igual
printf '%s\n' "./src/a.ts(1,1): error TS1: x" "$repo/src/a.ts(2,2): error TS1: x" 'src/b.ts(3,4): error TS2: y' > "$tsc_out"
run comprobar; [ "$rc" = 0 ] || fail "rutas ./ y absolutas rc=$rc: $out"

# menos errores que la base: bien
printf '%s\n' 'src/a.ts(1,1): error TS1: x' > "$tsc_out"
run comprobar; [ "$rc" = 0 ] || fail "menos errores rc=$rc: $out"

# mas errores en a.ts
printf '%s\n' 'src/a.ts(1,1): error TS1: x' 'src/a.ts(1,1): error TS1: x' 'src/a.ts(5,1): error TS1: z' 'src/b.ts(3,4): error TS2: y' > "$tsc_out"
run comprobar; [ "$rc" = 1 ] || fail "3 errores en a.ts deberia dar 1 (rc=$rc)"
grep -q 'src/a.ts' <<<"$out" || fail "la salida no nombra src/a.ts: $out"

# --cambiados con un fichero con deuda
printf '%s\n' 'src/a.ts(1,1): error TS1: x' 'src/a.ts(1,1): error TS1: x' 'src/b.ts(3,4): error TS2: y' > "$tsc_out"
run comprobar --cambiados src/b.ts; [ "$rc" = 1 ] || fail "--cambiados src/b.ts deberia dar 1 (rc=$rc)"
grep -q 'src/b.ts' <<<"$out" || fail "no nombra src/b.ts: $out"
run comprobar --cambiados src/c.ts; [ "$rc" = 0 ] || fail "--cambiados sin errores rc=$rc: $out"

# fichero sin base con errores
printf '%s\n' 'src/a.ts(1,1): error TS1: x' 'src/a.ts(1,1): error TS1: x' 'src/b.ts(3,4): error TS2: y' 'src/c.ts(1,1): error TS3: w' > "$tsc_out"
run comprobar; [ "$rc" = 1 ] || fail "error en c.ts deberia dar 1 (rc=$rc)"
grep -q 'src/c.ts' <<<"$out" || fail "no nombra src/c.ts: $out"

# sin tsc-base.json: ningun error permitido
rm .agents-kit/tsc-base.json
printf '%s\n' 'src/a.ts(1,1): error TS1: x' > "$tsc_out"
run comprobar; [ "$rc" = 1 ] || fail "sin base deberia dar 1 (rc=$rc)"
: > "$tsc_out"
run comprobar; [ "$rc" = 0 ] || fail "sin base y sin errores rc=$rc: $out"

# entorno: tsc que sale con 1 y sin errores reconocibles; tsc que no existe
printf '#!/usr/bin/env bash\necho "boom"\nexit 1\n' > "$d/bad-tsc"; chmod +x "$d/bad-tsc"
KIT_TSC="$d/bad-tsc" run comprobar; [ "$rc" = 2 ] || fail "tsc roto deberia dar 2 (rc=$rc)"
KIT_TSC="$d/no-existe" run comprobar; [ "$rc" = 2 ] || fail "tsc inexistente deberia dar 2 (rc=$rc)"
run foo; [ "$rc" = 1 ] || fail "subcomando desconocido deberia dar 1 (rc=$rc)"

echo ok
