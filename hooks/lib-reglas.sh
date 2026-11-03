#!/usr/bin/env bash
# Sourced by hooks/pre-edit, hooks/post-edit and hooks/stop-check (Claude Code PreToolUse, PostToolUse and Stop).
# They read the marker of the session's worktree (speed; the guarantee is kit-pr.sh fusionar) and stay inert (exit 0,
# no output) without .agents-kit.json, with "reglas": false, without "lint", or when the input has no usable path.
# Cost before the lint: one jq over the input, one git, one jq over the marker.
# Env: KIT_LINT_TIMEOUT (s, default 10, post-edit), KIT_TURNO_TIMEOUT (s, default 120, stop-check).

KR_PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KR_PLUGIN/scripts/lib/repo-hook.sh"

# kr_input: parse the hook input on stdin into KR_CWD (physical), KR_FILE (tool_input.file_path or notebook_path),
# KR_SID (session_id) and KR_FORBID (1 when the new text disables rules or types). Return 1 if unusable.
kr_input() {
  local cwd ok
  [ ! -t 0 ] || return 1
  KR_CWD=""; KR_FILE=""; KR_SID=""; KR_FORBID=0; ok=""
  { IFS= read -r -d '' cwd; IFS= read -r -d '' KR_FILE; IFS= read -r -d '' KR_SID; IFS= read -r -d '' KR_FORBID
    IFS= read -r -d '' ok; } < <(jq -j '
      def s: if type == "string" then . else "" end;
      (.tool_input | if type == "object" then . else {} end) as $i |
      (.cwd | s), "\u0000", ($i.file_path // $i.notebook_path | s), "\u0000", (.session_id | s), "\u0000",
      ([$i.content, $i.new_string, $i.new_source, ($i.edits | if type == "array" then .[] | objects | .new_string
        else empty end)] | map(strings) | join("\n")
        | if test("eslint-disable|@ts-ignore|@ts-nocheck|\\bas\\s+any(?![\\w$])") then "1" else "0" end),
      "\u0000", "ok", "\u0000"' 2>/dev/null)
  [ "$ok" = ok ] && [ -n "$cwd" ] || return 1
  KR_CWD="$(cd "$cwd" 2>/dev/null && pwd -P)" && [ -n "$KR_CWD" ]
}

# kr_root: KR_ROOT and KR_COMMON (git common dir, absolute) of KR_CWD. Return 1 outside git or without the marker.
kr_root() {
  local out
  out="$(git -C "$KR_CWD" rev-parse --show-toplevel --git-common-dir 2>/dev/null)" || return 1
  KR_ROOT="${out%%$'\n'*}"; KR_COMMON="${out#*$'\n'}"
  case "$KR_COMMON" in /*) ;; *) KR_COMMON="$KR_CWD/$KR_COMMON" ;; esac
  [ -n "$KR_ROOT" ] && [ -f "$KR_ROOT/.agents-kit.json" ]
}

# kr_resolve: KR_REL, KR_FILE relative to KR_ROOT (KR_FILE may be absolute or relative to KR_CWD, and may not exist
# yet). Symlinks in the existing part are resolved; '.' or '..' in the missing part, or a path outside the repo,
# return 1.
kr_resolve() {
  local p="$KR_FILE" d rest
  [ -n "$p" ] || return 1
  case "$p" in /*) ;; *) p="$KR_CWD/$p" ;; esac
  d="${p%/*}"; rest="${p##*/}"
  while [ -n "$d" ] && [ ! -d "$d" ]; do rest="${d##*/}/$rest"; d="${d%/*}"; done
  case "/$rest/" in */../*|*/./*|//) return 1 ;; esac
  d="$(cd "${d:-/}" 2>/dev/null && pwd -P)" || return 1
  case "$d/$rest" in "$KR_ROOT"/*) KR_REL="${d#"$KR_ROOT"}/$rest"; KR_REL="${KR_REL#/}" ;; *) return 1 ;; esac
}

# kr_config [<ext>]: KR_CMD (the .lint.fichero command whose comma-separated keys include <ext>, or empty), KR_TURNO
# (.lint.turno) and KR_GLOBS (.blindado, one per line: marker < global < plugin, arrays replace as in kit_config).
# Return 1 when inert: "reglas": false, no "lint" object, or a config that is not valid JSON.
kr_config() {
  local g="${KIT_CONFIG:-$HOME/.agents-kit/config.json}" on=""
  [ -f "$g" ] || g=/dev/null
  { IFS= read -r -d '' on; IFS= read -r -d '' KR_CMD; IFS= read -r -d '' KR_TURNO; IFS= read -r -d '' KR_GLOBS; } < <(
    jq -j --arg ext "${1:-}" --slurpfile g "$g" --slurpfile t "$KR_PLUGIN/templates/config.json" '
      def s: if type == "string" then . else "" end;
      if .reglas != false and (.lint | type) == "object" then
        "1", "\u0000",
        ([.lint.fichero | objects | to_entries[]
          | select($ext != "" and (.key | split(",") | map(gsub("^\\s+|\\s+$"; "") | ltrimstr(".")) | index([$ext])))
          | .value | strings][0] // ""), "\u0000",
        (.lint.turno | s), "\u0000",
        ((.blindado // ($g[0] | objects | .blindado) // $t[0].blindado) | if type == "array" then map(strings)
          | join("\n") else "" end), "\u0000"
      else "0", "\u0000" end' "$KR_ROOT/.agents-kit.json" 2>/dev/null)
  [ "$on" = 1 ]
}

# kr_lock <tope>: take <common>/agents-kit/lint.lock (shared by post-edit and stop-check; one lint per repo at a time)
# and release it on exit. A lock older than <tope> seconds is taken as dead and replaced. Return 1 if busy.
kr_lock() {
  local age
  KR_LOCK="$KR_COMMON/agents-kit/lint.lock"
  mkdir -p "$KR_COMMON/agents-kit" 2>/dev/null
  if ! mkdir "$KR_LOCK" 2>/dev/null; then
    age="$(perl -e 'my $m = (stat $ARGV[0])[9]; print defined $m ? time - $m : 0' "$KR_LOCK")"
    [ "${age:-0}" -gt "$1" ] || return 1
    rmdir "$KR_LOCK" 2>/dev/null
    mkdir "$KR_LOCK" 2>/dev/null || return 1
  fi
  trap 'rmdir "$KR_LOCK" 2>/dev/null' EXIT
  trap 'exit 143' HUP INT TERM
}

# kr_tope <valor> <defecto>: print <valor> if it is a positive number of seconds, else <defecto>.
kr_tope() {
  case "$1" in ''|*[!0-9]*|0*) echo "$2" ;; *) echo "$1" ;; esac
}

# kr_lint <tope> <qué> <comando> [args...]: run `<comando> <args>` from KR_ROOT under the lock and exit: 2 with the
# output on stderr when it fails; 0 when it passes, the lock is busy, the tool is missing (126/127) or it times out.
kr_lint() {
  local t="$1" what="$2" cmd="$3" rc; shift 3
  kr_lock "$t" || exit 0
  kit_run_timeout "$KR_ROOT" "$t" /bin/sh -c "$cmd \"\$@\"" kit-lint "$@"; rc=$?
  case $rc in
    0) exit 0 ;;
    126|127) echo "agents-kit: el lint no se pudo ejecutar ($cmd, exit $rc); no bloquea" >&2; exit 0 ;;
    142) echo "agents-kit: el lint pasó de $t s ($cmd); no bloquea" >&2; exit 0 ;;
  esac
  printf 'El lint falla en %s (%s, exit %s). Arréglalo:\n%s\n' "$what" "$cmd" "$rc" "$KIT_HOOK_OUT" >&2
  exit 2
}
