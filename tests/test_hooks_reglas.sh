#!/usr/bin/env bash
# Tests for hooks/pre-edit, hooks/post-edit and hooks/stop-check (fed by stdin with JSON, fake lint commands).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
H="$REPO_ROOT/hooks"
for h in pre-edit post-edit stop-check; do [ -x "$H/$h" ] || fail "hooks/$h falta o no es ejecutable"; done
jq -e '(.hooks.PreToolUse[0].matcher == "Edit|Write|MultiEdit|NotebookEdit")
  and (.hooks.PostToolUse[0].matcher == "Edit|Write|MultiEdit|NotebookEdit")
  and (.hooks.Stop[0] | has("matcher") | not)
  and (.hooks.PreToolUse[0].hooks[0].command | endswith("/hooks/pre-edit\""))
  and (.hooks.PostToolUse[0].hooks[0].command | endswith("/hooks/post-edit\""))
  and (.hooks.Stop[0].hooks[0].command | endswith("/hooks/stop-check\""))
  and (.hooks.SessionStart[0].matcher == "startup|resume|clear|compact|fork")' "$H/hooks.json" >/dev/null \
  || fail "hooks.json sin los hooks de reglas"

# hook <name> <json>: run it from / (the hook must use the cwd of the input); $out = stdout+stderr, $rc.
hook() { out="$(cd / && printf '%s' "$2" | "$H/$1" 2>&1)"; rc=$?; }
# inp [jq args...] <filter>: build the JSON input with jq -n.
inp() { jq -cn "$@"; }

r="$(mk_repo)"
bin="$(mktemp -d)"; LOG="$bin/log"; export LOG
cat > "$bin/fakelint" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$LOG"
echo "error de lint en $*"
exit "${FAKE_RC:-0}"
EOF
cat > "$bin/slowlint" <<'EOF'
#!/usr/bin/env bash
echo "$$" >> "$LOG"
sleep 21.37
EOF
chmod +x "$bin/fakelint" "$bin/slowlint"
marker() { printf '%s\n' "$1" > "$r/.agents-kit.json"; }
LINT="{\"lint\": {\"fichero\": {\"ts, tsx\": \"$bin/fakelint --rapido\"}, \"turno\": \"$bin/fakelint --turno\"}}"
common="$(cd "$r" && cd "$(git rev-parse --git-common-dir)" && pwd)"
lock="$common/agents-kit/lint.lock"

edit_json() { inp --arg c "$r" --arg f "$1" --arg t "$2" --arg s "${3:-s1}" \
  '{session_id: $s, cwd: $c, hook_event_name: "PreToolUse", tool_name: "Edit",
    tool_input: {file_path: $f, old_string: "x", new_string: $t}}'; }
post_json() { inp --arg c "${2:-$r}" --arg f "$1" '{session_id: "s1", cwd: $c, tool_name: "Write",
  tool_input: {file_path: $f, content: "x"}}'; }
stop_json() { inp --arg c "$r" '{session_id: "s1", cwd: $c, hook_event_name: "Stop", stop_hook_active: false}'; }

# --- inerte: sin marcador, "reglas": false o sin lint
mkdir -p "$r/src"; echo 'x' > "$r/src/a.ts"
for m in "" '{"reglas": false, "lint": {"fichero": {"ts": "false"}, "turno": "false"}}' '{}'; do
  if [ -z "$m" ]; then rm -f "$r/.agents-kit.json"; else marker "$m"; fi
  : > "$LOG"
  hook pre-edit "$(edit_json src/a.ts 'const y = x as any;')"; [ $rc -eq 0 ] && [ -z "$out" ] || fail "pre-edit inerte ($m): $rc $out"
  hook pre-edit "$(edit_json eslint.config.mjs 'x')"; [ $rc -eq 0 ] && [ -z "$out" ] || fail "pre-edit blindado inerte ($m): $rc $out"
  hook post-edit "$(post_json src/a.ts)"; [ $rc -eq 0 ] && [ -z "$out" ] || fail "post-edit inerte ($m): $rc $out"
  hook stop-check "$(stop_json)"; [ $rc -eq 0 ] && [ -z "$out" ] || fail "stop-check inerte ($m): $rc $out"
  [ ! -s "$LOG" ] || fail "inerte no debe lanzar nada ($m): $(cat "$LOG")"
