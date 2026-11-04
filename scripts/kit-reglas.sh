#!/usr/bin/env bash
# Usage: scripts/kit-reglas.sh <subcomando> <wt> [args...]
#   estado    <wt>
#   marcador  <wt> [--python <comando>]
#   trinquete <wt> <ref>
#   blindado  <wt> <ref>
#   abrir     <wt> <session_id>
#   cerrar    <wt>
# Mechanical checks of the deterministic rules (lint, types, structure) for kit-pr.sh fusionar, the hooks and the
# kit-reglas skill. "Changed" is the working tree of <wt> (committed or not, plus untracked files not ignored) against
# git merge-base <ref> HEAD, without rename detection: a renamed file counts as its old path deleted. So it serves both
# fusionar (ref=origin/<base>, clean tree) and a local review (ref = the review base, or HEAD for only the uncommitted).
#   estado: one line per fact, for kit-reglas to propose what is missing: "lenguajes: ts,js,py,sh|ninguno" (py: in
#     the root pyproject.toml, ruff.toml, .ruff.toml, requirements*.txt, setup.py or setup.cfg, or any versioned .py),
#     "lint: declarado|sin declarar" (marker of <wt>), with py the informative "ruff: sí|no" (ruff.toml, .ruff.toml or
#     [tool.ruff...] in pyproject.toml, of the root; the first of them, as ruff), "ruff select: <códigos>|ninguna|por
#     defecto" (lint.select or select;
#     [tool.ruff.lint] or [tool.ruff] in pyproject.toml) and "pyright: sí|no" (pyrightconfig.json or [tool.pyright]),
#     which never change the base, then each project ("." for the root, which is one when it has
#     tsconfig.json or typescript in its package.json; any other directory of the tree outside node_modules, when it
#     has both package.json and tsconfig.json) as "proyecto: <dir> (ts|js, base completa|base incompleta)". A project
#     is js when its tsconfig.json says "allowJs": true and none of its own files (those not under a nested project)
#     is TS source (.ts, .tsx, .mts, .cts; declarations .d.ts, .d.mts, .d.cts aside): its tsconfig only feeds types to
#     typescript-eslint. Then a ts project gets "tsconfig: <flag> sí|no" for each flag of the base (grep over its
#     tsconfig.json; "extends" is not followed), and a js one "tsconfig: strictNullChecks sí|no" (sí with
#     "strictNullChecks": true, or "strict": true without "strictNullChecks": false, comments aside: several strictTypeChecked rules
#     need it, also in JS) and "tsconfig: checkJs sí|no (opcional)" (the other strict flags go with checkJs, a
#     migration apart, never part of its base). Both: "eslint: strictTypeChecked sí|no", "eslint: noInlineConfig sí|no"
#     (grep over its eslint.config.*), "knip: sí|no", then the informative lines that never change the base:
#     "directivas-en-linea: <n>" (ESLint directive comments, // or /* followed by eslint, eslint-disable,
#     eslint-disable-line, eslint-disable-next-line or eslint-enable, in its own files with a lint extension, those
#     not under a nested project; text in a string that looks like one also counts) and, for each of .agents-kit/turno.sh and .agents-kit/tsc-base.mjs that exists,
#     "plantilla: <fichero> al día|desfasada: <qué hacer>" against templates/reglas/ of this kit (turno.sh without its
#     TSC_EXT=, LINT_EXT=, TSC= and ANTES_TSC= lines). Last, its "deuda-lint: <n> entradas|ninguna" (its
#     eslint-suppressions.json, one entry per file and rule) and "deuda-tsc: <n> ficheros|ninguna" (its
#     .agents-kit/tsc-base.json). The root's debt lines always appear: right after "lint:" when the root is not a TS
#     project. FIN: base completa (lint declared and every project complete, or no TS project) or FIN: base incompleta.
#   marcador: the flags of kit-activate.sh for the "lint" of the marker, one per line and quoted for the shell, so
#     they work as they are after "kit-activate.sh <wt>": with a TS or JS project, --lint-fichero of ESLint without
#     types (ts,tsx,mts,cts,js,jsx,mjs,cjs with a TS project, js,jsx,mjs,cjs with only JS ones, plus astro, vue or
#     svelte when a project has such files); with py, --lint-fichero 'py=<ruff>' (--python <comando>:
#     "<comando>" -m ruff check --quiet, a value without double quotes, $(...) allowed; else .venv/bin/ruff check
#     --quiet when it is executable, else ruff check --quiet; never uvx nor pipx; with a project in a subdirectory,
#     from where the hooks run it, a path relative to the root goes from $(git rev-parse --show-toplevel): .venv/bin/ruff,
#     a <comando> with a / and $(<ruta relativa>)); with versioned .sh, 'sh,bash=shellcheck';
#     with a TS or JS project, --lint-turno 'bash .agents-kit/turno.sh' when the root is a project or has that file,
#     else '[ ! -f .agents-kit/turno.sh ] || bash .agents-kit/turno.sh'. FIN: <n> (the number of flags).
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

