#!/usr/bin/env bash
# Tests for scripts/lib/config.sh: plugin (templates/config.json) < global (KIT_CONFIG) < repo (lista blanca).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
source "$REPO_ROOT/scripts/lib/config.sh"

export HOME="$(mktemp -d)"
g="$(mktemp -d)/sub/config.json"
export KIT_CONFIG="$g"
d="$(mktemp -d)"

# no marker
err="$(kit_require_marker "$d" 2>&1)"; rc=$?
[ $rc -eq 1 ] || fail "sin marcador: exit $rc, esperado 1"
[ "$err" = "kit no activado: ejecuta kit-on" ] || fail "sin marcador: stderr '$err'"

# global ausente: valores de la plantilla
echo '{}' > "$d/.agents-kit.json"
kit_require_marker "$d" || fail "con marcador: require falló"
[ "$(kit_config "$d" .maxReviewRounds)" = "10" ] || fail "maxReviewRounds"
[ "$(kit_config "$d" .notify)" = "ntfy" ] || fail "notify"
[ "$(kit_config "$d" .autoMerge)" = "true" ] || fail "autoMerge"
[ "$(kit_config "$d" '.implementador | tojson')" = '{"familia":"claude","nivel":"profundo"}' ] || fail "implementador"
[ "$(kit_config "$d" '.proveedores | keys_unsorted | join(",")')" = "claude,gpt" ] || fail "proveedores"
[ "$(kit_config "$d" '.proveedores.gpt.cli')" = "opencode" ] || fail "gpt cli"
[ "$(kit_config "$d" '.revision.puestos | length')" = "3" ] || fail "puestos"
[ "$(kit_config "$d" '[.revision.puestos[].familia] | join(",")')" = "otra,otra,misma" ] || fail "familias"
err="$(kit_config "$d" .notify 2>&1 >/dev/null)"; [ -z "$err" ] || fail "marcador vacío avisa: '$err'"
[ ! -e "$g" ] || fail "kit_config no debe crear el global"

# precedencia: plugin < global < repo
mkdir -p "$(dirname "$g")"
echo '{"maxReviewRounds": 4, "autoMerge": false, "notify": "none"}' > "$g"
[ "$(kit_config "$d" .maxReviewRounds)" = "4" ] || fail "global maxReviewRounds"
[ "$(kit_config "$d" .notify)" = "none" ] || fail "global notify"
[ "$(kit_config "$d" '.proveedores.claude.modelos.profundo')" = "opus" ] || fail "global sin proveedores usa la plantilla"
echo '{"maxReviewRounds": 2}' > "$d/.agents-kit.json"
[ "$(kit_config "$d" .maxReviewRounds)" = "2" ] || fail "repo maxReviewRounds"
[ "$(kit_config "$d" .autoMerge)" = "false" ] || fail "repo sin autoMerge usa el global"

# proveedores del global sustituyen a los de la plantilla
echo '{"proveedores": {"gpt": {"cli": "codex", "modelos": {"profundo": "gpt-x", "rapido": "gpt-y"}}}}' > "$g"
[ "$(kit_config "$d" '.proveedores | keys_unsorted | join(",")')" = "gpt" ] || fail "proveedores global sustituye"

# lista blanca: claves admitidas en el repo
rm "$g"
cat > "$d/.agents-kit.json" <<'J'
{"autoMerge": false, "contenido": ["docs/"], "protegido": ["lib/"], "setup": "s.sh",
 "checks": {"pre-merge": "c.sh"}, "changelog": false,
 "revision": {"puestos": [{"foco": "f", "nivel": "rapido", "familia": "misma"}]}}
J
err="$(kit_config "$d" .autoMerge 2>&1 >/dev/null)"; [ -z "$err" ] || fail "claves admitidas avisan: '$err'"
[ "$(kit_config "$d" .autoMerge)" = "false" ] || fail "repo autoMerge"
[ "$(kit_config "$d" '.contenido[0]')" = "docs/" ] || fail "contenido"
[ "$(kit_config "$d" '.protegido[0]')" = "lib/" ] || fail "protegido"
[ "$(kit_config "$d" .setup)" = "s.sh" ] || fail "setup"
[ "$(kit_config "$d" '.checks["pre-merge"]')" = "c.sh" ] || fail "checks"
[ "$(kit_config "$d" .changelog)" = "false" ] || fail "changelog"
# revision.puestos del repo sustituye la lista entera
[ "$(kit_config "$d" '.revision.puestos | length')" = "1" ] || fail "puestos repo sustituye"
[ "$(kit_config "$d" '.revision.puestos[0].foco')" = "f" ] || fail "puestos repo foco"