done
marker "$LINT"
hook pre-edit '{"cwd": "/", "tool_input": {"command": "*** Begin Patch"}}'; [ $rc -eq 0 ] && [ -z "$out" ] || fail "sin ruta: $rc $out"
hook pre-edit 'no es json{'; [ $rc -eq 0 ] && [ -z "$out" ] || fail "entrada rota: $rc $out"

# --- pre-edit: desactivar reglas o tipos
for t in 'const y = x as any;' 'f(x as  any)' '// eslint-disable-next-line no-console' '// @ts-ignore' '// @ts-nocheck'; do
  hook pre-edit "$(edit_json src/a.ts "$t")"
  [ $rc -eq 2 ] && [[ "$out" == *"No desactives reglas ni tipos: arregla la causa. Si la regla está mal, propón el cambio (kit-reglas)."* ]] \
    || fail "pre-edit debe bloquear '$t': $rc $out"
done
for t in 'const x = any' 'y as anything' 'z as any_t' 'w as any$' 'has any'; do
  hook pre-edit "$(edit_json src/a.ts "$t")"
  if [ "$t" = 'w as any$' ]; then [ $rc -eq 0 ] || fail "'as any\$' no bloquea (\$ es de identificador)"; continue; fi
  [ $rc -eq 0 ] && [ -z "$out" ] || fail "pre-edit no debe bloquear '$t': $rc $out"
done
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/b.ts", content: "let a = b as any"}}')"
[ $rc -eq 2 ] || fail "Write con content debe bloquear: $rc $out"
printf 'let a = b as any;\n' > "$r/src/heredado.ts"
wjson() { inp --arg c "$r" --arg t "$1" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/heredado.ts", content: $t}}'; }
hook pre-edit "$(wjson 'let a = b as any; // otro cambio')"; [ $rc -eq 0 ] || fail "Write con as any heredado no bloquea: $rc $out"
hook pre-edit "$(wjson 'let a = b as any; let c = d as any;')"; [ $rc -eq 2 ] || fail "Write que añade un as any bloquea: $rc"
ejson() { inp --arg c "$r" --arg o "$1" --arg n "$2" '{session_id: "s1", cwd: $c,
  tool_input: {file_path: "src/e.ts", old_string: $o, new_string: $n}}'; }
printf 'x as any; y\n' > "$r/src/e.ts"
hook pre-edit "$(ejson 'x as any; y' 'x as any; z')"; [ $rc -eq 0 ] || fail "Edit con as any heredado no bloquea: $rc $out"
hook pre-edit "$(ejson 'x as any; y' 'x as any; y as any')"; [ $rc -eq 2 ] || fail "Edit que añade un as any bloquea: $rc"
printf '// @ts-ignore\na\nb\n' > "$r/src/m.ts"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/m.ts",
  edits: [{old_string: "// @ts-ignore\na", new_string: "a"}, {old_string: "b", new_string: "// @ts-ignore\nb"}]}}')"
[ $rc -eq 0 ] || fail "MultiEdit que mueve un @ts-ignore no bloquea: $rc $out"
# a fragment that matches inside the file text (as any inside as anything) must not hide a real addition
printf 'let v = w as anything;\n' > "$r/src/f.ts"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/f.ts",
  old_string: "as any", new_string: "as any thing"}}')"
[ $rc -eq 2 ] || fail "un as any real creado al sustituir dentro de as anything bloquea: $rc $out"
# only the second Z makes a real as any: the first replacement alone does not, replace_all does
printf 'Z\nlet q = r as Z;\n' > "$r/src/g.ts"
gjson() { inp --arg c "$r" --argjson a "$1" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/g.ts",
  old_string: "Z", new_string: "any ", replace_all: $a}}'; }
hook pre-edit "$(gjson false)"; [ $rc -eq 0 ] || fail "sin replace_all solo cambia la primera Z: $rc $out"
hook pre-edit "$(gjson true)"; [ $rc -eq 2 ] || fail "replace_all que crea as any bloquea: $rc $out"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/f.ts",
  old_string: "no está", new_string: "x as any"}}')"
[ $rc -eq 0 ] || fail "un old_string que no está no cambia el fichero: $rc $out"
printf 'x\n' > "$r/src/MAY.TS"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/MAY.TS",
  old_string: "x", new_string: "x as any"}}')"
