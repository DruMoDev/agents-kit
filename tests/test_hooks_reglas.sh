#!/usr/bin/env bash
# Tests for hooks/pre-edit, hooks/post-edit and hooks/stop-check (fed by stdin with JSON, fake lint commands).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
export TMPDIR="$(mktemp -d)"
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
[ $rc -eq 2 ] || fail "un old_string que no está y un new_string con as any bloquea: $rc $out"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/f.ts",
  old_string: "p as any", new_string: "q as any"}}')"
[ $rc -eq 2 ] || fail "un old_string que no está con as any en new_string bloquea aunque old_string lo tenga: $rc $out"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/f.ts",
  old_string: "p as any", new_string: "q"}}')"
[ $rc -eq 0 ] || fail "un old_string que no está sin texto prohibido en new_string no bloquea: $rc $out"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/f.ts",
  edits: [{old_string: "w as anything", new_string: "w as anything2"}, {old_string: "no está", new_string: "// @ts-nocheck"}]}}')"
[ $rc -eq 2 ] || fail "una edición de MultiEdit que no casa con texto prohibido bloquea: $rc $out"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/f.ts",
  new_source: "x = 1", content: "let v = w as any;"}}')"
[ $rc -eq 2 ] || fail "todos los campos cuentan: new_source limpio y content con as any bloquea: $rc $out"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/f.ts",
  content: "let v = w as anything;", old_string: "anything", new_string: "any;"}}')"
[ $rc -eq 2 ] || fail "todos los campos cuentan: content limpio y Edit que crea as any bloquea: $rc $out"
printf 'let a = 1;\r\nlet b = c as any;\r\n' > "$r/src/crlf.ts"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/crlf.ts",
  old_string: "let a = 1;\nlet b = c as any;", new_string: "let a = 2;\nlet b = c as any;"}}')"
[ $rc -eq 0 ] || fail "CRLF en el fichero casa con LF en old_string: $rc $out"
# matched (with CRLF as LF) the file keeps one as any; unmatched, the input rule would block (0 -> 1)
printf 'c = d as any\r\nq\r\n' > "$r/src/crlf2.ts"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/crlf2.ts",
  old_string: "any\nq", new_string: "anything\nq as any"}}')"
[ $rc -eq 0 ] || fail "con CRLF normalizado la edición casa y la cuenta del fichero no sube: $rc $out"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_name: "NotebookEdit",
  tool_input: {notebook_path: "src/n.ipynb", cell_id: "c1", new_source: "x = y  # @ts-ignore"}}')"
[ $rc -eq 2 ] || fail "NotebookEdit con texto prohibido en new_source bloquea: $rc $out"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_name: "NotebookEdit",
  tool_input: {notebook_path: "src/n.ipynb", cell_id: "c1", new_source: "x = 1"}}')"
[ $rc -eq 0 ] || fail "NotebookEdit sin texto prohibido pasa: $rc $out"
printf 'x\n' > "$r/src/ilegible.ts"; chmod 000 "$r/src/ilegible.ts"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_input: {file_path: "src/ilegible.ts",
  old_string: "x", new_string: "y"}}')"
chmod 644 "$r/src/ilegible.ts"
[ $rc -eq 2 ] && [[ "$out" == *"No se pudo comprobar"* ]] || fail "un fichero ilegible bloquea: $rc $out"
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

# --- Codex: apply_patch (tool_input.command con el parche; puede tocar varios ficheros)
pjson() { inp --arg c "$r" --arg p "$1" --arg s "${2:-s1}" '{session_id: $s, cwd: $c, hook_event_name: "PreToolUse",
  tool_name: "apply_patch", tool_input: {command: $p}}'; }
