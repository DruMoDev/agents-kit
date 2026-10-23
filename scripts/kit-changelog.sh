#!/usr/bin/env bash
# Usage: scripts/kit-changelog.sh <subcomando> <root> [args...]
#   validar <root>
#   resumen <root> <id> <fichero>
# validar: formato de CHANGELOG.md (el de templates/CHANGELOG.md); lo que esté dentro de <!-- ... --> o de un
#   bloque de código (``` o ~~~) se ignora; un <!-- sin cerrar es un error. El enlace pendiente "[#PR](PR)" es válido
#   (la entrada va en el commit del código y kit-pr.sh abrir lo rellena); fusionar no deja pasarlo sin rellenar.
# resumen: comenta el fichero en el issue abierto "📦 Changelog" con el marcador <!-- kit-resumen: <id> -->;
#   si ya hay un comentario propio (login de `gh api user`) con ese marcador, no publica otro. FIN: <url del comentario>.
#   Con "changelog": false en el marcador no publica nada: FIN: sin-changelog.
# Exit: 0 ok, 1 rechazo (errores "CHANGELOG.md:<línea>: <motivo>" en stderr), 2 error de entorno.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/config.sh"
source "$here/lib/github-slug.sh"

usage() {
  echo "uso: $0 validar <root> | resumen <root> <id> <fichero>" >&2
  exit 1
}

[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1"; shift
case "$sub" in validar|resumen) ;; *) usage ;; esac
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
root="$(cd "$1" && pwd)"; shift
kit_require_marker "$root" || exit 1