[ $rc -eq 2 ] || fail "un .TS con as any añadido bloquea: $rc $out"
hook pre-edit "$(edit_json docs/regla.md 'No uses eslint-disable ni as any.')"
[ $rc -eq 0 ] && [ -z "$out" ] || fail "un .md que explica la regla no bloquea: $rc $out"
echo x > "$r/src/c.vue"
hook pre-edit "$(edit_json src/c.vue 'x as any')"; [ $rc -eq 2 ] || fail ".vue es código aunque no esté en .lint.fichero: $rc"
printf 'a\nb\n' > "$r/src/b.ts"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/b.ts",
  edits: [{old_string: "a", new_string: "ok"}, {old_string: "b", new_string: "// @ts-ignore"}]}}')"
[ $rc -eq 2 ] || fail "MultiEdit debe bloquear: $rc $out"

# --- pre-edit: ficheros blindados
blind='Fichero de reglas: solo se cambia con la aprobación de Dru (skill kit-reglas, o en kit-run un commit propio y kit-pr.sh regla).'
hook pre-edit "$(edit_json eslint.config.mjs 'export default []')"
[ $rc -eq 2 ] && [[ "$out" == *"$blind"* ]] || fail "eslint.config.mjs debe bloquear: $rc $out"
hook pre-edit "$(edit_json "$r/.github/workflows/ci.yml" 'on: push')"
[ $rc -eq 2 ] || fail "ruta absoluta blindada (prefijo) debe bloquear: $rc $out"
hook pre-edit "$(edit_json "$r/src/../tsconfig.json" '{}')"
[ $rc -eq 2 ] || fail "ruta con .. blindada debe bloquear: $rc $out"
hook pre-edit "$(edit_json package.json '{"scripts": {"lint": "true"}}')"
[ $rc -eq 0 ] || fail "package.json no se bloquea en pre-edit: $rc $out"
if [ "$(uname)" = Darwin ]; then
  hook pre-edit "$(edit_json ESLINT.CONFIG.MJS 'x')"; [ $rc -eq 2 ] || fail "en macOS, ESLINT.CONFIG.MJS bloquea: $rc $out"
fi
echo 'export default []' > "$r/eslint.config.mjs"; ln -s ../eslint.config.mjs "$r/src/l.ts"
hook pre-edit "$(edit_json src/l.ts 'x')"; [ $rc -eq 2 ] || fail "un enlace a un fichero blindado bloquea: $rc $out"
fuera_l="$(mktemp -d)"; echo 'x' > "$fuera_l/t.ts"; ln -s "$fuera_l/t.ts" "$r/src/fuera.ts"
hook pre-edit "$(edit_json src/fuera.ts 'x as any')"; [ $rc -eq 0 ] && [ -z "$out" ] || fail "un enlace fuera del repo no hace nada: $rc $out"
rm "$r/src/l.ts" "$r/src/fuera.ts" "$r/eslint.config.mjs"
bash "$REPO_ROOT/scripts/kit-reglas.sh" abrir "$r" sesion-ok >/dev/null || fail "abrir"
hook pre-edit "$(edit_json eslint.config.mjs 'export default []' sesion-ok)"
[ $rc -eq 0 ] && [ -z "$out" ] || fail "con abrir para la sesión debe pasar: $rc $out"
hook pre-edit "$(edit_json eslint.config.mjs 'export default []' otra-sesion)"
[ $rc -eq 2 ] || fail "con abrir para otra sesión debe bloquear: $rc $out"
echo x > "$r/eslint.config.mjs"; hook pre-edit "$(edit_json eslint.config.mjs '/* eslint-disable */' sesion-ok)"
[ $rc -eq 2 ] || fail "abrir no permite eslint-disable: $rc $out"
rm "$r/eslint.config.mjs"
bash "$REPO_ROOT/scripts/kit-reglas.sh" cerrar "$r" >/dev/null || fail "cerrar"
marker "$(jq -c '.blindado = ["reglas/"]' <<<"$LINT")"
hook pre-edit "$(edit_json eslint.config.mjs 'x')"; [ $rc -eq 0 ] || fail "el blindado del marcador manda: $rc $out"
hook pre-edit "$(edit_json reglas/x.yml 'x')"; [ $rc -eq 2 ] || fail "blindado del marcador: $rc $out"
marker "$LINT"

