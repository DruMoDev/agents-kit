#!/usr/bin/env bash
# Usage: scripts/kit-review.sh <wt> <pr> <puesto> <familia> <cli> <modelo> <foco> <ronda> <N>
# Runs one review seat with one reviewer CLI (adapter: claude, opencode, codex) headless in a throwaway independent
# clone of the PR head, with gh and git push blocked, no GitHub credentials and none of the launching session's
# harness variables. The reviewer answers JSON with the schema of skills/kit-run/references/revision-schema.json
# (claude: --json-schema; codex: --output-schema; opencode: schema in the prompt plus one repair turn). The answer
# is validated, rendered as markdown and posted on PR <pr> as
#   <!-- kit-revision: puesto <puesto> <familia>/<modelo> ronda <ronda> -->
# A stored report for that marker is printed again and never rerun or reposted.
# Env: KIT_REVIEW_TIMEOUT (s per reviewer run, default 1800); KIT_REVIEW_BASE (SHA of the default branch, already
#   fetched by kit-review-all.sh: no fetch here); KIT_REVIEW_MODO: completa (default: the whole diff, revisor.md) or
#   verificar (only that the previous round's fixes solve its findings without breaking anything, revisor-verificar.md,
#   on the diff since the head the previous round reviewed: each report records it as <!-- kit-revisado: <sha> -->).
# Exit: 0 ok (last line "FIN: <n> hallazgos"), 1 usage or rejected, 2 the seat stays unconfirmed: the last stderr
# line is "sin confirmar (<motivo>): <detalle>", motivo = acceso (CLI missing, login, model, quota or crash: another
# candidate may answer), tiempo, salida (empty or off-schema answer), bloqueado (the reviewer could not review),
# integridad (the real worktree changed during the run) or entorno (git, gh or the comment failed).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/github-slug.sh"
source "$here/lib/config.sh"
source "$here/lib/default-branch.sh"
template="$here/../skills/kit-run/references/revisor.md"
mode="${KIT_REVIEW_MODO:-completa}"
schema="$here/../skills/kit-run/references/revision-schema.json"

usage() {
  echo "uso: $0 <wt> <pr> <puesto> <familia> <cli> <modelo> <foco> <ronda> <N>" >&2
  exit 1
}
[ $# -eq 9 ] && [ -n "$1" ] || usage
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
wt="$(cd "$1" && pwd)"
p="$2" seat="$3" fam="$4" tool="$5" model="$6" focus="$7" round="$8" n="$9"
kit_require_marker "$wt" || exit $?
num() { [[ $2 =~ ^[1-9][0-9]*$ ]] || { echo "$1 inválido: $2" >&2; exit 1; }; }
num "número de PR" "$p"; num "número de puesto" "$seat"; num "número de ronda" "$round"; num "número de issue" "$n"
[[ $fam =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "familia inválida: '$fam'" >&2; exit 1; }
[[ $model =~ ^[^[:space:]]+$ ]] || { echo "modelo inválido: '$model'" >&2; exit 1; }
[ -n "$focus" ] || { echo "falta el foco" >&2; exit 1; }
case "$mode" in completa) ;; verificar) template="$here/../skills/kit-run/references/revisor-verificar.md" ;;
  *) echo "KIT_REVIEW_MODO inválido: $mode (completa o verificar)" >&2; exit 1 ;; esac
[ "$mode" = completa ] || [ "$round" -ge 2 ] || { echo "verificar necesita una ronda anterior (ronda $round)" >&2; exit 1; }
timeout="${KIT_REVIEW_TIMEOUT:-1800}"
[[ $timeout =~ ^[1-9][0-9]*$ ]] || { echo "error: KIT_REVIEW_TIMEOUT debe ser un número de segundos" >&2; exit 2; }

