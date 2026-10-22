#!/usr/bin/env bash
# Usage: scripts/kit-review-all.sh <wt> <pr> <ronda> <N>
# Launches every reviewer from .agents-kit.json (kit_reviewers) in parallel with kit-review.sh and waits for all.
# Prints one "revisor <i> (<herramienta>/<modelo>): exit <rc>" line each, then "salidas: <dir>" (rev-<i>.out
# and revisores.tsv inside) and "FIN: <n> revisores".
# Exit: 0 all launched and waited (read each exit), 1 usage or no reviewers configured, 2 environment error.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/config.sh"
review="${KIT_REVIEW_BIN:-$here/kit-review.sh}"

[ $# -eq 4 ] && [ -n "$1" ] || { echo "uso: $0 <wt> <pr> <ronda> <N>" >&2; exit 1; }
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
wt="$(cd "$1" && pwd)"
kit_require_marker "$wt" || exit $?
list="$(kit_reviewers "$wt")" || exit 2
d="$(mktemp -d)" || exit 2

i=0; pids=()
while IFS=$'\t' read -r tool model focus; do
  [ -n "$tool" ] && [ -n "$model" ] && [ -n "$focus" ] || continue
  i=$((i + 1)); printf '%s\t%s\t%s\t%s\n' "$i" "$tool" "$model" "$focus" >> "$d/revisores.tsv"
  "$review" "$wt" "$2" "$tool" "$model" "$focus" "$3" "$4" > "$d/rev-$i.out" 2>&1 </dev/null &
  pids+=("$!")
done <<< "$list"
if [ "$i" -eq 0 ]; then
  echo "sin revisores en .agents-kit.json" >&2
  exit 1
fi

for j in "${!pids[@]}"; do
  wait "${pids[$j]}"; rc=$?
  k=$((j + 1))
  echo "revisor $k ($(awk -F'\t' -v k="$k" '$1 == k { print $2 "/" $3 }' "$d/revisores.tsv")): exit $rc"
done
echo "salidas: $d"
echo "FIN: $i revisores"
