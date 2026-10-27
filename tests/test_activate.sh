#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1

S="$REPO_ROOT/scripts/kit-activate.sh"
dirs=()
trap 'rm -rf "${dirs[@]}"' EXIT
new_repo() { local d; d="$(mk_repo)"; dirs+=("$d"); echo "$d"; }
last_line() { tail -n 1 <<<"$1"; }

# 1. empty repo: everything created
r="$(new_repo)"
out="$(bash "$S" "$r" 2>/dev/null)" || fail "activate on empty repo should exit 0"
for f in .agents-kit.json CHANGELOG.md AGENTS.md CLAUDE.md; do [ -f "$r/$f" ] || fail "missing $f"; done
[ -d "$r/.agents/skills" ] || fail "missing .agents/skills"
[ -f "$r/.agents/skills/.gitkeep" ] || fail "missing .agents/skills/.gitkeep"
git -C "$r" status --porcelain -uall | grep -q '\.agents/skills/\.gitkeep' || fail ".gitkeep must be visible to git"
[ -L "$r/.claude/skills" ] || fail "missing .claude/skills symlink"
[ "$(cat "$r/CLAUDE.md")" = "@AGENTS.md" ] || fail "CLAUDE.md should be exactly @AGENTS.md"
[ "$(readlink "$r/.claude/skills")" = "../.agents/skills" ] || fail "wrong symlink target"
[ "$(jq -c . "$r/.agents-kit.json")" = "{}" ] || fail "el marcador nuevo debe ser {} (lo global va en ~/.agents-kit/config.json)"
[ "$(last_line "$out")" = "FIN: 7" ] || fail "expected FIN: 7, got: $(last_line "$out")"
grep -q "^# Changelog" "$r/CHANGELOG.md" || fail "CHANGELOG title"
grep -qx '## Reglas del proyecto' "$r/AGENTS.md" || fail "la plantilla AGENTS.md debe tener ## Reglas del proyecto"
grep -Eq 'senior vago|Tests y verificación|Flujo git' "$r/AGENTS.md" && fail "AGENTS.md template must not contain kit rules"

# 2. idempotent
before="$(cd "$r" && cat .agents-kit.json CHANGELOG.md AGENTS.md CLAUDE.md | shasum)"
out="$(bash "$S" "$r" 2>/dev/null)" || fail "second run should exit 0"
[ "$(last_line "$out")" = "FIN: 0" ] || fail "second run expected FIN: 0, got: $(last_line "$out")"
after="$(cd "$r" && cat .agents-kit.json CHANGELOG.md AGENTS.md CLAUDE.md | shasum)"
[ "$before" = "$after" ] || fail "files changed on second run"

# 2b. existing empty .agents/skills dir gets a .gitkeep; non-empty dir does not
r="$(new_repo)"; mkdir -p "$r/.agents/skills"
bash "$S" "$r" >/dev/null 2>&1; [ -f "$r/.agents/skills/.gitkeep" ] || fail "empty dir should get .gitkeep"
r="$(new_repo)"; mkdir -p "$r/.agents/skills/x"; echo s > "$r/.agents/skills/x/SKILL.md"
bash "$S" "$r" >/dev/null 2>&1; [ ! -e "$r/.agents/skills/.gitkeep" ] || fail "non-empty dir must not get .gitkeep"

# 3. existing AGENTS.md and CLAUDE.md preserved
r="$(new_repo)"
echo "Mi contenido" > "$r/AGENTS.md"
echo "Notas" > "$r/CLAUDE.md"
out="$(bash "$S" "$r" 2>/dev/null)" || fail "activate with existing files should exit 0"
[ "$(head -n 1 "$r/AGENTS.md")" = "Mi contenido" ] || fail "AGENTS.md lost its content"
grep -qx '## Reglas del proyecto' "$r/AGENTS.md" || fail "AGENTS.md sin la sección Reglas del proyecto"
grep -qx 'cambiado: AGENTS.md' <<<"$out" || fail "debe decir cambiado: AGENTS.md"
[ "$(head -n 1 "$r/CLAUDE.md")" = "@AGENTS.md" ] || fail "CLAUDE.md should start with @AGENTS.md"
grep -qx "Notas" "$r/CLAUDE.md" || fail "CLAUDE.md lost its content"
out="$(bash "$S" "$r" 2>/dev/null)"
[ "$(last_line "$out")" = "FIN: 0" ] || fail "rerun should be FIN: 0"
[ "$(grep -cx '@AGENTS.md' "$r/CLAUDE.md")" = "1" ] || fail "@AGENTS.md duplicated"

