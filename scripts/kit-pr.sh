#!/usr/bin/env bash
# Usage: scripts/kit-pr.sh <subcomando> <wt> [args...]
#   abrir      <wt> <N> <titulo> <fichero-cuerpo>
#   esperar-ci <wt> <pr>
#   gate-local <wt> <pr> <fichero-salida>
#   historial  <wt> <pr>
#   ronda      <wt> <pr> <n> <fichero>
#   fusionar   <wt> <pr> <N>
# PR lifecycle of an issue branch; <wt> is the issue worktree. Review state lives in HTML-comment markers on the PR.
# Env: KIT_CI_TIMEOUT (s, default 1800), KIT_CI_POLL (s, default 15).
# Exit: 0 ok, 1 rejected (reason on stderr), 2 environment error or undecidable.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/github-slug.sh"
source "$here/lib/config.sh"
source "$here/lib/default-branch.sh"

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
  git fetch -q origin "+refs/heads/$b:refs/remotes/origin/$b" || { echo "error: git fetch falló" >&2; exit 2; }
  printf '%s' "$b"
}
pr_json() { # <fields>: gh pr view of $p, exit 2 if unreadable
  gh pr view "$p" --repo "$slug" --json "$1" || { echo "error: no se pudo leer la PR #$p" >&2; exit 2; }
}
comment() { # <body-file>
  gh pr comment "$p" --repo "$slug" --body-file "$1" >/dev/null \
    || { echo "error: no se pudo comentar en la PR #$p" >&2; exit 2; }
}

