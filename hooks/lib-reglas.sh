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
# (1 when stop_hook_active is true), KR_PARCHE (1 for Codex's apply_patch), KR_AGENTE (agent_id: Claude Code sends it,
# with the session_id of the main session, in the hooks of a subagent), KR_EVENTO (hook_event_name), KR_TURN_ID
# (turn_id, which Codex sends and Claude Code does not) and KR_ITEMS, pairs "<path>" "<input>" of
# the files the tool touches, where <input> holds the tool_input that kr_sube_prohibido checks for that file:
#   - Claude Code: one pair, tool_input.file_path or notebook_path and the whole input (none without a path);
#   - Codex apply_patch (tool_input.command, the patch): one pair per "*** Add|Update|Delete File:" and per
#     "*** Move to:", as a Write (Add: content, the + lines), a MultiEdit (Update and its destination: one edit per
#     hunk, old_string the context and - lines, new_string the context and + lines) or nothing to check (Delete).
#     Lines are classified as Codex does: in an Add, "+" is content; in an Update, " ", "+" and "-" are hunk lines
#     (an empty line is empty context) and "@@" a hunk header; any other line, trimmed at both ends, must be a marker
#     (also outside any file; blank lines are fine there and after "*** End Patch", not in an Add). The patch is
#     unreadable on any other line, an empty path, a misplaced "*** Move to:", or a context line that is a marker once
#     trimmed (ambiguous). Then its pairs are the paths found after "File:" and "Move to:" anywhere, with the input
#     "ilegible": pre-edit blocks if one is in a repo with rules.
# Return 1 if unusable.
kr_input() {
  local cwd ok x
  [ ! -t 0 ] || return 1
  KR_JSON="$(cat)"; KR_CWD=""; KR_SID=""; KR_ACTIVO=""; KR_PARCHE=""; KR_AGENTE=""; KR_EVENTO=""; KR_TURN_ID=""
  KR_ITEMS=(); ok=""
  { IFS= read -r -d '' cwd; IFS= read -r -d '' KR_SID; IFS= read -r -d '' KR_ACTIVO; IFS= read -r -d '' KR_PARCHE
    IFS= read -r -d '' KR_AGENTE; IFS= read -r -d '' KR_EVENTO; IFS= read -r -d '' KR_TURN_ID
    IFS= read -r -d '' ok; while IFS= read -r -d '' x; do KR_ITEMS+=("$x"); done; } < <(
    printf '%s' "$KR_JSON" | jq -j '
      def s: if type == "string" then . else "" end;
      def lineas: map(. + "\n") | join("");
      def ultimo(f): .fs[(.fs | length) - 1] |= f;
      def hunk(f): (if (.h | length) == 0 then .h = [{o: [], n: []}] else . end) | .h[(.h | length) - 1] |= f;
      def tr: sub("^\\s+"; "") | sub("\\s+$"; "");
      def marca: . == "*** Begin Patch" or . == "*** End Patch" or . == "*** End of File"
        or test("^\\*\\*\\* (Add|Update|Delete) File:") or test("^\\*\\*\\* Move to:");
      def marcador($t; $op):
        if $t == "*** Begin Patch" or $t == "*** End of File" then .
        elif $t == "*** End Patch" then .fin = true
        elif ($t | test("^\\*\\*\\* (Add|Update|Delete) File:")) then
          ($t | capture("^\\*\\*\\* (?<op>[A-Za-z]+) File:(?<p>.*)$")) as $c | ($c.p | tr) as $p
          | if $p == "" then .mal = true else .fs += [{op: $c.op, p: $p, mv: null, add: [], h: []}] end
        elif ($t | test("^\\*\\*\\* Move to:")) then
          ($t | sub("^\\*\\*\\* Move to:"; "") | tr) as $p
          | if $op != "Update" or .fs[-1].mv != null or $p == "" then .mal = true else ultimo(.mv = $p) end
        elif $t == "" and $op != "Add" then .
        else .mal = true end;
      def parche: (split("\r\n") | join("\n") | split("\n") | if .[-1] == "" then .[:-1] else . end) as $ls
        | reduce $ls[] as $l ({fs: [], fin: false, mal: false}; ($l | tr) as $t | (.fs[-1].op // "") as $op |
        if .mal then .
        elif .fin then (if $t != "" then .mal = true else . end)
        elif $op == "Add" and ($l | startswith("+")) then ultimo(.add += [$l[1:]])
        elif $op == "Update" and $l == "" then ultimo(hunk(.o += [""] | .n += [""]))
        elif $op == "Update" and ($l | startswith(" ")) then
          (if ($t | marca) then .mal = true else ($l[1:]) as $x | ultimo(hunk(.o += [$x] | .n += [$x])) end)
        elif $op == "Update" and ($l | startswith("+")) then ultimo(hunk(.n += [$l[1:]]))
        elif $op == "Update" and ($l | startswith("-")) then ultimo(hunk(.o += [$l[1:]]))
        elif $op == "Update" and ($l | startswith("@@")) then ultimo(.h += [{o: [], n: []}])
        else marcador($t; $op) end)
        | if .mal then
            $ls[] | (capture("(File|Move to):(?<p>.*)$") // empty) | .p | tr | select(. != "")
            | ., "\u0000", "\"ilegible\"", "\u0000"
          else
            .fs[] | (if .op == "Add" then {content: (.add | lineas)}
                     elif .op == "Update" then {edits: [.h[] | {old_string: (.o | lineas), new_string: (.n | lineas)}]}
                     else {} end) as $i
            | (.p, (.mv | values)) | select(. != "") | ., "\u0000", ({tool_input: ($i + {file_path: .})} | tojson), "\u0000"
          end;
      (.tool_input | if type == "object" then . else {} end) as $i |
      (.cwd | s), "\u0000", (.session_id | s), "\u0000", (if .stop_hook_active == true then "1" else "" end), "\u0000",
      (if .tool_name == "apply_patch" then "1" else "" end), "\u0000", (.agent_id | s), "\u0000",
      (.hook_event_name | s), "\u0000", (.turn_id | s), "\u0000", "ok", "\u0000",
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

# kr_root: KR_ROOT and KR_COMMON (git common dir, physical) of the marked repo of KR_CWD (its own, or the nearest
# marked one that contains it: _kr_marcado). Return non-zero outside git or without a marked repo.
kr_root() { _kr_marcado "$KR_CWD"; }

# _kr_git <dir>: KR_ROOT and KR_COMMON (physical) of the repo of <dir> (cached for the last <dir>). Return 0 when that
# repo has .agents-kit.json, 3 when it has not, 1 outside git, 2 when its git common dir cannot be entered (KR_ROOT is
# set, KR_COMMON empty: pre-edit blocks if that repo has rules, nothing runs).
_kr_git() {
  local out top common
  if [ "$1" != "${_KR_GIT_DIR-}" ]; then
    _KR_GIT_DIR="$1"; _KR_GIT_OUT=""; _KR_GIT_RC=1
    out="$(git -C "$1" rev-parse --show-toplevel --git-common-dir 2>/dev/null)" || out=""
    top="${out%%$'\n'*}"; common="${out#*$'\n'}"
    if [ -n "$out" ] && [ -n "$top" ]; then
      case "$common" in /*) ;; *) common="$1/$common" ;; esac
      if common="$(cd "$common" 2>/dev/null && pwd -P)" && [ -n "$common" ]; then _KR_GIT_RC=0
      else common=""; _KR_GIT_RC=2; fi
      _KR_GIT_OUT="$top"$'\n'"$common"
    fi
  fi
  [ $_KR_GIT_RC -ne 1 ] || return 1
  out="$_KR_GIT_OUT"
  KR_ROOT="${out%%$'\n'*}"; KR_COMMON="${out#*$'\n'}"
  [ $_KR_GIT_RC -eq 0 ] || return 2
  [ -f "$KR_ROOT/.agents-kit.json" ] || return 3
}

# _kr_marcado <dir>: like _kr_git, but when the repo of <dir> has no marker it climbs to the repos that contain it (the
# toplevel of the parent of each toplevel: a nested repo or a submodule) and keeps the nearest marked one. Return 0
# with KR_ROOT/KR_COMMON of that repo, 1 when there is none, 2 as _kr_git.
_kr_marcado() {
  local rc prev
  _kr_git "$1"; rc=$?
  while [ $rc -eq 3 ]; do
    prev="$KR_ROOT"
    [ "${prev%/*}" != "" ] || return 1
    _kr_git "${prev%/*}"; rc=$?
    [ $rc -ne 3 ] || [ "$KR_ROOT" != "$prev" ] || return 1
  done
  return $rc
}

# kr_confianza: return 0 when KR_COMMON is the git common dir of the cwd's repo (kr_cwd_common) and KR_ROOT is its
# toplevel or one of the worktrees `git worktree list` registers for it: the same clone, so its worktrees (kit-run)
# count, and foreign repos or a directory with a .git file pointing at the clone's git dir do not. Only trusted repos get their lint commands
# run (post-edit, stop-check) or noted for the session (kr_apunta). Outside git, nothing is trusted.
kr_confianza() {
  local p
  kr_cwd_common && [ -n "$KR_COMMON" ] && [ "$KR_COMMON" = "$KR_CWD_COMMON" ] || return 1
  [ "$KR_ROOT" != "$KR_CWD_ROOT" ] || return 0
  while IFS= read -r p; do
    case "$p" in "worktree "/*) p="${p#worktree }" ;; *) continue ;; esac
    [ "$p" = "$KR_ROOT" ] && return 0
    [ "$(cd "$p" 2>/dev/null && pwd -P)" = "$KR_ROOT" ] && return 0
  done < <(git -C "$KR_CWD_ROOT" worktree list --porcelain 2>/dev/null)
  return 1
}

# kr_cwd_common: KR_CWD_ROOT and KR_CWD_COMMON (physical), the toplevel and git common dir of the repo of KR_CWD, or
# of the nearest marked repo that contains it when that one has no marker (looked up once). Return 1 outside git.
kr_cwd_common() {
  local root="${KR_ROOT-}" common="${KR_COMMON-}" rc
  if [ -z "${KR_CWD_COMMON+x}" ]; then
    KR_CWD_COMMON=""; KR_CWD_ROOT=""
    _kr_git "$KR_CWD"; rc=$?
    [ $rc -ne 3 ] || { _kr_marcado "$KR_CWD" || _kr_git "$KR_CWD"; rc=$?; }
    if [ $rc -eq 0 ] || [ $rc -eq 3 ]; then KR_CWD_ROOT="$KR_ROOT"; KR_CWD_COMMON="$KR_COMMON"; fi
    KR_ROOT="$root"; KR_COMMON="$common"
  fi
  [ -n "$KR_CWD_COMMON" ]
}

# kr_abs: KR_ABS, KR_FILE made absolute against KR_CWD and normalized without touching the disk ('.' and '..' as
# path.resolve does), so the path checked is the one the tool writes. Return 1 without a path.
kr_abs() {
  local p="$KR_FILE" out="" seg segs
  [ -n "$p" ] || return 1
  case "$p" in /*) ;; *) p="$KR_CWD/$p" ;; esac
  IFS=/ read -r -d '' -a segs < <(printf '%s' "$p")
  for seg in "${segs[@]}"; do
    case "$seg" in ''|.) ;; ..) out="${out%/*}" ;; *) out="$out/$seg" ;; esac
  done
  KR_ABS="${out:-/}"
}

# kr_item <path>: KR_ROOT, KR_COMMON and KR_REL for one file of the input. The repo is the one of the file (of its
# nearest existing directory; _kr_marcado), not the cwd's: kit-run edits in worktrees outside the session's cwd.
# Return 0 to check it; 1 to skip it (no path, outside git, no marked repo, or a symlink whose target is outside that
# repo); 2 when its path inside a marked repo cannot be resolved, also when its nearest existing directory cannot be
# entered (the caller blocks if that repo has rules).
kr_item() {
  local d f rc
  KR_FILE="$1"
  kr_abs || return 1
  d="${KR_ABS%/*}"
  while [ -n "$d" ] && [ ! -d "$d" ]; do d="${d%/*}"; done
  if ! f="$(cd "${d:-/}" 2>/dev/null && pwd -P)"; then
    while [ -n "$d" ] && ! f="$(cd "$d" 2>/dev/null && pwd -P)"; do d="${d%/*}"; done
    _kr_marcado "${f:-/}"; rc=$?
    [ $rc -eq 1 ] || [ $rc -eq 3 ] || return 2
    return 1
  fi
  _kr_marcado "$f"; rc=$?
  [ $rc -ne 2 ] || return 2
  [ $rc -eq 0 ] || return 1
  kr_resolve
}

# kr_apunta: when the repo of the item (KR_ROOT) does not contain KR_CWD and is trusted (kr_confianza), note it in
# the session's file (kr_sesion_fichero) so stop-check also checks it. Nothing without a session_id.
kr_apunta() {
  local f nuevo=""
  case "$KR_CWD/" in "$KR_ROOT"/*) return 0 ;; esac
  [ -n "$KR_SID" ] && kr_confianza && f="$(kr_sesion_fichero sesion)" || return 0
  [ -e "$f" ] || nuevo=1
  grep -qxF -- "$KR_ROOT" "$f" 2>/dev/null || printf '%s\n' "$KR_ROOT" >> "$f"
  [ -z "$nuevo" ] || kr_sesion_limpia
}

# Session file lines (kr_sesion_fichero sesion): "<root>" (kr_apunta), "<root><tab>f<tab><ruta>" (a file the session
# edited through a tool, kr_anota), "<root><tab>base" and "<root><tab>b<tab><hash>  <ruta>" (the baseline of the cwd's
# root, written by hooks/session-start: it exists, and a file that was already changed when the session started,
# with its git hash-object). The file
# kr_sesion_fichero inicio (mtime = when the session started) is touched by hooks/session-start too.

# kr_sucios: KR_SUC, the changed files of KR_ROOT that exist (git diff --name-only HEAD plus untracked files not
# ignored), and KR_HASH, the git hash-object of each of them, in the same order (one git hash-object --stdin-paths;
# empty for a name with a tab or a newline).
kr_sucios() {
  local p h i=0 j=0 lista=() hs=()
  KR_SUC=(); KR_HASH=()
  while IFS= read -r -d '' p; do
    [ -f "$KR_ROOT/$p" ] || continue
    KR_SUC+=("$p")
    case "$p" in *$'\t'*|*$'\n'*) ;; *) lista+=("$p") ;; esac
  done < <(git -C "$KR_ROOT" diff --name-only --no-renames -z HEAD -- 2>/dev/null
           git -C "$KR_ROOT" ls-files --others --exclude-standard -z 2>/dev/null)
  if [ ${#lista[@]} -gt 0 ]; then
    while IFS= read -r h; do hs+=("$h"); done < <(printf '%s\n' "${lista[@]}" \
      | git -C "$KR_ROOT" hash-object --stdin-paths 2>/dev/null)
  fi
  while [ $i -lt ${#KR_SUC[@]} ]; do
    h=""
    case "${KR_SUC[$i]}" in *$'\t'*|*$'\n'*) ;; *) h="${hs[$j]-}"; j=$((j + 1)) ;; esac
    KR_HASH+=("$h"); i=$((i + 1))
  done
}

# kr_anota: note the file KR_REL of KR_ROOT for this session ("f" line), so stop-check checks what this session did
# and not the half-done files of other sessions in the same clone. A name with a tab or a newline is noted as "*"
# (all the changed files of that repo). Nothing without a session_id; the caller checks the trust first
# (kr_confianza), and stop-check checks it again for every noted root.
kr_anota() {
  local f i l rel="$KR_REL" nuevo=""
  [ -n "$KR_SID" ] && f="$(kr_sesion_fichero sesion)" || return 0
  case "$rel" in *$'\t'*|*$'\n'*) rel='*' ;; esac
  l="$KR_ROOT"$'\t'"f"$'\t'"$rel"
  [ -e "$f" ] || nuevo=1
  # a subagent whose SubagentStart did not run (the kit installed halfway): its start is its first edit
  if [ -n "${KR_AGENTE-}" ] && i="$(kr_sesion_fichero inicio)" && [ ! -e "$i" ]; then : > "$i"; fi
  grep -qxF -- "$l" "$f" 2>/dev/null || printf '%s\n' "$l" >> "$f"
  [ -z "$nuevo" ] || kr_sesion_limpia
}

# kr_base: at the start of a session (hooks/session-start) or of a subagent (hooks/subagent-start, with KR_AGENTE),
# with KR_SID and KR_ROOT set, touch the session's
# "inicio" file and write the baseline of KR_ROOT (kr_sucios), each only when it does not exist yet for this session
# (resume, clear, compact and fork start it again with the same session_id).
kr_base() {
  local f i x
  [ -n "$KR_SID" ] && f="$(kr_sesion_fichero sesion)" && i="$(kr_sesion_fichero inicio)" || return 0
  [ -e "$i" ] || : > "$i"
  if [ -e "$f" ]; then
    grep -qxF -- "$KR_ROOT"$'\t'base "$f" 2>/dev/null && return 0
  fi
  kr_sucios
  printf '%s\tbase\n' "$KR_ROOT" >> "$f"
  x=0
  while [ $x -lt ${#KR_SUC[@]} ]; do
    [ -z "${KR_HASH[$x]}" ] || printf '%s\tb\t%s  %s\n' "$KR_ROOT" "${KR_HASH[$x]}" "${KR_SUC[$x]}"
    x=$((x + 1))
  done >> "$f"
  kr_sesion_limpia
}

# kr_sesion_dir: print ${TMPDIR:-/tmp}/agents-kit-<uid>, created with mode 0700. Return 1 (nothing that depends on it
# may run) when it exists but is a symlink, is not ours or has another mode.
kr_sesion_dir() {
  local d="${TMPDIR:-/tmp}"
  d="${d%/}/agents-kit-$(id -u)"
  [ -e "$d" ] || [ -L "$d" ] || mkdir -m 700 "$d" 2>/dev/null
  [ -d "$d" ] && [ ! -L "$d" ] && [ -O "$d" ] || return 1
  [ -n "$(find "$d" -maxdepth 0 -perm 700 2>/dev/null)" ] || return 1
  printf '%s\n' "$d"
}

# kr_sesion_fichero <qué>: print <kr_sesion_dir>/<qué>-<sha256 of the session_id ("-" without one)>, followed by
# -<sha256 of the agent_id> in the hooks of a subagent (KR_AGENTE): a subagent notes its edits, keeps its start and
# baseline and counts its blocks apart from the main session, so the Stop of the main session leaves them to the
# subagent's SubagentStop, and the files of one session and its subagents share a prefix (stop-check: "familia").
# Return 1 when the directory is not reliable or the file exists and is a symlink or not ours.
kr_sesion_fichero() {
  local d h a f
  d="$(kr_sesion_dir)" || return 1
  h="$(printf '%s' "${KR_SID:--}" | shasum -a 256 2>/dev/null)"; h="${h%% *}"
  [ ${#h} -eq 64 ] || return 1
  if [ -n "${KR_AGENTE-}" ]; then
    a="$(printf '%s' "$KR_AGENTE" | shasum -a 256 2>/dev/null)"; a="${a%% *}"
    [ ${#a} -eq 64 ] || return 1
    h="$h-$a"
  fi
  f="$d/$1-$h"
  [ ! -L "$f" ] || return 1
  [ ! -e "$f" ] || { [ -f "$f" ] && [ -O "$f" ]; } || return 1
  printf '%s\n' "$f"
}

# kr_sesion_limpia: remove the session files older than 7 days (when a new one is written).
kr_sesion_limpia() {
  local d
  d="$(kr_sesion_dir)" && find "$d" -type f -mtime +7 -delete 2>/dev/null
  return 0
}

# kr_resolve: KR_REL, KR_ABS relative to KR_ROOT (KR_ABS may not exist yet). Symlinks in the existing part are
# resolved, and so is a last component that is a symlink (up to 8 levels). Return 1 when the result is outside the
# repo, 2 when it cannot be resolved (more levels, an unreadable directory). On macOS (case-insensitive file
# systems) the root is compared without case.
kr_resolve() {
  local p="$KR_ABS" d rest i=0 t
  [ -n "$p" ] || return 2
  while :; do
    d="${p%/*}"; rest="${p##*/}"
    while [ -n "$d" ] && [ ! -d "$d" ]; do rest="${d##*/}/$rest"; d="${d%/*}"; done
    case "/$rest/" in */../*|*/./*|//) return 2 ;; esac
    d="$(cd "${d:-/}" 2>/dev/null && pwd -P)" || return 2
    p="${d%/}/$rest"
    [ -L "$p" ] && [ $i -lt 8 ] || break
    t="$(readlink "$p")" || return 2
    case "$t" in /*) p="$t" ;; *) p="${p%/*}/$t" ;; esac
    i=$((i + 1))
  done
  [ ! -L "$p" ] || return 2
  case "$OSTYPE" in darwin*) shopt -s nocasematch ;; esac
  [[ "$p" == "$KR_ROOT"/?* ]]; t=$?
  shopt -u nocasematch
  [ $t -eq 0 ] || return 1
  KR_REL="${p:$((${#KR_ROOT} + 1))}"
}

# kr_proyecto <rel>: KR_PROY, the TS project of the file <rel> (relative to KR_ROOT): the nearest directory going up,
# below the root, with package.json and tsconfig.json (the projects of scripts/kit-reglas.sh estado); empty for a file
# of the root or of no project, and for anything under node_modules. Its lint runs inside it (kr_lint with KR_DIR):
# its suppressions, tsc baseline and binaries are relative to it, and parsers like Astro's load typescript from the cwd.
kr_proyecto() {
  local d="$1"
  KR_PROY=""
  case "/$d" in */node_modules/*) return 0 ;; esac
  while :; do
    case "$d" in */*) d="${d%/*}" ;; *) return 0 ;; esac
    if [ -f "$KR_ROOT/$d/package.json" ] && [ -f "$KR_ROOT/$d/tsconfig.json" ]; then KR_PROY="$d"; return 0; fi
  done
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

# kr_lint <tope> <qué> <comando> [args...]: run `<comando> <args>` from KR_DIR (a TS project of KR_ROOT, or KR_ROOT
# when empty) under the lock of KR_ROOT's clone (taken with <tope> on
# the first call; later calls reuse it) and return: 2 with the output on stderr when it fails; 0 when it passes, the
# lock is busy, the tool is missing (126/127) or it times out.
kr_lint() {
  local t="$1" what="$2" cmd="$3" rc; shift 3
  [ -n "${KR_LOCK_OK:-}" ] || { kr_lock "$t" || return 0; KR_LOCK_OK=1; }
  kit_run_timeout "${KR_DIR:-$KR_ROOT}" "$t" /bin/sh -c "$cmd \"\$@\"" kit-lint "$@"; rc=$?
  case $rc in
    0) return 0 ;;
    126|127) echo "agents-kit: el lint no se pudo ejecutar ($cmd, exit $rc); no bloquea" >&2; return 0 ;;
    142) echo "agents-kit: el lint pasó de $t s ($cmd); no bloquea" >&2; return 0 ;;
  esac
  kr_recorta
  printf 'El lint falla en %s (%s, exit %s). Arréglalo:\n%s\n' "$what" "$cmd" "$rc" "$KR_SALIDA" >&2
  return 2
}

