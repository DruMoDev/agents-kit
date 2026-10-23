#!/usr/bin/env bash
# Usage: scripts/kit-pr.sh <subcomando> <wt> [args...]
#   abrir      <wt> <N> <titulo> <fichero-cuerpo>
#   esperar-ci <wt> <pr>
#   gate-local <wt> <pr> <fichero-salida>
#   historial  <wt> <pr>
#   ronda      <wt> <pr> <n> <fichero>
#   fusionar   <wt> <pr> <N>
# PR lifecycle of an issue branch; <wt> is the issue worktree. Review state lives in HTML-comment markers on the PR.
# Env: KIT_CI_TIMEOUT (s; default: ciTimeoutMin of the config, else from the repo history, lib/ci.sh), KIT_CI_POLL (s, default 15),
#   KIT_CI_GRACE (s, default 300: with workflows but no check run for the SHA after it, esperar-ci reports sin-ci).
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error or undecidable.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/github-slug.sh"
source "$here/lib/config.sh"
source "$here/lib/default-branch.sh"
source "$here/lib/repo-hook.sh"
source "$here/lib/ci.sh"
source "$here/lib/locks.sh"

usage() {
  echo "uso: $0 abrir <wt> <N> <titulo> <fichero-cuerpo> | esperar-ci <wt> <pr> |" \
    "gate-local <wt> <pr> <fichero-salida> | historial <wt> <pr> | ronda <wt> <pr> <n> <fichero> |" \
    "fusionar <wt> <pr> <N>" >&2
  exit 1
}

[ $# -ge 2 ] && [ -n "$2" ] || usage
sub="$1"; shift
case "$sub" in abrir|esperar-ci|gate-local|historial|ronda|fusionar) ;; *) usage ;; esac
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
wt="$(cd "$1" && pwd)"; shift
kit_require_marker "$wt" || exit $?

case "$sub" in
  esperar-ci|historial) [ $# -eq 1 ] || usage ;;
  gate-local|fusionar) [ $# -eq 2 ] || usage ;;
  ronda) [ $# -eq 3 ] || usage ;;
  abrir) [ $# -eq 3 ] || usage ;;
esac
num() { [[ $2 =~ ^[1-9][0-9]*$ ]] || { echo "$1 inválido: $2" >&2; exit 1; }; }
if [ "$sub" = abrir ]; then n="$1"; num "número de issue" "$n"; else p="$1"; num "número de PR" "$p"; fi
case "$sub" in
  ronda) num "número de ronda" "$2" ;;
  fusionar) num "número de issue" "$2" ;;
esac

for c in gh git jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "error: falta '$c' en el PATH" >&2; exit 2; }
done
cd "$wt" || exit 2
slug="$(kit_origin_slug)"
[ -n "$slug" ] || { echo "error: el remoto 'origin' no es de GitHub" >&2; exit 2; }

tmpd="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmpd"' EXIT

read_file() { # <path>: print contents or exit 1
  [ -f "$1" ] && [ -r "$1" ] || { echo "no se puede leer el fichero: $1" >&2; exit 1; }
  cat "$1"
}
# quiet_push <git push args...>: git push without GitHub's "remote: Create a pull request..." lines, which git prints
# to stderr even with -q and the agent would read as part of the output; on failure they are shown.
quiet_push() {
  local e
  e="$(git push -q "$@" 2>&1)" && return 0
  printf '%s\n' "$e" >&2
  return 1
}
head_sha() { git rev-parse HEAD 2>/dev/null || { echo "error: no se pudo leer HEAD" >&2; exit 2; }; }
is_clean() { # exit 2 if git status fails
  local s
  s="$(git status --porcelain)" || { echo "error: git status falló" >&2; exit 2; }
  [ -z "$s" ]
}
base_branch() { # print origin's default branch after fetching it; exit 2 if unknown
  local b
  b="$(kit_default_branch)"
  [ -n "$b" ] || { echo "error: no pude saber la rama por defecto de origin" >&2; exit 2; }
  kit_fetch origin "+refs/heads/$b:refs/remotes/origin/$b" || { echo "error: git fetch falló" >&2; exit 2; }
  printf '%s' "$b"
}
pr_json() { # <fields>: gh pr view of $p, exit 2 if unreadable
  gh pr view "$p" --repo "$slug" --json "$1" || { echo "error: no se pudo leer la PR #$p" >&2; exit 2; }
}
comment() { # <body-file>
  gh pr comment "$p" --repo "$slug" --body-file "$1" >/dev/null \
    || { echo "error: no se pudo comentar en la PR #$p" >&2; exit 2; }
}