patch() { printf '*** Begin Patch\n%s\n*** End Patch\n' "$1"; }
hook pre-edit "$(pjson "$(patch $'*** Add File: src/p1.ts\n+const x = 1 as any')")"
[ $rc -eq 2 ] && [[ "$out" == *"src/p1.ts: No desactives reglas ni tipos"* ]] || fail "apply_patch Add con as any bloquea: $rc $out"
hook pre-edit "$(pjson "$(patch $'*** Add File: src/p1.ts\n+const x = 1')")"; [ $rc -eq 0 ] && [ -z "$out" ] || fail "apply_patch Add limpio pasa: $rc $out"
printf 'let a = b as any;\nlet c = 1;\n' > "$r/src/p2.ts"
hook pre-edit "$(pjson "$(patch $'*** Update File: src/p2.ts\n@@\n let a = b as any;\n-let c = 1;\n+let c = 2;')")"
[ $rc -eq 0 ] || fail "apply_patch Update con as any heredado en el contexto pasa: $rc $out"
hook pre-edit "$(pjson "$(patch $'*** Update File: src/p2.ts\n@@\n let a = b as any;\n-let c = 1;\n+let c = d as any;')")"
[ $rc -eq 2 ] || fail "apply_patch Update que añade as any bloquea: $rc $out"
hook pre-edit "$(pjson "$(patch $'*** Update File: src/p2.ts\n let a = b as any;\n+// @ts-ignore\n let c = 1;')")"
[ $rc -eq 2 ] || fail "apply_patch Update sin @@ que añade un @ts-ignore bloquea: $rc $out"
hook pre-edit "$(pjson "$(patch $'*** Update File: src/p2.ts\n@@\n-let a = b as any;\n+let a = b as unknown;')")"
[ $rc -eq 0 ] || fail "apply_patch Update que quita as any pasa: $rc $out"
# hunk que no casa con el fichero: cualquier coincidencia en su texto nuevo bloquea (falla cerrado)
hook pre-edit "$(pjson "$(patch $'*** Update File: src/p2.ts\n@@\n let a = b as any;\n-no está\n+otra')")"
[ $rc -eq 2 ] || fail "apply_patch con un hunk que no casa y as any en el contexto bloquea: $rc $out"
# varios ficheros: basta uno; el blindado se mira en cada uno (Delete y Move to incluidos)
hook pre-edit "$(pjson "$(patch $'*** Add File: README.md\n+hola\n*** Add File: src/p3.ts\n+// eslint-disable-next-line')")"
[ $rc -eq 2 ] && [[ "$out" == *"src/p3.ts: "* ]] || fail "apply_patch con varios ficheros bloquea por el segundo: $rc $out"
hook pre-edit "$(pjson "$(patch $'*** Delete File: eslint.config.mjs')")"
[ $rc -eq 2 ] && [[ "$out" == *"eslint.config.mjs: Fichero de reglas"* ]] || fail "apply_patch Delete de un blindado bloquea: $rc $out"
hook pre-edit "$(pjson "$(patch $'*** Update File: src/p2.ts\n*** Move to: tsconfig.json\n@@\n-let c = 1;\n+let c = 3;')")"
[ $rc -eq 2 ] && [[ "$out" == *"tsconfig.json: Fichero de reglas"* ]] || fail "apply_patch Move to a un blindado bloquea: $rc $out"
hook pre-edit "$(pjson "$(patch $'*** Add File: src/con espacios/q r.ts\n+x')")"; [ $rc -eq 0 ] || fail "apply_patch ruta con espacios: $rc $out"
fuera_p="$(mktemp -d)"
hook pre-edit "$(pjson "$(patch "*** Add File: $fuera_p/eslint.config.mjs"$'\n+x as any')")"
[ $rc -eq 0 ] && [ -z "$out" ] || fail "apply_patch fuera del repo no hace nada: $rc $out"
hook pre-edit "$(pjson $'*** Begin Patch\r\n*** Add File: src/p4.ts\r\n+x as any\r\n*** End Patch\r\n')"
[ $rc -eq 2 ] || fail "apply_patch con CRLF bloquea igual: $rc $out"
hook pre-edit "$(pjson 'esto no es un parche')"
[ $rc -eq 2 ] && [[ "$out" == *"No se pudo leer el parche"* ]] || fail "apply_patch ilegible bloquea: $rc $out"
hook pre-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_name: "apply_patch", tool_input: {}}')"
[ $rc -eq 2 ] || fail "apply_patch sin command bloquea: $rc $out"
bash "$REPO_ROOT/scripts/kit-reglas.sh" abrir "$r" sesion-p >/dev/null || fail "abrir (apply_patch)"
hook pre-edit "$(pjson "$(patch $'*** Add File: eslint.config.mjs\n+export default []')" sesion-p)"
[ $rc -eq 0 ] && [ -z "$out" ] || fail "apply_patch de un blindado con abrir para la sesión pasa: $rc $out"
bash "$REPO_ROOT/scripts/kit-reglas.sh" cerrar "$r" >/dev/null || fail "cerrar (apply_patch)"
rm -f "$r/src/p2.ts"

