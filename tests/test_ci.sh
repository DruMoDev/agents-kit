#!/usr/bin/env bash
# Tests for ci_timeout (scripts/lib/ci.sh): env, ciTimeoutMin of the config, repo history.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
use_gh_stub
source "$REPO_ROOT/scripts/lib/config.sh"
source "$REPO_ROOT/scripts/lib/ci.sh"
slug=dru/demo
unset KIT_CI_TIMEOUT GH_RUNS_SLOW

d="$(mk_repo)"
[ "$(ci_timeout "$d")" = 1800 ] || fail "sin historial ni marcador: 1800"
grep -q '^api repos/dru/demo/actions/runs?status=success' "$GH_LOG" || fail "no lee el historial del repo"
[ "$(GH_RUNS_SLOW=1000 ci_timeout "$d")" = 1800 ] || fail "CI rápido: mínimo 1800"
[ "$(GH_RUNS_SLOW=2880 ci_timeout "$d")" = 4320 ] || fail "CI de 48 min: 1,5 veces"
[ "$(GH_RUNS_SLOW=9000 ci_timeout "$d")" = 10800 ] || fail "tope de 10800"
[ "$(KIT_CI_TIMEOUT=60 GH_RUNS_SLOW=9000 ci_timeout "$d")" = 60 ] || fail "KIT_CI_TIMEOUT manda"

echo '{"ciTimeoutMin": 90}' > "$d/.agents-kit.json"
[ "$(GH_RUNS_SLOW=9000 ci_timeout "$d")" = 5400 ] || fail "ciTimeoutMin del marcador manda sobre el historial"
[ "$(KIT_CI_TIMEOUT=60 ci_timeout "$d")" = 60 ] || fail "KIT_CI_TIMEOUT manda sobre ciTimeoutMin"
e="$(mktemp -d)"
[ "$(ci_timeout "$e" "$d")" = 5400 ] || fail "primer directorio sin marcador: usa el siguiente"
set_global '{"ciTimeoutMin": 45}'
echo '{}' > "$d/.agents-kit.json"
[ "$(ci_timeout "$d")" = 2700 ] || fail "ciTimeoutMin global"
rm -f "$KIT_CONFIG"
echo '{"ciTimeoutMin": "x"}' > "$d/.agents-kit.json"
err="$(GH_RUNS_SLOW=2880 ci_timeout "$d" 2>&1 >/dev/null)"
case "$err" in *"ciTimeoutMin debe ser un número entero de minutos"*) ;; *) fail "ciTimeoutMin inválido sin aviso: '$err'";; esac
[ "$(GH_RUNS_SLOW=2880 ci_timeout "$d" 2>/dev/null)" = 4320 ] || fail "ciTimeoutMin inválido: usa el historial"
echo PASS