ci_unreadable() { echo "error: no se pudo leer el estado del CI" >&2; exit 2; }
# own_login: set $me to the gh login of this run; flow markers are trusted only from it. Exit 2 if unreadable.
own_login() {
  me="$(gh api user --jq .login)" && [ -n "$me" ] \
    || { echo "error: no se pudo leer el usuario de gh (gh api user)" >&2; exit 2; }
}

# Markers count only in comments written by $me (jq --arg me), in chronological (array) order.
OWN_JQ='[.comments[] | select(.author.login == $me) | .body // ""]'
# kit-ronda bodies
RONDAS_JQ="$OWN_JQ"' | map(select(test("^\\s*<!-- kit-ronda: [0-9]+ -->")))'
# review state: sin-ronda | pendiente (a kit-revision after the last kit-ronda, by position)
#   | aplicado (the last kit-ronda applied changes, so a new round is due)
#   | incompleta <r> <i,j...> (seats 1..$nseats without an own confirmed review in round <r>) | ok
# Reviews: v3 "kit-revision: puesto <i> <familia>/<modelo> ronda <r>" (confirmed) or "... puesto <i> sin-confirmar
# ronda <r>"; a round with v2 reviews only ("kit-revision: <herramienta>/<modelo> ronda <r>") is read as before.
REVIEW_JQ="$OWN_JQ"' as $b
  | ([range(0; $b | length) | select($b[.] | test("^\\s*<!-- kit-ronda: [0-9]+ -->"))] | last // -1) as $r
  | if $r < 0 then "sin-ronda"
    elif any(range($r + 1; $b | length); $b[.] | test("^\\s*<!-- kit-revision: ")) then "pendiente"
    elif any($b[$r] | split("\n")[]; sub("\\s+$"; "") | endswith(" → aplicado")) then "aplicado"
    else ($b[$r] | capture("^\\s*<!-- kit-ronda: (?<n>[0-9]+) -->").n) as $rn
      | [$b[] | capture("^\\s*<!-- kit-revision: puesto (?<i>[0-9]+) (?<who>\\S+) ronda (?<r>[0-9]+) -->")
         | select(.r == $rn)] as $v3
      | ([$b[] | select(test("^\\s*<!-- kit-revision: (?!puesto )\\S+ ronda \($rn) -->"))] | length) as $v2
      | [range(1; $nseats + 1) | tostring | select(. as $i | any($v3[]; .i == $i and (.who | contains("/"))) | not)] as $miss
      | if ($v3 | length) == 0 and $v2 > 0 then "ok"
        elif ($miss | length) > 0 then "incompleta \($rn) \($miss | join(", "))"
        else "ok" end
    end'

# after_merge <url>: everything fusionar does once the PR is merged (close the issue, release its axis locks, kit-soltado,
# drop en-curso) and its final lines. Idempotent: a rerun of fusionar on a merged PR comes straight here.
after_merge() {
  local url="$1" ist axes e
  ist="$(gh issue view "$n" --repo "$slug" --json state --jq .state)" \
    || { echo "error: PR fusionada pero no se pudo leer el issue #$n" >&2; exit 2; }
  if [ "$ist" = OPEN ]; then
    gh issue close "$n" --repo "$slug" --comment "Resuelto en #$p." >/dev/null \
      || { echo "error: PR fusionada pero no se pudo cerrar el issue #$n" >&2; exit 2; }
  fi
  # the axis locks of the issue (lib/locks.sh) go before en-curso, as in kit-issue.sh release; a failure only warns, naming the command that frees it
  if axes="$(gh issue view "$n" --repo "$slug" --json labels --jq '.labels[].name | select(startswith("serializa:"))')"; then
    while IFS= read -r e; do
      [ -n "$e" ] && lock_valid "$e" || continue
      lock_release "$e" "$n" \
        || echo "AVISO: PR fusionada, pero el candado $(lock_ref "$e") sigue tomado: kit-issue.sh liberar-eje <raíz> ${e#serializa:}" >&2
    done <<< "$axes"
  else
    echo "AVISO: PR fusionada, pero no se pudo leer las etiquetas de #$n: mira si quedó algún candado en refs/locks/" >&2
  fi
  # the claim is over: an own kit-soltado (so a reopened issue can be claimed again), then drop en-curso; a failure
  # only warns, the merge already happened
  # (both only while en-curso is still there: a rerun after a finished cleanup posts nothing twice)
  if [ "$(gh issue view "$n" --repo "$slug" --json labels --jq '[.labels[].name] | index("en-curso") != null' 2>/dev/null)" != false ]; then
    printf '<!-- kit-soltado: fusionar -->\nPR #%s fusionada: este issue queda libre.\n' "$p" > "$tmpd/soltado"
    gh issue comment "$n" --repo "$slug" --body-file "$tmpd/soltado" >/dev/null \
      || echo "aviso: PR fusionada, pero no se pudo publicar kit-soltado en el issue #$n" >&2
    # the issue is done: drop en-curso (a v2 listo stays: never remove a label the repo may not have)
    gh issue edit "$n" --repo "$slug" --remove-label en-curso >/dev/null \
      || echo "aviso: PR fusionada y issue cerrado, pero no se pudo quitar la etiqueta en-curso del issue #$n" >&2
  fi
  echo "PR fusionado: $url"
  echo "FIN: ok"
  exit 0
}

case "$sub" in
  abrir)
    titulo="$2"
    body="$(read_file "$3")" || exit 1
    is_clean || { echo "el árbol tiene cambios sin confirmar" >&2; exit 1; }
    base="$(base_branch)" || exit 2
    ahead="$(git rev-list --count "origin/$base..HEAD")" || { echo "error: git rev-list falló" >&2; exit 2; }
    [ "$ahead" -gt 0 ] || { echo "no hay commits sobre origin/$base" >&2; exit 1; }
    branch="$(git symbolic-ref --short -q HEAD)" || { echo "HEAD no está en una rama" >&2; exit 1; }
    printf '%s' "$body" | grep -Eq "Cierra #$n([^0-9]|$)" || body="$body

