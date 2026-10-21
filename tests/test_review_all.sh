#!/usr/bin/env bash
# Tests for scripts/kit-review-all.sh (kit-review.sh replaced by a stub through KIT_REVIEW_BIN).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
all="$REPO_ROOT/scripts/kit-review-all.sh"
stub="$(mktemp -d)/review"
cat > "$stub" <<'EOF'
#!/usr/bin/env bash
# args: wt pr tool model focus round N; opus fails, the rest succeed
echo "args: $*"
[ "$4" = opus ] && exit 2
exit 0
EOF
chmod +x "$stub"
export KIT_REVIEW_BIN="$stub"

r="$(mk_repo)"
cat > "$r/.agents-kit.json" <<'EOF'
{"reviewers": {"claude": [{"model": "opus", "focus": "a"}, {"model": "sonnet", "focus": "b c"}],
               "opencode": [{"model": "openai/x", "focus": "d"}]}}
EOF
out="$(zsh -c '"$1" "$2" 7 2 3' _ "$all" "$r" 2>&1)"; rc=$?
[ $rc -eq 0 ] || fail "exit $rc ($out)"
grep -qx "revisor 1 (claude/opus): exit 2" <<<"$out" || fail "revisor 1: $out"
grep -qx "revisor 2 (claude/sonnet): exit 0" <<<"$out" || fail "revisor 2: $out"
grep -qx "revisor 3 (opencode/openai/x): exit 0" <<<"$out" || fail "revisor 3: $out"
[ "$(printf '%s\n' "$out" | sed -n '$p')" = "FIN: 3 revisores" ] || fail "FIN: $out"
d="$(sed -n 's/^salidas: //p' <<<"$out")"
grep -qx "args: $r 7 claude sonnet b c 2 3" "$d/rev-2.out" || fail "args sonnet: $(cat "$d/rev-2.out")"
[ "$(wc -l < "$d/revisores.tsv" | tr -d ' ')" = 3 ] || fail "revisores.tsv"

# no reviewers
echo '{"reviewers": {}}' > "$r/.agents-kit.json"
err="$(bash "$all" "$r" 7 2 3 2>&1)"; rc=$?
[ $rc -eq 1 ] || fail "sin revisores: exit $rc"
grep -q "sin revisores" <<<"$err" || fail "sin revisores msg: $err"

# broken marker, no marker, usage
echo '[' > "$r/.agents-kit.json"
bash "$all" "$r" 7 2 3 >/dev/null 2>&1; [ $? -eq 2 ] || fail "marcador roto"
rm "$r/.agents-kit.json"
bash "$all" "$r" 7 2 3 >/dev/null 2>&1; [ $? -eq 1 ] || fail "sin marcador"
bash "$all" "$r" 7 >/dev/null 2>&1; [ $? -eq 1 ] || fail "uso"
echo "OK test_review_all"
