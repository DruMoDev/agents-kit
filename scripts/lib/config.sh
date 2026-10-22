#!/usr/bin/env bash
# Sourced helper: kit configuration in three layers, no side effects on source.
#   plugin (templates/config.json) < global (${KIT_CONFIG:-$HOME/.agents-kit/config.json}) < repo (.agents-kit.json,
#   filtered by a whitelist: a repo can never set proveedores, implementador or notify).

_KIT_TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/templates/config.json"

# Keys a repo marker may set (plus revision.puestos, which replaces the whole list).
_KIT_REPO_KEYS='["autoMerge","maxReviewRounds","contenido","protegido","setup","checks","changelog"]'

# kit_global_path: print the global config path.
kit_global_path() {
  printf '%s\n' "${KIT_CONFIG:-$HOME/.agents-kit/config.json}"
}

# kit_require_marker <root>: return 1 unless <root>/.agents-kit.json exists.
kit_require_marker() {
  if [ ! -f "$1/.agents-kit.json" ]; then
    echo "kit no activado: ejecuta kit-on" >&2
    return 1
  fi
}

# kit_global_init: create the global config from the template if missing (file 600, new dirs 700).
# Prints "creada la configuración global en <ruta>" when it creates it; nothing if it already exists.
# Return: 0 ok, 2 could not create it.
kit_global_init() {
  local g; g="$(kit_global_path)"
  [ -e "$g" ] && return 0
  if ! (umask 077; mkdir -p "$(dirname "$g")" && cp "$_KIT_TEMPLATE" "$g" && chmod 600 "$g") 2>/dev/null; then
    echo "error: no se pudo crear $g" >&2
    return 2
  fi
  echo "creada la configuración global en $g"
}

# _kit_warn_once <scope> <text>: print the warnings on stderr unless the same text for the same scope was printed in
# the last hour (kit-run reads the config from many processes; Dru only needs to see it once per run). A stamp per
# scope and text lives in ${KIT_AVISOS_DIR:-$TMPDIR/agents-kit-avisos-<uid>}; if it cannot be written, always warn.
_kit_warn_once() {
  local dir="${KIT_AVISOS_DIR:-${TMPDIR:-/tmp}/agents-kit-avisos-$(id -u)}" key
  key="$(printf '%s\n%s' "$1" "$2" | cksum | tr ' ' '-')"
  [ -n "$(find "$dir/$key" -mmin -60 2>/dev/null)" ] && return 0
  printf '%s\n' "$2" >&2
  (umask 077; mkdir -p "$dir" && touch "$dir/$key") 2>/dev/null || true
}

