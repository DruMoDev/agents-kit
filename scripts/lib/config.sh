#!/usr/bin/env bash
# Sourced helper: read .agents-kit.json merged over the plugin template. No side effects on source.

_KIT_TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/templates/agents-kit.json"

# kit_require_marker <root>: return 1 unless <root>/.agents-kit.json exists.
kit_require_marker() {
  if [ ! -f "$1/.agents-kit.json" ]; then
    echo "kit no activado: ejecuta kit-on" >&2
    return 1
  fi
}

# kit_config <root> <jq-filter>: run the filter over template * marker (marker reviewers replace the template's).
kit_config() {
  local merged
  # marker must be a JSON object (empty file, [], null, 5 are rejected)
  if ! jq -e 'type == "object"' "$1/.agents-kit.json" >/dev/null 2>&1; then
    echo "error: .agents-kit.json no es JSON válido" >&2
    return 2
  fi
  if ! merged="$(jq -c -s '. as $s | ($s[0] * $s[1]) | .reviewers = ($s[1].reviewers // $s[0].reviewers)' \
    "$_KIT_TEMPLATE" "$1/.agents-kit.json")"; then
    echo "error: .agents-kit.json no es JSON válido" >&2
    return 2
  fi
  printf '%s' "$merged" | jq -r "$2"
}

# kit_reviewers <root>: one line per reviewer, tool<TAB>model<TAB>focus (claude, opencode, codex order).
kit_reviewers() {
  kit_config "$1" '.reviewers as $r | ["claude","opencode","codex"][] as $t | ($r[$t] // [])[] | [$t, .model, .focus] | @tsv'
}