# claves prohibidas o desconocidas: se ignoran con un aviso por clave
cat > "$d/.agents-kit.json" <<'J'
{"proveedores": {"evil": {"cli": "sh", "modelos": {"profundo": "x"}}}, "implementador": {"familia": "evil"},
 "notify": "claude-push", "otra": 1, "revision": {"puestos": [], "extra": 2}}
J
out="$(kit_config "$d" '.notify' 2>/dev/null)"
[ "$out" = "ntfy" ] || fail "notify del repo no se ignora: '$out'"
[ "$(kit_config "$d" '.proveedores | has("evil")' 2>/dev/null)" = "false" ] || fail "proveedores del repo no se ignoran"
[ "$(kit_config "$d" '.implementador.familia' 2>/dev/null)" = "claude" ] || fail "implementador del repo no se ignora"
[ "$(kit_config "$d" 'has("otra")' 2>/dev/null)" = "false" ] || fail "clave desconocida no se ignora"
[ "$(kit_config "$d" '.revision | has("extra")' 2>/dev/null)" = "false" ] || fail "revision.extra no se ignora"
[ "$(kit_config "$d" '.revision.puestos | length' 2>/dev/null)" = "0" ] || fail "puestos vacío del repo"
err="$(kit_config "$d" .notify 2>&1 >/dev/null)"
for k in proveedores implementador notify otra revision.extra; do
  [ "$(grep -c "'$k'" <<<"$err")" = 1 ] || fail "aviso de '$k' (uno): '$err'"
done
grep -q "proveedores' solo se lee de la configuración global" <<<"$err" || fail "texto aviso global: '$err'"
grep -q "clave 'otra' no admitida en el repo" <<<"$err" || fail "texto aviso desconocida: '$err'"

# claves v2: aviso con la clave nueva
echo '{"reviewers": {"claude": []}, "implementer": {"claude": "opus"}, "notify": "none", "maxReviewRounds": 3}' > "$d/.agents-kit.json"
err="$(kit_config "$d" .maxReviewRounds 2>&1 >/dev/null)"
grep -q "'reviewers' es de la v2.*'revision.puestos'" <<<"$err" || fail "aviso reviewers: '$err'"
grep -q "'implementer' es de la v2.*'implementador'" <<<"$err" || fail "aviso implementer: '$err'"
grep -q "'notify'.*configuración global" <<<"$err" || fail "aviso notify: '$err'"
[ "$(kit_config "$d" .maxReviewRounds 2>/dev/null)" = "3" ] || fail "v2: sigue leyendo lo admitido"
[ "$(kit_config "$d" '.revision.puestos | length' 2>/dev/null)" = "3" ] || fail "v2: reviewers no sustituye puestos"

# KIT_CONFIG ausente: HOME/.agents-kit/config.json
echo '{}' > "$d/.agents-kit.json"
mkdir -p "$HOME/.agents-kit"; echo '{"maxReviewRounds": 7}' > "$HOME/.agents-kit/config.json"
[ "$(KIT_CONFIG= kit_config "$d" .maxReviewRounds)" = "7" ] || fail "global en HOME"
[ "$(kit_config "$d" .maxReviewRounds)" = "10" ] || fail "KIT_CONFIG manda sobre HOME"

# global roto: exit 2
mkdir -p "$(dirname "$g")"
for bad in '{nope' '[]' '5'; do
  printf '%s' "$bad" > "$g"
  err="$(kit_config "$d" .maxReviewRounds 2>&1)"; rc=$?
  [ $rc -eq 2 ] || fail "global '$bad': exit $rc"
  [ "$err" = "error: $g no es JSON válido" ] || fail "global '$bad': stderr '$err'"
done
rm "$g"

# marcador inválido -> 2
echo '{nope' > "$d/.agents-kit.json"
err="$(kit_config "$d" .maxReviewRounds 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "JSON inválido: exit $rc"
[ "$err" = "error: .agents-kit.json no es JSON válido" ] || fail "JSON inválido: stderr '$err'"
for bad in '' '[]' 'null' '5'; do
  printf '%s' "$bad" > "$d/.agents-kit.json"
  err="$(kit_config "$d" .maxReviewRounds 2>&1)"; rc=$?
  [ $rc -eq 2 ] || fail "marcador '$bad': exit $rc, esperado 2"
  [ "$err" = "error: .agents-kit.json no es JSON válido" ] || fail "marcador '$bad': stderr '$err'"
done