# --- pre-edit: fuera del repo
fuera="$(mktemp -d)"
hook pre-edit "$(edit_json "$fuera/eslint.config.mjs" 'x as any')"
[ $rc -eq 0 ] && [ -z "$out" ] || fail "fuera del repo no hace nada: $rc $out"
hook pre-edit "$(edit_json "../$(basename "$fuera")/eslint.config.mjs" 'x as any')"
[ $rc -eq 0 ] && [ -z "$out" ] || fail "relativa fuera del repo no hace nada: $rc $out"

# --- post-edit
: > "$LOG"
hook post-edit "$(post_json src/a.ts)"
[ $rc -eq 0 ] && [ "$(cat "$LOG")" = "$(printf -- '--rapido\n./src/a.ts')" ] || fail "post-edit ok: $rc $out / $(cat "$LOG")"
[ ! -d "$lock" ] || fail "el candado debe liberarse"
: > "$LOG"; mkdir -p "$r/src/con espacios"; echo x > "$r/src/con espacios/b c.tsx"
hook post-edit "$(post_json "$r/src/con espacios/b c.tsx" "$r/src")"
[ $rc -eq 0 ] && [ "$(sed -n 2p "$LOG")" = "./src/con espacios/b c.tsx" ] || fail "ruta con espacios: $rc $out / $(cat "$LOG")"
: > "$LOG"
hook post-edit "$(post_json "con espacios/b c.tsx" "$r/src")"
[ "$(sed -n 2p "$LOG")" = "./src/con espacios/b c.tsx" ] || fail "ruta relativa al cwd: $(cat "$LOG")"
: > "$LOG"; echo x > "$r/--fix.ts"
hook post-edit "$(post_json --fix.ts)"
[ "$(sed -n 2p "$LOG")" = "./--fix.ts" ] || fail "un nombre con - va con ./ delante: $(cat "$LOG")"
rm "$r/--fix.ts"; : > "$LOG"
FAKE_RC=1 hook post-edit "$(post_json src/a.ts)"
[ $rc -eq 2 ] && [[ "$out" == *"error de lint en --rapido ./src/a.ts"* ]] || fail "lint con exit 1: $rc $out"
FAKE_RC=127 hook post-edit "$(post_json src/a.ts)"; [ $rc -eq 0 ] || fail "exit 127 no bloquea: $rc $out"
FAKE_RC=126 hook post-edit "$(post_json src/a.ts)"; [ $rc -eq 0 ] || fail "exit 126 no bloquea: $rc $out"
: > "$LOG"; echo x > "$r/README.md"
hook post-edit "$(post_json README.md)"; [ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "un .md no lanza nada: $(cat "$LOG")"
echo x > "$fuera/a.ts"
hook post-edit "$(post_json "$fuera/a.ts")"; [ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "fuera del repo no lanza nada"
hook post-edit "$(post_json src/no-existe.ts)"; [ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "un fichero que no existe no lanza nada"
# old <dir> <s>: set the mtime of <dir> <s> seconds in the past.
old() { touch -t "$(date -r $(( $(date +%s) - $2 )) +%Y%m%d%H%M.%S)" "$1"; }
ahora=$(date +%s)
mkdir -p "$lock"
hook post-edit "$(post_json src/a.ts)"; [ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "candado tomado: no lanza nada"
[ -d "$lock" ] || fail "no debe soltar un candado ajeno"
old "$lock" 30
hook post-edit "$(post_json src/a.ts)"; [ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "sin dueño y con menos de 125 s no se roba"
old "$lock" 200
hook post-edit "$(post_json src/a.ts)"; [ $rc -eq 0 ] && [ -s "$LOG" ] || fail "sin dueño y con más de 125 s se recupera: $rc $out"
[ ! -d "$lock" ] || fail "el candado recuperado debe liberarse"
sleep 60 & vivo=$!
mkdir -p "$lock"; echo "$vivo $((ahora + 100))" > "$lock/dueño"; old "$lock" 30; : > "$LOG"
hook post-edit "$(post_json src/a.ts)"; [ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "un dueño vivo en plazo no se roba"
[ "$(cat "$lock/dueño")" = "$vivo $((ahora + 100))" ] || fail "el candado de un dueño vivo no se toca"
echo "$vivo $((ahora - 1))" > "$lock/dueño"
hook post-edit "$(post_json src/a.ts)"; [ -s "$LOG" ] || fail "un dueño fuera de plazo se recupera: $rc $out"
[ ! -d "$lock" ] || fail "el candado de plazo vencido debe liberarse"
kill "$vivo"; wait "$vivo" 2>/dev/null
mkdir -p "$lock"; echo "$vivo $((ahora + 100))" > "$lock/dueño"; : > "$LOG"
hook post-edit "$(post_json src/a.ts)"; [ -s "$LOG" ] || fail "un dueño muerto se recupera: $rc $out"
[ ! -d "$lock" ] || fail "el candado de un dueño muerto debe liberarse"
cat > "$bin/robalint" <<EOF
#!/usr/bin/env bash
echo "1 9999999999" > "$lock/dueño"
EOF
chmod +x "$bin/robalint"
marker "{\"lint\": {\"fichero\": {\"ts\": \"$bin/robalint\"}}}"
hook post-edit "$(post_json src/a.ts)"
[ "$(cat "$lock/dueño" 2>/dev/null)" = "1 9999999999" ] || fail "el trap no debe soltar el candado de otro"
rm "$lock/dueño"; rmdir "$lock"
marker "$LINT"; : > "$LOG"
: > "$LOG"
marker "{\"lint\": {\"fichero\": {\"ts\": \"$bin/slowlint\"}}}"
t0=$(date +%s)
KIT_LINT_TIMEOUT=2 hook post-edit "$(post_json src/a.ts)"
t1=$(date +%s)
[ $rc -eq 0 ] && [ $((t1 - t0)) -lt 8 ] || fail "lint lento con tope 2: rc=$rc $((t1 - t0)) s $out"
pid="$(sed -n 1p "$LOG")"; [ -n "$pid" ] || fail "el lint lento no arrancó"
sleep 1
! kill -0 "$pid" 2>/dev/null || fail "el lint lento sigue vivo"
! pgrep -f "sleep 21.37" >/dev/null 2>&1 || fail "queda un hijo del lint lento"
[ ! -d "$lock" ] || fail "el candado debe liberarse tras el tope"
marker "$LINT"

# --- tiempo: sobrecarga de post-edit con un lint que sale al momento
marker "{\"lint\": {\"fichero\": {\"ts\": \"true\"}}}"
best=999999
for i in 1 2 3 4 5; do
  s="$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')"
  hook post-edit "$(post_json src/a.ts)"
  e="$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')"
  [ $((e - s)) -lt $best ] && best=$((e - s))
done
echo "post-edit: sobrecarga mínima ${best} ms"
[ $best -lt 300 ] || fail "post-edit tarda ${best} ms (tope 300)"
marker "$LINT"

# --- stop-check
(cd "$r" && git add -A && git commit -q -m base) || fail "commit base"
: > "$LOG"
hook stop-check "$(stop_json)"; [ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "sin cambios no lanza nada: $rc $(cat "$LOG")"
rm "$r/README.md"; echo y >> "$r/src/a.ts"; echo z > "$r/src/nuevo.ts"; echo f > "$r/--fix.ts"; echo i > "$r/ignorado.log"; echo '*.log' > "$r/.gitignore"
hook stop-check "$(stop_json)"
[ $rc -eq 0 ] || fail "stop-check ok: $rc $out"
[ "$(sed -n 1p "$LOG")" = "--turno" ] || fail "stop-check sin --turno: $(cat "$LOG")"
got="$(sed -n '2,$p' "$LOG" | sort | tr '\n' ' ')"
[ "$got" = "./--fix.ts ./.gitignore ./src/a.ts ./src/nuevo.ts " ] || fail "stop-check pasa '$got'"
FAKE_RC=1 hook stop-check "$(stop_json)"
[ $rc -eq 2 ] && [[ "$out" == *"error de lint en --turno"* ]] || fail "stop-check con exit 1: $rc $out"
FAKE_RC=127 hook stop-check "$(stop_json)"; [ $rc -eq 0 ] || fail "stop-check exit 127 no bloquea: $rc"
FAKE_RC=1 hook stop-check "$(inp --arg c "$r" '{cwd: $c, stop_hook_active: true}')"
[ $rc -eq 2 ] || fail "stop_hook_active sigue comprobando: $rc"
mkdir -p "$lock"; : > "$LOG"
hook stop-check "$(stop_json)"; [ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "stop-check con candado no lanza nada"
rmdir "$lock"
marker "{\"lint\": {\"fichero\": {\"ts\": \"$bin/fakelint\"}}}"
hook stop-check "$(stop_json)"; [ $rc -eq 0 ] && [ -z "$out" ] || fail "sin turno no hace nada: $rc $out"

echo ok
