#!/usr/bin/env bash
# Sourced by hooks/pre-edit, hooks/post-edit and hooks/stop-check (Claude Code PreToolUse, PostToolUse and Stop).
# They read the marker of the session's worktree (speed; the guarantee is kit-pr.sh fusionar) and stay inert (exit 0,
# no output) without .agents-kit.json, with "reglas": false, without "lint", or when the input has no usable path.
# Cost before the lint: one jq over the input, one git, one jq over the marker (pre-edit: one more over the current
# file for a Write that adds disabling text).
# Env: KIT_LINT_TIMEOUT (s, default 10, post-edit), KIT_TURNO_TIMEOUT (s, default 120, stop-check).

KR_PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KR_PLUGIN/scripts/lib/repo-hook.sh"

# Rule- or type-disabling text: eslint-disable, @ts-ignore, @ts-nocheck, `as any` not followed by an identifier char.
KR_PROHIBIDO='eslint-disable|@ts-ignore|@ts-nocheck|\bas\s+any(?![\w$])'
# Code extensions always checked for that text, besides the keys of .lint.fichero.
KR_CODIGO=',ts,tsx,js,jsx,mjs,cjs,mts,cts,astro,vue,svelte,'

# kr_input: parse the hook input on stdin into KR_CWD (physical), KR_FILE (tool_input.file_path or notebook_path),
# KR_SID (session_id), KR_NUEVO and KR_VIEJO (matches of KR_PROHIBIDO in the new text and in the replaced text:
# new_string/old_string, summed over edits[]; for a Write, KR_VIEJO is -1 and the current file is the old text).
# Return 1 if unusable.
kr_input() {
  local cwd ok
  [ ! -t 0 ] || return 1
  KR_CWD=""; KR_FILE=""; KR_SID=""; KR_NUEVO=0; KR_VIEJO=0; ok=""
  { IFS= read -r -d '' cwd; IFS= read -r -d '' KR_FILE; IFS= read -r -d '' KR_SID; IFS= read -r -d '' KR_NUEVO
    IFS= read -r -d '' KR_VIEJO; IFS= read -r -d '' ok; } < <(jq -j --arg re "$KR_PROHIBIDO" '
      def s: if type == "string" then . else "" end;
      def n: map(strings | [match($re; "g")] | length) | add // 0;
      (.tool_input | if type == "object" then . else {} end) as $i |
      ($i.edits | if type == "array" then map(objects) else [] end) as $e |
      (.cwd | s), "\u0000", ($i.file_path // $i.notebook_path | s), "\u0000", (.session_id | s), "\u0000",
      if ($i.content | type) == "string" then ([$i.content] | n | tostring), "\u0000", "-1"
      else ([$i.new_string, $i.new_source] + ($e | map(.new_string)) | n | tostring), "\u0000",
        ([$i.old_string] + ($e | map(.old_string)) | n | tostring) end,
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
# yet). Symlinks in the existing part are resolved, and so is a last component that is a symlink (up to 8 levels);
# '.' or '..' in the missing part, or a path outside the repo, return 1. On macOS (case-insensitive file systems) the
# root is compared without case.
kr_resolve() {
  local p="$KR_FILE" d rest i=0 t
  [ -n "$p" ] || return 1
  case "$p" in /*) ;; *) p="$KR_CWD/$p" ;; esac
  while :; do
    d="${p%/*}"; rest="${p##*/}"
    while [ -n "$d" ] && [ ! -d "$d" ]; do rest="${d##*/}/$rest"; d="${d%/*}"; done
    case "/$rest/" in */../*|*/./*|//) return 1 ;; esac
    d="$(cd "${d:-/}" 2>/dev/null && pwd -P)" || return 1
    p="${d%/}/$rest"
    [ -L "$p" ] && [ $i -lt 8 ] || break
    t="$(readlink "$p")" || return 1
    case "$t" in /*) p="$t" ;; *) p="${p%/*}/$t" ;; esac
    i=$((i + 1))
  done
  [ ! -L "$p" ] || return 1
  case "$OSTYPE" in darwin*) shopt -s nocasematch ;; esac
  [[ "$p" == "$KR_ROOT"/?* ]]; t=$?
  shopt -u nocasematch
  [ $t -eq 0 ] || return 1
  KR_REL="${p:$((${#KR_ROOT} + 1))}"
}

# kr_codigo <ext>: return 0 when <ext> is a code extension (KR_CMD found a .lint.fichero entry, or KR_CODIGO).
kr_codigo() {
  [ -n "$KR_CMD" ] || case "$KR_CODIGO" in *",$1,"*) [ -n "$1" ] ;; *) false ;; esac
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
# and release it on exit only while it is still ours. Inside, "dueño" holds "<pid> <hora límite>" (now + tope + 5 s).
# A lock is dead when its pid no longer exists or its deadline has passed; without "dueño" (an owner halfway through
# creating it), when its mtime is more than 125 s old. A dead lock is moved aside, checked again and replaced.
# Return 1 if busy.
kr_lock() {
  local ahora tmp
  KR_LOCK="$KR_COMMON/agents-kit/lint.lock"
  mkdir -p "$KR_COMMON/agents-kit" 2>/dev/null
  ahora="$(date +%s)"
  if ! mkdir "$KR_LOCK" 2>/dev/null; then
    _kr_muerto "$KR_LOCK" "$ahora" || return 1
    tmp="$KR_LOCK.muerto.$$"
    mv "$KR_LOCK" "$tmp" 2>/dev/null || return 1
    if ! _kr_muerto "$tmp" "$ahora"; then mv "$tmp" "$KR_LOCK" 2>/dev/null; return 1; fi
    rm -f "$tmp/dueño"; rmdir "$tmp" 2>/dev/null
    mkdir "$KR_LOCK" 2>/dev/null || return 1
  fi
  printf '%s %s\n' "$$" "$((ahora + $1 + 5))" > "$KR_LOCK/dueño"
  trap '_kr_soltar' EXIT
  trap 'exit 143' HUP INT TERM
}

# _kr_muerto <dir> <ahora>: return 0 when the lock <dir> is dead (see kr_lock).
_kr_muerto() {
  local pid="" lim=""
  [ ! -f "$1/dueño" ] || read -r pid lim < "$1/dueño" 2>/dev/null
  case "$pid:$lim" in
    *[!0-9:]*|:*|*:)
      [ "$(perl -e 'my $m = (stat $ARGV[0])[9]; print defined $m ? time - $m : 0' "$1")" -gt 125 ] ;;
    *) { ! kill -0 "$pid" 2>/dev/null && ! ps -p "$pid" >/dev/null 2>&1; } || [ "$2" -gt "$lim" ] ;;
  esac
}

# _kr_soltar: EXIT trap; remove the lock only if "dueño" still names this process.
_kr_soltar() {
  local pid="" lim
  [ -f "$KR_LOCK/dueño" ] && read -r pid lim < "$KR_LOCK/dueño" 2>/dev/null
  [ "$pid" = "$$" ] || return 0
  rm -f "$KR_LOCK/dueño"; rmdir "$KR_LOCK" 2>/dev/null
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
