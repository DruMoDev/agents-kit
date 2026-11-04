#!/usr/bin/env bash
# Usage: scripts/kit-reglas.sh <subcomando> <wt> [args...]
#   estado    <wt>
#   trinquete <wt> <ref>
#   blindado  <wt> <ref>
#   abrir     <wt> <session_id>
#   cerrar    <wt>
# Mechanical checks of the deterministic rules (lint, types, structure) for kit-pr.sh fusionar, the hooks and the
# kit-reglas skill. "Changed" is the working tree of <wt> (committed or not, plus untracked files not ignored) against
# git merge-base <ref> HEAD, without rename detection: a renamed file counts as its old path deleted. So it serves both
# fusionar (ref=origin/<base>, clean tree) and a local review (ref = the review base, or HEAD for only the uncommitted).
#   estado: one line per fact, for kit-reglas to propose what is missing: "lenguajes: ts,py,sh|ninguno",
#     "lint: declarado|sin declarar" (marker of <wt>), then each TS project ("." for the root, which is one when it has
#     tsconfig.json or typescript in its package.json; any other directory of the tree outside node_modules, when it
#     has both package.json and tsconfig.json) as "proyecto: <dir> (base completa|base incompleta)" followed by
#     "tsconfig: <flag> sí|no" for each flag of the base (grep over its tsconfig.json; "extends" is not followed),
#     "eslint: strictTypeChecked sí|no", "eslint: noInlineConfig sí|no" (grep over its eslint.config.*), "knip: sí|no"
#     and its "deuda-lint: <n> entradas|ninguna" (its eslint-suppressions.json, one entry per file and rule) and
#     "deuda-tsc: <n> ficheros|ninguna" (its .agents-kit/tsc-base.json). The root's debt lines always appear: right
#     after "lint:" when the root is not a TS project. FIN: base completa (lint declared and every project complete,
#     or no TS project) or FIN: base incompleta.
#   trinquete: exit 1 with one line per reason on stderr when a changed or deleted file still has entries in the
#     suppressions or the tsc baseline of the root or of a directory that contains it ("deuda en fichero tocado:
#     <ruta> (lint|tipos)"; the keys of a directory's debt files are relative to it), or when one of those files adds
#     a key or raises a count against the merge base ("la deuda crece: <ruta> <regla>|tipos (<fichero de deuda>)";
#     kit-pr.sh fusionar lets this one through with Dru's approval of the shielded diff, when it includes that debt
#     file). The directories checked are the root and those of every eslint-suppressions.json or
#     .agents-kit/tsc-base.json of the tree or changed. Paths are from the repo root. FIN: ok.
#   blindado: one line per changed shielded file and per package.json change that counts. The globs of .blindado come
#     from the marker of <ref>, never of the tree, and match the whole path as bash patterns ([[ == ]]: * crosses /,
#     so *tsconfig*.json also matches config/tsconfig.base.json); an entry ending in / is a prefix. A file that may live
#     in any directory goes as the pair x and */x (eslint.config.*, */eslint.config.*; .npmrc, */.npmrc), never *x,
#     which would also match any name ending in it (src/myknip.ts for *knip.*, foo.eslintignore for *.eslintignore).
#     A change that only shrinks an eslint-suppressions.json or .agents-kit/tsc-base.json (of the root or of a
#     directory) does not count. Lint
#     dependencies are those whose name contains eslint, typescript, knip or dependency-cruiser. Every package.json
#     of the repo outside node_modules (the root one and nested ones, versioned or new; a deleted or new file compares
#     against {}) gets the same comparison, and its lines start with its path: "package.json (...)" for the root one,
#     "web/package.json (...)" for a nested one. package.json lines:
#       "package.json (scripts.<x>)": a script of the shielded set changed. The set is the transitive closure, in the
#         base and in the tree (then joined), of the lint*/typecheck* scripts: each name brings its npm lifecycle
#         hooks pre<x>/post<x>, and every npm run <x>, pnpm [run] <x>, yarn [run] <x> or bun run <x> in the body of
#         any script of the set (hooks included) adds <x>, until nothing changes (cycles end there);
#       "package.json (quitada <dep>)" / "package.json (cambiada <dep>)": a lint dependency removed or with another
#         value (dependencies, devDependencies, peerDependencies, optionalDependencies);
#       "package.json (overrides <clave>)": overrides or resolutions changed for a key (nested keys joined with >)
#         that names a lint dependency;
#       "package.json (<clave>)": any change in eslintConfig, eslintIgnore, knip, pnpm (the whole object:
#         overrides, patchedDependencies, packageExtensions...), the top-level patchedDependencies or packageManager.
#     Then "hash: <sha256>" of the diff of those files (fixed options, without the user's git config) plus the
#     normalized fragment of each package.json that counts ("<ruta>TAB<json>", in path order), and FIN: <n>; FIN: 0
#     without hash if none.
#   abrir/cerrar: create (with <session_id>) or delete <git-common-dir>/agents-kit/reglas-abiertas, which lets the
#     pre-edit hook pass edits to shielded files. FIN: abierto / FIN: cerrado.
# Exit: 0 ok, 1 usage or rejected, 2 environment error.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/config.sh"
source "$here/lib/blindado.sh"