# 3b. CLAUDE.md already has @AGENTS.md later in the file: untouched
r="$(new_repo)"
printf 'Notas\n@AGENTS.md\n' > "$r/CLAUDE.md"
bash "$S" "$r" >/dev/null 2>&1 || fail "exit 0 expected"
[ "$(head -n 1 "$r/CLAUDE.md")" = "Notas" ] || fail "CLAUDE.md with existing import was changed"

# 3c. CLAUDE.md symlink to AGENTS.md: satisfied, not modified
r="$(new_repo)"
echo "Mi contenido" > "$r/AGENTS.md"
ln -s AGENTS.md "$r/CLAUDE.md"
bash "$S" "$r" >/dev/null 2>&1 || fail "exit 0 expected for CLAUDE.md symlink"
[ -L "$r/CLAUDE.md" ] || fail "CLAUDE.md symlink was replaced"
[ "$(head -n 1 "$r/AGENTS.md")" = "Mi contenido" ] || fail "AGENTS.md lost its content"

# 4. real .claude/skills directory: untouched, warning, exit 0
r="$(new_repo)"
mkdir -p "$r/.claude/skills/x"
echo "skill" > "$r/.claude/skills/x/SKILL.md"
err="$(bash "$S" "$r" 2>&1 >/dev/null)" || fail "real skills dir should still exit 0"
[ -f "$r/.claude/skills/x/SKILL.md" ] || fail "real skills dir was touched"
[ ! -L "$r/.claude/skills" ] || fail "real dir replaced by symlink"
grep -q "\.claude/skills" <<<"$err" || fail "stderr should mention .claude/skills"

# 5. broken symlink is redone
r="$(new_repo)"
mkdir -p "$r/.claude"
ln -s ../nowhere "$r/.claude/skills"
bash "$S" "$r" >/dev/null 2>&1 || fail "broken symlink case should exit 0"
[ "$(readlink "$r/.claude/skills")" = "../.agents/skills" ] || fail "broken symlink not redone"

# 6. existing marker is not overwritten
r="$(new_repo)"
echo '{"maxReviewRounds":3}' > "$r/.agents-kit.json"
bash "$S" "$r" >/dev/null 2>&1
[ "$(jq .maxReviewRounds "$r/.agents-kit.json")" = "3" ] || fail "marker overwritten"

# 6b. CLAUDE.md symlink to another file: nothing written through it
r="$(new_repo)"
o="$(mktemp -d)"; dirs+=("$o")
echo "ajeno" > "$o/other.md"
ln -s "$o/other.md" "$r/CLAUDE.md"
err="$(bash "$S" "$r" 2>&1 >/dev/null)" || fail "CLAUDE.md foreign symlink should exit 0"
[ "$(cat "$o/other.md")" = "ajeno" ] || fail "wrote through CLAUDE.md symlink"
[ -L "$r/CLAUDE.md" ] || fail "CLAUDE.md symlink replaced"
grep -q "CLAUDE.md" <<<"$err" || fail "stderr should mention CLAUDE.md"

# 6c. .claude and .agents symlinked outside: outside dirs untouched
r="$(new_repo)"
o1="$(mktemp -d)"; o2="$(mktemp -d)"; dirs+=("$o1" "$o2")
ln -s "$o1" "$r/.claude"; ln -s "$o2" "$r/.agents"
err="$(bash "$S" "$r" 2>&1 >/dev/null)" || fail "symlinked dirs should exit 0"
[ -z "$(ls -A "$o1")" ] || fail "wrote into outside dir via .claude"
[ -z "$(ls -A "$o2")" ] || fail "wrote into outside dir via .agents"
grep -q "\.claude" <<<"$err" || fail "stderr should mention .claude"
grep -q "\.agents" <<<"$err" || fail "stderr should mention .agents"

# 6d. AGENTS.md with the section already: untouched; AGENTS.md symlink: never written through
r="$(new_repo)"
printf 'Hola\n\n## Reglas del proyecto\n\n- una\n' > "$r/AGENTS.md"
before="$(cat "$r/AGENTS.md")"
out="$(bash "$S" "$r" 2>/dev/null)" || fail "exit 0 expected"
[ "$(cat "$r/AGENTS.md")" = "$before" ] || fail "AGENTS.md con la sección no debe cambiar"
grep -q 'AGENTS.md' <<<"$out" && fail "no debe listar AGENTS.md: $out"
r="$(new_repo)"; o="$(mktemp -d)"; dirs+=("$o")
echo "fuera" > "$o/A.md"; ln -s "$o/A.md" "$r/AGENTS.md"
err="$(bash "$S" "$r" 2>&1 >/dev/null)" || fail "AGENTS.md symlink: exit 0 expected"
[ "$(cat "$o/A.md")" = "fuera" ] || fail "escribió a través del symlink AGENTS.md"
grep -q 'AGENTS.md' <<<"$err" || fail "AGENTS.md symlink: falta aviso"

