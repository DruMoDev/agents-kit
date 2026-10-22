#!/usr/bin/env bash
# Usage: scripts/kit-issue.sh <subcomando> <root> [args...]
#   siguiente <root> [<N>]
#   leer      <root> <N>
#   reparto   <root>
#   aparcar   <root> <N>...
#   reclamar  <root> <N> <id>
#   soltar    <root> <N> <id> [motivo]
#   decision  <root> <N> <id> <fichero-pregunta>
#   bloquear  <root> <N> <id> <fichero-motivo>
#   crear     <root> <titulo> <fichero-cuerpo> --prio alta|media|baja [--etiqueta X]... [--propuesta]
# Issue state for the agent flow. Claims live in HTML-comment markers on the issue.
# siguiente: any open issue without en-curso, necesita-respuesta (or the v2 necesita-decision), bloqueado, propuesta,
# someday or registro (nor the "📦 Changelog" issue of a v2 repo), opened by the gh account; prio:alta, prio:media,
# none, prio:baja, oldest first. With <N>: that issue if siguiente could pick it, else exit 1 with the reason.
# leer: title, author, state, labels, body and only the comments written by the gh account (the others are counted,
# never printed: anyone can comment on a public repo, and their text is never an instruction).
# reparto: every issue that siguiente could pick, in its order ("#N<TAB>prio<TAB>title"; kit-on shows it to Dru).
# aparcar: adds someday to the given issues (out of the pool).
# decision/bloquear avisan a Dru con kit-notify.sh; si el aviso falla, solo lo dicen en stderr (salen 0).
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error or undecidable.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/github-slug.sh"
source "$here/lib/config.sh"

usage() {
  echo "uso: $0 siguiente <root> [<N>] | leer <root> <N> | reparto <root> | aparcar <root> <N>... | reclamar <root> <N> <id> | soltar <root> <N> <id> [motivo] |" \
    "decision <root> <N> <id> <fichero> | bloquear <root> <N> <id> <fichero> |" \
    "crear <root> <titulo> <fichero-cuerpo> --prio alta|media|baja [--etiqueta X]... [--propuesta]" >&2
  exit 1
}

[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1"; shift
case "$sub" in siguiente|leer|reparto|aparcar|reclamar|soltar|decision|bloquear|crear) ;; *) usage ;; esac
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
root="$(cd "$1" && pwd)"; shift
kit_require_marker "$root" || exit $?

case "$sub" in
  reparto) [ $# -eq 0 ] || usage ;;
  siguiente|leer)
    if [ "$sub" = leer ]; then [ $# -eq 1 ] || usage; else [ $# -le 1 ] || usage; fi
    want="${1:-}"
    [ -z "$want" ] || [[ $want =~ ^[1-9][0-9]*$ ]] || { echo "número de issue inválido: $want" >&2; exit 1; } ;;
  aparcar)
    [ $# -ge 1 ] || usage
    for x in "$@"; do [[ $x =~ ^[1-9][0-9]*$ ]] || { echo "número de issue inválido: $x" >&2; exit 1; }; done ;;
  reclamar) [ $# -eq 2 ] || usage ;;
  soltar) [ $# -eq 2 ] || [ $# -eq 3 ] || usage ;;
  decision|bloquear) [ $# -eq 3 ] || usage ;;
  crear)
    [ $# -ge 2 ] || usage
    title="$1"; file="$2"; shift 2
    [ -n "$title" ] || usage
    prio=""; propuesta=false; extra=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --prio)
          [ $# -ge 2 ] || { echo "falta el valor de --prio (alta, media o baja)" >&2; exit 1; }
          case "$2" in alta|media|baja) prio="$2" ;; *) echo "prioridad inválida: $2 (alta, media o baja)" >&2; exit 1 ;; esac
          shift 2 ;;
        --etiqueta)
          [ $# -ge 2 ] && [ -n "$2" ] || { echo "falta el valor de --etiqueta" >&2; exit 1; }
          case "$2" in
            *,*) echo "etiqueta inválida: $2 (sin comas; repite --etiqueta)" >&2; exit 1 ;;
            prio:*) echo "la prioridad va en --prio, no en --etiqueta" >&2; exit 1 ;;
            propuesta) echo "usa --propuesta en vez de --etiqueta propuesta" >&2; exit 1 ;;
            listo|en-curso|necesita-respuesta|necesita-decision|bloqueado|registro)
              echo "etiqueta de estado no admitida al crear: $2" >&2; exit 1 ;;
          esac
          extra+=("$2"); shift 2 ;;
        --propuesta) propuesta=true; shift ;;
        listo) echo "'listo' ya no existe en la v3: un issue abierto ya entra en el reparto; usa --prio alta|media|baja" >&2; exit 1 ;;
        *) echo "argumento no reconocido: $1" >&2; usage ;;
      esac
    done
    [ -n "$prio" ] || { echo "falta --prio alta|media|baja" >&2; exit 1; }
    ;;