usage() { echo "uso: $0 estado <wt> | trinquete <wt> <ref> | blindado <wt> <ref> | abrir <wt> <session_id> | cerrar <wt>" >&2; exit 1; }
[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1"; shift
case "$sub" in
  estado|cerrar) [ $# -eq 1 ] || usage ;;
  trinquete|blindado|abrir) [ $# -eq 2 ] && [ -n "$2" ] || usage ;;
  *) usage ;;
esac
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
wt="$(cd "$1" && pwd)"; shift
kit_require_marker "$wt" || exit $?
command -v jq >/dev/null 2>&1 || { echo "error: falta 'jq' en el PATH" >&2; exit 2; }
cd "$wt" || exit 2

SUP=eslint-suppressions.json
TSB=.agents-kit/tsc-base.json
FLAGS="strict noUncheckedIndexedAccess exactOptionalPropertyTypes verbatimModuleSyntax noImplicitOverride noFallthroughCasesInSwitch"
LINT_DEP='eslint|typescript|knip|dependency-cruiser'
# PKG_JQ (jq -n, $b/$h = package.json of the base/tree, $re = LINT_DEP): the package.json changes that count, as
# {scripts, quitadas, cambiadas, overrides, claves}; each map part is {<clave>: {antes, ahora}} with only what differs
# (a missing value is null). Empty output when nothing counts.
PKG_JQ='
  def diffmap($x; $y): [($x + $y) | keys[] | select($x[.] != $y[.]) | {key: ., value: {antes: $x[.], ahora: $y[.]}}]
    | from_entries;
  def sobj: .scripts | if type == "object" then . else {} end;
  def hooks: map(., "pre" + ., "post" + .) | unique;
  # Names (without their hooks) reached from the lint*/typecheck* scripts; it only grows with names found in
  # script bodies, a finite set, so it always ends (also with cycles).
  def reach($s): (hooks | map($s[.] | strings | scan("(?:^|[\\s;&|(])(?:npm\\s+run(?:-script)?|pnpm(?:\\s+run)?|yarn(?:\\s+run)?|bun\\s+run)\\s+(?:-\\S+\\s+)*([^\\s;&|()]+)")[0])) as $c
    | ((. + $c) | unique) as $n | if $n == . then . else ($n | reach($s)) end;
  def closure: sobj as $s | [$s | keys[] | select(test("^(lint|typecheck)"))] | reach($s) | hooks;
  def deps: [.dependencies, .devDependencies, .peerDependencies, .optionalDependencies | objects | to_entries[]]
    | group_by(.key) | map({key: .[0].key, value: map(.value)}) | from_entries
    | with_entries(select(.key | test($re)));
  def ovr: [{s: "overrides", v: .overrides}, {s: "resolutions", v: .resolutions}]
    | map(.s as $s | .v | objects | paths(scalars) as $p | {key: ($p | map(tostring) | join(">")), value: {($s): getpath($p)}})
    | group_by(.key) | map({key: .[0].key, value: (map(.value) | add)}) | from_entries
    | with_entries(select(.key | test($re)));
  (($b | closure) + ($h | closure) | unique) as $ks |
  ($b | sobj) as $sb | ($h | sobj) as $sh |
  ($b | deps) as $db | ($h | deps) as $dh |
  {scripts: diffmap($sb | with_entries(select(.key | IN($ks[]))); $sh | with_entries(select(.key | IN($ks[])))),
   quitadas: [$db | keys[] | select($dh[.] == null)],
   cambiadas: diffmap($db | with_entries(select(.key | IN($dh | keys[]))); $dh | with_entries(select(.key | IN($db | keys[])))),
   overrides: diffmap($b | ovr; $h | ovr),
   claves: diffmap($b | {eslintConfig, eslintIgnore, knip, pnpm, patchedDependencies, packageManager};
    $h | {eslintConfig, eslintIgnore, knip, pnpm, patchedDependencies, packageManager})}
  | if [.[] | length] | add == 0 then empty else . end'