# 8. changelog: written to the marker; false = no CHANGELOG.md
r="$(new_repo)"
out="$(bash "$S" "$r" --changelog false 2>/dev/null)" || fail "changelog false: exit $?"
[ "$(jq -c . "$r/.agents-kit.json")" = '{"changelog":false}' ] || fail "changelog false: marcador $(cat "$r/.agents-kit.json")"
[ ! -e "$r/CHANGELOG.md" ] || fail "changelog false: creó CHANGELOG.md"
[ "$(last_line "$out")" = "FIN: 6" ] || fail "changelog false: $(last_line "$out")"
out="$(bash "$S" "$r" --changelog false 2>/dev/null)"
[ "$(last_line "$out")" = "FIN: 0" ] || fail "changelog false rerun: $(last_line "$out")"
out="$(bash "$S" "$r" --changelog true 2>/dev/null)" || fail "changelog true: exit $?"
[ "$(jq -c . "$r/.agents-kit.json")" = '{"changelog":true}' ] || fail "changelog true: marcador"
grep -qx 'cambiado: .agents-kit.json' <<<"$out" || fail "changelog true: debe decir cambiado: .agents-kit.json"
[ -f "$r/CHANGELOG.md" ] || fail "changelog true: falta CHANGELOG.md"
r="$(new_repo)"
bash "$S" "$r" --changelog true >/dev/null 2>&1 || fail "changelog true nuevo"
[ "$(jq -c . "$r/.agents-kit.json")" = '{"changelog":true}' ] || fail "changelog true nuevo: marcador"
bash "$S" "$r" --changelog quizá >/dev/null 2>&1; [ $? -eq 1 ] || fail "changelog inválido debe salir 1"
echo '{' > "$r/.agents-kit.json"
bash "$S" "$r" --changelog false >/dev/null 2>&1; [ $? -eq 2 ] || fail "marcador roto debe salir 2"

# 9. global config: created once from the template
g="$(mktemp -d)"; dirs+=("$g")
r="$(new_repo)"
out="$(KIT_CONFIG="$g/sub/config.json" bash "$S" "$r" 2>/dev/null)" || fail "global: exit $?"
[ -f "$g/sub/config.json" ] || fail "global: no se creó"
jq -e '.proveedores' "$g/sub/config.json" >/dev/null || fail "global: no viene de la plantilla"
grep -q "creada la configuración global en $g/sub/config.json" <<<"$out" || fail "global: falta el aviso ($out)"
out="$(KIT_CONFIG="$g/sub/config.json" bash "$S" "$r" 2>/dev/null)"
grep -q 'configuración global' <<<"$out" && fail "global: avisa otra vez"

# 10. versioned git hooks without setup: warning; with setup: none
r="$(new_repo)"
git -C "$r" config core.hooksPath tools/hooks
err="$(bash "$S" "$r" 2>&1 >/dev/null)" || fail "hooksPath: exit $?"
grep -q 'core.hooksPath' <<<"$err" && grep -q 'setup' <<<"$err" || fail "hooksPath: falta aviso ($err)"
mkdir -p "$r/tools"; printf '#!/bin/sh\n' > "$r/tools/prep.sh"
bash "$S" "$r" --setup tools/prep.sh >/dev/null 2>&1 || fail "--setup: exit $?"
[ "$(jq -r .setup "$r/.agents-kit.json")" = tools/prep.sh ] || fail "--setup: no está en el marcador"
err="$(bash "$S" "$r" 2>&1 >/dev/null)"
grep -q 'core.hooksPath' <<<"$err" && fail "con setup no debe avisar ($err)"
bash "$S" "$r" --setup tools/nada.sh >/dev/null 2>&1; [ $? -eq 1 ] || fail "--setup inexistente debe salir 1"
bash "$S" "$r" --setup /etc/passwd >/dev/null 2>&1; [ $? -eq 1 ] || fail "--setup absoluto debe salir 1"
r="$(new_repo)"
mkdir -p "$r/.husky"; echo x > "$r/.husky/pre-commit"; git -C "$r" add .husky; git -C "$r" commit -q -m husky
err="$(bash "$S" "$r" 2>&1 >/dev/null)"
grep -q '.husky' <<<"$err" || fail "husky versionado: falta aviso ($err)"
r="$(new_repo)"
err="$(bash "$S" "$r" 2>&1 >/dev/null)"
grep -q 'hooks' <<<"$err" && fail "repo sin hooks: aviso de más ($err)"
bash "$S" "$r" --otro >/dev/null 2>&1; [ $? -eq 1 ] || fail "opción desconocida debe salir 1"

