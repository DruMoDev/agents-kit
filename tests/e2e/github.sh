#!/usr/bin/env bash
# Usage: tests/e2e/github.sh <owner/repo> [--con-revisores]
# End-to-end run of the kit scripts against a real GitHub repo made for it (DruMoDev/agents-kit-sandbox): what the
# stubs of tests/run.sh cannot see (GitHub's API, refs/locks pushes, merges, timing). Run it by hand before a release;
# it creates and closes issues and PRs in that repo, never in another. Long: launch it with scripts/kit-bg.sh.
# Flow: labels (kit-github-setup) -> issue with an axis (crear) -> siguiente -> reclamar (lock) -> worktree -> commit
# with the changelog placeholder -> abrir (fills it) -> esperar-ci -> gate-local -> validar -> review round (no seats by
# default, a temporary global config; real seats with --con-revisores) -> fusionar (lock released) -> limpiar (main
# fast-forward). Then a lock left by a closed issue is recovered by the next reclamar of that axis.
# Prints "ok: <step>" per step and "FIN: e2e ok"; exit 1 at the first failed check (the repo keeps what it had).
set -u
repo="${1:-}"
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "uso: $0 <owner/repo> [--con-revisores]" >&2; exit 1; }
seats=false
[ "${2:-}" = --con-revisores ] && seats=true
kit="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="$kit/scripts"
stamp="$(date +%Y%m%d%H%M%S)"
id="e2e-$stamp"
axis="e2e-$stamp"
work="$(mktemp -d)"
export KIT_WORKTREES="$work/worktrees" KIT_TMP="$work/tmp"
mkdir -p "$KIT_TMP"
if [ "$seats" = false ]; then
  export KIT_CONFIG="$work/config.json"
  echo '{"revision": {"puestos": []}, "notify": "none"}' > "$KIT_CONFIG"
fi

ok() { echo "ok: $*"; }
n="" pr="" m="" root=""
# cleanup <motivo>: best effort, leaves the test repo as it was (PR closed, issues released and closed, no lock or label)
cleanup() {
  [ -n "$pr" ] && gh pr view "$pr" --repo "$repo" --json state --jq .state 2>/dev/null | grep -q OPEN \
    && gh pr close "$pr" --repo "$repo" --delete-branch --comment "Prueba e2e: $1" >/dev/null 2>&1
  for i in $n $m; do
    [ -n "$root" ] && bash "$S/kit-issue.sh" soltar "$root" "$i" "$id" "prueba e2e: $1" >/dev/null 2>&1
    gh issue close "$i" --repo "$repo" --comment "Prueba e2e: $1" >/dev/null 2>&1
  done
  [ -n "$root" ] && git -C "$root" push -q origin ":refs/locks/$axis" >/dev/null 2>&1
  gh label delete "serializa:$axis" --repo "$repo" --yes >/dev/null 2>&1
}
die() { echo "FALLO: $*" >&2; cleanup "abortada"; echo "(trabajo en $work)" >&2; exit 1; }
last() { printf '%s\n' "$1" | sed -n '$p'; }
run() { # <desc> <cmd...>: run, keep output in $out, die unless exit 0
  local d="$1"; shift
  out="$("$@" 2>&1)" || die "$d (exit $?): $out"
}

gh repo clone "$repo" "$work/clon" -- -q 2>/dev/null || die "no se pudo clonar $repo"
root="$work/clon"
[ -f "$root/.agents-kit.json" ] || die "$repo no tiene el kit activado (.agents-kit.json)"
run "etiquetas del kit" bash "$S/kit-github-setup.sh" "$root"; ok "etiquetas del kit"
gh label create "serializa:$axis" --repo "$repo" --color FBCA04 --description "e2e del kit" >/dev/null 2>&1 || die "etiqueta del eje"

body="$KIT_TMP/issue.md"
printf '## Qué\n\nPrueba de punta a punta del kit (%s).\n\n## Hecho cuando\n\nExiste e2e/%s.txt en main.\n' "$stamp" "$stamp" > "$body"
run "crear" bash "$S/kit-issue.sh" crear "$root" "e2e $stamp" "$body" --prio baja --entorno nube --etiqueta "serializa:$axis"
n="$(printf '%s\n' "$out" | grep -oE '/issues/[0-9]+' | sed -n '$s|/issues/||p')"
[[ $n =~ ^[0-9]+$ ]] || die "crear no dio el número del issue: $out"
ok "crear #$n"

run "siguiente $n" bash "$S/kit-issue.sh" siguiente "$root" "$n"; ok "siguiente #$n"
run "reclamar" bash "$S/kit-issue.sh" reclamar "$root" "$n" "$id"
case "$out" in *"candado: refs/locks/$axis"*) ;; *) die "reclamar no tomó el candado: $out" ;; esac
[ -n "$(git -C "$root" ls-remote origin "refs/locks/$axis")" ] || die "refs/locks/$axis no está en origin"
ok "reclamar con candado"

run "worktree" bash "$S/kit-worktree.sh" abrir "$root" "$n" "e2e-$stamp"
wt="$(last "$out" | sed 's/^FIN: //')"
mkdir -p "$wt/e2e" && echo "$stamp" > "$wt/e2e/$stamp.txt"
changelog=false
if [ -f "$wt/CHANGELOG.md" ] && [ "$(jq -r '.changelog // true' "$root/.agents-kit.json")" != false ]; then
  changelog=true
  # the entry goes on top of the first section (or right after the header comment)
  awk -v d="$(date +%Y-%m-%d)" -v s="$stamp" '
    !done && /^## / { print "## " d "\n\n### Interno: prueba e2e " s " · [#PR](PR)\nPrueba de punta a punta del kit.\n"; done = 1 }
    { print }
    END { if (!done) print "\n## " d "\n\n### Interno: prueba e2e " s " · [#PR](PR)\nPrueba de punta a punta del kit." }' \
    "$wt/CHANGELOG.md" > "$KIT_TMP/cl" && mv "$KIT_TMP/cl" "$wt/CHANGELOG.md"