# json_tree <fichero>: print the file of the tree as a JSON object ({} if missing); return 2 if it is not one.
json_tree() {
  if [ ! -e "$1" ]; then echo '{}'; return 0; fi
  jq -ce 'if type == "object" then . else error end' "$1" 2>/dev/null || { echo "error: $1 no es un objeto JSON válido" >&2; return 2; }
}

# json_base <fichero>: same, for the file at the merge base $mb.
json_base() {
  git cat-file -e "$mb:$1" 2>/dev/null || { echo '{}'; return 0; }
  git show "$mb:$1" | jq -ce 'if type == "object" then . else error end' 2>/dev/null \
    || { echo "error: $1 de $mb no es un objeto JSON válido" >&2; return 2; }
}

# set_base <ref>: set $mb to git merge-base <ref> HEAD.
set_base() {
  mb="$(git merge-base "$1" HEAD 2>/dev/null)" || { echo "error: no pude calcular la base común de '$1' y HEAD" >&2; exit 2; }
}

# changed_list: NUL-separated paths changed in the tree against $mb (deleted ones included) plus untracked ones.
changed_list() {
  git --literal-pathspecs -c core.quotepath=false diff -z --name-only --no-renames "$mb" -- || return 2
  git --literal-pathspecs ls-files -z --others --exclude-standard || return 2
}

# list_changed: write changed_list to a new temp file ($lst, removed on exit); exit 2 if git fails, so the gate never
# fails open.
list_changed() {
  lst="$(mktemp)" || exit 2
  trap 'rm -f "$lst"' EXIT
  changed_list > "$lst" || { echo "error: no pude listar los ficheros cambiados (git falló)" >&2; exit 2; }
}

# tree_files: newline-separated paths of the tree (versioned plus untracked not ignored), outside node_modules.
tree_files() {
  { git -c core.quotepath=false ls-files --cached --others --exclude-standard || return 2; } | grep -v -E '(^|/)node_modules/' || :
}

