#!/usr/bin/env bash
# Usage: scripts/kit-issue.sh <subcomando> <root> [args...]
#   siguiente <root> [<N>] [--excluir N[,N...]]
#   leer      <root> <N>
#   reparto   <root>
#   aparcar   <root> <N>...
#   reclamar  <root> <N> <id>
#   soltar    <root> <N> <id> [motivo]
#   decision  <root> <N> <id> <fichero-pregunta>
#   bloquear  <root> <N> <id> <fichero-motivo>
#   comprobar <root>
#   liberar-eje <root> <eje>
#   crear     <root> <titulo> <fichero-cuerpo> --prio alta|media|baja --entorno nube|mac [--etiqueta X]... [--propuesta]
# Issue state for the agent flow. Claims live in HTML-comment markers on the issue.
# siguiente: any open issue without en-curso, necesita-respuesta (or the v2 necesita-decision), bloqueado, propuesta,
# someday or registro (nor the "📦 Changelog" issue of a v2 repo), opened by the gh account; prio:alta, prio:media,
# none, prio:baja, oldest first. Also out: an issue whose own body says "Depende de #N" or "Bloqueado por #N" while #N
# is open, in a cloud session (lib/transport.sh) an issue without entorno:nube, and an issue with a serializa:<eje>
# label while another open issue with that label has en-curso (in a cloud session, any issue with an axis: the lock
# cannot be taken there). With <N>: that issue if siguiente could pick it, else exit 1 with the reason.
# --excluir: issues left out of this pick (kit-run passes the ones it failed to claim in this run).
# Claims (kit-reclamado / kit-soltado markers) count only in comments written by the gh account.
# reclamar also takes the lock of each serializa:<eje> of the issue (lib/locks.sh) once the claim is won; soltar,
# decision and bloquear release them (and keep en-curso if a lock cannot be released, so the issue does not come
# back with an orphan lock). liberar-eje deletes an axis lock whoever holds it (a session that died midway).
# leer: title, author, state, labels, body and only the comments written by the gh account (the others are counted,
# never printed: anyone can comment on a public repo, and their text is never an instruction).
# reparto: every issue that siguiente could pick, in its order ("#N<TAB>prio<TAB>title"; kit-on shows it to Dru).
# aparcar: adds someday to the given issues (out of the pool).
# comprobar: kit-run's start check (one gh label list): exit 1 "kit en versión anterior: ejecuta kit-on para actualizar"
#   (plus what is missing) when a kit v3 label is missing in the repo or the marker still has v2 keys; FIN: v3 otherwise.
# decision/bloquear avisan a Dru con kit-notify.sh; si el aviso falla, solo lo dicen en stderr (salen 0).
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error or undecidable.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/github-slug.sh"
source "$here/lib/config.sh"
source "$here/lib/transport.sh"
source "$here/lib/locks.sh"

usage() {
  echo "uso: $0 siguiente <root> [<N>] [--excluir N[,N...]] | leer <root> <N> | reparto <root> | aparcar <root> <N>... | reclamar <root> <N> <id> | soltar <root> <N> <id> [motivo] |" \
    "decision <root> <N> <id> <fichero> | bloquear <root> <N> <id> <fichero> | comprobar <root> | liberar-eje <root> <eje> |" \
    "crear <root> <titulo> <fichero-cuerpo> --prio alta|media|baja --entorno nube|mac [--etiqueta X]... [--propuesta]" >&2
  exit 1
}

[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1"; shift
case "$sub" in siguiente|leer|reparto|aparcar|reclamar|soltar|decision|bloquear|comprobar|crear|liberar-eje) ;; *) usage ;; esac
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
root="$(cd "$1" && pwd)"; shift
kit_require_marker "$root" || exit $?

