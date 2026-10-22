#!/usr/bin/env bash
# Usage: scripts/kit-review-all.sh <wt> <pr> <ronda> <N> [--implementador <familia>]
# Runs every review seat of revision.puestos in parallel with kit-review.sh and waits for all. Each seat tries its
# candidates (lib/review-seats.sh: CLI in the PATH, other family first) in order: a login, model or quota failure
# (motivo acceso) moves on to the next candidate; any other failure, or no candidate left, leaves the seat
# unconfirmed, and a "<!-- kit-revision: puesto <i> sin-confirmar ronda <r> -->" comment says so on the PR.
# The implementer family comes from --implementador or the environment (CODEX_THREAD_ID -> gpt, CLAUDECODE -> claude).
# Prints per seat "puesto <i> (<familia>/<modelo>): ok | sin-confirmar (<motivo>) | fallback a <familia>/<modelo>"
# (plus "aviso: ..." lines), then "salidas: <dir>" (rev-<i>.out, the output of the seat's last attempt, and
# puestos.tsv: i, familia, cli, modelo, foco, estado, detalle) and "FIN: <n> puestos, <m> sin confirmar".
# Exit: 0 all seats ran (read each state), 1 usage, unknown family or no seats, 2 unknown implementer or broken config.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/config.sh"
source "$here/lib/review-seats.sh"
source "$here/lib/github-slug.sh"
review="${KIT_REVIEW_BIN:-$here/kit-review.sh}"

usage() { echo "uso: $0 <wt> <pr> <ronda> <N> [--implementador <familia>]" >&2; exit 1; }
[ $# -ge 4 ] && [ -n "$1" ] || usage
wt_arg="$1" p="$2" round="$3" n="$4"; shift 4
impl_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --implementador) [ $# -ge 2 ] && [ -n "$2" ] || usage; impl_arg="$2"; shift 2 ;;
    *) usage ;;
  esac
done
for x in "$p" "$round" "$n"; do [[ $x =~ ^[1-9][0-9]*$ ]] || usage; done
[ -d "$wt_arg" ] || { echo "error: '$wt_arg' no es un directorio" >&2; exit 2; }
wt="$(cd "$wt_arg" && pwd)"
kit_require_marker "$wt" || exit $?
impl="$(kit_implementer_family "$impl_arg")" || exit 2
cands="$(kit_seat_candidates "$wt" "$impl")" || exit $?
if [ -z "$cands" ]; then
  echo "sin puestos de revisión configurados (revision.puestos)" >&2
  exit 1
fi
d="$(mktemp -d)" || exit 2
printf '%s\n' "$cands" > "$d/candidatos.tsv"
seats="$(cut -f1 "$d/candidatos.tsv" | uniq)"

# run_seat <i>: try the seat's candidates in order; writes puesto-<i>.log (lines to print) and puesto-<i>.tsv
run_seat() {
  local i="$1" s j fam cli model focus nota prev="" rc motivo detalle out
  local log="$d/puesto-$i.log"
  : > "$log"; : > "$d/puesto-$i.avisos"
  while IFS=$'\t' read -r s j fam cli model focus nota; do
    [ "$s" = "$i" ] || continue
    if [ "$j" = 0 ]; then
      echo "puesto $i ($fam): sin-confirmar (ningún CLI de revisión disponible en el PATH para este puesto)" >> "$log"
      printf '%s\t%s\t-\t-\t%s\tsin-confirmar\tningún CLI de revisión disponible\n' "$i" "$fam" "$focus" > "$d/puesto-$i.tsv"
      return
    fi
    [ -z "$prev" ] || echo "puesto $i ($prev): fallback a $fam/$model" >> "$log"
    out="$d/rev-$i-$j.out"
    "$review" "$wt" "$p" "$i" "$fam" "$cli" "$model" "$focus" "$round" "$n" > "$out" 2>&1 </dev/null
    rc=$?
    cp "$out" "$d/rev-$i.out"
    if [ $rc -eq 0 ]; then
      echo "puesto $i ($fam/$model): ok${nota:+ (misma familia: no hay otra familia disponible)}" >> "$log"
      printf '%s\t%s\t%s\t%s\t%s\tok\t%s\n' "$i" "$fam" "$cli" "$model" "$focus" "$nota" > "$d/puesto-$i.tsv"
      return
    fi
    motivo="$(sed -n 's/^sin confirmar (\([a-z]*\)): .*/\1/p' "$out" | sed -n '$p')"
    detalle="$(sed -n 's/^sin confirmar ([a-z]*): //p' "$out" | sed -n '$p')"
    if [ -z "$motivo" ]; then
      motivo=entorno
      detalle="kit-review.sh terminó con código $rc"
    fi
    printf '%s\t%s\t%s\t%s\t%s\tsin-confirmar\t%s: %s\n' "$i" "$fam" "$cli" "$model" "$focus" "$motivo" "$detalle" > "$d/puesto-$i.tsv"
    if [ "$motivo" = acceso ]; then
      echo "aviso: $fam/$model ($cli) no respondió: revisa el login, el modelo o la cuota ($detalle)" >> "$d/puesto-$i.avisos"
      prev="$fam/$model"
      continue
    fi
    echo "puesto $i ($fam/$model): sin-confirmar ($motivo: $detalle)" >> "$log"
    return
  done < "$d/candidatos.tsv"
  # every candidate failed with acceso
  echo "puesto $i ($prev): sin-confirmar ($(cut -f7 "$d/puesto-$i.tsv"))" >> "$log"
}

pids=""
for i in $seats; do
  run_seat "$i" &
  pids="$pids $!"
done
for pid in $pids; do wait "$pid"; done

: > "$d/puestos.tsv"
k=0; u=0
for i in $seats; do
  k=$((k + 1))
  cat "$d/puesto-$i.log"
  cat "$d/puesto-$i.tsv" >> "$d/puestos.tsv"
done
# one warning per failing provider, however many seats hit it
for i in $seats; do cat "$d/puesto-$i.avisos"; done | awk '!seen[$0]++'
# unconfirmed seats are said on the PR (best effort: fusionar asks for a confirmed review per seat in any case)
unconf="$(awk -F'\t' '$6 == "sin-confirmar"' "$d/puestos.tsv")"
if [ -n "$unconf" ]; then
  slug="$(cd "$wt" && kit_origin_slug)"
  while IFS=$'\t' read -r i fam cli model focus _ detalle; do
    u=$((u + 1))
    who="$fam/$model"; [ "$model" != - ] || who="$fam"
    {
      echo "<!-- kit-revision: puesto $i sin-confirmar ronda $round -->"
      echo "### Revisión del puesto $i sin confirmar, ronda $round"
      echo
      echo "**Foco:** $focus"
      echo "**Último intento:** $who: $detalle"
      echo
      echo "Este puesto no entregó una revisión válida: la ronda $round no cuenta como completa hasta que la entregue."
    } > "$d/sin-confirmar-$i.md"
    if [ -z "$slug" ] || ! gh pr comment "$p" --repo "$slug" --body-file "$d/sin-confirmar-$i.md" >/dev/null 2>&1; then
      echo "aviso: no se pudo publicar en la PR #$p que el puesto $i quedó sin confirmar"
    fi
  done <<< "$unconf"
fi
echo "salidas: $d"
echo "FIN: $k puestos, $u sin confirmar"
