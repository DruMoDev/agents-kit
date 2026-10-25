#!/usr/bin/env bash
# Sourced helper: CI state of a commit on GitHub. Needs $slug (owner/repo). No side effects on source.

# Only the repo's own active workflows (.github/workflows/) are its CI. GitHub's built-in ones (path dynamic/...:
# Dependabot, CodeQL default setup, Copilot) are not, and the results of code scanning (app github-advanced-security,
# checked on dependabot/dependabot-core and github/codeql-action) are analysis, not tests: neither counts as CI.
_CI_OWN_WF='[.workflows[]? | select((.path // "") | startswith(".github/workflows/")) | select((.state // "active") == "active")] | length'

# ci_has_workflows: print true/false (own active workflows, see above); return 2 if gh fails or it is unreadable.
ci_has_workflows() {
  local c
  c="$(ci_gh_retry api "repos/$slug/actions/workflows?per_page=100" --jq "$_CI_OWN_WF")" || return 2
  [[ $c =~ ^[0-9]+$ ]] || return 2
  if [ "$c" -gt 0 ]; then echo true; else echo false; fi
}
# ci_state <sha> [externos]: one read of the workflow runs and check runs of <sha>. By default only the check runs of
# the repo's own workflow runs (path .github/workflows/, matched by check suite) count: the CI. With "externos", the
# others: not GitHub's built-in workflows (dynamic/...) nor code scanning results, but third-party apps (deploy
# previews...). Latest attempt per app and check name, by id. Prints ninguno | esperando | verde | rojo <conclusion> |
# sin-cuota (own CI only: every failed job is one GitHub never started for billing, the account's Actions minutes or
# spending limit, which reads as a plain failure); return 2 if unreadable.
ci_state() {
  local runs r s id
  runs="$(ci_gh_retry api "repos/$slug/actions/runs?head_sha=$1&per_page=100")" || return 2
  r="$(ci_gh_retry api "repos/$slug/commits/$1/check-runs?filter=all&per_page=100")" || return 2
  s="$(printf '%s' "$r" | jq -r --argjson runs "$runs" --arg mode "${2:-propio}" '
    ([$runs.workflow_runs[]? | select((.path // "") | startswith(".github/workflows/")) | .check_suite_id]) as $own
    | ([$runs.workflow_runs[]? | select((.path // "") | startswith(".github/workflows/") | not) | .check_suite_id]) as $builtin
    | if (.check_runs | type) != "array" then error("sin check_runs") else .check_runs end
    | map(select((.app.slug // "") != "github-advanced-security"))
    | map((.check_suite.id // null) as $cs
        | select(if $mode == "externos" then ($own | index($cs) | not) and ($builtin | index($cs) | not)
                 else ($own | index($cs)) != null end))
    | group_by([.app.id, .name]) | map(max_by(.id))
    | if length == 0 then "ninguno"
      elif any(.[]; .status != "completed") then "esperando"
      else [.[] | select((.conclusion // "sin conclusión") as $x | ["success", "skipped", "neutral"] | index($x) | not)]
      | if length == 0 then "verde"
        else "rojo \(.[0].conclusion // "sin conclusión")\t\(if all(.[]; .conclusion == "failure" and (.id | type) == "number")
          then map(.id | tostring) | join(" ") else "" end)" end
      end' 2>/dev/null)" || return 2
  case "$s" in
    rojo*) ;;
    *) printf '%s\n' "$s"; return 0 ;;
  esac
  # the failed jobs' ids go after a tab only when all of them failed outright: the candidates for a billing block
  if [ "${2:-propio}" = propio ] && [ -n "${s#*$'\t'}" ]; then
    for id in ${s#*$'\t'}; do
      ci_gh_retry api "repos/$slug/check-runs/$id/annotations" --jq \
        'any(.[]?; .annotation_level == "failure" and ((.message // "") | test("job was not started because"; "i")))' \
        2>/dev/null | grep -qx true || { printf '%s\n' "${s%%$'\t'*}"; return 0; }
    done
    echo sin-cuota; return 0
  fi
  printf '%s\n' "${s%%$'\t'*}"
}
# ci_quota_rerun <sha>: re-run the failed jobs of the own workflow runs of <sha> that ended before this month's billing
# period (day 1, 00:00 UTC, when the account's Actions minutes come back): jobs blocked for lack of minutes last month
# may run now. Prints how many runs it re-ran; return 2 if gh fails.
ci_quota_rerun() {
  local month ids id n=0
  month="$(date -u +%Y-%m-01T00:00:00Z)"
  ids="$(ci_gh_retry api "repos/$slug/actions/runs?head_sha=$1&per_page=100" --jq "[.workflow_runs[]?
    | select((.path // \"\") | startswith(\".github/workflows/\")) | select(.conclusion == \"failure\")
    | select((.updated_at // \"\") < \"$month\") | .id] | .[]")" || return 2
  for id in $ids; do
    ci_gh_retry api "repos/$slug/actions/runs/$id/rerun-failed-jobs" --method POST >/dev/null || return 2
    n=$((n + 1))
  done
  echo "$n"
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
# ci_wait <sha> [timeout]: wait for the CI of <sha>. Prints verde, sin-ci (no workflows, or workflows that start no
# check run for the SHA within KIT_CI_GRACE) or sin-cuota (GitHub did not start the jobs: no Actions minutes; jobs
# blocked before this month's billing period are re-run once, in case the minutes came back). Return 1 (reason on stderr) if it ends red, 3 if checks are still running
# after <timeout> seconds (default KIT_CI_TIMEOUT, else 1800), 2 if unreadable.
# KIT_CI_POLL (s, default 15), KIT_CI_GRACE (s, default 300).
ci_wait() {
  local timeout="${2:-${KIT_CI_TIMEOUT:-1800}}" poll="${KIT_CI_POLL:-15}" grace="${KIT_CI_GRACE:-300}" wf s start=$SECONDS
  [[ $timeout =~ ^[0-9]+$ ]] && [[ $poll =~ ^[0-9]+$ ]] && [[ $grace =~ ^[0-9]+$ ]] \
    || { echo "error: KIT_CI_TIMEOUT, KIT_CI_POLL y KIT_CI_GRACE deben ser segundos enteros" >&2; return 2; }
  wf="$(ci_has_workflows)" || { echo "error: no se pudo leer el estado del CI" >&2; return 2; }
  if [ "$wf" = false ]; then echo sin-ci; return 0; fi
  local fails=0 rerun=false n
  while :; do
    # a wait of hours must survive a bad minute of GitHub: 5 failed reads in a row end it, not one
    if ! s="$(ci_state "$1")"; then
      fails=$((fails + 1))
      [ "$fails" -lt 5 ] || { echo "error: no se pudo leer el estado del CI (5 lecturas seguidas fallidas)" >&2; return 2; }
      sleep "$poll"; continue
    fi
    fails=0
    case "$s" in
      verde) echo verde; return 0 ;;
      sin-cuota)
        if [ "$rerun" = false ]; then
          rerun=true
          n="$(ci_quota_rerun "$1")" || { echo "error: no se pudo relanzar el CI bloqueado por cuota" >&2; return 2; }
          if [ "$n" -gt 0 ]; then
            echo "aviso: el CI de ${1:0:8} se bloqueó por falta de minutos antes del día 1; relanzado ($n workflows)" >&2
            sleep "$poll"; continue
          fi
        fi
        echo sin-cuota; return 0 ;;
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