# 11. kit-agents-md.sh: the reorder is shown as a diff and only written by aplicar
A="$REPO_ROOT/scripts/kit-agents-md.sh"
r="$(new_repo)"
printf '# Viejo\n\nRegla: no tocar lib/.\n' > "$r/AGENTS.md"
p="$(mktemp)"; printf '# AGENTS.md\n\n## Qué es\n\nAlgo.\n\n## Reglas del proyecto\n\n- No tocar lib/.\n' > "$p"
before="$(cat "$r/AGENTS.md")"
out="$(bash "$A" diff "$r" "$p" 2>&1)" || fail "agents-md diff: exit $? ($out)"
[ "$(cat "$r/AGENTS.md")" = "$before" ] || fail "agents-md diff escribió AGENTS.md"
grep -q '^-Regla: no tocar lib/.' <<<"$out" && grep -q '^+## Reglas del proyecto' <<<"$out" || fail "agents-md diff: salida '$out'"
[ "$(last_line "$out")" = "FIN: con cambios" ] || fail "agents-md diff FIN: $(last_line "$out")"
out="$(bash "$A" aplicar "$r" "$p" 2>&1)" || fail "agents-md aplicar: exit $? ($out)"
cmp -s "$p" "$r/AGENTS.md" || fail "agents-md aplicar no escribió la propuesta"
[ "$(last_line "$out")" = "FIN: ok" ] || fail "agents-md aplicar FIN"
out="$(bash "$A" diff "$r" "$p" 2>&1)"
[ "$(last_line "$out")" = "FIN: sin cambios" ] || fail "agents-md diff igual: '$out'"
q="$(mktemp)"; printf '# Sin reglas\n' > "$q"
bash "$A" diff "$r" "$q" >/dev/null 2>&1; [ $? -eq 1 ] || fail "propuesta sin Reglas del proyecto debe salir 1"
bash "$A" aplicar "$r" "$q" >/dev/null 2>&1; [ $? -eq 1 ] || fail "aplicar sin Reglas del proyecto debe salir 1"
cmp -s "$p" "$r/AGENTS.md" || fail "aplicar rechazado escribió"
bash "$A" diff "$r" /nonexistent >/dev/null 2>&1; [ $? -eq 1 ] || fail "propuesta inexistente debe salir 1"
bash "$A" otra "$r" "$p" >/dev/null 2>&1; [ $? -eq 1 ] || fail "subcomando desconocido debe salir 1"
r="$(new_repo)"; o="$(mktemp -d)"; dirs+=("$o"); echo x > "$o/A.md"; ln -s "$o/A.md" "$r/AGENTS.md"
bash "$A" aplicar "$r" "$p" >/dev/null 2>&1; [ $? -eq 1 ] || fail "AGENTS.md symlink debe salir 1"
[ "$(cat "$o/A.md")" = x ] || fail "aplicar escribió a través del symlink"

# 12. v2 marker (kit-on in actualizar mode): v2 keys dropped, each with a note of where it goes; repo keys stay
r="$(new_repo)"
echo '{"reviewers": ["claude/opus"], "implementer": "claude", "notify": "none", "changelog": true, "protegido": ["lib/"]}' > "$r/.agents-kit.json"
out="$(bash "$S" "$r" 2>/dev/null)" || fail "v2: exit $?"
[ "$(jq -c . "$r/.agents-kit.json")" = '{"changelog":true,"protegido":["lib/"]}' ] || fail "v2: marcador $(cat "$r/.agents-kit.json")"
grep -qx "cambiado: .agents-kit.json" <<<"$out" || fail "v2: sin cambiado: $out"
for x in "nota: 'reviewers' (v2) quitada del marcador: los revisores van en 'revision.puestos'" \
         "nota: 'implementer' (v2) quitada del marcador: el implementador va en 'implementador'" \
         "nota: 'notify' (v2) quitada del marcador: el canal de avisos va en 'notify'"; do
  grep -qF "$x" <<<"$out" || fail "v2: falta '$x': $out"