usage() { echo "uso: $0 estado <wt> | marcador <wt> [--python <comando>] | trinquete <wt> <ref> | blindado <wt> <ref> | abrir <wt> <session_id> | cerrar <wt>" >&2; exit 1; }
[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1"; shift
opt_python=""
case "$sub" in
  estado|cerrar) [ $# -eq 1 ] || usage ;;
  marcador)
    if [ $# -gt 1 ]; then
      [ $# -eq 3 ] && [ "$2" = --python ] && [ -n "$3" ] || usage
      case "$3" in *'"'*|*$'\n'*) echo "valor de --python inválido: '$3' (sin comillas dobles ni saltos de línea)" >&2; exit 1 ;; esac
      opt_python="$3"; set -- "$1"
    fi ;;
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
# lint.fichero of ESLint: each edit, without types, with cache (references/base.md of kit-reglas says why each flag).
ESLINT_RAPIDO='KIT_LINT_RAPIDO=1 node_modules/.bin/eslint --cache --cache-location node_modules/.cache/agents-kit/eslint-rapido --no-warn-ignored --pass-on-unpruned-suppressions'
PLANTILLAS="$here/../templates/reglas"
# Extensions whose files can carry ESLint directives (directivas-en-linea).
DIR_EXT='js|jsx|mjs|cjs|ts|tsx|mts|cts|astro|vue|svelte'
# An ESLint directive comment (perl, over the whole file): // or /* (then any blank, line breaks included) and eslint
# (inline config), eslint-disable[-line|-next-line] or eslint-enable, followed by a blank, the end of the comment or
# the end of the file. Text inside strings that looks like one also counts (no JS lexer here).
DIR_RE='(?://[ \t]*|/\*\s*)eslint(?:-disable(?:-next-line|-line)?|-enable)?(?=\s|\*/|\z)'
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
  jq -ce 'if type == "object" then . else error end' < "$1" 2>/dev/null || { echo "error: $1 no es un objeto JSON válido" >&2; return 2; }
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
# Return 2 if git fails (never an empty list that would let the gates pass).
tree_files() {
  local out
  # -z: unquoted names, also with tabs or other control characters (a newline in a name is not supported)
  out="$(git ls-files -z --cached --others --exclude-standard | tr '\0' '\n'; exit "${PIPESTATUS[0]}")" || return 2
  printf '%s\n' "$out" | grep -v -E '(^|/)node_modules/' || :
}

# ts_projects: the TS projects of the tree, one directory per line ("." for the root), sorted. The root is one when it
# has tsconfig.json or typescript in its package.json dependencies (as before monorepos: a single app in the root
# behaves the same); any other directory, when it has both package.json and tsconfig.json (versioned or new). A
# tsconfig.*.json or a tsconfig.json without its own package.json is not one. Directory names are kept as they are
# (repeated, leading or trailing spaces, tabs).
ts_projects() {
  local pkg files
  pkg="$(json_tree package.json)" || return 2
  if [ -f tsconfig.json ] || jq -e '[.dependencies, .devDependencies, .peerDependencies] | map(objects | has("typescript")) | any' \
      <<<"$pkg" >/dev/null; then echo "."; fi
  files="$(tree_files)" || return 2
  LC_ALL=C comm -12 <(printf '%s\n' "$files" | sed -n 's#^\(.*\)/package\.json$#\1#p' | LC_ALL=C sort -u) \
    <(printf '%s\n' "$files" | sed -n 's#^\(.*\)/tsconfig\.json$#\1#p' | LC_ALL=C sort -u) \
    | while IFS= read -r d; do [ -n "$d" ] && [ -f "$d/package.json" ] && [ -f "$d/tsconfig.json" ] && printf '%s\n' "$d"; done
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

# jsonc <fichero>: the file without its // and /* */ comments (tsconfig.json is JSONC), strings kept as they are, so a
# commented out option never counts.
jsonc() {
  perl -0777 -pe 's{("(?:[^"\\]|\\.)*")|//[^\n]*|/\*.*?\*/}{defined $1 ? $1 : ""}gse' -- "$1" 2>/dev/null
}

# own_files <dir> <projects> <files>: the files of <files> that are the project's own (under <dir>, not under another
# of <projects> nested in it), one per line, paths from the repo root.
own_files() {
  D="$1" P="$2" awk '
    BEGIN { d = ENVIRON["D"]; pre = (d == ".") ? "" : d "/"; n = split(ENVIRON["P"], ps, "\n")
      for (i = 1; i <= n; i++) if (ps[i] != "" && ps[i] != d && ps[i] != "." && (pre == "" || index(ps[i] "/", pre) == 1)) hijo[ps[i] "/"] = 1 }
    pre != "" && index($0, pre) != 1 { next }
    { for (h in hijo) if (index($0, h) == 1) next }
    $0 != ""' <<<"$3"
}

# project_kind <dir> <own files>: "js" when <dir>/tsconfig.json says "allowJs": true and none of the project's own
# files still on disk is TS source (declarations aside); "ts" otherwise. A versioned file deleted but not staged is
# in the list and no longer counts.
project_kind() {
  local f
  jsonc "./$1/tsconfig.json" | grep -Eq '"allowJs"[[:space:]]*:[[:space:]]*true' || { echo ts; return 0; }
  while IFS= read -r f; do
    [ -e "$f" ] && { echo ts; return 0; }
  done < <(grep -E '\.(ts|tsx|mts|cts)$' <<<"$2" | grep -Ev '\.d\.(ts|mts|cts)$')
  echo js
}

# directives <own files>: the number of ESLint directive comments in those files (with a DIR_EXT extension and still
# on disk). Paths from the repo root (the current directory).
directives() {
  local n
  n="$(grep -Ei "\.($DIR_EXT)\$" <<<"$1" | while IFS= read -r f; do [ -f "$f" ] && printf '%s\0' "$f"; done \
    | DIR_RE="$DIR_RE" xargs -0 perl -0777 -ne 'BEGIN { $n = 0 } $n += () = /$ENV{DIR_RE}/g; END { print "$n\n" }' /dev/null \
    | awk '{ n += $1 } END { print n + 0 }')"
  echo "$n"
}

# scan: set projs, files, kinds, dirs_n (one line per project, as projs without empty lines) and extras (the
# extensions astro, vue and svelte present in the own files of any project, comma separated).
scan() {
  local d own e
  projs="$(ts_projects)" || { echo "error: no pude listar los proyectos TS (git falló)" >&2; exit 2; }
  files="$(tree_files)" || { echo "error: no pude listar los ficheros (git falló)" >&2; exit 2; }
  kinds=""; dirs_n=""; extras=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    own="$(own_files "$d" "$projs" "$files")"
    kinds="$kinds$(project_kind "$d" "$own")"$'\n'
    dirs_n="$dirs_n$(directives "$own")"$'\n'
    for e in astro vue svelte; do
      case ",$extras," in *",$e,"*) continue ;; esac
      grep -Eqi "\.$e\$" <<<"$own" && extras="${extras:+$extras,}$e"
    done
  done <<<"$projs"
}

# has_py: the repo has Python (in its root: pyproject.toml, ruff.toml, .ruff.toml, requirements*.txt, setup.py,
# setup.cfg; or any versioned .py).
has_py() {
  local f
  for f in pyproject.toml ruff.toml .ruff.toml setup.py setup.cfg requirements*.txt; do [ -f "$f" ] && return 0; done
  [ -n "$(git ls-files -- '*.py')" ]
}

# toml_ruff_select <fichero> <secciones>: the codes of "select" (in one line or several) of the first of <secciones>
# (separated by |, "" for the top level) that sets it, comma separated, or "-" for an empty list; nothing if none.
toml_ruff_select() {
  S="$2" perl -ne '
    BEGIN { @orden = split /\|/, $ENV{S}, -1; %ok = map { $_ => 1 } @orden; $sec = "" }
    s/#.*//;
    if (!$in && /^\s*\[\s*([^\]]*?)\s*\]\s*$/) { $sec = $1; next }
    if (!$in) { next unless $ok{$sec} && !exists $res{$sec} && /^\s*select\s*=\s*\[(.*)/s; $in = 1; $buf = $1 } else { $buf .= $_ }
    if ($buf =~ /\]/) { $buf =~ s/\].*//s; $res{$sec} = join(",", $buf =~ /["\x27]([^"\x27]*)["\x27]/g); $res{$sec} = "-" if $res{$sec} eq ""; $in = 0 }
    END { for (@orden) { if (exists $res{$_}) { print "$res{$_}\n"; last } } }
  ' -- "$1"
}