Cierra #$n"
    printf '%s\n' "$body" > "$tmpd/body"
    # idempotent: an open PR for the branch is reused (pushed, never recreated)
    open_pr="$(gh pr list --repo "$slug" --head "$branch" --state open --json number,url)" \
      || { echo "error: gh pr list falló" >&2; exit 2; }
    open_pr="$(printf '%s' "$open_pr" | jq -r 'if type == "array" then (.[0] // {} | "\(.number // "")\t\(.url // "")") else error("") end' 2>/dev/null)" \
      || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    quiet_push -u origin HEAD || { echo "error: git push falló" >&2; exit 2; }
    if [ -n "${open_pr%%$'\t'*}" ]; then
      url="${open_pr#*$'\t'}"
    else
      url="$(gh pr create --repo "$slug" --base "$base" --head "$branch" --title "$titulo" --body-file "$tmpd/body")" \
        || { echo "error: gh pr create falló" >&2; exit 2; }
      url="$(printf '%s\n' "$url" | grep -E '/pull/[0-9]+' | sed -n '$p')"
      [ -n "$url" ] || { echo "error: gh pr create no devolvió la URL de la PR" >&2; exit 2; }
    fi
    # the CHANGELOG.md entry goes in the first commit with the placeholder [#PR](PR), since the number only exists now:
    # filled here in a commit of its own that skips the project's hooks (it only touches that link)
    if grep -qF '[#PR](PR)' CHANGELOG.md 2>/dev/null; then
      pn="${url##*/}"
      # renames first: a failure leaves CHANGELOG.md untouched, so a rerun of abrir finds the placeholder again
      for img in docs/changelog/PR-*; do
        [ -e "$img" ] || continue
        [ ! -e "docs/changelog/$pn-${img#docs/changelog/PR-}" ] \
          || { echo "error: ya existe docs/changelog/$pn-${img#docs/changelog/PR-}: no renombro nada" >&2; exit 2; }
        git ls-files --error-unmatch -- "$img" >/dev/null 2>&1 \
          || { echo "error: $img no está confirmada: confírmala y relanza abrir" >&2; exit 2; }
      done
      shots=()
      for img in docs/changelog/PR-*; do
        [ -e "$img" ] || continue
        git mv "$img" "docs/changelog/$pn-${img#docs/changelog/PR-}" || { echo "error: no se pudo renombrar $img" >&2; exit 2; }
        shots+=("$img" "docs/changelog/$pn-${img#docs/changelog/PR-}")
      done
      PN="$pn" URL="$url" perl -pi -e 's/\[#PR\]\(PR\)/[#$ENV{PN}]($ENV{URL})/g; s{docs/changelog/PR-}{docs/changelog/$ENV{PN}-}g' CHANGELOG.md \
        || { echo "error: no se pudo poner el enlace de la PR en CHANGELOG.md" >&2; exit 2; }
      git -c core.hooksPath=/dev/null commit -q --no-verify -m "changelog: enlace a la PR #$pn" -- CHANGELOG.md ${shots[@]+"${shots[@]}"} \
        || { echo "error: no se pudo confirmar el enlace de la PR en CHANGELOG.md" >&2; exit 2; }
      quiet_push origin HEAD || { echo "error: git push falló tras poner el enlace del changelog" >&2; exit 2; }
      cl_line="changelog: enlace a la PR #$pn puesto en CHANGELOG.md"
    fi
    echo "${url##*/}"
    [ -z "${cl_line:-}" ] || echo "$cl_line"
    echo "FIN: $url"
    ;;

  esperar-ci)
    sha="$(head_sha)" || exit 2
    oid="$(pr_json headRefOid | jq -r '.headRefOid // ""')" || exit 2
    # right after a push GitHub takes a few seconds to move the PR head: if origin already has this commit, wait for
    # the PR to show it (KIT_PR_LAG s, default 60) instead of failing
    if [ "$oid" != "$sha" ]; then
      br="$(git symbolic-ref --short -q HEAD)"
      if [ -n "$br" ] && [ "$(git ls-remote origin "refs/heads/$br" 2>/dev/null | cut -f1)" = "$sha" ]; then
        lag="${KIT_PR_LAG:-60}"; [[ $lag =~ ^[0-9]+$ ]] || lag=60
        lag_end=$((SECONDS + lag))
        while [ "$oid" != "$sha" ] && [ $SECONDS -lt $lag_end ]; do
          sleep 3
          oid="$(pr_json headRefOid | jq -r '.headRefOid // ""')" || exit 2
        done
      fi
    fi
    [ "$oid" = "$sha" ] || { echo "la PR apunta a $oid y aquí estás en $sha: empuja o espera" >&2; exit 2; }
    t="$(ci_timeout "$wt")"
    res="$(ci_wait "$sha" "$t")"; rc=$?
    [ $rc -ne 3 ] || exit 1 # still running: a rejection, kit-run waits again
    [ $rc -eq 0 ] || exit $rc
    # no check run can also mean GitHub never started the CI: a draft or a PR in conflict with its base. Then the fix
    # is ready or rebase, never the local gate (the full suite on the agent's machine). A repo without workflows has no CI.
    if [ "$res" = sin-ci ] && [ "$(ci_has_workflows)" = true ]; then
      st="$(pr_json isDraft,mergeable)" || exit 2
      if [ "$(printf '%s' "$st" | jq -r '.isDraft // false')" = true ]; then
        echo "la PR está en borrador y su CI puede no arrancar: quítale el borrador (gh pr ready $p --repo $slug) y vuelve a esperar" >&2
        exit 1
      fi
      if [ "$(printf '%s' "$st" | jq -r '.mergeable // ""')" = CONFLICTING ]; then
        echo "la PR tiene conflictos con su base y GitHub no lanza su CI: rebasa, empuja y vuelve a esperar" >&2
        exit 1
      fi
    fi
    echo "FIN: $res"
    ;;

  gate-local)
    out="$(read_file "$2")" || exit 1
    sha="$(head_sha)" || exit 2
    # GitHub rejects comments over 65536 characters: a long output keeps its head and its tail (where a suite reports)
    max=60000
    if [ "${#out}" -gt "$max" ]; then
      out="${out:0:20000}

