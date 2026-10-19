#!/usr/bin/env bash
# Run every tests/test_*.sh; exit non-zero if any fails.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
failed=0
for t in test_*.sh; do
  [ -e "$t" ] || continue
  echo "== $t"
  if bash "$t"; then echo "PASS $t"; else echo "FAIL $t"; failed=1; fi
done
exit $failed
