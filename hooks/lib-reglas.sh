#!/usr/bin/env bash
# Sourced by hooks/pre-edit, hooks/post-edit and hooks/stop-check (PreToolUse, PostToolUse and Stop of Claude Code and
# of Codex, whose apply_patch reaches the Edit|Write matcher with tool_name "apply_patch"; see kr_input).
# They read the marker of the session's worktree (speed; the guarantee is kit-pr.sh fusionar) and stay inert (exit 0,
# no output) without .agents-kit.json, with "reglas": false, without "lint", or when the input has no usable path.
# Cost before the lint: one jq over the input, one git, one jq over the marker (pre-edit: one more over the input and
# the current file, for code files).
# Env: KIT_LINT_TIMEOUT (s, default 10, post-edit), KIT_TURNO_TIMEOUT (s, default 120, stop-check).

KR_PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KR_PLUGIN/scripts/lib/repo-hook.sh"

# Rule- or type-disabling text: eslint-disable, @ts-ignore, @ts-nocheck, `as any` not followed by an identifier char.
KR_PROHIBIDO='eslint-disable|@ts-ignore|@ts-nocheck|\bas\s+any(?![\w$])'
# Code extensions always checked for that text, besides the keys of .lint.fichero (ipynb: cells of NotebookEdit).
KR_CODIGO=',ts,tsx,js,jsx,mjs,cjs,mts,cts,astro,vue,svelte,ipynb,'