# marcadores reconocidos sobre la línea recortada (como apply_patch); lo que no se entiende hace ilegible el parche
hook pre-edit "$(pjson $'*** Begin Patch\n*** Add File: README.md\n+hola\n *** Add File: src/x.ts\n+x as any\n*** End Patch')"
[ $rc -eq 2 ] || fail "un marcador con espacio delante no esconde un Add con as any: $rc $out"
hook pre-edit "$(pjson $'*** Begin Patch\n*** Delete File: viejo.md\n *** Add File: src/x.ts\n+x as any\n*** End Patch')"
[ $rc -eq 2 ] || fail "tras un Delete, un Add con espacio delante bloquea: $rc $out"
hook pre-edit "$(pjson $'*** Begin Patch\n*** Delete File: viejo.md\nx as any\n*** End Patch')"
[ $rc -eq 2 ] && [[ "$out" == *"No se pudo leer el parche"* ]] || fail "una línea tras un Delete hace ilegible el parche: $rc $out"
hook pre-edit "$(pjson $'*** Begin Patch\n*** Add File: src/x.ts\nx as any\n*** End Patch')"
[ $rc -eq 2 ] && [[ "$out" == *"No se pudo leer el parche"* ]] || fail "una línea de Add sin + hace ilegible el parche: $rc $out"
hook pre-edit "$(pjson $'*** Begin Patch\n*** Add File: README.md\n+hola\n*** Raro: src/x.ts\n*** End Patch')"
[ $rc -eq 2 ] && [[ "$out" == *"No se pudo leer el parche"* ]] || fail "un *** desconocido hace ilegible el parche: $rc $out"
hook pre-edit "$(pjson $'*** Begin Patch\n*** Add File:src/x.ts  \n+x as any\n*** End Patch')"
[ $rc -eq 2 ] && [[ "$out" == *"src/x.ts: No desactives"* ]] || fail "Add File: sin espacio y con espacios al final se reconoce: $rc $out"
hook pre-edit "$(pjson $'*** Begin Patch\n*** Add File: README.md\n+hola\n*** End Patch\n*** Add File: src/x.ts\n+x as any')"
[ $rc -eq 2 ] || fail "algo tras *** End Patch bloquea: $rc $out"
printf 'let a = b as any;\n' > "$r/src/p5.ts"
hook pre-edit "$(pjson "$(patch $'*** Update File: src/p5.ts\n@@\n-let a = b as any;\n+let a = b;\n*** Add File: src/p6.ts\n+let c = d as any;')")"
[ $rc -eq 2 ] && [[ "$out" == *"src/p6.ts: "* ]] || fail "quitar as any de un fichero no tapa meterlo en otro: $rc $out"
rm -f "$r/src/p5.ts"
# clasificación de líneas como Codex: un contexto que es un marcador una vez recortado hace ilegible el parche
printf '/**\n*** Update File: README.md\n*/\n' > "$r/src/byp.ts"
hook pre-edit "$(pjson "$(patch $'*** Update File: src/byp.ts\n@@\n *** Update File: README.md\n+const z = 1 as any;')")"
[ $rc -eq 2 ] || fail "un contexto que parece un marcador no esconde un as any: $rc $out"
rm -f "$r/src/byp.ts"
printf 'a\n***\nb ***negrita*** c\n' > "$r/doc.md"
hook pre-edit "$(pjson "$(patch $'*** Update File: doc.md\n@@\n a\n ***\n-b ***negrita*** c\n+b ***negrita*** d')")"
[ $rc -eq 0 ] && [ -z "$out" ] || fail "*** y ***negrita*** como contexto de markdown no bloquean: $rc $out"
hook pre-edit "$(pjson "$(patch $'*** Update File: doc.md\n@@\n a\n\n ***')")"
[ $rc -eq 0 ] || fail "una línea vacía en un Update es contexto vacío: $rc $out"
rm -f "$r/doc.md"
# rutas con .. normalizadas como path.resolve, aunque el directorio intermedio no exista
hook pre-edit "$(pjson "$(patch $'*** Add File: nodir/../src/x.ts\n+x as any')")"
[ $rc -eq 2 ] || fail "apply_patch con nodir/../src/x.ts y as any bloquea: $rc $out"
hook pre-edit "$(edit_json nodir/../src/x.ts 'x as any')"
[ $rc -eq 2 ] || fail "Edit con nodir/../src/x.ts y as any bloquea: $rc $out"
hook pre-edit "$(edit_json nodir/../eslint.config.mjs 'x')"
[ $rc -eq 2 ] || fail "Edit con nodir/../ sobre un blindado bloquea: $rc $out"

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
# apply_patch: un lint por comando con todos sus ficheros que existen, en el orden del parche
marker "{\"lint\": {\"fichero\": {\"ts\": \"$bin/fakelint --ts\", \"tsx\": \"$bin/fakelint --tsx\"}}}"
echo x > "$r/src/q1.ts"; echo x > "$r/src/q2.tsx"; : > "$LOG"
hook post-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_name: "apply_patch", tool_input: {command:
  "*** Begin Patch\n*** Add File: src/q1.ts\n+x\n*** Update File: src/q2.tsx\n@@\n-y\n+x\n*** Delete File: src/borrado.ts\n*** Add File: src/a.ts\n+x\n*** Add File: README.md\n+x\n*** End Patch\n"}}')"