case "$sub" in
  validar)
    [ $# -eq 0 ] || usage
    f="$root/CHANGELOG.md"
    if [ ! -f "$f" ]; then echo "FIN: sin-changelog"; exit 0; fi
    errs=0 entries=""
    # awk emits ERR<TAB>line<TAB>msg, IMG<TAB>line<TAB>path and a final COUNT<TAB>n
    while IFS=$'\t' read -r kind a b; do
      case "$kind" in
        ERR) echo "CHANGELOG.md:$a: $b" >&2; errs=$((errs + 1)) ;;
        COUNT) entries="$a" ;;
        IMG)
          case "$b" in
            http://*|https://*) ;;
            *)
              if [ ! -f "$root/$b" ]; then
                echo "CHANGELOG.md:$a: la imagen '$b' no existe" >&2; errs=$((errs + 1))
              elif [ "$(wc -c < "$root/$b")" -gt 512000 ]; then
                echo "aviso: CHANGELOG.md:$a: la imagen '$b' pesa más de 500 KB" >&2
              fi ;;
          esac ;;
      esac
    done < <(awk '
      function err(m) { printf "ERR\t%d\t%s\n", NR, m }
      function leap(y) { return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }
      function validdate(s,   y, m, d, dm) {
        y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
        if (m < 1 || m > 12) return 0
        dm = substr("312831303130313130313031", (m - 1) * 2 + 1, 2) + 0
        if (m == 2 && leap(y)) dm = 29
        return d >= 1 && d <= dm
      }
      {
        line = $0; sub(/\r$/, "", line); vis = ""
        # fenced code blocks: nothing inside counts (headings, images, comments)
        if (!inc) {
          if (fence != "") { if (index(line, fence) == 1) fence = ""; next }
          if (line ~ /^```/) { fence = "```"; next }
          if (line ~ /^~~~/) { fence = "~~~"; next }
        }
        while (line != "") {
          if (inc) {
            p = index(line, "-->")
            if (!p) { line = ""; break }
            line = substr(line, p + 3); inc = 0
          } else {
            p = index(line, "<!--")
            if (!p) { vis = vis line; line = ""; break }
            vis = vis substr(line, 1, p - 1); line = substr(line, p + 4); inc = 1; cline = NR
          }
        }
        if (vis ~ /^###? /) sub(/[ \t]+$/, "", vis)
        if (vis ~ /^## /) {
          if (vis !~ /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { err("fecha con formato inválido (## YYYY-MM-DD): " vis); date = ""; ndate = 1 }
          else {
            d = substr(vis, 4)
            if (!validdate(d)) err("fecha inexistente: " d)
            else if (prev != "" && d == prev) err("fecha repetida: " d)
            else if (prev != "" && d > prev) err("las fechas deben ir en orden descendente: " d " va después de " prev)
            prev = d; date = d; ndate = 1
          }
        } else if (vis ~ /^### /) {
          if (!ndate) err("entrada fuera de una fecha")
          if (vis !~ /^### (Nuevo|Mejora|Arreglo|Interno): /) err("tipo inválido (Nuevo, Mejora, Arreglo o Interno): " vis)
          else {
            rest = substr(vis, index(vis, ": ") + 2); sep = " · [#"; pos = 0; off = 0; tmp = rest
            while ((q = index(tmp, sep)) > 0) { pos = off + q; off += q; tmp = substr(tmp, q + 1) }
            if (!pos) err("falta el final \" · [#N](enlace)\": " vis)
            else {
              title = substr(rest, 1, pos - 1); tail = substr(rest, pos + length(sep))
              if (title ~ /^[ \t]*$/) err("título vacío")
              if (tail == "PR](PR)") entries++ # placeholder of an entry whose PR does not exist yet (kit-pr.sh abrir fills it)
              else if (tail !~ /^[0-9]+\]\(https:\/\/github\.com\/[^\/ ()]+\/[^\/ ()]+\/pull\/[0-9]+\)$/) err("enlace inválido (https://github.com/<owner>/<repo>/pull/<N>): " tail)
              else {
                n = tail; sub(/\].*/, "", n)
                u = tail; sub(/.*\/pull\//, "", u); sub(/\)$/, "", u)
                if (n + 0 != u + 0) err("el número de la PR (#" n ") no coincide con el del enlace (" u ")")
                else entries++
              }
            }
          }
        }
        s = vis
        while (match(s, /!\[[^]]*\]\([^)]*\)/)) {
          ref = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
          sub(/^!\[[^]]*\]\(/, "", ref); sub(/\)$/, "", ref); sub(/[ \t].*/, "", ref)
          printf "IMG\t%d\t%s\n", NR, ref
        }
      }
      END {
        if (inc) printf "ERR\t%d\t%s\n", cline, "comentario <!-- sin cerrar"
        printf "COUNT\t%d\n", entries + 0
      }
    ' "$f")
    # no COUNT line: awk failed, so nothing was validated
    [ -n "$entries" ] || { echo "error: no se pudo validar CHANGELOG.md" >&2; exit 2; }
    [ "$errs" -eq 0 ] || exit 1
    echo "FIN: valido $entries entradas"
    ;;

  resumen)
    [ $# -eq 2 ] || usage
    id="$1"; file="$2"
    # the id goes inside an HTML comment: keep it to a safe token
    [[ $id =~ ^[A-Za-z0-9._-]+$ ]] || { echo "id inválido: $id" >&2; exit 1; }
    [ -f "$file" ] && [ -r "$file" ] || { echo "no se puede leer el fichero: $file" >&2; exit 1; }
    # "changelog": false: no CHANGELOG.md nor "📦 Changelog" issue; the summary stays in the chat and the notice
    cl="$(kit_config "$root" '.changelog')" || exit 2
    if [ "$cl" = false ]; then
      echo "sin changelog: el marcador dice \"changelog\": false; el resumen va solo al chat y al aviso"
      echo "FIN: sin-changelog"
      exit 0
    fi
    for c in gh git jq; do
      command -v "$c" >/dev/null 2>&1 || { echo "error: falta '$c' en el PATH" >&2; exit 2; }
    done
    cd "$root" || exit 2
    slug="$(kit_origin_slug)"
    [ -n "$slug" ] || { echo "error: el remoto 'origin' no es de GitHub" >&2; exit 2; }
    title="📦 Changelog"; marker="<!-- kit-resumen: $id -->"
    list="$(gh issue list --repo "$slug" --state open --search "in:title $title" --limit 100 --json number,title)" \
      || { echo "error: no se pudo listar los issues" >&2; exit 2; }
    n="$(printf '%s' "$list" | jq -r --arg t "$title" 'map(select(.title == $t)) | min_by(.number) | .number // empty')" \
      || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    [ -n "$n" ] || { echo "no hay issue \"$title\": ejecuta kit-on" >&2; exit 2; }
    # markers are trusted only from this run's gh login
    me="$(gh api user --jq .login)" && [ -n "$me" ] \
      || { echo "error: no se pudo leer el usuario de gh (gh api user)" >&2; exit 2; }
    comments="$(gh issue view "$n" --repo "$slug" --json comments)" \
      || { echo "error: no se pudo leer los comentarios de #$n" >&2; exit 2; }
    url="$(printf '%s' "$comments" | jq -r --arg me "$me" --arg m "$marker" \
      '[.comments[] | select(.author.login == $me and ((.body // "") | startswith($m)))] | first | .url // empty')" \
      || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    if [ -n "$url" ]; then
      echo "resumen ya publicado: $url"
    else
      body="$(mktemp)" || exit 2
      trap 'rm -f "$body"' EXIT
      { printf '%s\n' "$marker"; cat "$file"; } > "$body"
      url="$(gh issue comment "$n" --repo "$slug" --body-file "$body")" \
        || { echo "error: no se pudo comentar en #$n" >&2; exit 2; }
      case "$url" in https://*) ;; *) echo "error: gh no devolvió la URL del comentario" >&2; exit 2 ;; esac
      echo "$url"
    fi
    echo "FIN: $url"
    ;;
esac
