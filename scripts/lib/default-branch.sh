#!/usr/bin/env bash
# Sourced helper: default branch of remote 'origin', and a fetch that tolerates other sessions. No side effects on source.

# kit_default_branch: print origin's default branch (asks the remote); prints nothing if unknown.
kit_default_branch() {
  git ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p'
}
# kit_fetch <git fetch args...>: git fetch -q in the current directory, retried quietly (3 tries, 2 s apart) because
# another session fetching the same clone makes git fail with "cannot lock ref". The last error goes to stderr.
kit_fetch() {
  local k err
  err="$(mktemp)" || return 2
  for k in 1 2 3; do
    if git fetch -q "$@" 2>"$err"; then rm -f "$err"; return 0; fi
    [ "$k" -eq 3 ] || sleep 2
  done
  cat "$err" >&2; rm -f "$err"
  return 1
}
