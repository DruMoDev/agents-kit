#!/usr/bin/env bash
# Usage: scripts/kit-review-all.sh <wt> <pr> <ronda> <N> [--implementador <familia>] [--completa]
# Runs every review seat of revision.puestos in parallel with kit-review.sh and waits for all. Each seat tries its
# candidates (lib/review-seats.sh: CLI in the PATH, other family first) in order: a login, model or quota failure
# (motivo acceso) moves on to the next candidate; any other failure, or no candidate left, leaves the seat
# unconfirmed, and a "<!-- kit-revision: puesto <i> sin-confirmar ronda <r> -->" comment says so on the PR.
# The seats come from the marker of origin/<default branch> (fetched once here, before launching; each seat gets its
# SHA in KIT_REVIEW_BASE and never fetches), the same source fusionar counts them from. INT/TERM/HUP stop every seat.
# The implementer family comes from --implementador or the environment (CODEX_THREAD_ID -> gpt, CLAUDECODE -> claude).
# Prints per seat "puesto <i> (<familia>/<modelo>): ok | sin-confirmar (<motivo>) | fallback a <familia>/<modelo>"
# (plus "aviso: ..." lines), then "salidas: <dir>" (rev-<i>.out, the output of the seat's last attempt; rev-<i>-<j>.out
# only for earlier attempts that fell back to the next candidate; and
# puestos.tsv: i, familia, cli, modelo, foco, estado, detalle, modo) and "FIN: <n> puestos, <m> sin confirmar".
# Mode per seat (KIT_REVIEW_MODO for kit-review.sh): with revision.rondas "mezcla" (global config, the default), from
# round 2 one seat, rotating by round, reviews the whole diff with a clean context (completa) and the others only check
# that the previous round's fixes solve its findings without breaking anything (verificar); with "completas", in
# round 1, or with --completa (the first round of a resumed issue: its new code is not a fix of the last round), every
# seat reviews the whole diff. A "modo: ..." line says which seat is the independent one.
# Exit: 0 all seats ran (read each state), 1 usage, unknown family or no seats, 2 unknown implementer, broken config or
# git (default branch or fetch).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/config.sh"
source "$here/lib/review-seats.sh"
source "$here/lib/github-slug.sh"
source "$here/lib/default-branch.sh"
review="${KIT_REVIEW_BIN:-$here/kit-review.sh}"

usage() { echo "uso: $0 <wt> <pr> <ronda> <N> [--implementador <familia>] [--completa]" >&2; exit 1; }
[ $# -ge 4 ] && [ -n "$1" ] || usage
wt_arg="$1" p="$2" round="$3" n="$4"; shift 4
impl_arg="" force_full=false
while [ $# -gt 0 ]; do
  case "$1" in
    --implementador) [ $# -ge 2 ] && [ -n "$2" ] || usage; impl_arg="$2"; shift 2 ;;
    --completa) force_full=true; shift ;;
    *) usage ;;
  esac
done
for x in "$p" "$round" "$n"; do [[ $x =~ ^[1-9][0-9]*$ ]] || usage; done
[ -d "$wt_arg" ] || { echo "error: '$wt_arg' no es un directorio" >&2; exit 2; }
wt="$(cd "$wt_arg" && pwd)"
kit_require_marker "$wt" || exit $?
impl="$(kit_implementer_family "$impl_arg")" || exit 2
b="$(cd "$wt" && kit_default_branch)"
[ -n "$b" ] || { echo "error: no pude saber la rama por defecto de origin" >&2; exit 2; }
(cd "$wt" && kit_fetch origin "+refs/heads/$b:refs/remotes/origin/$b") || { echo "error: git fetch falló" >&2; exit 2; }
KIT_REVIEW_BASE="$(git -C "$wt" rev-parse --verify -q "refs/remotes/origin/$b^{commit}")" \
  || { echo "error: no se pudo leer origin/$b" >&2; exit 2; }
export KIT_REVIEW_BASE
cands="$(kit_seat_candidates "$wt" "$impl" "origin/$b")" || exit $?
if [ -z "$cands" ]; then
  echo "sin puestos de revisión configurados (revision.puestos)" >&2
  exit 1
fi
# in the kit's temp dir (KIT_TMP, default ~/.agents-kit/tmp), where every tool may read it (OpenCode allows it)
kt="${KIT_TMP:-$HOME/.agents-kit/tmp}"
mkdir -p "$kt" && d="$(mktemp -d "$kt/revision.XXXXXX")" || exit 2
printf '%s\n' "$cands" > "$d/candidatos.tsv"
seats="$(cut -f1 "$d/candidatos.tsv" | uniq)"
rondas="$(kit_config "$wt" '.revision.rondas // "mezcla"')" || exit 2
case "$rondas" in mezcla|completas) ;; *) echo "aviso: revision.rondas debe ser mezcla o completas; se usa mezcla ('$rondas')"; rondas=mezcla ;; esac
indep=""
if [ "$rondas" = mezcla ] && [ "$round" -ge 2 ] && [ "$force_full" = false ]; then
  ns="$(printf '%s\n' "$seats" | grep -c .)"
  indep="$(printf '%s\n' "$seats" | sed -n "$(( (round - 2) % ns + 1 ))p")"
  [ "$ns" -gt 1 ] || indep="" # a single seat always reviews everything
fi
seat_mode() { if [ -z "$indep" ] || [ "$1" = "$indep" ]; then echo completa; else echo verificar; fi; }

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
    KIT_REVIEW_MODO="$(seat_mode "$i")" "$review" "$wt" "$p" "$i" "$fam" "$cli" "$model" "$focus" "$round" "$n" > "$out" 2>&1 </dev/null
    rc=$?
    cp "$out" "$d/rev-$i.out"
    if [ $rc -eq 0 ]; then
      echo "puesto $i ($fam/$model): ok${nota:+ (misma familia: no hay otra familia disponible)}" >> "$log"
      printf '%s\t%s\t%s\t%s\t%s\tok\t%s\n' "$i" "$fam" "$cli" "$model" "$focus" "$nota" > "$d/puesto-$i.tsv"
      rm -f "$out" # rev-<i>.out holds it: only attempts that fell back keep their own rev-<i>-<j>.out
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
    rm -f "$out"
    return
  done < "$d/candidatos.tsv"
  # every candidate failed with acceso
  echo "puesto $i ($prev): sin-confirmar ($(cut -f7 "$d/puesto-$i.tsv"))" >> "$log"
}

pids=""
# stop_seats: TERM each seat's kit-review.sh (its own trap stops the reviewer's process group), then the seat itself
stop_seats() {
  local pid
  for pid in $pids; do
    pkill -TERM -P "$pid" 2>/dev/null
    kill -TERM "$pid" 2>/dev/null
  done
  wait 2>/dev/null
  exit 130
}
trap stop_seats INT TERM HUP
for i in $seats; do
  run_seat "$i" &
  pids="$pids $!"
done
for pid in $pids; do wait "$pid"; done
trap - INT TERM HUP

: > "$d/puestos.tsv"
k=0; u=0
[ -z "$indep" ] || echo "modo: ronda $round (revision.rondas mezcla): el puesto $indep revisa todo el diff con contexto limpio; los demás revisan lo que cambió desde la ronda $((round - 1)) y sus arreglos"
for i in $seats; do
  k=$((k + 1))
  cat "$d/puesto-$i.log"
  printf '%s\t%s\n' "$(cat "$d/puesto-$i.tsv")" "$(seat_mode "$i")" >> "$d/puestos.tsv"
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