# kit_config <root> <jq-filter>: run the filter (jq -r) over plugin < global < repo.
# Repo keys outside the whitelist are ignored with one warning per key on stderr (v2 keys name their new key),
# printed once per hour for the same repo and warnings (_kit_warn_once).
# Return: 0 ok, 2 marker or global config is not a JSON object.
_kit_config_file() {
  local mk="$1" filter="$2" scope="$3" g global merged warnings
  if ! jq -e 'type == "object"' "$mk" >/dev/null 2>&1; then
    echo "error: .agents-kit.json no es JSON válido" >&2
    return 2
  fi
  g="$(kit_global_path)"
  if [ -e "$g" ]; then
    if ! jq -e 'type == "object"' "$g" >/dev/null 2>&1; then
      echo "error: $g no es JSON válido" >&2
      return 2
    fi
    global="$g"
  else
    global=/dev/null # slurps to []: treated as {}
  fi
  # \(q) is a single quote (the program itself is single-quoted for the shell).
  warnings="$(jq -r --argjson ok "$_KIT_REPO_KEYS" --arg g "$g" --arg q "'" '
    def warn($m): "aviso: .agents-kit.json: \($m)";
    to_entries[] | .key as $k | .value as $v |
    if ($ok | index([$k])) then empty
    elif $k == "revision" then
      if ($v | type) != "object" then warn("\($q)revision\($q) debe ser un objeto con \($q)puestos\($q); se ignora")
      else ($v | to_entries[] | select(.key != "puestos" or (.value | type) != "array") |
        warn("\($q)revision.\(.key)\($q) no admitida en el repo (solo \($q)revision.puestos\($q), una lista); se ignora"))
      end
    elif $k == "reviewers" then warn("\($q)reviewers\($q) es de la v2 y se ignora; define los revisores en \($q)revision.puestos\($q) (en \($g) o en el marcador)")
    elif $k == "implementer" then warn("\($q)implementer\($q) es de la v2 y se ignora; el implementador va en \($q)implementador\($q) de la configuración global (\($g))")
    elif $k == "notify" then warn("\($q)notify\($q) se ignora; el canal de avisos va en \($q)notify\($q) de la configuración global (\($g))")
    elif $k == "proveedores" or $k == "implementador" then warn("\($q)\($k)\($q) solo se lee de la configuración global (\($g)); se ignora")
    else warn("clave \($q)\($k)\($q) no admitida en el repo; se ignora")
    end' "$mk")"
  [ -z "$warnings" ] || _kit_warn_once "$scope" "$warnings"
  if ! merged="$(jq -c -n --argjson ok "$_KIT_REPO_KEYS" \
      --slurpfile t "$_KIT_TEMPLATE" --slurpfile g "$global" --slurpfile r "$mk" '
      $t[0] as $t | ($g[0] // {}) as $g | $r[0] as $r |
      (($r | with_entries(select(.key as $k | $ok | index([$k]))))
        + (if ($r.revision | type) == "object" and ($r.revision.puestos | type) == "array"
           then {revision: {puestos: $r.revision.puestos}} else {} end)) as $repo |
      ($t * $g) | .proveedores = ($g.proveedores // $t.proveedores) | . * $repo')"; then
    echo "error: no se pudo leer la configuración del kit" >&2
    return 2
  fi
  printf '%s' "$merged" | jq -r "$filter"
}

kit_config() {
  _kit_config_file "$1/.agents-kit.json" "$2" "$1"
}

# kit_config_base <wt> <jq-filter> <ref>: like kit_config, but the repo layer is the marker at <ref> (the default
# branch, e.g. origin/main), so a PR cannot weaken the merge gates by editing its own marker. No marker there = {}.
kit_config_base() {
  local wt="$1" filter="$2" ref="$3" tmp rc
  tmp="$(mktemp)" || return 2
  if git -C "$wt" cat-file -e "$ref:.agents-kit.json" 2>/dev/null; then
    git -C "$wt" show "$ref:.agents-kit.json" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 2; }
  else
    echo '{}' > "$tmp"
  fi
  _kit_config_file "$tmp" "$filter" "$wt@$ref"; rc=$?
  rm -f "$tmp"
  return $rc
}

# kit_seats <root> <familia-implementador>: one line per review seat, in revision.puestos order:
#   <i>TAB<familia>TAB<cli>TAB<modelo>TAB<foco>TAB<nota>
# familia "otra" = first family of proveedores (in order) other than the implementer's; "misma" = the
# implementer's; any other value = that family. <nota> is "misma-familia" when an "otra" seat falls back to the
# implementer's family (no other family configured), empty otherwise. No availability check (CLI, login) here.
# Return: 0 ok, 1 unknown family or level, 2 broken config.
kit_seats() {
  local merged out err rc
  merged="$(kit_config "$1" '{proveedores, puestos: .revision.puestos} | tojson')" || return $?
  err="$(mktemp)" || return 2
  out="$(printf '%s' "$merged" | jq -r --arg impl "$2" '
    .proveedores as $p | ([$p | keys_unsorted[] | select(. != $impl)][0]) as $otra |
    if ($p[$impl] | type) != "object" then error("familia del implementador desconocida: \($impl)") else . end |
    (.puestos // []) | to_entries[] | (.key + 1) as $i | .value as $s |
    (if $s.familia == "otra" then ($otra // $impl) elif $s.familia == "misma" then $impl else $s.familia end) as $f |
    if ($p[$f] | type) != "object" then error("puesto \($i): familia desconocida: \($s.familia)")
    elif ($p[$f].modelos[$s.nivel] | type) != "string" then error("puesto \($i): la familia \($f) no tiene modelo de nivel \($s.nivel)")
    else [($i | tostring), $f, $p[$f].cli, $p[$f].modelos[$s.nivel], $s.foco,
          (if $s.familia == "otra" and $otra == null then "misma-familia" else "" end)] | @tsv end' 2>"$err")"
  rc=$?
  if [ $rc -ne 0 ]; then
    sed 's/^jq: error ([^)]*): /error: /' "$err" >&2
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  [ -z "$out" ] || printf '%s\n' "$out"
}