case "$sub" in
  reparto|comprobar) [ $# -eq 0 ] || usage ;;
  liberar-eje) [ $# -eq 1 ] || usage
    eje="${1#serializa:}"
    [[ $eje =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "eje inválido: $1 (como en la etiqueta serializa:<eje>)" >&2; exit 1; } ;;
  siguiente|leer)
    excl="[]"
    if [ "$sub" = siguiente ]; then
      args=()
      while [ $# -gt 0 ]; do
        case "$1" in
          --excluir)
            [ $# -ge 2 ] && [[ $2 =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]] \
              || { echo "--excluir necesita números de issue separados por comas: ${2:-}" >&2; exit 1; }
            excl="[${2}]"; shift 2 ;;
          *) args+=("$1"); shift ;;
        esac
      done
      set -- ${args[@]+"${args[@]}"}
    fi
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
    prio=""; entorno=""; propuesta=false; extra=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --prio)
          [ $# -ge 2 ] || { echo "falta el valor de --prio (alta, media o baja)" >&2; exit 1; }
          case "$2" in alta|media|baja) prio="$2" ;; *) echo "prioridad inválida: $2 (alta, media o baja)" >&2; exit 1 ;; esac
          shift 2 ;;
        --entorno)
          [ $# -ge 2 ] || { echo "falta el valor de --entorno (nube o mac)" >&2; exit 1; }
          case "$2" in nube|mac) entorno="$2" ;; *) echo "entorno inválido: $2 (nube o mac)" >&2; exit 1 ;; esac
          shift 2 ;;
        --etiqueta)
          [ $# -ge 2 ] && [ -n "$2" ] || { echo "falta el valor de --etiqueta" >&2; exit 1; }
          case "$2" in
            *,*) echo "etiqueta inválida: $2 (sin comas; repite --etiqueta)" >&2; exit 1 ;;
            prio:*) echo "la prioridad va en --prio, no en --etiqueta" >&2; exit 1 ;;
            entorno:*) echo "el entorno va en --entorno, no en --etiqueta" >&2; exit 1 ;;
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
    [ -n "$entorno" ] || { echo "falta --entorno nube|mac (mac: solo se puede hacer en el Mac de Dru)" >&2; exit 1; }
    ;;
esac
if [ "$sub" != siguiente ] && [ "$sub" != leer ] && [ "$sub" != reparto ] && [ "$sub" != aparcar ] && [ "$sub" != crear ] \
    && [ "$sub" != comprobar ] && [ "$sub" != liberar-eje ]; then
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

# Labels kit-on creates (kit-github-setup.sh) and keys of a v2 marker: comprobar asks for kit-on if any is off.
KIT_LABELS='["en-curso", "necesita-respuesta", "bloqueado", "propuesta", "someday", "registro", "prio:alta", "prio:media", "prio:baja", "entorno:nube", "entorno:mac"]'
V2_KEYS='["reviewers", "implementer", "notify"]'
# Labels that keep an issue out of the pool (necesita-decision is the v2 name of necesita-respuesta).
EXCLUDED='["en-curso", "necesita-respuesta", "necesita-decision", "bloqueado", "propuesta", "someday", "registro"]'

