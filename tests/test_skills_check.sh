#!/usr/bin/env bash
# Tests for scripts/kit-skills-check.sh: broken file citations in skills fail; placeholders and fences do not.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
C="$REPO_ROOT/scripts/kit-skills-check.sh"

r="$(mk_repo)"
mkdir -p "$r/lib" "$r/projects" "$r/.agents/skills/demo/references" "$r/.agents/skills/otra"
: > "$r/lib/ok.py"
cat > "$r/.agents/skills/demo/SKILL.md" <<'MD'
---
name: demo
---
Usa `lib/ok.py` y la guía `references/guia.md`; el script `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-issue.sh" leer <raíz> <N>`.
También `scripts/kit-pr.sh`, `$PLUGIN/scripts/lib/config.sh`, `owner/repo`, `<wt>/lib/x.py`, `~/.agents-kit/config.json`.
Rotos: `lib/missing.py` y `references/nope.md`.
Kit roto: `"${CLAUDE_PLUGIN_ROOT}/scripts/kit-nope.sh" x` y `scripts/kit-tampoco.sh`.
```
lib/fenced-missing.py
```
Excluido: `projects/salida.mp4`, pero el texto que nombra projects no salva `lib/projects.py`.
Sin barra ni raíz conocida: `AGENTS.md`, `tools/agente/x.sh`, `https://x.y/z`, `HEAD:lib/a.py`.
MD
printf 'Detalle en `lib/gone.py`.\n' > "$r/.agents/skills/demo/references/guia.md"
printf -- '---\nname: otra\n---\nNada roto: `lib/ok.py/`.\n' > "$r/.agents/skills/otra/SKILL.md"

err="$(bash "$C" "$r" --excluir projects/ 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "citas rotas: exit $rc ($err)"
exp="$(printf '%s\n' \
  '.agents/skills/demo/SKILL.md:6: lib/missing.py no existe' \
  '.agents/skills/demo/SKILL.md:6: references/nope.md no existe' \
  '.agents/skills/demo/SKILL.md:7: scripts/kit-nope.sh no existe' \
  '.agents/skills/demo/SKILL.md:7: scripts/kit-tampoco.sh no existe' \
  '.agents/skills/demo/SKILL.md:11: lib/projects.py no existe' \
  '.agents/skills/demo/references/guia.md:1: lib/gone.py no existe')"
[ "$err" = "$exp" ] || fail "citas rotas: salida
$err"
# without the exclusion the runtime path is reported too
err="$(bash "$C" "$r" 2>&1 >/dev/null)"
grep -qx '.agents/skills/demo/SKILL.md:11: projects/salida.mp4 no existe' <<<"$err" || fail "sin --excluir: '$err'"

# all fine: FIN with the number of checked citations
rm "$r/.agents/skills/demo/SKILL.md" "$r/.agents/skills/demo/references/guia.md"
out="$(bash "$C" "$r" 2>&1)" || fail "sin roturas: exit $? ($out)"
[ "$out" = "FIN: 1 citas comprobadas" ] || fail "sin roturas: '$out'"

# a repo without project skills
e="$(mk_repo)"
out="$(bash "$C" "$e" 2>&1)" || fail "sin skills: exit $?"
[ "$out" = "FIN: 0 citas comprobadas" ] || fail "sin skills: '$out'"

# usage and environment
bash "$C" >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin argumentos debe salir 1"
bash "$C" "$r" --excluir >/dev/null 2>&1; [ $? -eq 1 ] || fail "--excluir sin valor debe salir 1"
bash "$C" "$r" --otra >/dev/null 2>&1; [ $? -eq 1 ] || fail "opción desconocida debe salir 1"
bash "$C" /nonexistent-dir-xyz >/dev/null 2>&1; [ $? -eq 2 ] || fail "directorio inexistente debe salir 2"

# the kit checks its own skills (skills/ and their references); runtime paths of the target repo are excluded by path
out="$(bash "$C" "$REPO_ROOT" --excluir .agents/skills 2>&1)" || fail "skills del kit: $out"
case "$out" in "FIN: "*" citas comprobadas") ;; *) fail "skills del kit: '$out'";; esac
[ "${out#FIN: }" != "0 citas comprobadas" ] || fail "skills del kit: no comprobó nada"
echo "ok"