# ts_projects: the TS projects of the tree, one directory per line ("." for the root), sorted. The root is one when it
# has tsconfig.json or typescript in its package.json dependencies; any other directory, when it has both package.json
# and tsconfig.json (versioned or new). A tsconfig.*.json or a tsconfig.json without its own package.json is not one.
ts_projects() {
  local pkg files
  pkg="$(json_tree package.json)" || return 2
  if [ -f tsconfig.json ] || jq -e '[.dependencies, .devDependencies, .peerDependencies] | map(objects | has("typescript")) | any' \
      <<<"$pkg" >/dev/null; then echo "."; fi
  files="$(tree_files)" || return 2
  printf '%s\n' "$files" | sed -n -E 's#^(.+)/(package|tsconfig)\.json$#\1 \2#p' | LC_ALL=C sort -u \
    | awk '{ d = $1; for (i = 2; i < NF; i++) d = d " " $i; n[d]++ } END { for (d in n) if (n[d] == 2) print d }' \
    | while IFS= read -r d; do [ -f "$d/package.json" ] && [ -f "$d/tsconfig.json" ] && echo "$d"; done | LC_ALL=C sort
}

# debt_dirs: the directories with debt files to check ("." always, plus each directory of an eslint-suppressions.json
# or .agents-kit/tsc-base.json of the tree or changed against $mb, from $lst), one per line, sorted.
debt_dirs() {
  local files
  files="$(tree_files)" || return 2
  { echo "."; { printf '%s\n' "$files"; tr '\0' '\n' < "$lst"; } | grep -v -E '(^|/)node_modules/' \
      | sed -n -E -e 's#^(.+)/eslint-suppressions\.json$#\1#p' -e 's#^(.+)/\.agents-kit/tsc-base\.json$#\1#p'; } | LC_ALL=C sort -u
}