# CI, shared by esperar-ci and fusionar.
# ci_has_workflows: print true/false; return 2 if gh fails or the answer is unreadable.
ci_has_workflows() {
  local c
  c="$(gh api "repos/$slug/actions/workflows" --jq .total_count)" || return 2
  [[ $c =~ ^[0-9]+$ ]] || return 2
  if [ "$c" -gt 0 ]; then echo true; else echo false; fi
}
# ci_state <sha>: one read of the check runs (latest attempt per check name, by id); prints esperando | verde | rojo <conclusion>; return 2 if unreadable.
ci_state() {
  local r
  r="$(gh api "repos/$slug/commits/$1/check-runs?filter=all&per_page=100")" || return 2
  printf '%s' "$r" | jq -r '
    if (.check_runs | type) != "array" then error("sin check_runs") else .check_runs end
    | group_by(.name) | map(max_by(.id))
    | if length == 0 or any(.[]; .status != "completed") then "esperando"
      else ([.[] | .conclusion // "sin conclusión" | select(. as $x | ["success", "skipped", "neutral"] | index($x) | not)]
        | first) as $bad
      | if $bad == null then "verde" else "rojo \($bad)" end
      end' 2>/dev/null || return 2
}
ci_unreadable() { echo "error: no se pudo leer el estado del CI" >&2; exit 2; }

# marker bodies of the PR comments, in chronological (array) order
RONDAS_JQ='[.comments[].body | select(test("^\\s*<!-- kit-ronda: [0-9]+ -->"))]'
# review state: sin-ronda | pendiente (a kit-revision after the last kit-ronda, by position) | ok
REVIEW_JQ='[.comments[].body] as $b
  | ([range(0; $b | length) | select($b[.] | test("^\\s*<!-- kit-ronda: [0-9]+ -->"))] | last // -1) as $r
  | if $r < 0 then "sin-ronda"
    elif any(range($r + 1; $b | length); $b[.] | test("^\\s*<!-- kit-revision: ")) then "pendiente"
    else "ok" end'

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
    git push -q -u origin HEAD || { echo "error: git push falló" >&2; exit 2; }
    url="$(gh pr create --repo "$slug" --base "$base" --head "$branch" --title "$titulo" --body-file "$tmpd/body")" \
      || { echo "error: gh pr create falló" >&2; exit 2; }
    url="$(printf '%s\n' "$url" | grep -E '/pull/[0-9]+' | sed -n '$p')"
    [ -n "$url" ] || { echo "error: gh pr create no devolvió la URL de la PR" >&2; exit 2; }
    echo "${url##*/}"
    echo "FIN: $url"
    ;;

  esperar-ci)
    timeout="${KIT_CI_TIMEOUT:-1800}"; poll="${KIT_CI_POLL:-15}"
    [[ $timeout =~ ^[0-9]+$ ]] && [[ $poll =~ ^[0-9]+$ ]] \
      || { echo "error: KIT_CI_TIMEOUT y KIT_CI_POLL deben ser segundos enteros" >&2; exit 2; }
    sha="$(head_sha)" || exit 2
    oid="$(pr_json headRefOid | jq -r '.headRefOid // ""')" || exit 2
    [ "$oid" = "$sha" ] || { echo "la PR apunta a $oid y aquí estás en $sha: empuja o espera" >&2; exit 2; }
    wf="$(ci_has_workflows)" || ci_unreadable
    if [ "$wf" = false ]; then echo "FIN: sin-ci"; exit 0; fi
    start=$SECONDS
    while :; do
      s="$(ci_state "$sha")" || ci_unreadable
      case "$s" in
        verde) echo "FIN: verde"; exit 0 ;;
        rojo*) echo "el CI terminó en '${s#rojo }'" >&2; exit 1 ;;
      esac
      if [ $((SECONDS - start)) -ge "$timeout" ]; then
        echo "el CI de ${sha:0:8} no concluyó en ${timeout}s" >&2
        exit 1
      fi
      sleep "$poll"
    done
    ;;

  gate-local)
    out="$(read_file "$2")" || exit 1
    sha="$(head_sha)" || exit 2
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
    c="$(pr_json comments)" || exit 2
    rondas="$(printf '%s' "$c" | jq -c "$RONDAS_JQ")" || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
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
    pj="$(pr_json isDraft,state,headRefOid,url,comments)" || exit 2
    printf '%s' "$pj" | jq -e '(.comments | type) == "array" and (.isDraft | type) == "boolean"' >/dev/null 2>&1 \
      || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
    state="$(printf '%s' "$pj" | jq -r .state)"
    oid="$(printf '%s' "$pj" | jq -r '.headRefOid // ""')"
    sha="$(head_sha)" || exit 2
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
          git push -q --force-with-lease origin HEAD \
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

    # CI of the PR head, skipped after a rebase (that SHA is gone)
    if [ "$rebased" = false ]; then
      wf="$(ci_has_workflows)" || ci_unreadable
      if [ "$wf" = true ]; then
        s="$(ci_state "$oid")" || ci_unreadable
        case "$s" in
          verde) ;;
          rojo*) reasons+=("el CI terminó en '${s#rojo }'") ;;
          *) reasons+=("el CI de ${oid:0:8} no ha concluido") ;;
        esac
      elif ! printf '%s' "$pj" | jq -e --arg m "<!-- kit-gate-local: $oid -->" \
          'any(.comments[].body; startswith($m))' >/dev/null; then
        reasons+=("no hay CI y falta el gate local de ${oid:0:8}")
      fi
    fi

    # review: at least one kit-ronda and no kit-revision after the last one (by position)
    review_reason() { # <pr-json>: append the review reason, if any
      local rev
      rev="$(printf '%s' "$1" | jq -r "$REVIEW_JQ")" || { echo "error: respuesta de gh ilegible" >&2; exit 2; }
      case "$rev" in
        sin-ronda) reasons+=("no hay ninguna ronda de revisión (kit-ronda)") ;;
        pendiente) reasons+=("hay una revisión posterior a la última ronda sin decisiones escritas") ;;
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

    report
    # a review may have landed while the gates ran: re-read just before merging
    late="$(pr_json comments)" || exit 2
    review_reason "$late"
    report

    # --match-head-commit: never merge a SHA pushed after the gates were checked
    gh pr merge "$p" --repo "$slug" --squash --match-head-commit "$oid" >/dev/null \
      || { echo "error: gh pr merge falló (¿la PR cambió de head tras las comprobaciones?)" >&2; exit 2; }
    after="$(pr_json state,url)" || exit 2
    [ "$(printf '%s' "$after" | jq -r .state)" = MERGED ] \
      || { echo "error: la PR #$p no aparece como fusionada tras gh pr merge" >&2; exit 2; }
    url="$(printf '%s' "$after" | jq -r .url)"
    ist="$(gh issue view "$n" --repo "$slug" --json state --jq .state)" \
      || { echo "error: PR fusionada pero no se pudo leer el issue #$n" >&2; exit 2; }
    if [ "$ist" = OPEN ]; then
      gh issue close "$n" --repo "$slug" --comment "Resuelto en #$p." >/dev/null \
        || { echo "error: PR fusionada pero no se pudo cerrar el issue #$n" >&2; exit 2; }
    fi
    # the issue is done: drop the work labels; a failure only warns, the merge already happened
    gh issue edit "$n" --repo "$slug" --remove-label en-curso --remove-label listo >/dev/null \
      || echo "aviso: PR fusionada y issue cerrado, pero no se pudieron quitar las etiquetas en-curso y listo del issue #$n" >&2
    echo "PR fusionado: $url"
    echo "FIN: ok"
    ;;
esac