[ $rc -eq 0 ] && [ "$(tr '\n' ' ' < "$LOG")" = "--ts ./src/q1.ts ./src/a.ts --tsx ./src/q2.tsx " ] || fail "post-edit de apply_patch: $rc $out / $(cat "$LOG")"
FAKE_RC=1 hook post-edit "$(inp --arg c "$r" '{session_id: "s1", cwd: $c, tool_name: "apply_patch", tool_input: {command:
  "*** Begin Patch\n*** Add File: src/q1.ts\n+x\n*** Add File: src/q2.tsx\n+x\n*** End Patch\n"}}')"
[ $rc -eq 2 ] && [[ "$out" == *"El lint falla en src/q1.ts"* ]] && [[ "$out" == *"El lint falla en src/q2.tsx"* ]] \
  || fail "post-edit de apply_patch con lint roto en los dos comandos: $rc $out"
[ ! -d "$lock" ] || fail "el candado debe liberarse tras apply_patch"
rm -f "$r/src/q1.ts" "$r/src/q2.tsx"; marker "$LINT"; : > "$LOG"
# old <dir> <s>: set the mtime of <dir> <s> seconds in the past (perl: the same on macOS and Linux).
old() { perl -e 'my $t = time - $ARGV[1]; utime $t, $t, $ARGV[0] or exit 1' "$1" "$2"; }
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

# --- la raíz sale de la ruta del fichero: sesión en el clon A (sin marcador) editando su worktree B (con marcador)
ra="$(mk_repo)"; rb="$(mktemp -d)/wt b"; rc_="$(mk_repo)"; rf="$(mk_repo)"
git -C "$ra" worktree add -q -b wt "$rb" || fail "worktree B"
printf '%s\n' "$LINT" > "$rb/.agents-kit.json"; mkdir -p "$rb/src" "$rc_/src" "$rf/src"
(cd "$rb" && git add -A && git commit -q -m base) || fail "commit base de B"
xjson() { inp --arg c "${4:-$ra}" --arg f "$1" --arg t "$2" --arg e "$3" --arg s "${5:-cruz}" '{session_id: $s, cwd: $c,
  hook_event_name: $e, tool_name: "Write", tool_input: {file_path: $f, content: $t}}'; }
