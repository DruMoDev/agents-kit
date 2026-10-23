#!/usr/bin/env bash
# Sourced helper: CI state of a commit on GitHub. Needs $slug (owner/repo). No side effects on source.

# ci_has_workflows: print true/false; return 2 if gh fails or the answer is unreadable.
ci_has_workflows() {
  local c
  c="$(gh api "repos/$slug/actions/workflows" --jq .total_count)" || return 2
  [[ $c =~ ^[0-9]+$ ]] || return 2
  if [ "$c" -gt 0 ]; then echo true; else echo false; fi
}
# ci_state <sha>: one read of the check runs (latest attempt per app and check name, by id);
# prints ninguno (no check run) | esperando | verde | rojo <conclusion>; return 2 if unreadable.
ci_state() {
  local r
  r="$(gh api "repos/$slug/commits/$1/check-runs?filter=all&per_page=100")" || return 2
  printf '%s' "$r" | jq -r '
    if (.check_runs | type) != "array" then error("sin check_runs") else .check_runs end
    | group_by([.app.id, .name]) | map(max_by(.id))
    | if length == 0 then "ninguno"
      elif any(.[]; .status != "completed") then "esperando"
      else ([.[] | .conclusion // "sin conclusión" | select(. as $x | ["success", "skipped", "neutral"] | index($x) | not)]
        | first) as $bad
      | if $bad == null then "verde" else "rojo \($bad)" end
      end' 2>/dev/null || return 2
}
_CI_SLOWEST='[.workflow_runs[] | select(.run_started_at and .updated_at) | (.updated_at | fromdate) - (.run_started_at | fromdate)] | max // 0'
# ci_timeout [dir...]: seconds ci_wait waits by default. KIT_CI_TIMEOUT if set; else ciTimeoutMin (minutes) from the
# kit config of the first <dir> with .agents-kit.json (needs lib/config.sh); else from the repo history: the larger of
# 1800 and 1.5 x the slowest of the last 20 successful runs, at most 10800. gh failure or no history = 1800.
ci_timeout() {
  local d m slow t
  if [ -n "${KIT_CI_TIMEOUT:-}" ]; then printf '%s\n' "$KIT_CI_TIMEOUT"; return 0; fi
  if declare -F kit_config >/dev/null; then
    for d in "$@"; do
      [ -f "$d/.agents-kit.json" ] || continue
      m="$(kit_config "$d" '.ciTimeoutMin // empty' 2>/dev/null)" || m=""
      if [[ $m =~ ^[1-9][0-9]*$ ]]; then echo $((m * 60)); return 0; fi
      [ -z "$m" ] || echo "aviso: ciTimeoutMin debe ser un número entero de minutos; se ignora '$m'" >&2
      break
    done
  fi
  slow="$(gh api "repos/$slug/actions/runs?status=success&per_page=20" --jq "$_CI_SLOWEST" 2>/dev/null)" || slow=0
  [[ $slow =~ ^[0-9]+$ ]] || slow=0
  t=$((slow * 3 / 2))
  [ "$t" -ge 1800 ] || t=1800
  [ "$t" -le 10800 ] || t=10800
  echo "$t"
}
# ci_wait <sha> [timeout]: wait for the CI of <sha>. Prints verde, or sin-ci (no workflows, or workflows that start no
# check run for the SHA within KIT_CI_GRACE). Return 1 (reason on stderr) if it ends red, 3 if checks are still running
# after <timeout> seconds (default KIT_CI_TIMEOUT, else 1800), 2 if unreadable.
# KIT_CI_POLL (s, default 15), KIT_CI_GRACE (s, default 300).
ci_wait() {
  local timeout="${2:-${KIT_CI_TIMEOUT:-1800}}" poll="${KIT_CI_POLL:-15}" grace="${KIT_CI_GRACE:-300}" wf s start=$SECONDS
  [[ $timeout =~ ^[0-9]+$ ]] && [[ $poll =~ ^[0-9]+$ ]] && [[ $grace =~ ^[0-9]+$ ]] \
    || { echo "error: KIT_CI_TIMEOUT, KIT_CI_POLL y KIT_CI_GRACE deben ser segundos enteros" >&2; return 2; }
  wf="$(ci_has_workflows)" || { echo "error: no se pudo leer el estado del CI" >&2; return 2; }
  if [ "$wf" = false ]; then echo sin-ci; return 0; fi
  while :; do
    s="$(ci_state "$1")" || { echo "error: no se pudo leer el estado del CI" >&2; return 2; }
    case "$s" in
      verde) echo verde; return 0 ;;
      rojo*) echo "el CI terminó en '${s#rojo }'" >&2; return 1 ;;
      ninguno) if [ $((SECONDS - start)) -ge "$grace" ]; then echo sin-ci; return 0; fi ;;
    esac
    if [ $((SECONDS - start)) -ge "$timeout" ]; then
      echo "el CI de ${1:0:8} sigue en marcha tras $((timeout / 60)) min (${timeout}s)" >&2
      return 3
    fi
    sleep "$poll"
  done
}
# ci_gh_retry <gh args...>: run gh, retrying up to KIT_GH_RETRIES times (default 3 attempts in all, waits of
# KIT_GH_RETRY_WAIT s, default 10, doubled each time) when it fails with a transient GitHub error (GraphQL "Something
# went wrong", HTTP 5xx, timeouts). Any other failure, or the last one, returns gh's code with its stderr.
ci_gh_retry() {
  local tries="${KIT_GH_RETRIES:-3}" wait="${KIT_GH_RETRY_WAIT:-10}" k=1 err rc
  err="$(mktemp)" || return 2
  while :; do
    gh "$@" 2>"$err"; rc=$?
    if [ $rc -eq 0 ]; then rm -f "$err"; return 0; fi
    if [ "$k" -ge "$tries" ] || ! grep -qiE 'something went wrong|HTTP 5[0-9][0-9]|50[234]|timed? ?out|timeout|connection reset|EOF' "$err"; then
      cat "$err" >&2; rm -f "$err"; return $rc
    fi
    echo "aviso: fallo transitorio de GitHub ($(sed -n 1p "$err")); reintento en ${wait}s" >&2
    sleep "$wait"; wait=$((wait * 2)); k=$((k + 1))
  done
}
