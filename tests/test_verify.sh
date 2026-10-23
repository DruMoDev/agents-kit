#!/usr/bin/env bash
# Tests for scripts/kit-verify.sh and the verificar options of kit-activate.sh (local bare origin, git real).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
v="$REPO_ROOT/scripts/kit-verify.sh"
last_line() { printf '%s\n' "$1" | sed -n '$p'; }

r="$(mk_repo)"; o="$(mktemp -d)"
git init -q --bare "$o"
(cd "$r" && git remote add origin https://github.com/dru/demo.git && git config "url.$o.insteadOf" "https://github.com/dru/demo.git" \
  && git push -q -u origin main) >/dev/null 2>&1 || fail "setup remoto"
git -C "$o" symbolic-ref HEAD refs/heads/main
mk() { printf '%s\n' "$1" > "$r/.agents-kit.json"; (cd "$r" && git add .agents-kit.json && git commit -q -m mk && git push -q origin main) >/dev/null 2>&1 || fail "mk"; }

# --- kit-activate writes verificar
bash "$REPO_ROOT/scripts/kit-activate.sh" "$r" --changelog false --verificar-rapido "echo rapido" --verificar-completo "echo completo; exit 3" >/dev/null 2>&1 \
  || fail "activate con verificar"
[ "$(jq -c .verificar "$r/.agents-kit.json")" = '{"rapido":"echo rapido","completo":"echo completo; exit 3"}' ] || fail "marcador: $(cat "$r/.agents-kit.json")"
(cd "$r" && git add -A && git commit -q -m kit && git push -q origin main) >/dev/null 2>&1 || fail "push kit"

# --- correr
out="$(bash "$v" correr "$r" rapido 2>&1)" || fail "correr rapido: $out"
[ "$(last_line "$out")" = "FIN: ok" ] || fail "correr rapido FIN: $out"
f="$(sed -n 's/^salida: //p' <<<"$out")"
grep -qx 'rapido' "$f" && grep -qx '$ echo rapido' "$f" || fail "salida rapido: $(cat "$f")"
sal="$(mktemp)"
err="$(bash "$v" correr "$r" completo --salida "$sal" 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "completo con fallo: exit $rc"
case "$err" in *"falló (exit 3): verificar.completo"*) ;; *) fail "completo msg: $err";; esac
grep -qx completo "$sal" || fail "completo sin salida en --salida"
# a PR cannot change what it is checked with: the marker of origin/main counts, not the worktree's
jq '.verificar.rapido = "echo trampa"' "$r/.agents-kit.json" > "$r/m" && mv "$r/m" "$r/.agents-kit.json"
out="$(bash "$v" correr "$r" rapido 2>&1)" || fail "rapido de origin: $out"
grep -qx rapido "$(sed -n 's/^salida: //p' <<<"$out")" || fail "usó el marcador del worktree"
git -C "$r" checkout -q .agents-kit.json
mk '{"changelog": false}'
err="$(bash "$v" correr "$r" rapido 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] || fail "sin verificar: exit $rc"
case "$err" in *"sin verificar.rapido"*"AGENTS.md"*) ;; *) fail "sin verificar msg: $err";; esac
bash "$v" correr "$r" medio >/dev/null 2>&1; [ $? -eq 1 ] || fail "nivel inválido debe dar 1"

# --- estado
out="$(bash "$v" estado "$r" 2>&1)" || fail "estado: $out"
for x in "ci: ninguno" "hook: ninguno" "verificar.rapido: sin declarar" "verificar.completo: sin declarar"; do
  grep -qxF "$x" <<<"$out" || fail "estado sin '$x': $out"
done
mkdir -p "$r/.github/workflows" "$r/tools/hooks"
printf 'on: pull_request\njobs:\n  t:\n    steps:\n      - uses: actions/checkout@v4\n' > "$r/.github/workflows/ci.yml"
out="$(bash "$v" estado "$r" 2>&1)"
grep -qxF "ci: 1 workflows (.github/workflows/ci.yml)" <<<"$out" && grep -qxF "ci-cancela: no" <<<"$out" && grep -qxF "ci-cache: no" <<<"$out" \
  || fail "estado ci pelado: $out"
printf 'concurrency:\n  group: ci-${{ github.ref }}\n  cancel-in-progress: true\n' >> "$r/.github/workflows/ci.yml"
printf '      - uses: actions/setup-node@v4\n        with:\n          cache: npm\n' >> "$r/.github/workflows/ci.yml"
out="$(bash "$v" estado "$r" 2>&1)"
grep -qxF "ci-cancela: sí" <<<"$out" && grep -qxF "ci-cache: sí" <<<"$out" || fail "estado ci completo: $out"
touch "$r/.pre-commit-config.yaml"
grep -qxF "hook: ninguno instalado (el repo trae .pre-commit-config.yaml: sin instalar en este clon)" <<<"$(bash "$v" estado "$r" 2>&1)" \
  || fail "estado hook sin instalar"
printf '#!/bin/sh\nsleep 1\necho medido >> "$HOOK_LOG"\n' > "$r/tools/hooks/pre-commit"; chmod +x "$r/tools/hooks/pre-commit"
git -C "$r" config core.hooksPath tools/hooks
grep -qxF "hook: tools/hooks/pre-commit" <<<"$(bash "$v" estado "$r" 2>&1)" || fail "estado hook con hooksPath"

# --- medir-hook
export HOOK_LOG; HOOK_LOG="$(mktemp)"
out="$(bash "$v" medir-hook "$r" 2>&1)" || fail "medir-hook: $out"
case "$out" in *"hook: "[1-9]*" s (exit 0), sin cambios preparados: es una cota inferior"*) ;; *) fail "medir-hook: $out";; esac
grep -qx medido "$HOOK_LOG" || fail "medir-hook no ejecutó el hook"
git -C "$r" config --unset core.hooksPath
bash "$v" medir-hook "$r" >/dev/null 2>&1; [ $? -eq 1 ] || fail "medir-hook sin hook debe dar 1"
echo "OK test_verify"