# kr_input: parse the hook input on stdin (kept in KR_JSON) into KR_CWD (physical), KR_SID (session_id), KR_ACTIVO
# (1 when stop_hook_active is true), KR_PARCHE (1 for Codex's apply_patch) and KR_ITEMS, pairs "<path>" "<input>" of
# the files the tool touches, where <input> holds the tool_input that kr_sube_prohibido checks for that file:
#   - Claude Code: one pair, tool_input.file_path or notebook_path and the whole input (none without a path);
#   - Codex apply_patch (tool_input.command, the patch): one pair per "*** Add|Update|Delete File:" and per
#     "*** Move to:", as a Write (Add: content, the + lines), a MultiEdit (Update and its destination: one edit per
#     hunk, old_string the context and - lines, new_string the context and + lines) or nothing to check (Delete).
# Return 1 if unusable.
kr_input() {
  local cwd ok x
  [ ! -t 0 ] || return 1
  KR_JSON="$(cat)"; KR_CWD=""; KR_SID=""; KR_ACTIVO=""; KR_PARCHE=""; KR_ITEMS=(); ok=""
  { IFS= read -r -d '' cwd; IFS= read -r -d '' KR_SID; IFS= read -r -d '' KR_ACTIVO; IFS= read -r -d '' KR_PARCHE
    IFS= read -r -d '' ok; while IFS= read -r -d '' x; do KR_ITEMS+=("$x"); done; } < <(
    printf '%s' "$KR_JSON" | jq -j '
      def s: if type == "string" then . else "" end;
      def lineas: map(. + "\n") | join("");
      def ultimo(f): .fs[(.fs | length) - 1] |= f;
      def hunk(f): (if (.h | length) == 0 then .h = [{o: [], n: []}] else . end) | .h[(.h | length) - 1] |= f;
      def parche: reduce (split("\r\n") | join("\n") | split("\n"))[] as $l ({fs: [], fin: false};
        if .fin then .
        elif $l == "*** End Patch" then .fin = true
        elif ($l | test("^\\*\\*\\* (Add|Update|Delete) File: ")) then
          ($l | capture("^\\*\\*\\* (?<op>[A-Za-z]+) File: (?<p>.*)$")) as $c
          | .fs += [{op: $c.op, p: ($c.p | sub("\\s+$"; "")), mv: null, add: [], h: []}]
        elif (.fs | length) == 0 then .
        elif ($l | startswith("*** Move to: ")) then ultimo(.mv = ($l[13:] | sub("\\s+$"; "")))
        elif ($l | startswith("*** ")) then .
        elif .fs[-1].op == "Add" then ultimo(.add += [$l | if startswith("+") then .[1:] else . end])
        elif .fs[-1].op != "Update" then .
        elif ($l | startswith("@@")) then ultimo(.h += [{o: [], n: []}])
        elif ($l | startswith("+")) then ultimo(hunk(.n += [$l[1:]]))
        elif ($l | startswith("-")) then ultimo(hunk(.o += [$l[1:]]))
        else ($l | if startswith(" ") then .[1:] else . end) as $x | ultimo(hunk(.o += [$x] | .n += [$x])) end)
        | .fs[] | (if .op == "Add" then {content: (.add | lineas)}
                   elif .op == "Update" then {edits: [.h[] | {old_string: (.o | lineas), new_string: (.n | lineas)}]}
                   else {} end) as $i
        | (.p, (.mv | values)) | select(. != "") | ., "\u0000", ({tool_input: ($i + {file_path: .})} | tojson), "\u0000";
      (.tool_input | if type == "object" then . else {} end) as $i |
      (.cwd | s), "\u0000", (.session_id | s), "\u0000", (if .stop_hook_active == true then "1" else "" end), "\u0000",
      (if .tool_name == "apply_patch" then "1" else "" end), "\u0000", "ok", "\u0000",
      (if .tool_name == "apply_patch" then ($i.command // $i.patch // $i.input | s | parche)
       else ($i.file_path // $i.notebook_path | s) as $f | select($f != "") | $f, "\u0000", tojson, "\u0000" end)
      ' 2>/dev/null)
  [ "$ok" = ok ] && [ -n "$cwd" ] || return 1
  KR_CWD="$(cd "$cwd" 2>/dev/null && pwd -P)" && [ -n "$KR_CWD" ]
}

# kr_ext: KR_EXT, the extension of KR_REL in lower case (empty without one).
kr_ext() {
  local base="${KR_REL##*/}"
  KR_EXT=""
  case "$base" in ?*.*) KR_EXT="${base##*.}" ;; esac
  case "$KR_EXT" in *[A-Z]*) KR_EXT="$(printf '%s' "$KR_EXT" | tr 'A-Z' 'a-z')" ;; esac
}

# kr_sube_prohibido: print "no" only when the edit in KR_JSON does not raise the number of KR_PROHIBIDO matches; any
# other output (also a jq error or an unreadable file) means it must be blocked. Text is compared with CRLF as LF.
# Every field present counts, whatever the tool; any of them can block:
#   - new_source (NotebookEdit): any match (the cell is not compared);
#   - content (Write): more matches than KR_ROOT/KR_REL (a file that does not exist counts as empty);
#   - old_string/new_string and each of edits[], in that order, simulated as the tool would over the current file
#     (first literal occurrence of old_string, all of them with replace_all: true): the result must not have more
#     matches than the file; and an edit whose old_string is not in the simulated text (the tool also normalizes
#     quotes and whitespace, which this does not reproduce) must not bring any match in its new_string.
kr_sube_prohibido() {
  local f="$KR_ROOT/$KR_REL"
  [ -e "$f" ] || f=/dev/null
  printf '%s' "$KR_JSON" | jq -r --arg re "$KR_PROHIBIDO" --rawfile cur "$f" '
    def lf: if type == "string" then split("\r\n") | join("\n") else "" end;
    def cnt: [match($re; "g")] | length;
    (.tool_input | if type == "object" then . else {} end) as $i | ($cur | lf) as $antes | ($antes | cnt) as $na |
    (($i.new_source | type) == "string" and ($i.new_source | lf | cnt) > 0) as $celda |
    (($i.content | type) == "string" and ($i.content | lf | cnt) > $na) as $escrito |
    ([if ($i.old_string | type) == "string" or ($i.new_string | type) == "string" then $i else empty end]
      + ($i.edits | if type == "array" then map(objects) else [] end)) as $ediciones |
    (reduce $ediciones[] as $e ({t: $antes, mal: false};
       ($e.old_string | lf) as $o | ($e.new_string | lf) as $n |
       if $o == "" and .t == "" then .t = $n
       elif $o != "" and (.t | index($o)) != null then
         (.t | split($o)) as $p
         | .t = (if $e.replace_all == true then $p | join($n) else $p[0] + $n + ($p[1:] | join($o)) end)
       else .mal = (.mal or ($n | cnt) > 0) end)
     | .mal or (($ediciones | length) > 0 and (.t | cnt) > $na)) as $editado |
    if $celda or $escrito or $editado then "sube" else "no" end' 2>/dev/null
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

# kr_config [<ext>]: KR_CMD (the .lint.fichero command whose comma-separated keys, without case, include <ext>, which
# is lower case (kr_ext); or empty), KR_TURNO
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
          | select($ext != "" and (.key | ascii_downcase | split(",") | map(gsub("^\\s+|\\s+$"; "") | ltrimstr(".")) | index([$ext])))
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

# kr_lint <tope> <qué> <comando> [args...]: run `<comando> <args>` from KR_ROOT under the lock (taken with <tope> on
# the first call; later calls reuse it) and return: 2 with the output on stderr when it fails; 0 when it passes, the
# lock is busy, the tool is missing (126/127) or it times out.
kr_lint() {
  local t="$1" what="$2" cmd="$3" rc; shift 3
  [ -n "${KR_LOCK_OK:-}" ] || { kr_lock "$t" || return 0; KR_LOCK_OK=1; }
  kit_run_timeout "$KR_ROOT" "$t" /bin/sh -c "$cmd \"\$@\"" kit-lint "$@"; rc=$?
  case $rc in
    0) return 0 ;;
    126|127) echo "agents-kit: el lint no se pudo ejecutar ($cmd, exit $rc); no bloquea" >&2; return 0 ;;
    142) echo "agents-kit: el lint pasó de $t s ($cmd); no bloquea" >&2; return 0 ;;
  esac
  printf 'El lint falla en %s (%s, exit %s). Arréglalo:\n%s\n' "$what" "$cmd" "$rc" "$KIT_HOOK_OUT" >&2
  return 2
}
