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
# fusionar (ref=origin/<base>, clean tree) and a local review (ref=HEAD).
#   estado: one line per fact, for kit-reglas to propose what is missing: "lenguajes: ts,py,sh|ninguno",
#     "lint: declarado|sin declarar" (marker of <wt>), and with ts: "tsconfig: <flag> sí|no" for each flag of the base
#     (grep over tsconfig.json; "extends" is not followed), "eslint: strictTypeChecked sí|no", "eslint: noInlineConfig
#     sí|no" (grep over eslint.config.*), "knip: sí|no"; always "deuda-lint: <n> entradas|ninguna" (eslint-suppressions
#     .json, one entry per file and rule) and "deuda-tsc: <n> ficheros|ninguna" (.agents-kit/tsc-base.json).
#     FIN: base completa (lint declared and every ts line says sí, or no ts) or FIN: base incompleta.
#   trinquete: exit 1 with one line per reason on stderr when a changed or deleted file still has entries in the
#     suppressions or the tsc baseline of the tree ("deuda en fichero tocado: <ruta> (lint|tipos)"), or when either
#     file adds a key or raises a count against the merge base ("la deuda crece: <ruta> <regla>|tipos"). FIN: ok.
#   blindado: one line per changed shielded file and per package.json change that counts. The globs of .blindado come
#     from the marker of <ref>, never of the tree, and match the whole path as bash patterns ([[ == ]]: * crosses /,
#     so *tsconfig*.json also matches config/tsconfig.base.json); an entry ending in / is a prefix. A change that only
#     shrinks eslint-suppressions.json or .agents-kit/tsc-base.json does not count. Lint dependencies are those whose
#     name contains eslint, typescript, knip or dependency-cruiser. package.json lines:
#       "package.json (scripts.<x>)": a lint*/typecheck* script changed, or a script one of them calls (one level:
#         npm run <x>, pnpm [run] <x>, yarn [run] <x>, bun run <x>, in the base or the tree);
#       "package.json (quitada <dep>)" / "package.json (cambiada <dep>)": a lint dependency removed or with another
#         value (dependencies, devDependencies, peerDependencies, optionalDependencies);
#       "package.json (overrides <clave>)": overrides, resolutions or pnpm.overrides changed for a key (nested keys
#         joined with >) that names a lint dependency.
#     Then "hash: <sha256>" of the diff of those files (fixed options, without the user's git config) plus the
#     normalized package.json fragment, and FIN: <n>; FIN: 0 without hash if none.
#   abrir/cerrar: create (with <session_id>) or delete <git-common-dir>/agents-kit/reglas-abiertas, which lets the
#     pre-edit hook pass edits to shielded files. FIN: abierto / FIN: cerrado.
# Exit: 0 ok, 1 usage or rejected, 2 environment error.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/config.sh"

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