done
grep -q "valor anterior: \"none\"" <<<"$out" || fail "v2: sin valor anterior: $out"
out="$(bash "$S" "$r" 2>/dev/null)"
[ "$(last_line "$out")" = "FIN: 0" ] && ! grep -q '^nota:' <<<"$out" || fail "v2: no idempotente: $out"

# 7. environment errors exit 2
# 11. contenido and protegido: flags replace the lists; suggestions from direct commits while contenido is missing
r="$(new_repo)"
c() { # <subject> <file>...: commit those files
  local m="$1"; shift
  for f in "$@"; do mkdir -p "$r/$(dirname "$f")"; echo "$m" >> "$r/$f"; done
  git -C "$r" add -A && git -C "$r" commit -q -m "$m"
}
for i in 1 2 3 4 5; do c "vídeo $i" "studio/content/v$i.md"; done
c "arreglo (#7)" studio/content/v1.md lib/a.py
for i in 1 2 3 4 5; do c "código $i (#$((10 + i)))" "lib/b$i.py"; done
for i in 1 2 3 4 5; do c "skill $i" ".agents/skills/x/SKILL.md"; done
for i in 1 2 3 4; do c "pocos $i" "docs/d$i.md"; done
out="$(bash "$S" "$r" 2>/dev/null)" || fail "sugerencias: exit $?"
[ "$(grep '^sugerencia' <<<"$out")" = "sugerencia contenido: studio/content/ (5 commits directos, 1 por PR)" ] \
  || fail "sugerencias: '$out'"
bash "$S" "$r" --contenido studio/content/ --protegido lib/ --protegido cli/ >/dev/null 2>&1 || fail "--contenido: exit $?"
[ "$(jq -c '[.contenido, .protegido]' "$r/.agents-kit.json")" = '[["studio/content/"],["lib/","cli/"]]' ] \
  || fail "--contenido/--protegido: $(cat "$r/.agents-kit.json")"
out="$(bash "$S" "$r" 2>/dev/null)"
grep -q '^sugerencia' <<<"$out" && fail "con contenido declarado no debe sugerir ('$out')"
# a repo that merges PRs with merge commits: the branch commits do not count as direct
m="$(new_repo)"
git -C "$m" checkout -q -b rama
for i in 1 2 3 4 5 6; do mkdir -p "$m/src"; echo "$i" > "$m/src/f$i.py"; git -C "$m" add src; git -C "$m" commit -q -m "paso $i"; done
git -C "$m" checkout -q -
git -C "$m" merge -q --no-ff rama -m "Merge pull request #3 from x/rama"
out="$(bash "$S" "$m" 2>/dev/null)"
grep -q '^sugerencia' <<<"$out" && fail "merge commits: sugiere código como contenido ('$out')"
for bad in "--contenido" "--contenido /etc" "--protegido ../x" "--protegido"; do
  bash "$S" "$r" $bad >/dev/null 2>&1; [ $? -eq 1 ] || fail "'$bad' debe salir 1"
done

# --reglas/--flujo: written as booleans, idempotent, a bad value is a usage error
fl="$(mk_repo)"; dirs+=("$fl")
out="$(bash "$S" "$fl" --changelog false --reglas true --flujo false 2>/dev/null)" || fail "flujo false: exit $?"
[ "$(jq -c '{reglas, flujo}' "$fl/.agents-kit.json")" = '{"reglas":true,"flujo":false}' ] || fail "flujo false: $(cat "$fl/.agents-kit.json")"
out="$(bash "$S" "$fl" --flujo false 2>/dev/null)"
[ "$(last_line "$out")" = "FIN: 0" ] || fail "flujo false rerun: $(last_line "$out")"
out="$(bash "$S" "$fl" --flujo true 2>/dev/null)" && [ "$(jq .flujo "$fl/.agents-kit.json")" = true ] || fail "flujo true"
bash "$S" "$fl" --reglas si >/dev/null 2>&1; [ $? -eq 1 ] || fail "--reglas si should exit 1"

bash "$S" "/nonexistent-dir-xyz" >/dev/null 2>&1; [ $? -eq 2 ] || fail "missing dir should exit 2"
nd="$(mktemp -d)"; dirs+=("$nd")
bash "$S" "$nd" >/dev/null 2>&1; [ $? -eq 2 ] || fail "non-git dir should exit 2"
bash "$S" >/dev/null 2>&1; [ $? -eq 1 ] || fail "no args should exit 1"
echo "ok"