tmpd=""
# unconfirmed <motivo> <detalle>: report why this seat delivered nothing, then exit 2
unconfirmed() {
  echo "el revisor $fam/$model ($tool) no entregó: $2" >&2
  if [ -n "$tmpd" ] && [ -s "$tmpd/err" ]; then
    echo "salida de error del revisor:" >&2
    strip "$tmpd/err" >&2
  fi
  echo "sin confirmar ($1): $2" >&2
  exit 2
}
envfail() { echo "error: $1" >&2; echo "sin confirmar (entorno): $1" >&2; exit 2; }
strip() { sed $'s/\x1b\\[[0-9;?]*[A-Za-z]//g; s/\r$//' "$1"; }

case "$tool" in claude|opencode|codex) ;; *) unconfirmed acceso "revisor no disponible: $tool (adaptadores: claude, opencode, codex)" ;; esac
command -v "$tool" >/dev/null 2>&1 || unconfirmed acceso "revisor no disponible: $tool no está en el PATH"
for c in gh git jq perl; do
  command -v "$c" >/dev/null 2>&1 || envfail "falta '$c' en el PATH"
done
[ -r "$template" ] || envfail "no se encuentra la plantilla del revisor: $template"
jq -e 'type == "object"' "$schema" >/dev/null 2>&1 || envfail "no se encuentra el esquema de la revisión: $schema"
schema="$(cd "$(dirname "$schema")" && pwd)/$(basename "$schema")"
cd "$wt" || exit 2
slug="$(kit_origin_slug)"
[ -n "$slug" ] || envfail "el remoto 'origin' no es de GitHub"

# idempotent per marker: a stored report for this seat/family/model/round is replayed, never rerun or reposted.
# Only reports posted by this gh user count.
me="$(gh api user --jq .login)" && [ -n "$me" ] || envfail "no se pudo leer el usuario de gh (gh api user)"
marker="<!-- kit-revision: puesto $seat $fam/$model ronda $round -->"
cj="$(gh pr view "$p" --repo "$slug" --json comments)" || envfail "no se pudieron leer los comentarios de la PR #$p"
prev="$(printf '%s' "$cj" | jq -r --arg m "$marker" --arg me "$me" \
  '[.comments[]? | select(.author.login == $me) | select((.body // "") | sub("^\\s+"; "") | startswith($m))][0].body // empty')" \
  || envfail "respuesta de gh ilegible"
if [ -n "$prev" ]; then
  rep="$(printf '%s\n' "$prev" | awk -v m="$marker" 'BEGIN{d=0} !d && index($0, m) { d=1; next } /^<!-- kit-revisado: / { next } { print }')"
  ptotal="$(printf '%s\n' "$rep" | sed -n 's/^[[:space:]]*[`*]*HALLAZGOS: \([0-9][0-9]*\)[`*]*[[:space:]]*$/\1/p' | sed -n '$p')"
  if [ -n "$ptotal" ]; then
    printf '%s\n' "$rep"
    echo "FIN: $ptotal hallazgos"
    exit 0
  fi
fi