# grows_sup / grows_tsb: print "<ruta>TAB<regla>" for each key added or count raised against the merge base.
grows_sup() {
  local b h
  b="$(json_base "$SUP")" || return 2; h="$(json_tree "$SUP")" || return 2
  jq -rn --argjson b "$b" --argjson h "$h" '$h | to_entries[] | .key as $f | (.value | objects | to_entries[]) |
    select((.value.count? // 0) > ($b[$f][.key]?.count? // -1)) | "\($f)\t\(.key)"'
}
grows_tsb() {
  local b h
  b="$(json_base "$TSB")" || return 2; h="$(json_tree "$TSB")" || return 2
  jq -rn --argjson b "$b" --argjson h "$h" '$h | to_entries[] | select((.value // 0) > ($b[.key] // -1)) | "\(.key)\ttipos"'
}

case "$sub" in
  estado)
    langs=""
    pkg="$(json_tree package.json)" || exit 2
    if [ -f tsconfig.json ] || jq -e '[.dependencies, .devDependencies, .peerDependencies] | map(objects | has("typescript")) | any' \
        <<<"$pkg" >/dev/null; then langs="ts"; fi
    [ -f pyproject.toml ] && langs="${langs:+$langs,}py"
    [ -n "$(git ls-files -- '*.sh')" ] && langs="${langs:+$langs,}sh"
    echo "lenguajes: ${langs:-ninguno}"
    l="$(kit_config "$wt" 'if .lint == null then "" else "sí" end')" || exit 2
    completa=1
    if [ -n "$l" ]; then echo "lint: declarado"; else echo "lint: sin declarar"; fi
    case ",$langs," in
      *,ts,*)
        [ -n "$l" ] || completa=0
        for flag in $FLAGS; do
          if [ -f tsconfig.json ] && grep -Eq "\"$flag\"[[:space:]]*:[[:space:]]*true" tsconfig.json; then v="sí"; else v="no"; completa=0; fi
          echo "tsconfig: $flag $v"
        done
        for k in strictTypeChecked noInlineConfig; do
          v="no"
          for f in eslint.config.*; do [ -f "$f" ] && grep -q "$k" "$f" && v="sí"; done
          [ "$v" = "sí" ] || completa=0
          echo "eslint: $k $v"
        done
        v="no"
        for f in knip.json knip.jsonc knip.ts knip.config.*; do [ -f "$f" ] && v="sí"; done
        jq -e 'has("knip")' <<<"$pkg" >/dev/null && v="sí"
        [ "$v" = "sí" ] || completa=0
        echo "knip: $v"
        ;;
    esac
    j="$(json_tree "$SUP")" || exit 2
    n="$(jq '[.[] | objects | length] | add // 0' <<<"$j")" || exit 2
    if [ "$n" -gt 0 ]; then echo "deuda-lint: $n entradas"; else echo "deuda-lint: ninguna"; fi
    j="$(json_tree "$TSB")" || exit 2
    n="$(jq 'length' <<<"$j")" || exit 2
    if [ "$n" -gt 0 ]; then echo "deuda-tsc: $n ficheros"; else echo "deuda-tsc: ninguna"; fi
    if [ $completa -eq 1 ]; then echo "FIN: base completa"; else echo "FIN: base incompleta"; fi
    ;;

  trinquete)
    set_base "$1"
    sup="$(json_tree "$SUP")" || exit 2; tsb="$(json_tree "$TSB")" || exit 2
    list_changed
    motivos=""
    while IFS= read -r -d '' f; do
      jq -e --arg f "$f" 'has($f)' <<<"$sup" >/dev/null && motivos="$motivos"$'\n'"deuda en fichero tocado: $f (lint)"
      jq -e --arg f "$f" 'has($f)' <<<"$tsb" >/dev/null && motivos="$motivos"$'\n'"deuda en fichero tocado: $f (tipos)"
    done < "$lst"
    crece="$(grows_sup)" || exit 2; c2="$(grows_tsb)" || exit 2
    crece="$(printf '%s\n%s' "$crece" "$c2" | sed '/^$/d' | tr '\t' ' ')"
    [ -z "$crece" ] || motivos="$motivos"$'\n'"$(sed 's/^/la deuda crece: /' <<<"$crece")"
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
      hit=0
      while IFS= read -r g; do
        [ -n "$g" ] || continue
        case "$g" in */) [[ "$f" == "$g"* ]] && hit=1 ;; *) [[ "$f" == $g ]] && hit=1 ;; esac
        [ $hit -eq 1 ] && break
      done <<<"$globs"
      [ $hit -eq 1 ] || continue
      if [ "$f" = "$SUP" ]; then c="$(grows_sup)" || exit 2; [ -n "$c" ] || continue; fi
      if [ "$f" = "$TSB" ]; then c="$(grows_tsb)" || exit 2; [ -n "$c" ] || continue; fi
      echo "$f"; total=$((total + 1))
      if git cat-file -e "$mb:$f" 2>/dev/null || git --literal-pathspecs ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
        lista+=("$f")
      else
        nuevos+=("$f")
      fi
    done < "$lst"
    frag=""
    if ! git --literal-pathspecs diff --quiet "$mb" -- package.json 2>/dev/null \
        || [ -n "$(git --literal-pathspecs ls-files --others --exclude-standard -- package.json)" ]; then
      pb="$(json_base package.json)" || exit 2; ph="$(json_tree package.json)" || exit 2
      # Each part is {<clave>: {antes, ahora}} with only what differs; a missing value is null.
      frag="$(jq -cnS --argjson b "$pb" --argjson h "$ph" --arg re "$LINT_DEP" '
        def diffmap($x; $y): [($x + $y) | keys[] | select($x[.] != $y[.]) | {key: ., value: {antes: $x[.], ahora: $y[.]}}]
          | from_entries;
        def lkeys: (.scripts // {}) | objects | keys[] | select(test("^(lint|typecheck)"));
        def calls: (.scripts // {}) as $s | lkeys | $s[.] | strings |
          scan("(?:^|[\\s;&|(])(?:npm\\s+run(?:-script)?|pnpm(?:\\s+run)?|yarn(?:\\s+run)?|bun\\s+run)\\s+(?:-\\S+\\s+)*([^\\s;&|()]+)")[0];
        def deps: [.dependencies, .devDependencies, .peerDependencies, .optionalDependencies | objects | to_entries[]]
          | group_by(.key) | map({key: .[0].key, value: map(.value)}) | from_entries
          | with_entries(select(.key | test($re)));
        def ovr: [{s: "overrides", v: .overrides}, {s: "resolutions", v: .resolutions}, {s: "pnpm.overrides", v: .pnpm.overrides?}]
          | map(.s as $s | .v | objects | paths(scalars) as $p | {key: ($p | map(tostring) | join(">")), value: {($s): getpath($p)}})
          | group_by(.key) | map({key: .[0].key, value: (map(.value) | add)}) | from_entries
          | with_entries(select(.key | test($re)));
        ([$b, $h] | map(lkeys, calls) | unique) as $ks |
        def sobj: .scripts | if type == "object" then . else {} end;
        ($b | sobj) as $sb | ($h | sobj) as $sh |
        ($b | deps) as $db | ($h | deps) as $dh |
        {scripts: diffmap($sb | with_entries(select(.key | IN($ks[]))); $sh | with_entries(select(.key | IN($ks[])))),
         quitadas: [$db | keys[] | select($dh[.] == null)],
         cambiadas: diffmap($db | with_entries(select(.key | IN($dh | keys[]))); $dh | with_entries(select(.key | IN($db | keys[])))),
         overrides: diffmap($b | ovr; $h | ovr)}
        | if (.scripts | length) + (.quitadas | length) + (.cambiadas | length) + (.overrides | length) == 0 then empty else . end')" \
        || { echo "error: no pude comparar package.json" >&2; exit 2; }
      if [ -n "$frag" ]; then
        jq -r '(.scripts | keys[] | "package.json (scripts.\(.))"), (.quitadas[] | "package.json (quitada \(.))"),
          (.cambiadas | keys[] | "package.json (cambiada \(.))"), (.overrides | keys[] | "package.json (overrides \(.))")' <<<"$frag"
        total=$((total + $(jq '(.scripts | length) + (.quitadas | length) + (.cambiadas | length) + (.overrides | length)' <<<"$frag")))
      fi
    fi
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