hook pre-edit "$(xjson "$rb/src/x.ts" 'x as any' PreToolUse)"
[ $rc -eq 2 ] || fail "pre-edit desde A aplica las reglas de B: $rc $out"
hook pre-edit "$(xjson "$rb/eslint.config.mjs" 'x' PreToolUse)"
[ $rc -eq 2 ] || fail "pre-edit desde A aplica el blindado de B: $rc $out"
hook pre-edit "$(xjson "$rc_/src/x.ts" 'x as any' PreToolUse)"
[ $rc -eq 0 ] && [ -z "$out" ] || fail "un repo sin marcador sigue inerte aunque no sea el del cwd: $rc $out"
echo 'export const y = 1;' > "$rb/src/y.ts"; : > "$LOG"
hook post-edit "$(xjson "$rb/src/y.ts" 'x' PostToolUse)"
[ $rc -eq 0 ] && [ "$(cat "$LOG")" = "$(printf -- '--rapido\n./src/y.ts')" ] || fail "post-edit desde A pasa el lint de su worktree B: $rc $out / $(cat "$LOG")"
: > "$LOG"
FAKE_RC=1 hook stop-check "$(inp --arg c "$ra" '{session_id: "cruz", cwd: $c, stop_hook_active: false}')"
[ $rc -eq 2 ] && [[ "$out" == *"los ficheros cambiados de "* ]] && [ "$(sed -n 1p "$LOG")" = "--turno" ] \
  && grep -qx './src/y.ts' "$LOG" || fail "stop-check desde A revisa B: $rc $out / $(cat "$LOG")"