# python_lines: "ruff: sí|no", "ruff select: <códigos>|por defecto" (only with ruff) and "pyright: sí|no", from the
# config files of the root (ruff.toml, .ruff.toml or [tool.ruff] in pyproject.toml; pyrightconfig.json or
# [tool.pyright]). Informative: they never change the base.
python_lines() {
  local f="" sel=""
  # The same precedence as ruff: .ruff.toml, ruff.toml, pyproject.toml.
  if [ -f .ruff.toml ]; then f=.ruff.toml; elif [ -f ruff.toml ]; then f=ruff.toml
  elif [ -f pyproject.toml ] && grep -Eq '^[[:space:]]*\[tool\.ruff(\.|\])' pyproject.toml; then f=pyproject.toml; fi
  if [ -n "$f" ]; then
    echo "ruff: sí"
    if [ "$f" = pyproject.toml ]; then sel="$(toml_ruff_select "$f" "tool.ruff.lint|tool.ruff")"
    else sel="$(toml_ruff_select "$f" "lint|")"; fi
    case "$sel" in
      "") echo "ruff select: por defecto" ;;
      -) echo "ruff select: ninguna" ;;
      *) echo "ruff select: $sel" ;;
    esac
  else
    echo "ruff: no"
  fi
  if [ -f pyrightconfig.json ] || { [ -f pyproject.toml ] && grep -Eq '^[[:space:]]*\[tool\.pyright\]' pyproject.toml; }; then
    echo "pyright: sí"
  else
    echo "pyright: no"
  fi
}