fi
git -C "$wt" add "e2e/$stamp.txt" $([ "$changelog" = true ] && echo CHANGELOG.md) || die "git add"
git -C "$wt" commit -q -m "e2e $stamp" || die "commit"
ok "worktree y commit"

printf 'Prueba e2e del kit.\n' > "$KIT_TMP/pr.md"
run "abrir" bash "$S/kit-pr.sh" abrir "$wt" "$n" "e2e $stamp" "$KIT_TMP/pr.md"
pr="$(printf '%s\n' "$out" | sed -n 1p)"
[[ $pr =~ ^[0-9]+$ ]] || die "abrir: la primera línea no es el número de la PR: $out"
if [ "$changelog" = true ]; then
  case "$out" in *"changelog: enlace a la PR #$pr puesto"*) ;; *) die "abrir no rellenó el changelog: $out" ;; esac
  run "validar" bash "$S/kit-changelog.sh" validar "$wt"
fi
ok "abrir PR #$pr"

out="$(bash "$S/kit-pr.sh" esperar-ci "$wt" "$pr" 2>&1)"; rc=$?
case "$rc:$(last "$out")" in
  0:"FIN: verde") ok "CI verde" ;;
  0:"FIN: sin-ci")
    echo "e2e $stamp: sin CI propio; gate local de la prueba" > "$KIT_TMP/gate"
    run "gate-local" bash "$S/kit-pr.sh" gate-local "$wt" "$pr" "$KIT_TMP/gate"; ok "sin CI: gate local" ;;
  *) die "esperar-ci (exit $rc): $out" ;;
esac

if [ "$seats" = true ]; then
  run "revisores" bash "$S/kit-review-all.sh" "$wt" "$pr" 1 "$n"
  case "$(last "$out")" in "FIN: "*" 0 sin confirmar") ;; *) die "revisores sin confirmar: $out" ;; esac
  printf 'Ronda 1 (e2e): hallazgos no aplicados en una prueba.\n' > "$KIT_TMP/ronda"
  k=0
  for f in "$(sed -n 's/^salidas: //p' <<<"$out")"/rev-*.out; do
    while IFS= read -r t; do k=$((k + 1)); echo "- [R1.$k] (puesto ${f##*rev-}) $t → rechazado: prueba e2e" >> "$KIT_TMP/ronda"; done \
      < <(sed -n 's/^[0-9][0-9]*\. \*\*\[[a-z]*\]\*\* //p' "$f")
  done
  ok "revisores reales"
else
  printf 'Ronda 1: 0 hallazgos (e2e sin puestos de revisión).\n' > "$KIT_TMP/ronda"
fi
run "ronda" bash "$S/kit-pr.sh" ronda "$wt" "$pr" 1 "$KIT_TMP/ronda"; ok "ronda publicada"

run "fusionar" bash "$S/kit-pr.sh" fusionar "$wt" "$pr" "$n"
case "$out" in *"candado soltado: refs/locks/$axis"*"FIN: ok") ;; *) die "fusionar sin soltar el candado: $out" ;; esac
[ -z "$(git -C "$root" ls-remote origin "refs/locks/$axis")" ] || die "el candado sigue en origin tras fusionar"
[ "$(gh issue view "$n" --repo "$repo" --json state --jq .state)" = CLOSED ] || die "el issue #$n no se cerró"
ok "fusionar"

run "limpiar" bash "$S/kit-worktree.sh" limpiar "$root" "$n"
case "$out" in *"principal al día con origin/"*) ;; *) die "limpiar no avanzó el clon: $out" ;; esac
[ -f "$root/e2e/$stamp.txt" ] || die "el clon no tiene el cambio fusionado"
ok "limpiar y clon al día"

# a lock left by a closed issue (merged by hand, say) is recovered by the next reclamar of its axis
sha="$(git -C "$root" commit-tree "$(git -C "$root" hash-object -t tree /dev/null)" -m "agente:muerto issue:$n eje:$axis")"
git -C "$root" push -q origin "$sha:refs/locks/$axis" || die "candado viejo"
printf '## Qué\n\nSegundo issue del eje (e2e %s).\n' "$stamp" > "$body"
run "crear 2" bash "$S/kit-issue.sh" crear "$root" "e2e $stamp (2)" "$body" --prio baja --entorno nube --etiqueta "serializa:$axis"
m="$(printf '%s\n' "$out" | grep -oE '/issues/[0-9]+' | sed -n '$s|/issues/||p')"
[[ $m =~ ^[0-9]+$ ]] || die "crear 2 sin número: $out"
run "reclamar 2" bash "$S/kit-issue.sh" reclamar "$root" "$m" "$id"
case "$out" in *"(era de #$n, ya cerrado)"*) ;; *) die "no recuperó el candado del issue cerrado: $out" ;; esac
run "soltar 2" bash "$S/kit-issue.sh" soltar "$root" "$m" "$id" "fin de la prueba e2e"
gh issue close "$m" --repo "$repo" --comment "Prueba e2e terminada." >/dev/null 2>&1 || die "cerrar #$m"
[ -z "$(git -C "$root" ls-remote origin "refs/locks/$axis")" ] || die "el candado sigue tras soltar"
gh label delete "serializa:$axis" --repo "$repo" --yes >/dev/null 2>&1 || echo "aviso: no se pudo borrar la etiqueta serializa:$axis" >&2
ok "candado de issue cerrado recuperado"

rm -rf "$work"
echo "FIN: e2e ok"
