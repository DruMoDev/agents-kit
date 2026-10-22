#!/usr/bin/env bash
# Sourced helper: review seats by provider family. Needs lib/config.sh (kit_config). No side effects on source.

# Reviewer adapters kit-review.sh knows: the "cli" of a provider must be one of these.
KIT_REVIEW_ADAPTERS="claude opencode codex"

# kit_implementer_family [familia]: print the family of the model that implemented. An explicit value wins; else the
# environment of the calling harness (innermost first: CODEX_THREAD_ID -> gpt; inside OpenCode it is unknown, since
# OpenCode runs any model; CLAUDECODE -> claude). Return 2 (asking for --implementador) when unknown.
kit_implementer_family() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
  elif [ -n "${CODEX_THREAD_ID:-}" ]; then
    echo gpt
  elif [ -z "${OPENCODE:-}" ] && [ -n "${CLAUDECODE:-}" ]; then
    echo claude
  else
    echo "error: no sé de qué familia es el modelo que implementó (en OpenCode, o fuera de Claude Code y Codex): pasa --implementador <familia>" >&2
    return 2
  fi
}

# kit_review_available: print, one per line, the adapters whose CLI is in the PATH (the cheap availability check).
kit_review_available() {
  local c
  for c in $KIT_REVIEW_ADAPTERS; do
    command -v "$c" >/dev/null 2>&1 && printf '%s\n' "$c"
  done
  return 0
}

# kit_seat_candidates <root> <familia-implementador>: the candidates of every seat of revision.puestos, in the order
# they are tried, one line each:
#   <i>TAB<j>TAB<familia>TAB<cli>TAB<modelo>TAB<foco>TAB<nota>
# Only providers whose CLI is a known adapter in the PATH and that have a model for the seat's level count.
#   familia "otra":  every other family in proveedores order, then the implementer's (nota misma-familia).
#   familia "misma": the implementer's.
#   a family name:   that family, then the implementer's (nota misma-familia).
# A seat without any candidate gets one line with j = 0, cli and modelo "-" and nota sin-candidatos.
# Return: 0 ok, 1 unknown family (implementer or seat) or a misma/named seat whose family lacks the level, 2 broken config.
kit_seat_candidates() {
  local merged avail out err rc
  merged="$(kit_config "$1" '{proveedores, puestos: .revision.puestos} | tojson')" || return $?
  avail="$(kit_review_available | jq -R -s -c 'split("\n") | map(select(. != ""))')" || return 2
  err="$(mktemp)" || return 2
  out="$(printf '%s' "$merged" | jq -r --arg impl "$2" --argjson av "$avail" '
    def uniq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
    (.proveedores // {}) as $p |
    if ($p[$impl] | type) != "object" then error("familia del implementador desconocida: \($impl)") else . end |
    def model($f; $n): $p[$f].modelos[$n] // null;
    def usable($f; $n): (model($f; $n) | type) == "string" and ($av | index([$p[$f].cli])) != null;
    (.puestos // []) | to_entries[] | (.key + 1) as $i | .value as $s |
    ($s.foco // "" | tostring | if . == "" then "revisión general del cambio" else . end) as $foco |
    (if $s.familia == "otra" then [$p | keys_unsorted[] | select(. != $impl)] + [$impl]
     elif $s.familia == "misma" then [$impl]
     elif ($p[$s.familia] | type) != "object" then error("puesto \($i): familia desconocida: \($s.familia)")
     else [$s.familia, $impl] | uniq end) as $fams |
    if $s.familia != "otra" and (model($fams[0]; $s.nivel) | type) != "string"
    then error("puesto \($i): la familia \($fams[0]) no tiene modelo de nivel \($s.nivel)") else . end |
    [$fams[] | select(usable(.; $s.nivel))] as $ok |
    if ($ok | length) == 0 then [($i | tostring), "0", ($s.familia // "?" | tostring), "-", "-", $foco, "sin-candidatos"] | @tsv
    else $ok | to_entries[] | .value as $f
      | [($i | tostring), (.key + 1 | tostring), $f, $p[$f].cli, model($f; $s.nivel), $foco,
         (if $f == $impl and $s.familia != "misma" and $s.familia != $impl then "misma-familia" else "" end)] | @tsv
    end' 2>"$err")"
  rc=$?
  if [ $rc -ne 0 ]; then
    sed 's/^jq: error ([^)]*): /error: /' "$err" >&2
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  [ -z "$out" ] || printf '%s\n' "$out"
}