# kit_global_init: crea desde la plantilla (600 en dir 700) y lo dice; si existe, no toca nada
echo '{}' > "$d/.agents-kit.json"
g2="$(mktemp -d)/nuevo/config.json"
out="$(KIT_CONFIG="$g2" kit_global_init)"; rc=$?
[ $rc -eq 0 ] || fail "init rc=$rc"
[ "$out" = "creada la configuración global en $g2" ] || fail "init msg: '$out'"
cmp -s "$g2" "$REPO_ROOT/templates/config.json" || fail "init contenido"
perm() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
[ "$(perm "$g2")" = 600 ] || fail "init modo fichero $(perm "$g2")"
[ "$(perm "$(dirname "$g2")")" = 700 ] || fail "init modo dir"
echo '{"notify":"none"}' > "$g2"
out="$(KIT_CONFIG="$g2" kit_global_init)"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] || fail "init existente: rc=$rc '$out'"
[ "$(jq -r .notify "$g2")" = none ] || fail "init sobrescribió"
out="$(HOME="$(mktemp -d)" KIT_CONFIG= kit_global_init)" || fail "init en HOME"
grep -q '/.agents-kit/config.json$' <<<"$out" || fail "init en HOME msg: '$out'"
KIT_CONFIG=/dev/null/x/config.json kit_global_init >/dev/null 2>&1; [ $? -eq 2 ] || fail "init no escribible"

# kit_seats: puestos resueltos (i, familia, cli, modelo, foco, nota)
got="$(kit_seats "$d" claude)" || fail "seats claude rc"
want="$(printf '1\tgpt\topencode\topenai/gpt-6.1-sol\tcorrección, casos límite y tests\t\n2\tgpt\topencode\topenai/gpt-6.1-sol\tfallos de uso real, seguridad y lo que otros darían por bueno\t\n3\tclaude\tclaude\tsonnet\tsimplicidad, reutilización y scope\t')"
[ "$got" = "$want" ] || fail "seats claude: '$got'"
got="$(kit_seats "$d" gpt | cut -f2-4 | tr "\n\t" "  ")"
[ "$got" = "claude claude opus claude claude opus gpt opencode openai/gpt-6.1-sol " ] || fail "seats gpt: '$got'"
# sin otra familia: la cubre la del implementador y se anota
mkdir -p "$(dirname "$g")"
echo '{"proveedores": {"claude": {"cli": "claude", "modelos": {"profundo": "opus", "rapido": "sonnet"}}}}' > "$g"
got="$(kit_seats "$d" claude | sed -n 1p)"
[ "$got" = "$(printf '1\tclaude\tclaude\topus\tcorrección, casos límite y tests\tmisma-familia')" ] || fail "seats sin otra: '$got'"
rm "$g"
# familia por nombre
echo '{"revision": {"puestos": [{"foco": "x", "nivel": "rapido", "familia": "claude"}]}}' > "$d/.agents-kit.json"
[ "$(kit_seats "$d" claude)" = "$(printf '1\tclaude\tclaude\tsonnet\tx\t')" ] || fail "seats por nombre"
# errores de uso
kit_seats "$d" marciano >/dev/null 2>&1; [ $? -eq 1 ] || fail "seats familia desconocida"
echo '{"revision": {"puestos": [{"foco": "x", "nivel": "rapido", "familia": "marciano"}]}}' > "$d/.agents-kit.json"
kit_seats "$d" claude >/dev/null 2>&1; [ $? -eq 1 ] || fail "seats puesto familia desconocida"
echo '{"revision": {"puestos": [{"foco": "x", "nivel": "lento", "familia": "misma"}]}}' > "$d/.agents-kit.json"
kit_seats "$d" claude >/dev/null 2>&1; [ $? -eq 1 ] || fail "seats nivel desconocido"

# kit_reviewers (compatibilidad hasta Task 3): puestos sin repetir cli/modelo, focos unidos
echo '{}' > "$d/.agents-kit.json"
got="$(env -u CODEX_THREAD_ID bash -c 'source "$1"; kit_reviewers "$2"' _ "$REPO_ROOT/scripts/lib/config.sh" "$d")"
want="$(printf 'opencode\topenai/gpt-6.1-sol\tcorrección, casos límite y tests; fallos de uso real, seguridad y lo que otros darían por bueno\nclaude\tsonnet\tsimplicidad, reutilización y scope')"
[ "$got" = "$want" ] || fail "reviewers: '$got'"
got="$(CODEX_THREAD_ID=x bash -c 'source "$1"; kit_reviewers "$2"' _ "$REPO_ROOT/scripts/lib/config.sh" "$d" | cut -f1,2 | tr '\n\t' ' /')"
[ "$got" = "claude/opus opencode/openai/gpt-6.1-sol " ] || fail "reviewers en codex: '$got'"

echo "ok"