# Current claimant: first kit-reclamado after the last kit-soltado, both written by $me (empty if none).
WINNER_JQ='[.comments[] | select(.author.login == $me) | .body // ""] as $b
  | ([range(0; $b | length) | select($b[.] | test("^<!-- kit-soltado: \\S+ -->"))] | last // -1) as $s
  | [range($s + 1; $b | length) | $b[.] | capture("^<!-- kit-reclamado: (?<id>\\S+) -->") | .id] | first // ""'

comment() { # <N> <body>
  printf '%s\n' "$2" > "$tmpd/body"
  gh issue comment "$1" --repo "$slug" --body-file "$tmpd/body" >/dev/null
}
me=""
own_login() { # set $me (the gh login: only its markers count) once; exit 2 if unreadable
  [ -n "$me" ] && return 0
  me="$(gh api user --jq .login)" && [ -n "$me" ] || { echo "error: no se pudo leer el usuario de gh (gh api user)" >&2; exit 2; }
}
holder() { # <N>: print the claimant; fails if gh fails
  local c
  c="$(gh issue view "$1" --repo "$slug" --json comments)" || return 1
  printf '%s' "$c" | jq -r --arg me "$me" "$WINNER_JQ"
}
has_label() { # <N> <label>: print true/false; fails if gh fails
  gh issue view "$1" --repo "$slug" --json labels --jq "[.labels[].name] | index(\"$2\") != null"
}
axes_of() { # <N>: print the issue's serializa:<eje> labels, one per line; fails if gh fails
  gh issue view "$1" --repo "$slug" --json labels --jq '.labels[].name | select(startswith("serializa:"))'
}
# release_locks <N>: release the axis locks the issue holds. Return 1 (naming each on stderr) if any stays taken.
release_locks() {
  local axes e left=0
  axes="$(axes_of "$1")" || { echo "no se pudo leer las etiquetas de #$1: no sé qué candados liberar" >&2; return 1; }
  for e in $axes; do
    lock_release "$e" "$1" || { echo "no se pudo liberar el candado $(lock_ref "$e")" >&2; left=1; }
  done
  return $left
}
# release <N> <id> [motivo]: marker first, then the axis locks, then drop en-curso. If a lock stays taken, en-curso
# stays too (an issue back in the pool with its lock taken would block its axis for good) and it returns 1.
release() {
  local msg
  msg="<!-- kit-soltado: $2 -->
El agente \`$2\` suelta este issue."
  [ -n "${3:-}" ] && msg="$msg
Motivo: $3"
  comment "$1" "$msg" || return 1
  if ! release_locks "$1"; then
    echo "se mantiene en-curso en #$1: libera el candado con kit-issue.sh liberar-eje y quita la etiqueta a mano" >&2
    return 1
  fi
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
    list="$(gh issue list --repo "$slug" --state open --limit 1000 --json number,title,labels,author,body)" \
      || { echo "error: no se pudo listar los issues" >&2; exit 2; }
    # only issues opened by this gh account: anyone can open an issue in a public repo, and kit-run acts on it unattended
    me="$(gh api user --jq .login)" && [ -n "$me" ] || { echo "error: no se pudo leer el usuario de gh (gh api user)" >&2; exit 2; }
    # every open issue with why it stays out ("" = in the pool), in the order siguiente picks them. why: an excluding
    # label, the changelog issue, another author, an open dependency or, in a cloud session, no entorno:nube.
    # A dependency is "Depende de #N[ (nota)][, #M y #K]" or "Bloqueado por #N" opening a line, list item or sentence of an own
    # body, with the references right after the phrase ("No depende de #N" or "depende de X, como #N" are not).
    all="$(printf '%s' "$list" | jq -c --arg me "$me" --arg env "$(kit_transport)" --argjson x "$EXCLUDED" '
        def rank: if index("prio:alta") then 0 elif index("prio:media") then 1 elif index("prio:baja") then 3 else 2 end;
        def axes: [.labels[].name | select(startswith("serializa:"))];
        map(.number) as $open
        | ([.[] | select([.labels[].name] | index("en-curso")) | .number as $n | axes[] | {key: ., value: $n}]
           | from_entries) as $held
        | map([.labels[].name] as $l | .number as $n
          | ([$x[] | select(. as $e | $l | index($e))] | first) as $b
          | ([(.body // "") | scan("(?:^|\\n|[.:;!?]\\s+)\\s*(?:[-*]\\s+)?(?i:depende de|bloqueado por)\\s+((?:#[0-9]+(?:\\s*\\([^)\\n]*\\))?(?:\\s*(?:,|\\by\\b)\\s*)?)+)")
              | .[0] | scan("#([0-9]+)") | .[0]
              | tonumber | select(. != $n and (. as $d | $open | index($d)))] | unique) as $deps
          | axes as $ax | ([$ax[] | select($held[.] != null and $held[.] != $n) | "\(.) en #\($held[.])"]) as $busy
          | {number, title, mine: (.author.login == $me), r: ($l | rank), deps: $deps, busy: $busy,
             why: (if $b != null then "lleva \($b): kit-run no lo coge mientras la tenga"
               elif .title == "📦 Changelog" then "es el registro del changelog"
               elif .author.login != $me then "lo abrió otra cuenta (\(.author.login)): kit-run solo coge issues de \($me)"
               elif ($deps | length) > 0 then "depende de issues abiertos: \($deps | map("#\(.)") | join(", "))"
               elif $env == "nube" and ($l | index("entorno:nube") | not) then "no lleva entorno:nube y esta sesión corre en la nube"
               elif $env == "nube" and ($ax | length) > 0 then "lleva \($ax | join(", ")) y en la nube no se puede tomar su candado"
               elif ($busy | length) > 0 then "su eje está ocupado: \($busy | join(", "))"
               else "" end)})
        | sort_by(.r, .number)')" || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    pool="$(printf '%s' "$all" | jq -c 'map(select(.why == ""))')"
    if [ "$sub" = siguiente ] && [ -n "$want" ]; then
      why="$(printf '%s' "$all" | jq -r --argjson n "$want" '(map(select(.number == $n)) | first) as $i
          | if $i == null then "#\($n) no está abierto o no existe" elif $i.why == "" then "" else "#\($n) \($i.why)" end')"
      [ -z "$why" ] || { echo "$why" >&2; exit 1; }
      echo "$want"
      echo "FIN: $want"
    elif [ "$sub" = siguiente ]; then
      next="$(printf '%s' "$pool" | jq -r --argjson ex "$excl" 'map(select(.number as $n | $ex | index($n) | not)) | first | .number // empty')"
      [ -n "$next" ] || { echo "no hay issues disponibles" >&2; exit 1; }
      echo "$next"
      echo "FIN: $next"
    else
      printf '%s' "$pool" | jq -r '.[] | "#\(.number)\t\(["prio:alta", "prio:media", "sin prio", "prio:baja"][.r])\t\(.title)"'
      waiting="$(printf '%s' "$all" | jq -r '[.[] | select(.mine and (.deps | length) > 0 and (.why | startswith("depende")))
        | "#\(.number) (\(.deps | map("#\(.)") | join(", ")))"] | join(" ")')"
      [ -z "$waiting" ] || echo "esperan a otro issue: $waiting"
      axis="$(printf '%s' "$all" | jq -r '[.[] | select(.why | startswith("su eje")) | "#\(.number) (\(.busy | join(", ")))"] | join(" ")')"
      [ -z "$axis" ] || echo "esperan a que se libere su eje: $axis"
      cloud="$(printf '%s' "$all" | jq -r '[.[] | select(.why | startswith("no lleva entorno")) | "#\(.number)"] | join(" ")')"
      [ -z "$cloud" ] || echo "solo en el Mac (sin entorno:nube): $cloud"
      locked="$(printf '%s' "$all" | jq -r '[.[] | select(.why | contains("no se puede tomar su candado")) | "#\(.number)"] | join(" ")')"
      [ -z "$locked" ] || echo "solo en el Mac (con eje serializa:*, sin candado en la nube): $locked"
      others="$(printf '%s' "$all" | jq -r '[.[] | select((.mine | not) and (.why | startswith("lo abrió"))) | "#\(.number)"] | join(" ")')"
      [ -z "$others" ] || echo "de otras cuentas (nunca entran): $others"
      echo "FIN: $(printf '%s' "$pool" | jq 'length')"
    fi
    ;;

  leer)
    me="$(gh api user --jq .login)" && [ -n "$me" ] || { echo "error: no se pudo leer el usuario de gh (gh api user)" >&2; exit 2; }
    v="$(gh issue view "$want" --repo "$slug" --json number,title,body,state,labels,author,comments)" \
      || { echo "error: no se pudo leer #$want" >&2; exit 2; }
    # every text line is quoted with "| " so no body can forge a "---" delimiter; another account's body is left out
    printf '%s' "$v" | jq -r --arg me "$me" '
      def nl: "\r\n|[\r\n\u000b\u000c\u0085\u2028\u2029]";
      def quote: [splits(nl)] | map("| " + .) | join("\n");
      def flat: gsub(nl; " ");
      "#\(.number) \(.title | flat)",
      "autor: \(.author.login)" + (if .author.login == $me then "" else " (otra cuenta)" end),
      "estado: \(.state)",
      "etiquetas: " + (if (.labels | length) == 0 then "(ninguna)" else [.labels[].name | flat] | join(", ") end),
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

  comprobar)
    v2="$(jq -r --argjson v "$V2_KEYS" 'if type == "object" then [keys_unsorted[] | select(. as $k | $v | index([$k]))] | join(", ") else error("") end' \
      "$root/.agents-kit.json" 2>/dev/null)" || { echo "error: .agents-kit.json no es JSON válido" >&2; exit 2; }
    have="$(gh label list --repo "$slug" --limit 1000 --json name)" || { echo "error: no se pudieron listar las etiquetas" >&2; exit 2; }
    miss="$(printf '%s' "$have" | jq -r --argjson k "$KIT_LABELS" '[.[].name] as $h | [$k[] | select(. as $l | $h | index([$l]) | not)] | join(", ")')" \
      || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    if [ -n "$miss" ] || [ -n "$v2" ]; then
      {
        echo "kit en versión anterior: ejecuta kit-on para actualizar"
        [ -z "$miss" ] || echo "faltan etiquetas del kit en el repo: $miss"
        [ -z "$v2" ] || echo "el marcador .agents-kit.json tiene claves de la v2: $v2"
      } >&2
      exit 1
    fi
    echo "FIN: v3"
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
    own_login
    # en-curso always excludes, whoever set it (another kit agent or another flow without kit markers)
    l="$(has_label "$n" en-curso)" || { echo "error: no se pudo leer las etiquetas de #$n" >&2; exit 2; }
    [ "$l" = true ] && { echo "#$n ya tiene en-curso: otro agente u otro flujo lo está trabajando" >&2; exit 1; }
    axes="$(axes_of "$n")" || { echo "error: no se pudo leer las etiquetas de #$n" >&2; exit 2; }
    if [ -n "$axes" ] && [ "$(kit_transport)" = nube ]; then
      echo "#$n lleva $(printf '%s' "$axes" | tr '\n' ' ' | sed 's/ *$//') y en la nube no se puede tomar su candado" >&2
      exit 1
    fi
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
    # the claim is won: now the axis locks (after, not before, so the loser of a claim race never holds one)
    for e in $axes; do
      lock_take "$e" "$id" "$n"; rc=$?
      [ $rc -eq 0 ] && { echo "candado: $(lock_ref "$e")"; continue; }
      if [ $rc -eq 1 ]; then
        o="$(lock_owner "$e")" || o="desconocido"
        reason="el eje $e lo tiene otro ($o)"; code=1
      else
        reason="no se pudo tomar el candado de $e (red o git)"; code=2
      fi
      release "$n" "$id" "$reason" || echo "aviso: no se pudo deshacer la reclamación de #$n" >&2
      echo "#$n: $reason; reclamación deshecha" >&2
      exit $code
    done
    echo "FIN: reclamado #$n"
    ;;

  soltar)
    own_login
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
    own_login
    require_not_foreign "$n" "$id"
    comment "$n" "$marker
$text" || { echo "error: no se pudo comentar en #$n" >&2; exit 2; }
    gh issue edit "$n" --repo "$slug" --add-label "$label" --add-assignee @me >/dev/null \
      || { echo "error: no se pudo marcar #$n como $label" >&2; exit 2; }
    release "$n" "$id" "$motivo" || { echo "error: no se pudo soltar #$n" >&2; exit 2; }
    notify "$n" "$aviso"
    echo "FIN: $label #$n"
    ;;

  liberar-eje)
    o="$(lock_owner "$eje")"; rc=$?
    [ $rc -eq 1 ] && { echo "el eje $eje no tiene candado" >&2; exit 1; }
    [ $rc -eq 0 ] || { echo "error: no se pudo leer el candado $(lock_ref "$eje")" >&2; exit 2; }
    ref="$(lock_ref "$eje")"
    sha="$(git ls-remote origin "$ref" | cut -f1)" && [ -n "$sha" ] || { echo "error: no se pudo leer $ref" >&2; exit 2; }
    git push -q --force-with-lease="$ref:$sha" origin ":$ref" >/dev/null 2>&1 \
      || { echo "error: no se pudo borrar $ref" >&2; exit 2; }
    echo "liberado $ref (era: $o)"
    echo "FIN: liberado $eje"
    ;;

  crear)
    read_file "$file" >/dev/null || exit 1
    list="$(gh issue list --repo "$slug" --state open --limit 1000 --json number,title)" \
      || { echo "error: no se pudo listar los issues" >&2; exit 2; }
    dup="$(printf '%s' "$list" | jq -r --arg t "$title" \
      'map(select((.title | ascii_downcase) == ($t | ascii_downcase))) | first | .number // empty')" \
      || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    [ -z "$dup" ] || { echo "ya existe #$dup con ese título" >&2; exit 1; }
    largs=(--label "prio:$prio" --label "entorno:$entorno")
    $propuesta && largs+=(--label propuesta)
    for e in ${extra[@]+"${extra[@]}"}; do largs+=(--label "$e"); done
    url="$(gh issue create --repo "$slug" --title "$title" --body-file "$file" "${largs[@]}")" \
      || { echo "error: no se pudo crear el issue (¿existen en el repo todas las etiquetas? kit-on crea las del kit)" >&2; exit 2; }
    case "$url" in https://*) ;; *) echo "error: gh no devolvió la URL del issue" >&2; exit 2 ;; esac
    echo "$url"
    echo "FIN: $url"
    ;;
esac