# grows_sup / grows_tsb <dir>: print "<ruta>TAB<regla>" (the path from the repo root) for each key added or count
# raised against the merge base in the debt file of <dir> ("." for the root).
grows_sup() {
  local b h p=""; [ "$1" = . ] || p="$1/"
  b="$(json_base "$p$SUP")" || return 2; h="$(json_tree "$p$SUP")" || return 2
  jq -rn --argjson b "$b" --argjson h "$h" --arg p "$p" '$h | to_entries[] | .key as $f | (.value | objects | to_entries[]) |
    select((.value.count? // 0) > ($b[$f][.key]?.count? // -1)) | "\($p)\($f)\t\(.key)"'
}
grows_tsb() {
  local b h p=""; [ "$1" = . ] || p="$1/"
  b="$(json_base "$p$TSB")" || return 2; h="$(json_tree "$p$TSB")" || return 2
  jq -rn --argjson b "$b" --argjson h "$h" --arg p "$p" '$h | to_entries[] | select((.value // 0) > ($b[.key] // -1)) | "\($p)\(.key)\ttipos"'
}

# ts_checks <lint>: the checks of the base for the TS project in the current directory, one line each; return 1 if
# any says no (or <lint> is empty: the marker does not declare lint).
ts_checks() {
  local ok=0 flag k v f pkg
  [ -n "$1" ] || ok=1
  pkg="$(json_tree package.json)" || return 2
  for flag in $FLAGS; do
    if [ -f tsconfig.json ] && grep -Eq "\"$flag\"[[:space:]]*:[[:space:]]*true" tsconfig.json; then v="sí"; else v="no"; ok=1; fi
    echo "tsconfig: $flag $v"
  done
  for k in strictTypeChecked noInlineConfig; do
    v="no"
    for f in eslint.config.*; do [ -f "$f" ] && grep -q "$k" "$f" && v="sí"; done
    [ "$v" = "sí" ] || ok=1
    echo "eslint: $k $v"
  done
  v="no"
  for f in knip.json knip.jsonc knip.ts knip.config.*; do [ -f "$f" ] && v="sí"; done
  jq -e 'has("knip")' <<<"$pkg" >/dev/null && v="sí"
  [ "$v" = "sí" ] || ok=1
  echo "knip: $v"
  return $ok
}

# debt_lines: "deuda-lint:" and "deuda-tsc:" for the current directory.
debt_lines() {
  local j n
  j="$(json_tree "$SUP")" || return 2
  n="$(jq '[.[] | objects | length] | add // 0' <<<"$j")" || return 2
  if [ "$n" -gt 0 ]; then echo "deuda-lint: $n entradas"; else echo "deuda-lint: ninguna"; fi
  j="$(json_tree "$TSB")" || return 2
  n="$(jq 'length' <<<"$j")" || return 2
  if [ "$n" -gt 0 ]; then echo "deuda-tsc: $n ficheros"; else echo "deuda-tsc: ninguna"; fi
}

case "$sub" in
  estado)
    projs="$(ts_projects)" || { echo "error: no pude listar los proyectos TS (git falló)" >&2; exit 2; }
    langs=""
    [ -n "$projs" ] && langs="ts"
    [ -f pyproject.toml ] && langs="${langs:+$langs,}py"
    [ -n "$(git ls-files -- '*.sh')" ] && langs="${langs:+$langs,}sh"
    echo "lenguajes: ${langs:-ninguno}"
    l="$(kit_config "$wt" 'if .lint == null then "" else "sí" end')" || exit 2
    completa=1
    if [ -n "$l" ]; then echo "lint: declarado"; else echo "lint: sin declarar"; fi
    # The root's debt goes first when the root is not a TS project; each project prints its own after its checks.
    case "$projs" in .|.$'\n'*) ;; *) debt_lines || exit 2 ;; esac
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      blk="$(cd "$d" || exit 2; ts_checks "$l")"; rc=$?
      [ $rc -le 1 ] || exit 2
      if [ $rc -eq 0 ]; then echo "proyecto: $d (base completa)"; else echo "proyecto: $d (base incompleta)"; completa=0; fi
      printf '%s\n' "$blk"
      (cd "$d" || exit 2; debt_lines) || exit 2
    done <<<"$projs"
    if [ $completa -eq 1 ]; then echo "FIN: base completa"; else echo "FIN: base incompleta"; fi
    ;;

  trinquete)
    set_base "$1"
    list_changed
    dirs="$(debt_dirs)" || { echo "error: no pude listar los ficheros de deuda (git falló)" >&2; exit 2; }
    motivos=""
    while IFS= read -r d; do
      p=""; [ "$d" = . ] || p="$d/"
      sup="$(json_tree "$p$SUP")" || exit 2; tsb="$(json_tree "$p$TSB")" || exit 2
      while IFS= read -r -d '' f; do
        case "$f" in "$p"*) ;; *) continue ;; esac
        jq -e --arg f "${f#"$p"}" 'has($f)' <<<"$sup" >/dev/null && motivos="$motivos"$'\n'"deuda en fichero tocado: $f (lint)"
        jq -e --arg f "${f#"$p"}" 'has($f)' <<<"$tsb" >/dev/null && motivos="$motivos"$'\n'"deuda en fichero tocado: $f (tipos)"
      done < "$lst"
      c1="$(grows_sup "$d")" || exit 2; c2="$(grows_tsb "$d")" || exit 2
      crece="$(printf '%s\n' "$c1" | sed '/^$/d' | sed "s#\$# ($p$SUP)#"; printf '%s\n' "$c2" | sed '/^$/d' | sed "s#\$# ($p$TSB)#")"
      crece="$(printf '%s\n' "$crece" | sed '/^$/d' | tr '\t' ' ')"
      [ -z "$crece" ] || motivos="$motivos"$'\n'"$(sed 's/^/la deuda crece: /' <<<"$crece")"
    done <<<"$dirs"
    if [ -n "$motivos" ]; then printf '%s\n' "${motivos#$'\n'}" >&2; exit 1; fi
    echo "FIN: ok"
    ;;

  blindado)
    ref="$1"
    set_base "$ref"
    globs="$(kit_config_base "$wt" '.blindado // [] | .[]' "$ref")" || exit 2
    list_changed
    lista=(); nuevos=(); total=0
    while IFS= read -r -d '' f; do
      kit_blindado_match "$f" "$globs" || continue
      case "$f" in
        "$SUP"|*/"$SUP") d="${f%"$SUP"}"; d="${d%/}"; c="$(grows_sup "${d:-.}")" || exit 2; [ -n "$c" ] || continue ;;
        "$TSB"|*/"$TSB") d="${f%"$TSB"}"; d="${d%/}"; c="$(grows_tsb "${d:-.}")" || exit 2; [ -n "$c" ] || continue ;;
      esac
      echo "$f"; total=$((total + 1))
      if git cat-file -e "$mb:$f" 2>/dev/null || git --literal-pathspecs ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
        lista+=("$f")
      else
        nuevos+=("$f")
      fi
    done < "$lst"
    # Each package.json changed (or deleted, or new) outside node_modules, in path order; its fragment line is
    # "<ruta>TAB<json>" so the path is in the hash.
    frag=""
    while IFS= read -r -d '' f; do
      case "$f" in package.json|*/package.json) ;; *) continue ;; esac
      case "/$f" in */node_modules/*) continue ;; esac
      pb="$(json_base "$f")" || exit 2; ph="$(json_tree "$f")" || exit 2
      pf="$(jq -cnS --argjson b "$pb" --argjson h "$ph" --arg re "$LINT_DEP" "$PKG_JQ")" \
        || { echo "error: no pude comparar $f" >&2; exit 2; }
      [ -n "$pf" ] || continue
      jq -r --arg p "$f" '(.scripts | keys[] | "\($p) (scripts.\(.))"), (.quitadas[] | "\($p) (quitada \(.))"),
        (.cambiadas | keys[] | "\($p) (cambiada \(.))"), (.overrides | keys[] | "\($p) (overrides \(.))"),
        (.claves | keys[] | "\($p) (\(.))")' <<<"$pf"
      total=$((total + $(jq '[.[] | length] | add' <<<"$pf")))
      frag="$frag$f"$'\t'"$pf"$'\n'
    done < <(LC_ALL=C sort -zu "$lst")
    if [ $total -gt 0 ]; then
      # Fixed diff options, without global or system git config, so the hash does not depend on the user's setup.
      # -O/dev/null overrides a repo diff.orderFile (an empty diff.orderFile= makes git fail).
      dif=""
      if [ ${#lista[@]} -gt 0 ]; then
        dif="$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git --literal-pathspecs -c core.quotepath=false \
          -c diff.interHunkContext=0 -c diff.suppressBlankEmpty=false diff -O/dev/null --no-ext-diff --no-textconv --no-color \
          --binary --full-index --no-renames -U3 --diff-algorithm=myers --indent-heuristic --src-prefix=a/ --dst-prefix=b/ "$mb" -- "${lista[@]}")" \
          || { echo "error: git diff falló" >&2; exit 2; }
      fi
      for f in ${nuevos[@]+"${nuevos[@]}"}; do
        o="$(git hash-object -- "$f")" || { echo "error: no pude leer $f" >&2; exit 2; }
        dif="$dif"$'\n'"nuevo $f $o"
      done
      h="$(printf '%s\n%s\n' "$dif" "$frag" | shasum -a 256 | cut -d' ' -f1)"
      [ ${#h} -eq 64 ] || { echo "error: shasum falló" >&2; exit 2; }
      echo "hash: $h"
    fi
    echo "FIN: $total"
    ;;

  abrir|cerrar)
    d="$(git rev-parse --git-common-dir 2>/dev/null)" || { echo "error: '$wt' no es un repo git" >&2; exit 2; }
    case "$d" in /*) ;; *) d="$wt/$d" ;; esac
    d="$d/agents-kit"
    if [ "$sub" = abrir ]; then
      mkdir -p "$d" && printf '%s\n' "$1" > "$d/reglas-abiertas" || { echo "error: no se pudo escribir $d/reglas-abiertas" >&2; exit 2; }
      echo "FIN: abierto"
    else
      rm -f "$d/reglas-abiertas" || { echo "error: no se pudo borrar $d/reglas-abiertas" >&2; exit 2; }
      echo "FIN: cerrado"
    fi
    ;;
esac
