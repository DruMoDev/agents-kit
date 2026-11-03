#!/usr/bin/env bash
# Sourced helper: the Claude Code permission rule that lets kit-run merge in auto mode. No side effects on source.
# In auto mode Claude Code's classifier denies "kit-pr.sh fusionar" as a merge without review; a matching
# permissions.allow rule skips the classifier. A plugin cannot ship permission rules, so the rule goes in the repo's
# .claude/settings.json (committed, so it works on any Mac; Claude Code applies it once the folder is trusted).
# It names the bare command bin/kit-fusionar (the plugin's bin/ is on the Bash PATH): no wildcard before the command,
# so no other program matches it.

KIT_PERMISO='Bash(kit-fusionar *)'

# kit_permiso <repo> poner|quitar: add or remove the rule, keeping every other key and rule. Prints
# "creado:|cambiado:|borrado: .claude/settings.json" when it changes something (quitar deletes a file left empty).
# A symlinked .claude or settings.json, invalid JSON or a non-array permissions.allow is left untouched with an
# "aviso:" on stderr (return 0: the repo works, kit-run just asks before merging). Return 2 on a write error.
kit_permiso() {
  local repo="$1" op="$2" dir f cur want tmp
  dir="$repo/.claude"; f="$dir/settings.json"
  if [ -L "$dir" ] || [ -L "$f" ]; then
    echo "aviso: .claude/settings.json (o .claude) es un symlink; no le pongo la regla '$KIT_PERMISO': en modo auto, kit-run pedirá permiso para fusionar." >&2
    return 0
  fi
  if [ -e "$f" ]; then
    # exactly one JSON value, read whole: jq on "{...}{ roto" prints the first object before failing
    cur="$(jq -cs 'if length == 1 then .[0] else error("") end' "$f" 2>/dev/null)" || cur=""
    if [ -z "$cur" ] || ! jq -e 'type == "object" and ((.permissions // {}) | type == "object")
        and ((.permissions.allow // []) | type == "array")' <<<"$cur" >/dev/null 2>&1; then
      echo "aviso: .claude/settings.json no es JSON válido o su permissions.allow no es una lista; no lo toco. Añade a mano la regla '$KIT_PERMISO' para que kit-run fusione en modo auto." >&2
      return 0
    fi
  else
    [ "$op" = poner ] || return 0
    cur='{}'
  fi
  if [ "$op" = poner ]; then
    want="$(jq -c --arg r "$KIT_PERMISO" 'if (.permissions.allow // []) | index($r) then . else .permissions.allow += [$r] end' <<<"$cur")"
  else
    want="$(jq -c --arg r "$KIT_PERMISO" '
      if (.permissions.allow // []) | index($r) | not then . else
        .permissions.allow -= [$r] | if .permissions.allow == [] then del(.permissions.allow) else . end
        | if .permissions == {} then del(.permissions) else . end end' <<<"$cur")"
  fi
  [ -n "$want" ] || return 2
  [ -e "$f" ] && [ "$want" = "$cur" ] && return 0
  if [ "$want" = '{}' ]; then
    rm -f "$f" || return 2
    echo "borrado: .claude/settings.json"
    return 0
  fi
  mkdir -p "$dir" || return 2
  tmp="$(mktemp "$dir/settings.json.XXXXXX")" || return 2
  printf '%s\n' "$want" | jq . > "$tmp" && chmod 644 "$tmp" || { rm -f "$tmp"; return 2; }
  if [ -e "$f" ]; then
    mv -f "$tmp" "$f" && echo "cambiado: .claude/settings.json"
  else
    mv -f "$tmp" "$f" && echo "creado: .claude/settings.json"
  fi || { rm -f "$tmp"; return 2; }
}