[... salida recortada: ${#out} caracteres en total; el fichero completo es $2 en la máquina del agente ...]

${out: -38000}"
    fi
    {
      echo "<!-- kit-gate-local: $sha -->"
      echo "Gate local sobre \`${sha:0:8}\` (tests, lint y build):"
      echo
      echo '````text'
      printf '%s\n' "$out"
      echo '````'
    } > "$tmpd/body"
    comment "$tmpd/body"
    echo "FIN: gate-local ${sha:0:8}"
    ;;

  historial)
    own_login
    c="$(pr_json comments)" || exit 2
    rondas="$(printf '%s' "$c" | jq -c --arg me "$me" "$RONDAS_JQ")" || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    k="$(printf '%s' "$rondas" | jq length)"
    if [ "$k" -eq 0 ]; then
      echo "(sin rondas previas)"
    else
      printf '%s' "$rondas" | jq -r 'map(sub("\\s+$"; "")) | join("\n-----\n")'
    fi
    echo "FIN: $k rondas"
    ;;

  ronda)
    r="$2"
    text="$(read_file "$3")" || exit 1
    i=0
    while IFS= read -r line || [ -n "$line" ]; do
      i=$((i + 1))
      line="${line%$'\r'}"
      [[ $line =~ ^-\ \[R([0-9]+)\.[0-9]+\] ]] || continue
      [ "${BASH_REMATCH[1]}" = "$r" ] || { echo "línea $i: el hallazgo no es de la ronda $r: $line" >&2; exit 1; }
      t="${line%"${line##*[![:space:]]}"}"
      case "$t" in
        *" → aplicado") ;;
        *" → rechazado: "*[![:space:]]*) ;;
        *) echo "línea $i: hallazgo sin decisión (→ aplicado o → rechazado: <motivo>): $line" >&2; exit 1 ;;
      esac
    done < "$3"
    printf '<!-- kit-ronda: %s -->\n%s\n' "$r" "$text" > "$tmpd/body"
    comment "$tmpd/body"
    echo "FIN: ronda $r"
    ;;

  fusionar)
    n="$2"
    reasons=()
    own_login
    pj="$(pr_json isDraft,state,headRefOid,url,comments,body)" || exit 2
    printf '%s' "$pj" | jq -e '(.comments | type) == "array" and (.isDraft | type) == "boolean"' >/dev/null 2>&1 \
      || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    state="$(printf '%s' "$pj" | jq -r .state)"
    oid="$(printf '%s' "$pj" | jq -r '.headRefOid // ""')"
    sha="$(head_sha)" || exit 2
    # a rerun after a merge whose cleanup did not finish (process killed, gh failure): finish it, nothing else
    if [ "$state" = MERGED ] && [ "$oid" = "$sha" ]; then
      echo "la PR ya estaba fusionada: termino la limpieza del issue #$n"
      after_merge "$(printf '%s' "$pj" | jq -r .url)"
    fi
    [ "$state" = OPEN ] || reasons+=("la PR no está abierta ($state)")
    [ "$(printf '%s' "$pj" | jq -r .isDraft)" = false ] || reasons+=("la PR está en borrador")
    clean=true
    is_clean || { clean=false; reasons+=("el árbol tiene cambios sin confirmar"); }
    same=true
    [ "$oid" = "$sha" ] || { same=false; reasons+=("el HEAD local (${sha:0:8}) no es el de la PR (${oid:0:8})"); }

    base="$(base_branch)" || exit 2
    rebased=false
    if ! git merge-base --is-ancestor "origin/$base" HEAD; then
      if [ "$clean" = true ] && [ "$same" = true ]; then
        if git rebase -q "origin/$base" >/dev/null 2>&1; then
          quiet_push --force-with-lease origin HEAD \
            || { echo "error: git push --force-with-lease falló tras rebasar sobre $base" >&2; exit 2; }
          rebased=true
          reasons+=("rebasada sobre $base: vuelve a esperar el CI")
        else
          git rebase --abort >/dev/null 2>&1 || { echo "error: git rebase --abort falló" >&2; exit 2; }
          reasons+=("conflicto con $base: resuélvelo")
        fi
      else
        reasons+=("la rama no contiene origin/$base: hay que rebasar")
      fi
    fi

    # CI of the PR head, skipped after a rebase (that SHA is gone). The CI is the check runs of the repo's own workflow
    # runs (lib/ci.sh): when they exist they decide; when none ran for the SHA (no own workflows, or own ones that never
    # run on PRs) an own gate-local is required, whatever GitHub's built-in workflows or third-party apps report. A red
    # third-party check (a deploy preview, say) always blocks; a pending one does not.
    if [ "$rebased" = false ]; then
      s="$(ci_state "$oid")" || ci_unreadable
      x="$(ci_state "$oid" externos)" || ci_unreadable
      own="$(ci_has_workflows)" || ci_unreadable
      has_gate() {
        printf '%s' "$pj" | jq -e --arg me "$me" --arg m "<!-- kit-gate-local: $oid -->" \
          "$OWN_JQ"' | any(.[]; startswith($m))' >/dev/null
      }
      if [ "$own" = true ]; then
        case "$s" in
          verde) ;;
          rojo*) reasons+=("el CI terminó en '${s#rojo }'") ;;
          ninguno) has_gate || reasons+=("no hay CI y falta el gate local de ${oid:0:8}") ;;
          *) reasons+=("el CI de ${oid:0:8} no ha concluido") ;;
        esac
      else
        has_gate || reasons+=("el repo no tiene CI propio y falta el gate local de ${oid:0:8}")
      fi
      case "$x" in rojo*) reasons+=("un check externo terminó en '${x#rojo }'") ;; esac
    fi

    # review: at least one kit-ronda, no kit-revision after the last one (by position) and, in that round, an own
    # confirmed review for every seat of revision.puestos
    nseats="$(kit_config_base "$wt" '.revision.puestos // [] | length' "origin/$base")" || exit 2
    [[ $nseats =~ ^[0-9]+$ ]] || { echo "error: revision.puestos no es una lista" >&2; exit 2; }
    review_reason() { # <pr-json>: append the review reason, if any
      local rev
      rev="$(printf '%s' "$1" | jq -r --arg me "$me" --argjson nseats "$nseats" "$REVIEW_JQ")" \
        || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
      case "$rev" in
        sin-ronda) reasons+=("no hay ninguna ronda de revisión (kit-ronda)") ;;
        pendiente) reasons+=("hay una revisión posterior a la última ronda sin decisiones escritas") ;;
        aplicado) reasons+=("la última ronda aplicó cambios: falta una ronda nueva") ;;
        incompleta*)
          set -- $rev
          reasons+=("la ronda $2 tiene puestos sin confirmar (${rev#incompleta $2 }): relanza esos puestos antes de publicar la ronda, o haz una ronda nueva") ;;
      esac
    }
    report() {
      [ ${#reasons[@]} -gt 0 ] || return 0
      {
        echo "no se puede fusionar:"
        printf '  - %s\n' "${reasons[@]}"
      } >&2
      exit 1
    }
    review_reason "$pj"

    # CHANGELOG.md, when the repo has one, must keep the fixed format (a PR without a new entry is fine), unless the
    # default branch's marker says "changelog": false (the project keeps its own changelog, in its own format).
    # Without the marker kit-changelog refuses for that reason, not for the format: skip it (the dirty tree stops the merge).
    cl="$(kit_config_base "$wt" '.changelog' "origin/$base")" || exit 2
    if [ "$cl" != false ] && [ -f "$wt/CHANGELOG.md" ] && [ -f "$wt/.agents-kit.json" ]; then
      cl_err="$("$here/kit-changelog.sh" validar "$wt" 2>&1 >/dev/null)"; cl_rc=$?
      grep -qF '[#PR](PR)' "$wt/CHANGELOG.md" \
        && reasons+=("CHANGELOG.md tiene el enlace pendiente [#PR](PR): relanza kit-pr.sh abrir para rellenarlo")
      case $cl_rc in
        0) ;;
        1) reasons+=("CHANGELOG.md mal formado:
$cl_err") ;;
        *) echo "error: kit-changelog.sh falló: $cl_err" >&2; exit 2 ;;
      esac
    fi

    # Gates from the default branch's marker (a PR cannot weaken them by editing its own).
    # protegido: touched protected paths must be listed in the "## Zonas protegidas" section of the PR body.
    prot="$(kit_config_base "$wt" '(.protegido // []) | if type == "array" then map(select(type == "string" and . != "")) else [] end | .[]' "origin/$base")" || exit 2
    if [ -n "$prot" ]; then
      changed="$(git diff --name-only --no-renames "origin/$base...HEAD")" || { echo "error: git diff falló" >&2; exit 2; }
      section="$(printf '%s' "$pj" | jq -r '.body // ""' | awk '
        /^##[ \t]+Zonas protegidas[ \t]*$/ { on = 1; next }
        /^##[ \t]/ { on = 0 }
        on { print }')"
      has_section=false
      printf '%s' "$pj" | jq -r '.body // ""' | grep -Eq '^##[[:space:]]+Zonas protegidas[[:space:]]*$' && has_section=true
      missing=()
      while IFS= read -r pre; do
        [ -n "$pre" ] || continue
        pn="${pre%/}"
        hit=false
        while IFS= read -r f; do
          [ -n "$f" ] || continue
          if [ "$f" = "$pn" ] || [ "${f#"$pn"/}" != "$f" ]; then hit=true; break; fi
        done <<< "$changed"
        [ "$hit" = true ] || continue
        if [ "$has_section" = false ]; then
          missing+=("$pre")
        else
          # whole token: not glued to a longer path or word on either side
          esc="$(printf '%s' "$pre" | sed 's/[][\\.*^$+?(){}|]/\\&/g')"
          case "$pre" in */) tail_re='' ;; *) tail_re='($|[^A-Za-z0-9_-])' ;; esac
          printf '%s\n' "$section" | grep -Eq -- "(^|[^A-Za-z0-9_./-])${esc}${tail_re}" || missing+=("$pre")
        fi
      done <<< "$prot"
      if [ ${#missing[@]} -gt 0 ]; then
        reasons+=("la PR toca rutas protegidas (${missing[*]}) y su cuerpo no las menciona bajo '## Zonas protegidas'")
      fi
    fi

    # checks.pre-merge: script of the repo, run in the worktree over the head. The path comes from the default branch's
    # marker and the file must be exactly the default branch's version (a PR cannot edit its own gate); it runs in place,
    # so it can find its sibling files through $0.
    pm="$(kit_config_base "$wt" '(.checks // {}) | if type == "object" and (.["pre-merge"] | type) == "string" then .["pre-merge"] else empty end' "origin/$base")" || exit 2
    if [ -n "$pm" ]; then
      kit_hook_rel checks.pre-merge "$pm" || exit 2
      pm_base="$(git rev-parse -q --verify "origin/$base:$pm" 2>/dev/null)"
      pm_head="$(git rev-parse -q --verify "HEAD:$pm" 2>/dev/null)"
      git diff --quiet "origin/$base...HEAD" -- "$pm"; pm_diff=$?
      [ $pm_diff -le 1 ] || { echo "error: git diff falló" >&2; exit 2; }
      if [ -z "$pm_base" ]; then
        reasons+=("checks.pre-merge apunta a $pm, que no existe en origin/$base")
      elif [ $pm_diff -eq 1 ]; then
        reasons+=("la PR modifica el script de checks.pre-merge ($pm): una PR no puede cambiar su propia puerta; deshaz ese cambio en la rama")
      elif [ "$pm_head" = "$pm_base" ] && [ "$clean" = true ]; then
        # (a different blob not changed by the PR = the branch lacks origin/$base: the rebase reason already stops it)
        pm_path="$(kit_hook_path "$wt" "$wt" checks.pre-merge "$pm")" || exit 2
        kit_hook_run "$wt" "$pm_path"; pm_rc=$?
        case $pm_rc in
          0) ;;
          142) reasons+=("checks.pre-merge agotó el tiempo (${KIT_HOOK_TIMEOUT:-1800}s):
$KIT_HOOK_OUT") ;;
          *) reasons+=("checks.pre-merge falló (exit $pm_rc):
$KIT_HOOK_OUT") ;;
        esac
      fi
    fi

    report
    # a review may have landed while the gates ran: re-read just before merging
    late="$(pr_json comments)" || exit 2
    review_reason "$late"
    report

    # --match-head-commit: never merge a SHA pushed after the gates were checked
    if ! ci_gh_retry pr merge "$p" --repo "$slug" --squash --match-head-commit "$oid" >/dev/null; then
      # a transient error may hide a merge that did happen: the state decides
      [ "$(pr_json state | jq -r .state 2>/dev/null)" = MERGED ] \
        || { echo "error: gh pr merge falló (el error de gh está arriba: la PR cambió de head tras las comprobaciones, el repo no permite squash...)" >&2; exit 2; }
    fi
    after="$(pr_json state,url)" || exit 2
    [ "$(printf '%s' "$after" | jq -r .state)" = MERGED ] \
      || { echo "error: la PR #$p no aparece como fusionada tras gh pr merge" >&2; exit 2; }
    after_merge "$(printf '%s' "$after" | jq -r .url)"
    ;;
esac