# q <texto>: <texto> quoted for the shell, between single quotes.
q() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

# templates_lines: "plantilla: ..." for the kit templates copied into the project in the current directory.
templates_lines() {
  local q='^(TSC_EXT|LINT_EXT|TSC|ANTES_TSC)='
  if [ -f .agents-kit/turno.sh ]; then
    if cmp -s <(grep -Ev "$q" .agents-kit/turno.sh) <(grep -Ev "$q" "$PLANTILLAS/turno.sh"); then
      echo "plantilla: .agents-kit/turno.sh al día"
    else
      echo "plantilla: .agents-kit/turno.sh desfasada: vuelve a copiar templates/reglas/turno.sh del kit (conserva TSC_EXT, LINT_EXT, TSC y ANTES_TSC)"
    fi
  fi
  if [ -f .agents-kit/tsc-base.mjs ]; then
    if cmp -s .agents-kit/tsc-base.mjs "$PLANTILLAS/tsc-base.mjs"; then
      echo "plantilla: .agents-kit/tsc-base.mjs al día"
    else
      echo "plantilla: .agents-kit/tsc-base.mjs desfasada: vuelve a copiar templates/reglas/tsc-base.mjs del kit"
    fi
  fi
}

# base_checks <lint> <ts|js>: the checks of the base for the project in the current directory, one line each; return 1
# if any says no (or <lint> is empty: the marker does not declare lint). A js project has no tsconfig flags in its base.
base_checks() {
  local ok=0 flag k v f pkg tsc=""
  [ -n "$1" ] || ok=1
  pkg="$(json_tree package.json)" || return 2
  [ -f tsconfig.json ] && tsc="$(jsonc tsconfig.json)"
  if [ "$2" = js ]; then
    v="no"
    if grep -Eq '"strictNullChecks"[[:space:]]*:[[:space:]]*true' <<<"$tsc"; then v="sí"
    elif grep -Eq '"strict"[[:space:]]*:[[:space:]]*true' <<<"$tsc" \
      && ! grep -Eq '"strictNullChecks"[[:space:]]*:[[:space:]]*false' <<<"$tsc"; then v="sí"; fi
    [ "$v" = "sí" ] || ok=1
    echo "tsconfig: strictNullChecks $v"
    if grep -Eq '"checkJs"[[:space:]]*:[[:space:]]*true' <<<"$tsc"; then v="sí"; else v="no"; fi
    echo "tsconfig: checkJs $v (opcional)"
  else
    for flag in $FLAGS; do
      if grep -Eq "\"$flag\"[[:space:]]*:[[:space:]]*true" <<<"$tsc"; then v="sí"; else v="no"; ok=1; fi
      echo "tsconfig: $flag $v"
    done
  fi
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
    scan
    langs=""
    grep -qx ts <<<"$kinds" && langs="ts"
    grep -qx js <<<"$kinds" && langs="${langs:+$langs,}js"
    has_py && langs="${langs:+$langs,}py"
    [ -n "$(git ls-files -- '*.sh')" ] && langs="${langs:+$langs,}sh"
    echo "lenguajes: ${langs:-ninguno}"
    l="$(kit_config "$wt" 'if .lint == null then "" else "sí" end')" || exit 2
    completa=1
    if [ -n "$l" ]; then echo "lint: declarado"; else echo "lint: sin declarar"; fi
    has_py && python_lines
    # The root's debt goes first when the root is not a TS project; each project prints its own after its checks.
    case "$projs" in .|.$'\n'*) ;; *) debt_lines || exit 2 ;; esac
    while IFS= read -r d && IFS= read -r t <&3 && IFS= read -r nd <&4; do
      [ -n "$d" ] || continue
      blk="$(cd "./$d" || exit 2; base_checks "$l" "$t")"; rc=$?
      [ $rc -le 1 ] || exit 2
      if [ $rc -eq 0 ]; then echo "proyecto: $d ($t, base completa)"; else echo "proyecto: $d ($t, base incompleta)"; completa=0; fi
      printf '%s\n' "$blk"
      echo "directivas-en-linea: $nd"
      (cd "./$d" || exit 2; templates_lines; debt_lines) || exit 2
    done <<<"$(grep -v '^$' <<<"$projs")" 3<<<"$kinds" 4<<<"$dirs_n"
    if [ $completa -eq 1 ]; then echo "FIN: base completa"; else echo "FIN: base incompleta"; fi
    ;;

  marcador)
    scan
    n=0
    if [ -n "$kinds" ]; then
      if grep -qx ts <<<"$kinds"; then ex="ts,tsx,mts,cts,js,jsx,mjs,cjs"; else ex="js,jsx,mjs,cjs"; fi
      echo "--lint-fichero $(q "$ex${extras:+,$extras}=$ESLINT_RAPIDO")"; n=$((n + 1))
    fi
    if has_py; then
      # The hooks run lint.fichero from the project of each file: with a project in a subdirectory, a path relative to
      # the root (.venv/bin/ruff, tools/python.sh) goes from the root of the worktree.
      raiz=""
      grep -Eqv '^(\.)?$' <<<"$projs" && raiz='$(git rev-parse --show-toplevel)'
      if [ -n "$opt_python" ]; then
        p="$opt_python"
        if [ -n "$raiz" ]; then
          case "$p" in
            '$('[!/\$]*')') p='$("'"$raiz"'"/'"${p#\$(}" ;;
            [!/\$]*/*) p="$raiz/$p" ;;
          esac
        fi
        c="\"$p\" -m ruff check --quiet"
      elif [ -x .venv/bin/ruff ]; then
        if [ -n "$raiz" ]; then c="\"$raiz/.venv/bin/ruff\" check --quiet"; else c=".venv/bin/ruff check --quiet"; fi
      else c="ruff check --quiet"; fi
      echo "--lint-fichero $(q "py=$c")"; n=$((n + 1))
    fi
    if [ -n "$(git ls-files -- '*.sh')" ]; then echo "--lint-fichero $(q "sh,bash=shellcheck")"; n=$((n + 1)); fi
    if [ -n "$kinds" ]; then
      case "$projs" in
        .|.$'\n'*) t="bash .agents-kit/turno.sh" ;;
        *) if [ -f .agents-kit/turno.sh ]; then t="bash .agents-kit/turno.sh"; else t="[ ! -f .agents-kit/turno.sh ] || bash .agents-kit/turno.sh"; fi ;;
      esac
      echo "--lint-turno $(q "$t")"; n=$((n + 1))
    fi
    echo "FIN: $n"
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
      while IFS=$'\t' read -r k rg; do
        [ -z "$k" ] || motivos="$motivos"$'\n'"la deuda crece: $k $rg ($p$SUP)"
      done <<<"$c1"
      while IFS=$'\t' read -r k rg; do
        [ -z "$k" ] || motivos="$motivos"$'\n'"la deuda crece: $k $rg ($p$TSB)"
      done <<<"$c2"
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