tmpd="$(mktemp -d)" || exit 2
scratch="$tmpd/clon"
rpid=""
cleanup() {
  # stop the reviewer's process group (the runner forwards TERM to it), then drop every temp copy
  if [ -n "$rpid" ]; then
    kill -TERM "$rpid" 2>/dev/null
    wait "$rpid" 2>/dev/null
  fi
  rm -rf "$tmpd"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# prompt inputs (the PR body goes in as claims to verify)
issue="$(gh issue view "$n" --repo "$slug" --json title,body | jq -r '"# \(.title)\n\n\(.body // "")"')" \
  || envfail "no se pudo leer el issue #$n"
pj="$(gh pr view "$p" --repo "$slug" --json headRefOid,body)" || envfail "no se pudo leer la PR #$p"
oid="$(printf '%s' "$pj" | jq -r '.headRefOid // ""')" || envfail "respuesta de gh ilegible"
prbody="$(printf '%s' "$pj" | jq -r '.body // "" | if . == "" then "(sin descripción)" else . end')"
[[ $oid =~ ^[0-9a-f]{40}$ ]] || envfail "la PR #$p no tiene un head legible"
git cat-file -e "$oid^{commit}" 2>/dev/null || envfail "el head de la PR ($oid) no está en el worktree: haz fetch o push"
if [ -n "${KIT_REVIEW_BASE:-}" ]; then
  # kit-review-all.sh already fetched the default branch once for every seat: seats in parallel never fetch (they
  # would race on refs/remotes/origin/<b> and fail with "cannot lock ref")
  [[ $KIT_REVIEW_BASE =~ ^[0-9a-f]{40}$ ]] && git cat-file -e "$KIT_REVIEW_BASE^{commit}" 2>/dev/null \
    || envfail "KIT_REVIEW_BASE no es un commit de este repo: $KIT_REVIEW_BASE"
  base="$(git merge-base "$KIT_REVIEW_BASE" "$oid")" || envfail "no hay merge-base entre la rama por defecto y la PR"
else
  b="$(kit_default_branch)"
  [ -n "$b" ] || envfail "no pude saber la rama por defecto de origin"
  git fetch -q origin "+refs/heads/$b:refs/remotes/origin/$b" || envfail "git fetch falló"
  base="$(git merge-base "origin/$b" "$oid")" || envfail "no hay merge-base entre origin/$b y la PR"
fi
hist="$(bash "$here/kit-pr.sh" historial "$wt" "$p")" || envfail "no se pudo leer el historial de la PR #$p"
hist="$(printf '%s\n' "$hist" | sed '${/^FIN: /d;}')"
# verificar: the diff since the head the previous round reviewed (any own report of that round records it); without
# one (reports from before 3.4) the whole diff, and the prompt says so
since="$base"
if [ "$mode" = verificar ]; then
  for s in $(printf '%s' "$cj" | jq -r --arg me "$me" --arg r "$((round - 1))" '.comments[]? | select(.author.login == $me)
      | (.body // "") | select(test("^\\s*<!-- kit-revision: puesto [0-9]+ \\S+ ronda \($r) -->"))
      | capture("<!-- kit-revisado: (?<s>[0-9a-f]{40}) -->").s'); do
    if git cat-file -e "$s^{commit}" 2>/dev/null && git merge-base --is-ancestor "$s" "$oid"; then since="$s"; break; fi
  done
fi
# single pass, so text inside the substituted values is never re-expanded
prompt="$(jq -Rrs --arg FOCO "$focus" --arg RONDA "$round" --arg ISSUE "$issue" --arg BASE "$base" --arg HISTORIAL "$hist" \
  --arg PR "$prbody" --arg DESDE "$since" --arg ANTERIOR "$((round - 1))" \
  '$ARGS.named as $m | gsub("\\{\\{(?<k>FOCO|RONDA|ISSUE|BASE|HISTORIAL|PR|DESDE|ANTERIOR)\\}\\}"; $m[.k])' "$template")" \
  || envfail "no se pudo construir el prompt"
# without a native output schema the schema travels in the prompt
if [ "$tool" = opencode ]; then
  prompt="$prompt

Esquema JSON de la respuesta (responde con un único objeto JSON que lo cumpla, sin texto alrededor):
$(jq -c . "$schema")"
fi

# independent clone (own .git, no hooks, config or remote of the real repo) at the PR head
{ git clone -q --no-hardlinks "$wt" "$scratch" && git -C "$scratch" checkout -q --detach "$oid" \
    && git -C "$scratch" remote remove origin; } >/dev/null 2>&1 \
  || envfail "no se pudo crear la copia desechable"
# agent config committed in the PR is untrusted: drop it from the copy (it stays reviewable via git diff)
# never through a symlink: rm -rf on a link path drops the link only, and a linked .claude is dropped whole
(
  cd "$scratch" || exit 1
  rm -rf .mcp.json .opencode opencode.json opencode.jsonc .codex || exit 1
  if [ -L .claude ]; then
    rm -f .claude
  elif [ -d .claude ]; then
    rm -rf .claude/settings.json .claude/settings.local.json .claude/hooks
  fi
  # the reviewer sees a clean status at the PR head: those removals are not part of the change
  git ls-files --deleted -z | xargs -0 git update-index --skip-worktree -- 2>/dev/null
  true
) || envfail "no se pudo limpiar la copia desechable"
mkdir "$tmpd/gh" || exit 2

# runner: reviewer in its own process group; on timeout or TERM/INT/HUP the whole group gets TERM, then KILL.
# Exit: the reviewer's code (128+signal if killed), 142 on timeout.
runner='
  my ($t, @cmd) = @ARGV;
  my $pid = fork;
  defined $pid or exit 126;
  if (!$pid) { setpgrp(0, 0); exec @cmd or exit 127; }
  setpgrp($pid, $pid);
  my $stop = sub {
    kill "TERM", -$pid;
    for (1 .. 20) {
      waitpid($pid, 1);  # WNOHANG: reap the leader so a zombie does not keep the group alive
      last unless kill 0, -$pid;
      select(undef, undef, undef, 0.1);
    }
    kill "KILL", -$pid;
  };
  $SIG{ALRM} = sub { $stop->(); exit 142 };
  $SIG{$_} = sub { $stop->(); exit 143 } for qw(TERM INT HUP);
  alarm $t;
  waitpid($pid, 0);
  my $st = $?;
  alarm 0;
  kill "KILL", -$pid;
  exit($st & 127 ? 128 + ($st & 127) : $st >> 8);
'
# launch <cmd...>: run the reviewer in the copy, isolated, stdin closed; stdout to $tmpd/out, stderr to $tmpd/err.
# Sets rc. Waits in a background job so INT/TERM traps fire at once.
launch() {
  (
    cd "$scratch" || exit 2
    # a fresh top-level session: none of the launching harness variables (user config dirs stay, for the login)
    for v in $(compgen -e); do
      case "$v" in
        CLAUDE_CONFIG_DIR|CODEX_HOME) ;;
        CLAUDE*|CODEX_*|OPENCODE*) unset "$v" ;;
      esac
    done
    unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
    export GH_CONFIG_DIR="$tmpd/gh" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
    # an empty credential.helper resets the helper list, so no stored credential is ever offered
    export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=
    export GIT_AUTHOR_NAME=kit-revisor GIT_AUTHOR_EMAIL=kit-revisor@localhost \
      GIT_COMMITTER_NAME=kit-revisor GIT_COMMITTER_EMAIL=kit-revisor@localhost
    exec perl -e "$runner" "$timeout" "$@"
  ) </dev/null >"$tmpd/out" 2>"$tmpd/err" &
  rpid=$!
  wait "$rpid"; rc=$?
  rpid=""
}

# the real worktree must not change while a reviewer runs (HEAD and status, untracked files included)
wt_state() { git -C "$wt" rev-parse HEAD && git -C "$wt" status --porcelain; }
wt_before="$(wt_state)" || envfail "no se pudo leer el estado del worktree"
check_wt() {
  local now
  now="$(wt_state)" || envfail "no se pudo leer el estado del worktree"
  [ "$now" = "$wt_before" ] || unconfirmed integridad "el worktree $wt cambió (HEAD o ficheros) mientras corría el revisor"
}
# after_run: classify a finished run (timeout, exit code); returns only when the CLI exited 0
after_run() {
  [ "$rc" -ne 142 ] || unconfirmed tiempo "agotó el tiempo (${timeout}s)"
  check_wt
  if [ "$rc" -ne 0 ]; then
    local why
    why="$(strip "$tmpd/out" | jq -r 'select(type == "object" and .is_error == true) | .result // empty' 2>/dev/null | sed -n '$p')"
    unconfirmed acceso "terminó con código $rc${why:+: $why} (¿login, modelo o cuota?)"
  fi
}

# reply_json: the JSON object inside a text reply (code fences and prose around it are dropped), or null
REPLY_JQ='(capture("(?<j>\\{[\\s\\S]*\\})")? | .j | fromjson?) // null'
# schema check (the subset of JSON Schema the schema uses) plus the verdict/findings coherence; one error per line
VALIDATE_JQ='
  def errs($s; $p):
    . as $v
    | ($s.type // null | if . == null then [] elif type == "array" then . else [.] end) as $ts
    | def ok($t): if $t == "integer" then ($v | type) == "number" and ($v | floor) == $v else ($v | type) == $t end;
    if ($ts | length) > 0 and ([$ts[] | ok(.)] | any | not) then ["\($p): se esperaba \($ts | join("/"))"]
    elif $s.enum != null and ([$s.enum[] | . == $v] | any | not) then ["\($p): \($v | tojson) no es uno de \($s.enum | tojson)"]
    elif ($v | type) == "object" then
      [($s.required // [])[] | select(. as $k | $v | has($k) | not) | "\($p): falta \(.)"]
      + (if $s.additionalProperties == false
         then [$v | keys_unsorted[] | select(. as $k | ($s.properties // {}) | has($k) | not) | "\($p): sobra \(.)"]
         else [] end)
      + [$v | to_entries[] | select(.key as $k | ($s.properties // {}) | has($k))
         | .key as $k | .value | errs($s.properties[$k]; "\($p).\($k)")[]]
    elif ($v | type) == "array" and $s.items != null then
      [range(0; $v | length) as $i | $v[$i] | errs($s.items; "\($p)[\($i)]")[]]
    else [] end;
  if type != "object" then ["no hay un objeto JSON en la respuesta"]
  else errs($schema[0]; "$")
    + (if .veredicto == "sin_hallazgos" and (.hallazgos | type) == "array" and (.hallazgos | length) > 0
       then ["$.veredicto: sin_hallazgos con hallazgos"] else [] end)
    + (if .veredicto == "hallazgos" and (.hallazgos | type) == "array" and (.hallazgos | length) == 0
       then ["$.veredicto: hallazgos sin ningún hallazgo"] else [] end)
  end | .[]'
# check <json-file>: print the schema errors (none = valid)
check() { jq -r --slurpfile schema "$schema" "$VALIDATE_JQ" "$1"; }

case "$tool" in
  claude)
    launch claude -p --model "$model" --permission-mode bypassPermissions --setting-sources user --strict-mcp-config \
      --no-session-persistence --disallowedTools "Bash(git push:*)" "Bash(gh:*)" \
      --output-format json --json-schema "$(jq -c . "$schema")" "$prompt"
    after_run
    [ -s "$tmpd/out" ] || unconfirmed salida "respuesta vacía"
    res="$(strip "$tmpd/out" | jq -s -c 'map(objects) | last // {}' 2>/dev/null)" || res='{}'
    why="$(printf '%s' "$res" | jq -r 'select(.is_error == true) | .result // "error sin detalle"')"
    [ -z "$why" ] || unconfirmed acceso "$why"
    printf '%s' "$res" | jq -c '.structured_output // null' > "$tmpd/json"
    ;;
  opencode)
    oc_cfg='{"permission":{"bash":{"*":"allow","gh *":"deny","git push*":"deny"},"edit":"allow","external_directory":"deny"}}'
    # oc_read: last assistant message text, session id and first error event of the JSON events
    oc_read() {
      strip "$tmpd/out" | jq -R -s -c '[split("\n")[] | fromjson? | objects] as $ev
        | ([$ev[] | select(.type == "text")] | (last.part.messageID // null) as $m
           | map(select(.part.messageID == $m) | .part.text // "") | join("")) as $text
        | {text: $text, sid: ([$ev[] | .sessionID // empty] | last // ""),
           err: ([$ev[] | select(.type == "error") | tojson] | first // "")}'
    }
    attempt=1
    msg="$prompt"
    sid=""
    while :; do
      launch env OPENCODE_CONFIG_CONTENT="$oc_cfg" opencode run --pure --format json -m "$model" ${sid:+-s "$sid"} "$msg"
      after_run
      ev="$(oc_read)" || ev='{}'
      err="$(printf '%s' "$ev" | jq -r '.err // ""')"
      [ -z "$err" ] || unconfirmed acceso "opencode informó de un error: ${err:0:300}"
      text="$(printf '%s' "$ev" | jq -r '.text // ""')"
      [ -n "$text" ] || unconfirmed salida "respuesta vacía"
      printf '%s' "$text" | jq -R -s -c "$REPLY_JQ" > "$tmpd/json"
      errs="$(check "$tmpd/json")"
      [ -n "$errs" ] || break
      sid="$(printf '%s' "$ev" | jq -r '.sid // ""')"
      [ "$attempt" -eq 1 ] && [ -n "$sid" ] \
        || unconfirmed salida "la respuesta no cumple el esquema: $(printf '%s\n' "$errs" | sed -n 1,5p | paste -sd ';' -)"
      attempt=2
      msg="Tu última respuesta no cumple el esquema de salida:
$(printf '%s\n' "$errs" | sed -n 1,10p | sed 's/^/- /')
Responde otra vez solo con el objeto JSON corregido, completo."
    done
    ;;
  codex)
    # workspace-write sandbox without network: gh and git push cannot reach GitHub; no user config, rules or session files.
    # Codex takes a bare model id: the OpenCode-style "openai/" prefix of a family that moved to codex is dropped.
    launch codex exec --ephemeral --ignore-user-config --ignore-rules --sandbox workspace-write \
      -c 'approval_policy="never"' -c sandbox_workspace_write.network_access=false --color never \
      -m "${model#openai/}" -C "$scratch" --output-schema "$schema" -o "$tmpd/last" "$prompt"
    after_run
    [ -s "$tmpd/last" ] || unconfirmed salida "respuesta vacía"
    jq -R -s -c "$REPLY_JQ" "$tmpd/last" > "$tmpd/json"
    ;;
esac

errs="$(check "$tmpd/json")"
[ -z "$errs" ] || unconfirmed salida "la respuesta no cumple el esquema: $(printf '%s\n' "$errs" | sed -n 1,5p | paste -sd ';' -)"
if [ "$(jq -r .veredicto "$tmpd/json")" = bloqueado ]; then
  unconfirmed bloqueado "el revisor no pudo revisar: $(jq -r .resumen "$tmpd/json")"
fi

# readable markdown; text from the reviewer can never open an HTML comment (a fake kit marker)
jq -r --arg seat "$seat" --arg who "$fam/$model" --arg r "$round" --arg foco "$focus" --arg mode "$mode" '
  def safe: tostring | gsub("<!--"; "&lt;!--");
  def inline: safe | gsub("\\s*\n\\s*"; " ");
  def ord: {"grave": 0, "medio": 1, "menor": 2}[.severidad];
  "### Revisión del puesto \($seat): \($who), ronda \($r)",
  "",
  "**Foco:** \($foco | inline)",
  (if $mode == "verificar" then "**Modo:** verifica los arreglos de la ronda \($r | tonumber - 1) (sin revisión completa del diff)" else empty end),
  "**Veredicto:** \(.veredicto | sub("_"; " "))",
  "",
  (.resumen | safe),
  "",
  ((.hallazgos | sort_by(ord) | to_entries[]) as $e | $e.value as $h
    | "\($e.key + 1). **[\($h.severidad)]** `\($h.fichero | inline)\(if $h.linea != null then ":\($h.linea)" else "" end)` \($h.titulo | inline) (confianza \($h.confianza))",
      "   - Escenario: \($h.escenario | inline)",
      "   - Evidencia: \($h.evidencia | inline)",
      (if $h.sugerencia != null and $h.sugerencia != "" then "   - Sugerencia: \($h.sugerencia | inline)" else empty end),
      ""),
  (if (.comprobado | length) > 0 then "**Comprobado:**", (.comprobado[] | "- \(inline)"), "" else empty end),
  "HALLAZGOS: \(.hallazgos | length)"' "$tmpd/json" > "$tmpd/report" || envfail "no se pudo componer el informe"
total="$(jq '.hallazgos | length' "$tmpd/json")"

{
  echo "$marker"
  echo "<!-- kit-revisado: $oid -->"
  cat "$tmpd/report"
} > "$tmpd/body"
gh pr comment "$p" --repo "$slug" --body-file "$tmpd/body" >/dev/null || envfail "no se pudo comentar en la PR #$p"
cat "$tmpd/report"
echo "FIN: $total hallazgos"
