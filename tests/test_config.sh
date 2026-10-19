#!/usr/bin/env bash
# Tests for scripts/lib/config.sh.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$REPO_ROOT/scripts/lib/config.sh"

d="$(mktemp -d)"

# no marker
err="$(kit_require_marker "$d" 2>&1)"; rc=$?
[ $rc -eq 1 ] || fail "sin marcador: exit $rc, esperado 1"
[ "$err" = "kit no activado: ejecuta kit-on" ] || fail "sin marcador: stderr '$err'"

# empty marker -> default reviewers in order
echo '{}' > "$d/.agents-kit.json"
kit_require_marker "$d" || fail "con marcador: require falló"
got="$(kit_reviewers "$d")"
want="$(printf 'claude\topus\tcorrección, casos límite y tests\nclaude\tsonnet\tsimplicidad, reutilización y scope\nopencode\topenai/gpt-6.1-sol\tfallos de uso real, seguridad y lo que otros revisores darían por bueno')"
[ "$got" = "$want" ] || fail "defaults: '$got'"

# marker reviewers replace the template's entirely
echo '{"reviewers":{"claude":[{"model":"sonnet","focus":"x"}]}}' > "$d/.agents-kit.json"
got="$(kit_reviewers "$d")"
[ "$got" = "$(printf 'claude\tsonnet\tx')" ] || fail "sustitución: '$got'"

# missing key falls back to template
echo '{}' > "$d/.agents-kit.json"
[ "$(kit_config "$d" .maxReviewRounds)" = "10" ] || fail "maxReviewRounds"

# invalid JSON -> 2
echo '{nope' > "$d/.agents-kit.json"
err="$(kit_config "$d" .maxReviewRounds 2>&1)"; rc=$?
[ $rc -eq 2 ] || fail "JSON inválido: exit $rc"
[ "$err" = "error: .agents-kit.json no es JSON válido" ] || fail "JSON inválido: stderr '$err'"

echo "ok"