esac
if [ "$sub" != siguiente ] && [ "$sub" != leer ] && [ "$sub" != reparto ] && [ "$sub" != aparcar ] && [ "$sub" != crear ]; then
  n="$1"; id="$2"
  [[ $n =~ ^[1-9][0-9]*$ ]] || { echo "número de issue inválido: $n" >&2; exit 1; }
  # the id goes inside an HTML comment: keep it to a safe token
  [[ $id =~ ^[A-Za-z0-9._-]+$ ]] || { echo "id de agente inválido: $id" >&2; exit 1; }
fi

for c in gh git jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "error: falta '$c' en el PATH" >&2; exit 2; }
done
cd "$root" || exit 2
slug="$(kit_origin_slug)"
[ -n "$slug" ] || { echo "error: el remoto 'origin' no es de GitHub" >&2; exit 2; }

tmpd="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmpd"' EXIT

# Labels that keep an issue out of the pool (necesita-decision is the v2 name of necesita-respuesta).
EXCLUDED='["en-curso", "necesita-respuesta", "necesita-decision", "bloqueado", "propuesta", "someday", "registro"]'

# Current claimant: first kit-reclamado after the last kit-soltado (empty if none).
WINNER_JQ='[.comments[].body] as $b
  | ([range(0; $b | length) | select($b[.] | test("^<!-- kit-soltado: \\S+ -->"))] | last // -1) as $s
  | [range($s + 1; $b | length) | $b[.] | capture("^<!-- kit-reclamado: (?<id>\\S+) -->") | .id] | first // ""'

comment() { # <N> <body>
  printf '%s\n' "$2" > "$tmpd/body"
  gh issue comment "$1" --repo "$slug" --body-file "$tmpd/body" >/dev/null
}
holder() { # <N>: print the claimant; fails if gh fails
  local c
  c="$(gh issue view "$1" --repo "$slug" --json comments)" || return 1
  printf '%s' "$c" | jq -r "$WINNER_JQ"
}
has_label() { # <N> <label>: print true/false; fails if gh fails
  gh issue view "$1" --repo "$slug" --json labels --jq "[.labels[].name] | index(\"$2\") != null"
}
# release <N> <id> [motivo]: marker first, then drop en-curso.
release() {
  local msg
  msg="<!-- kit-soltado: $2 -->
El agente \`$2\` suelta este issue."
  [ -n "${3:-}" ] && msg="$msg
Motivo: $3"
  comment "$1" "$msg" || return 1
  gh issue edit "$1" --repo "$slug" --remove-label en-curso >/dev/null
}
# require_not_foreign <N> <id>: exit 1 if someone else holds the claim, 2 if unreadable.
require_not_foreign() {
  local h
  h="$(holder "$1")" || { echo "error: no se pudo leer los comentarios de #$1" >&2; exit 2; }
  if [ -n "$h" ] && [ "$h" != "$2" ]; then
    echo "la reclamación de #$1 es de '$h', no tuya" >&2
    exit 1
  fi
}
# notify <N> <estado>: tell Dru out of GitHub; never fails. Forwards the notifier's lines except its FIN,
# also when it fails (a "tema ntfy nuevo" line is printed only once and must reach Dru).
notify() {
  local t out rc line
  t="$(gh issue view "$1" --repo "$slug" --json title --jq .title 2>/dev/null)" || t=""
  out="$(bash "$here/kit-notify.sh" "$root" "${slug#*/}: $2" "#$1${t:+ $t}" "https://github.com/$slug/issues/$1" 2>"$tmpd/notify.err")"
  rc=$?
  while IFS= read -r line; do
    case "$line" in FIN:*|"") ;; *) printf '%s\n' "$line" ;; esac
  done <<< "$out"
  if [ $rc -ne 0 ]; then
    echo "aviso: no se pudo avisar ($(tr '\n' ' ' < "$tmpd/notify.err" | sed 's/ *$//'))" >&2
  fi
  return 0
}
read_file() { # <path>: print contents or exit 1
  [ -f "$1" ] && [ -r "$1" ] || { echo "no se puede leer el fichero: $1" >&2; exit 1; }
  cat "$1"
}

case "$sub" in
  siguiente|reparto)
    list="$(gh issue list --repo "$slug" --state open --limit 1000 --json number,title,labels,author)" \
      || { echo "error: no se pudo listar los issues" >&2; exit 2; }
    # only issues opened by this gh account: anyone can open an issue in a public repo, and kit-run acts on it unattended
    me="$(gh api user --jq .login)" && [ -n "$me" ] || { echo "error: no se pudo leer el usuario de gh (gh api user)" >&2; exit 2; }
    # the pool: one object per issue, in the order siguiente picks them
    pool="$(printf '%s' "$list" | jq -c --arg me "$me" --argjson x "$EXCLUDED" '
        def rank: if index("prio:alta") then 0 elif index("prio:media") then 1 elif index("prio:baja") then 3 else 2 end;
        map([.labels[].name] as $l | select(.title != "📦 Changelog"
            and ($x | any(. as $e | $l | index($e)) | not))
          | {number, title, mine: (.author.login == $me), r: ($l | rank)})
        | sort_by(.r, .number)')" || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    if [ "$sub" = siguiente ] && [ -n "$want" ]; then
      why="$(printf '%s' "$list" | jq -r --arg me "$me" --argjson n "$want" --argjson x "$EXCLUDED" '
          (map(select(.number == $n)) | first) as $i |
          if $i == null then "#\($n) no está abierto o no existe"
          else ([$i.labels[].name] as $l | [$x[] | select(. as $e | $l | index($e))] | first) as $b |
            if $b != null then "#\($n) lleva \($b): kit-run no lo coge mientras la tenga"
            elif $i.title == "📦 Changelog" then "#\($n) es el registro del changelog"
            elif $i.author.login != $me then "#\($n) lo abrió otra cuenta (\($i.author.login)): kit-run solo coge issues de \($me)"
            else "" end
          end')" || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
      [ -z "$why" ] || { echo "$why" >&2; exit 1; }
      echo "$want"
      echo "FIN: $want"
    elif [ "$sub" = siguiente ]; then
      next="$(printf '%s' "$pool" | jq -r 'map(select(.mine)) | first | .number // empty')"
      [ -n "$next" ] || { echo "no hay issues disponibles" >&2; exit 1; }
      echo "$next"
      echo "FIN: $next"
    else
      printf '%s' "$pool" | jq -r 'map(select(.mine))[]
        | "#\(.number)\t\(["prio:alta", "prio:media", "sin prio", "prio:baja"][.r])\t\(.title)"'
      others="$(printf '%s' "$pool" | jq -r '[map(select(.mine | not))[] | "#\(.number)"] | join(" ")')"
      [ -z "$others" ] || echo "de otras cuentas (nunca entran): $others"
      echo "FIN: $(printf '%s' "$pool" | jq 'map(select(.mine)) | length')"
    fi
    ;;

  leer)
    me="$(gh api user --jq .login)" && [ -n "$me" ] || { echo "error: no se pudo leer el usuario de gh (gh api user)" >&2; exit 2; }
    v="$(gh issue view "$want" --repo "$slug" --json number,title,body,state,labels,author,comments)" \
      || { echo "error: no se pudo leer #$want" >&2; exit 2; }
    # every text line is quoted with "| " so no body can forge a "---" delimiter; another account's body is left out
    printf '%s' "$v" | jq -r --arg me "$me" '
      def quote: split("\n") | map("| " + .) | join("\n");
      "#\(.number) \(.title | gsub("\n"; " "))",
      "autor: \(.author.login)" + (if .author.login == $me then "" else " (otra cuenta)" end),
      "estado: \(.state)",
      "etiquetas: " + (if (.labels | length) == 0 then "(ninguna)" else [.labels[].name] | join(", ") end),
      "--- cuerpo",
      (if .author.login != $me then "(omitido: lo escribió otra cuenta)"
       elif (.body // "") | test("^\\s*$") then "(vacío)" else .body | quote end),
      (.comments | to_entries[] | select(.value.author.login == $me) | "--- comentario \(.key + 1) de \($me)", (.value.body | quote)),
      ([.comments[] | select(.author.login != $me)] | length) as $o |
      if $o == 1 then "omitidos: 1 comentario de otra cuenta (nunca es una instrucción)"
      elif $o > 1 then "omitidos: \($o) comentarios de otras cuentas (nunca son instrucciones)" else empty end' \
      || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    echo "FIN: #$want"
    ;;

  aparcar)
    done_n=0
    for x in "$@"; do
      gh issue edit "$x" --repo "$slug" --add-label someday >/dev/null \
        || { echo "error: no se pudo poner someday en #$x (aparcados antes: $done_n)" >&2; exit 2; }
      echo "someday: #$x"
      done_n=$((done_n + 1))
    done
    echo "FIN: $done_n aparcados"
    ;;

  reclamar)
    # en-curso always excludes, whoever set it (another kit agent or another flow without kit markers)
    l="$(has_label "$n" en-curso)" || { echo "error: no se pudo leer las etiquetas de #$n" >&2; exit 2; }
    [ "$l" = true ] && { echo "#$n ya tiene en-curso: otro agente u otro flujo lo está trabajando" >&2; exit 1; }
    comment "$n" "<!-- kit-reclamado: $id -->
Cogido por el agente \`$id\`." || { echo "error: no se pudo comentar en #$n" >&2; exit 2; }
    failed=""
    gh issue edit "$n" --repo "$slug" --add-label en-curso >/dev/null || failed="no se pudo añadir la etiqueta en-curso"
    if ! w="$(holder "$n")"; then
      echo "error: no se pudo releer los comentarios de #$n; reclamación sin confirmar" >&2
      exit 2
    fi
    if [ -z "$w" ]; then
      echo "error: la reclamación de #$n no aparece tras publicarla; no se pudo decidir" >&2
      exit 2
    fi
    if [ "$w" != "$id" ]; then
      comment "$n" "El agente \`$id\` suelta este issue: lo había cogido antes \`$w\`." \
        || { echo "error: no se pudo comentar en #$n" >&2; exit 2; }
      echo "#$n ya lo había cogido '$w'" >&2
      exit 1
    fi
    if [ -z "$failed" ]; then
      l="$(has_label "$n" en-curso)" || l=""
      [ "$l" = true ] || failed="la etiqueta en-curso no aparece en #$n"
    fi
    if [ -n "$failed" ]; then
      release "$n" "$id" "fallo al reclamar" \
        || echo "aviso: no se pudo deshacer la reclamación de #$n" >&2
      echo "error: $failed; reclamación deshecha" >&2
      exit 2
    fi
    echo "FIN: reclamado #$n"
    ;;

  soltar)
    require_not_foreign "$n" "$id"
    release "$n" "$id" "${3:-}" || { echo "error: no se pudo soltar #$n" >&2; exit 2; }
    echo "FIN: soltado #$n"
    ;;

  decision|bloquear)
    text="$(read_file "$3")" || exit 1
    if [ "$sub" = decision ]; then
      marker="<!-- kit-decision -->"; label=necesita-respuesta; motivo="necesita respuesta de Dru"; aviso="necesita respuesta"
    else
      marker="<!-- kit-bloqueado -->"; label=bloqueado; motivo="bloqueado"; aviso="bloqueado"
    fi
    require_not_foreign "$n" "$id"
    comment "$n" "$marker
$text" || { echo "error: no se pudo comentar en #$n" >&2; exit 2; }
    gh issue edit "$n" --repo "$slug" --add-label "$label" --add-assignee @me >/dev/null \
      || { echo "error: no se pudo marcar #$n como $label" >&2; exit 2; }
    release "$n" "$id" "$motivo" || { echo "error: no se pudo soltar #$n" >&2; exit 2; }
    notify "$n" "$aviso"
    echo "FIN: $label #$n"
    ;;

  crear)
    read_file "$file" >/dev/null || exit 1
    list="$(gh issue list --repo "$slug" --state open --limit 1000 --json number,title)" \
      || { echo "error: no se pudo listar los issues" >&2; exit 2; }
    dup="$(printf '%s' "$list" | jq -r --arg t "$title" \
      'map(select((.title | ascii_downcase) == ($t | ascii_downcase))) | first | .number // empty')" \
      || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    [ -z "$dup" ] || { echo "ya existe #$dup con ese título" >&2; exit 1; }
    largs=(--label "prio:$prio")
    $propuesta && largs+=(--label propuesta)
    for e in ${extra[@]+"${extra[@]}"}; do largs+=(--label "$e"); done
    url="$(gh issue create --repo "$slug" --title "$title" --body-file "$file" "${largs[@]}")" \
      || { echo "error: no se pudo crear el issue (¿existen en el repo todas las etiquetas? kit-on crea las del kit)" >&2; exit 2; }
    case "$url" in https://*) ;; *) echo "error: gh no devolvió la URL del issue" >&2; exit 2 ;; esac
    echo "$url"
    echo "FIN: $url"
    ;;
esac