# kr_recorta: KR_SALIDA, KIT_HOOK_OUT for the agent. With more than KIT_LINT_LINEAS lines (40), only the first three
# quarters and the last quarter (the summary of tools like ESLint, with their --fix hint), with the number of lines
# left out and the path of a file with the whole output (in kr_sesion_dir, removed after 7 days like the session
# files; without it, only the number). Every line is cut at 400 characters (minified code). The agent fixes what it
# sees and the next check shows the rest; Claude Code moves a hook text of more than 10,000 characters to a file.
kr_recorta() {
  local max n f="" d
  max="$(kr_tope "${KIT_LINT_LINEAS:-}" 40)"
  n="$(printf '%s\n' "$KIT_HOOK_OUT" | awk 'END { print NR }')"
  if [ "$n" -gt "$max" ] && d="$(kr_sesion_dir)" && f="$(mktemp "$d/lint-XXXXXX" 2>/dev/null)"; then
    printf '%s\n' "$KIT_HOOK_OUT" > "$f"
  else f=""; fi
  KR_SALIDA="$(printf '%s\n' "$KIT_HOOK_OUT" | awk -v max="$max" -v n="$n" -v f="$f" '
    function corta(l) { return length(l) > 400 ? substr(l, 1, 400) "..." : l }
    BEGIN { cab = max - int(max / 4) }
    n <= max || NR <= cab || NR > n - (max - cab) { print corta($0) }
    n > max && NR == cab + 1 {
      print "... (" n - max " líneas omitidas" (f == "" ? ")" : "; la salida completa está en " f ")") }')"
}
