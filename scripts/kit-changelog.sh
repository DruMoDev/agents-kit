#!/usr/bin/env bash
# Usage: scripts/kit-changelog.sh <subcomando> <root> [args...]
#   validar <root>
# Formato de CHANGELOG.md (el de templates/CHANGELOG.md); lo que esté dentro de <!-- ... --> se ignora.
# Exit: 0 ok, 1 rechazo (errores "CHANGELOG.md:<línea>: <motivo>" en stderr), 2 error de entorno.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/config.sh"

usage() {
  echo "uso: $0 validar <root>" >&2
  exit 1
}

[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1"; shift
case "$sub" in validar) ;; *) usage ;; esac
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
root="$(cd "$1" && pwd)"; shift
kit_require_marker "$root" || exit 1

case "$sub" in
  validar)
    [ $# -eq 0 ] || usage
    f="$root/CHANGELOG.md"
    if [ ! -f "$f" ]; then echo "FIN: sin-changelog"; exit 0; fi
    errs=0 entries=0
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
        while (line != "") {
          if (inc) {
            p = index(line, "-->")
            if (!p) { line = ""; break }
            line = substr(line, p + 3); inc = 0
          } else {
            p = index(line, "<!--")
            if (!p) { vis = vis line; line = ""; break }
            vis = vis substr(line, 1, p - 1); line = substr(line, p + 4); inc = 1
          }
        }
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
              if (tail !~ /^[0-9]+\]\(https:\/\/github\.com\/[^\/ ()]+\/[^\/ ()]+\/pull\/[0-9]+\)$/) err("enlace inválido (https://github.com/<owner>/<repo>/pull/<N>): " tail)
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
          sub(/^!\[[^]]*\]\(/, "", ref); sub(/\)$/, "", ref)
          printf "IMG\t%d\t%s\n", NR, ref
        }
      }
      END { printf "COUNT\t%d\n", entries + 0 }
    ' "$f")
    [ "$errs" -eq 0 ] || exit 1
    echo "FIN: valido $entries entradas"
    ;;
esac
