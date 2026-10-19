#!/usr/bin/env bash
# Usage: scripts/kit-issue.sh <subcomando> <root> [args...]
#   siguiente <root>
#   reclamar  <root> <N> <id>
#   soltar    <root> <N> <id> [motivo]
#   decision  <root> <N> <id> <fichero-pregunta>
#   bloquear  <root> <N> <id> <fichero-motivo>
#   crear     <root> <titulo> <fichero-cuerpo> <listo|propuesta>
# Issue state for the agent flow. Claims live in HTML-comment markers on the issue.
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error or undecidable.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/github-slug.sh"
source "$here/lib/config.sh"

usage() {
  echo "uso: $0 siguiente <root> | reclamar <root> <N> <id> | soltar <root> <N> <id> [motivo] |" \
    "decision <root> <N> <id> <fichero> | bloquear <root> <N> <id> <fichero> |" \
    "crear <root> <titulo> <fichero-cuerpo> <listo|propuesta>" >&2
  exit 1
}

[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1"; shift
case "$sub" in siguiente|reclamar|soltar|decision|bloquear|crear) ;; *) usage ;; esac
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
root="$(cd "$1" && pwd)"; shift
kit_require_marker "$root" || exit $?

case "$sub" in
  siguiente) [ $# -eq 0 ] || usage ;;
  reclamar) [ $# -eq 2 ] || usage ;;
  soltar) [ $# -eq 2 ] || [ $# -eq 3 ] || usage ;;
  decision|bloquear|crear) [ $# -eq 3 ] || usage ;;
esac
if [ "$sub" != siguiente ] && [ "$sub" != crear ]; then
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
read_file() { # <path>: print contents or exit 1
  [ -f "$1" ] && [ -r "$1" ] || { echo "no se puede leer el fichero: $1" >&2; exit 1; }
  cat "$1"
}

case "$sub" in
  siguiente)
    list="$(gh issue list --repo "$slug" --state open --label listo --limit 1000 --json number,labels)" \
      || { echo "error: no se pudo listar los issues" >&2; exit 2; }
    next="$(printf '%s' "$list" | jq -r 'map(select([.labels[].name] as $l
        | ["en-curso", "necesita-decision", "bloqueado"] | any(. as $x | $l | index($x)) | not))
      | min_by(.number) | .number // empty')" || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    [ -n "$next" ] || { echo "no hay issues listos" >&2; exit 1; }
    echo "$next"
    echo "FIN: $next"
    ;;

  reclamar)
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
      marker="<!-- kit-decision -->"; label=necesita-decision; motivo="necesita decisión de producto"
    else
      marker="<!-- kit-bloqueado -->"; label=bloqueado; motivo="bloqueado"
    fi
    require_not_foreign "$n" "$id"
    comment "$n" "$marker
$text" || { echo "error: no se pudo comentar en #$n" >&2; exit 2; }
    gh issue edit "$n" --repo "$slug" --add-label "$label" --add-assignee @me >/dev/null \
      || { echo "error: no se pudo marcar #$n como $label" >&2; exit 2; }
    release "$n" "$id" "$motivo" || { echo "error: no se pudo soltar #$n" >&2; exit 2; }
    echo "FIN: $label #$n"
    ;;

  crear)
    title="$1"; file="$2"; label="$3"
    [ -n "$title" ] || usage
    case "$label" in listo|propuesta) ;; *) echo "etiqueta inválida: $label (listo o propuesta)" >&2; exit 1 ;; esac
    read_file "$file" >/dev/null || exit 1
    list="$(gh issue list --repo "$slug" --state open --limit 1000 --json number,title)" \
      || { echo "error: no se pudo listar los issues" >&2; exit 2; }
    dup="$(printf '%s' "$list" | jq -r --arg t "$title" \
      'map(select((.title | ascii_downcase) == ($t | ascii_downcase))) | first | .number // empty')" \
      || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    [ -z "$dup" ] || { echo "ya existe #$dup con ese título" >&2; exit 1; }
    url="$(gh issue create --repo "$slug" --title "$title" --body-file "$file" --label "$label")" \
      || { echo "error: no se pudo crear el issue" >&2; exit 2; }
    case "$url" in https://*) ;; *) echo "error: gh no devolvió la URL del issue" >&2; exit 2 ;; esac
    echo "$url"
    echo "FIN: $url"
    ;;
esac