: > "$LOG"
FAKE_RC=1 hook stop-check "$(inp --arg c "$ra" '{session_id: "otra-cruz", cwd: $c, stop_hook_active: false}')"
[ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "otra sesión en A no revisa B: $rc $out"
# parche ilegible hacia B desde A (sin marcador): bloquea; hacia un repo sin marcador, no
xpatch() { inp --arg c "$ra" --arg p "$1" '{session_id: "cruz", cwd: $c, tool_name: "apply_patch", tool_input: {command: $p}}'; }
hook pre-edit "$(xpatch "*** Begin Patch"$'\n'"*** Add File: $rb/src/q.ts"$'\nbasura\n*** End Patch')"
[ $rc -eq 2 ] && [[ "$out" == *"No se pudo leer el parche"* ]] || fail "un parche ilegible hacia B bloquea desde A: $rc $out"
hook pre-edit "$(xpatch "*** Begin Patch"$'\n'"*** Add File: $rc_/src/q.ts"$'\nbasura\n*** End Patch')"
[ $rc -eq 0 ] || fail "un parche ilegible hacia un repo sin marcador no bloquea: $rc $out"
# repo ajeno con marcador (otro clon): sus reglas se aplican, pero su lint no se ejecuta nunca
printf '{"lint": {"fichero": {"ts": "touch testigo"}, "turno": "touch testigo-turno"}}\n' > "$rf/.agents-kit.json"
(cd "$rf" && git add -A && git commit -q -m base) || fail "commit base ajeno"
echo 'x' > "$rf/src/z.ts"
hook pre-edit "$(xjson "$rf/src/z.ts" 'x as any' PreToolUse)"; [ $rc -eq 2 ] || fail "pre-edit aplica las reglas del repo ajeno: $rc $out"
hook post-edit "$(xjson "$rf/src/z.ts" 'x' PostToolUse)"
[ $rc -eq 0 ] && [ ! -e "$rf/testigo" ] || fail "post-edit no ejecuta el lint de un repo ajeno: $rc $out"
nogit_cwd="$(mktemp -d)"; : > "$LOG"
hook post-edit "$(xjson "$rb/src/y.ts" 'x' PostToolUse "$nogit_cwd")"
[ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "con el cwd fuera de git no se ejecuta ningún lint: $rc $(cat "$LOG")"
sesdir="$TMPDIR/agents-kit-$(id -u)"
h="$(printf '%s' cruz | shasum -a 256)"; printf '%s\n' "$rf" >> "$sesdir/sesion-${h%% *}"
FAKE_RC=1 hook stop-check "$(inp --arg c "$ra" '{session_id: "cruz", cwd: $c, stop_hook_active: false}')"
[ ! -e "$rf/testigo-turno" ] || fail "stop-check no ejecuta el turno de un repo ajeno metido en el fichero de sesión"
[ $rc -eq 2 ] || fail "stop-check sigue revisando B con una entrada envenenada: $rc $out"
# repo anidado sin marcador dentro de B: se aplica B (el repo marcado más cercano), y su lint por confianza
mkdir -p "$rb/sub" && git -C "$rb/sub" init -q && echo 'x' > "$rb/sub/n.ts"
hook pre-edit "$(xjson "$rb/sub/n.ts" 'x as any' PreToolUse)"; [ $rc -eq 2 ] || fail "un repo anidado sin marcador hereda B: $rc $out"
: > "$LOG"; hook post-edit "$(xjson "$rb/sub/n.ts" 'x' PostToolUse)"
[ "$(sed -n 2p "$LOG")" = "./sub/n.ts" ] || fail "post-edit en el repo anidado pasa el lint de B: $(cat "$LOG")"
rm -rf "$rb/sub"
# un directorio en el que no se puede entrar, dentro de B: bloquea
mkdir -p "$rb/src/cerrado/x"; chmod 000 "$rb/src/cerrado"
hook pre-edit "$(xjson "$rb/src/cerrado/x/y.ts" 'x' PreToolUse)"
chmod 755 "$rb/src/cerrado"; rm -rf "$rb/src/cerrado"
[ $rc -eq 2 ] && [[ "$out" == *"No se pudo resolver la ruta"* ]] || fail "un directorio cerrado dentro de B bloquea: $rc $out"
# directorio de sesión con otro modo o que es un enlace: no se usa (ni se apunta B ni se lleva la cuenta del tope)
for mal in modo enlace; do
  export TMPDIR="$(mktemp -d)"; sd="$TMPDIR/agents-kit-$(id -u)"
  if [ $mal = modo ]; then mkdir -m 755 "$sd"; else mkdir -m 700 "$TMPDIR/otro"; ln -s "$TMPDIR/otro" "$sd"; fi
  hook post-edit "$(xjson "$rb/src/y.ts" 'x' PostToolUse "$ra" s-$mal)"
  [ -z "$(ls -A "$sd/")" ] || fail "directorio de sesión no fiable ($mal): no se escribe nada: $(ls -A "$sd/")"
  : > "$LOG"
  FAKE_RC=1 hook stop-check "$(inp --arg c "$ra" --arg s s-$mal '{session_id: $s, cwd: $c, stop_hook_active: false}')"
  [ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "sin directorio de sesión fiable no se revisa B ($mal): $rc $out"
done
export TMPDIR="$(mktemp -d)"
# stat de GNU (stat -f muestra el sistema de ficheros y sale con 1): el directorio de sesión sigue valiendo
gnubin="$(mktemp -d)"
printf '#!/bin/sh\n[ "$1" = -f ] && { echo "  File: \\"$3\\""; echo "    ID: 0 Namelen: 255 Type: apfs"; exit 1; }\n[ "$1" = -c ] && [ "$2" = %%a ] && { echo 700; exit 0; }\nexit 1\n' > "$gnubin/stat"
chmod +x "$gnubin/stat"
echo "export const y = 1;" > "$rb/src/y.ts"
echo "export const y = 1;" > "$rb/src/y.ts"
PATH="$gnubin:$PATH" hook post-edit "$(xjson "$rb/src/y.ts" 'x' PostToolUse "$ra" s-gnu)"
h="$(printf '%s' s-gnu | shasum -a 256)"
grep -qxF "$(cd "$rb" && pwd -P)" "$TMPDIR/agents-kit-$(id -u)/sesion-${h%% *}" 2>/dev/null \
  || fail "con un stat de GNU se apunta igual el worktree: $(ls -la "$TMPDIR/agents-kit-$(id -u)/" 2>&1)"
# un directorio con un .git que apunta al gitdir del clon pero no está en git worktree list: no es de confianza
falso="$(mktemp -d)"; printf 'gitdir: %s/.git\n' "$ra" > "$falso/.git"; mkdir -p "$falso/src"
printf '{"lint": {"fichero": {"ts": "touch testigo"}, "turno": "touch testigo-turno"}}\n' > "$falso/.agents-kit.json"
echo x > "$falso/src/z.ts"
[ "$(cd "$(git -C "$falso" rev-parse --git-common-dir)" && pwd -P)" = "$(cd "$ra/.git" && pwd -P)" ] \
  || fail "el .git falso debería compartir el gitdir de A"
hook post-edit "$(xjson "$falso/src/z.ts" 'x' PostToolUse)"
[ ! -e "$falso/testigo" ] || fail "post-edit no ejecuta el lint de un directorio con un .git hacia el clon fuera de worktree list"
h="$(printf '%s' cruz | shasum -a 256)"; printf '%s\n' "$(cd "$falso" && pwd -P)" >> "$TMPDIR/agents-kit-$(id -u)/sesion-${h%% *}"
hook stop-check "$(inp --arg c "$ra" '{session_id: "cruz", cwd: $c, stop_hook_active: false}')"
[ ! -e "$falso/testigo-turno" ] || fail "stop-check no ejecuta el turno del directorio falso apuntado"
# cwd en un repo anidado sin marcador dentro de B: se usa B (respaldo del parche ilegible, stop-check y confianza)
mkdir -p "$rb/sub" && git -C "$rb/sub" init -q && echo 'x' > "$rb/sub/n.ts"
hook pre-edit "$(inp --arg c "$rb/sub" '{session_id: "an", cwd: $c, tool_name: "apply_patch", tool_input: {command: "basura"}}')"
[ $rc -eq 2 ] && [[ "$out" == *"No se pudo leer el parche"* ]] || fail "parche ilegible con el cwd anidado en B bloquea: $rc $out"
echo 'export const y = 1;' > "$rb/src/y.ts"; : > "$LOG"
hook post-edit "$(xjson "$rb/src/y.ts" 'x' PostToolUse "$rb/sub" an)"
[ "$(sed -n 2p "$LOG")" = "./src/y.ts" ] || fail "post-edit con el cwd anidado en B pasa el lint de B: $(cat "$LOG")"
: > "$LOG"
FAKE_RC=1 hook stop-check "$(inp --arg c "$rb/sub" '{session_id: "an2", cwd: $c, stop_hook_active: false}')"
[ $rc -eq 2 ] && [ "$(sed -n 1p "$LOG")" = "--turno" ] || fail "stop-check con el cwd anidado revisa B: $rc $out / $(cat "$LOG")"
rm -rf "$rb/sub"; : > "$LOG"
# git-common-dir en el que no se puede entrar: pre-edit bloquea si el repo tiene reglas; post-edit no ejecuta nada
gitbin="$(mktemp -d)"; realgit="$(command -v git)"
cat > "$gitbin/git" <<EOF
#!/bin/sh
if [ "\$1" = -C ] && [ "\$3" = rev-parse ] && [ "\$4" = --show-toplevel ]; then
  case "\$2" in "$(cd "$rb" && pwd -P)"*) printf '%s\n/no/existe/common\n' "$(cd "$rb" && pwd -P)"; exit 0 ;; esac
fi
exec "$realgit" "\$@"
EOF
chmod +x "$gitbin/git"
PATH="$gitbin:$PATH" hook pre-edit "$(xjson "$rb/src/y.ts" 'x' PreToolUse)"
[ $rc -eq 2 ] && [[ "$out" == *"No se pudo resolver la ruta"* ]] || fail "un git-common-dir inaccesible bloquea en pre-edit: $rc $out"
: > "$LOG"; PATH="$gitbin:$PATH" hook post-edit "$(xjson "$rb/src/y.ts" 'x' PostToolUse)"
[ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "un git-common-dir inaccesible no ejecuta lint: $rc $(cat "$LOG")"
export TMPDIR="$(mktemp -d)"
rm -f "$rb/src/y.ts"; : > "$LOG"

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
# tope propio de bloqueos seguidos (Codex no tiene): con stop_hook_active, a los 8 deja terminar y vuelve a empezar
sjson() { inp --arg c "$r" --arg s "$1" --argjson a "$2" '{session_id: $s, cwd: $c, stop_hook_active: $a}'; }
cnt() { local h; h="$(printf '%s' "$1" | shasum -a 256)"; echo "$TMPDIR/agents-kit-$(id -u)/turno-bloqueos-${h%% *}"; }
FAKE_RC=1 hook stop-check "$(sjson t1 false)"; [ $rc -eq 2 ] || fail "primer bloqueo: $rc"
for k in 2 3 4 5 6 7; do FAKE_RC=1 hook stop-check "$(sjson t1 true)"; [ $rc -eq 2 ] || fail "bloqueo $k: $rc"; done
FAKE_RC=1 hook stop-check "$(sjson otra true)"; [ $rc -eq 2 ] || fail "otra sesión no hereda la cuenta: $rc"
FAKE_RC=1 hook stop-check "$(sjson t1 true)"; [ $rc -eq 2 ] || fail "otra sesión entre medias no reinicia la cuenta (8.º): $rc"
[ "$(cat "$(cnt t1)")" = 8 ] && [ "$(cat "$(cnt otra)")" = 1 ] || fail "cada sesión lleva su cuenta: $(cat "$(cnt t1)") $(cat "$(cnt otra)")"
FAKE_RC=1 hook stop-check "$(sjson otra true)"; [ $rc -eq 2 ] && [ "$(cat "$(cnt otra)")" = 2 ] || fail "la cuenta de otra sigue: $rc"
: > "$LOG"; FAKE_RC=1 hook stop-check "$(sjson t1 true)"
[ $rc -eq 0 ] && [[ "$out" == *"tras 8 intentos seguidos"* ]] && [ ! -s "$LOG" ] || fail "al noveno deja terminar: $rc $out"
[ ! -f "$(cnt t1)" ] && [ -f "$(cnt otra)" ] || fail "al llegar al tope se borra solo la cuenta de esa sesión"
FAKE_RC=1 hook stop-check "$(sjson t1 true)"; [ $rc -eq 2 ] || fail "tras dejar terminar vuelve a comprobar: $rc"
FAKE_RC=1 hook stop-check "$(sjson t1 false)"; [ $rc -eq 2 ] && [ "$(cat "$(cnt t1)")" = 1 ] || fail "sin stop_hook_active empieza de cero: $rc"
FAKE_RC=1 KIT_TURNO_BLOQUEOS=1 hook stop-check "$(sjson t1 true)"; [ $rc -eq 0 ] || fail "KIT_TURNO_BLOQUEOS manda: $rc"
FAKE_RC=1 hook stop-check "$(sjson t1 false)"
hook stop-check "$(sjson t1 false)"; [ $rc -eq 0 ] && [ ! -f "$(cnt t1)" ] || fail "un turno limpio borra la cuenta: $rc"
mkdir -p "$lock"; : > "$LOG"
hook stop-check "$(stop_json)"; [ $rc -eq 0 ] && [ ! -s "$LOG" ] || fail "stop-check con candado no lanza nada"
rmdir "$lock"
marker "{\"lint\": {\"fichero\": {\"ts\": \"$bin/fakelint\"}}}"
hook stop-check "$(stop_json)"; [ $rc -eq 0 ] && [ -z "$out" ] || fail "sin turno no hace nada: $rc $out"

echo ok
