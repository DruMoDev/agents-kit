#!/usr/bin/env bash
# Usage: scripts/kit-activate.sh <repo_root> [--changelog true|false] [--setup <ruta>]
# Local, file-only, idempotent activation of the kit in a repo (kit-on runs it in a temporary worktree). Does not commit.
# Also creates the global config (~/.agents-kit/config.json or KIT_CONFIG) if missing, appends "## Reglas del proyecto"
# to an existing AGENTS.md that lacks it, and warns about versioned git hooks when the marker declares no "setup".
# --changelog and --setup are written to the marker; "changelog": false means no CHANGELOG.md.
# Exit: 0 ok, 1 usage, 2 environment error.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/config.sh"
source "$here/lib/repo-hook.sh"

usage() {
  echo "uso: $0 <repo_root> [--changelog true|false] [--setup <ruta>]" >&2
  exit 1
}
[ $# -ge 1 ] && [ -n "$1" ] || usage
arg_repo="$1"; shift
opt_changelog=""; opt_setup=""; has_setup=false
while [ $# -gt 0 ]; do
  case "$1" in
    --changelog)
      [ $# -ge 2 ] || usage
      case "$2" in true|false) opt_changelog="$2" ;; *) echo "valor de --changelog inválido: $2 (true o false)" >&2; exit 1 ;; esac
      shift 2 ;;
    --setup)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      opt_setup="$2"; has_setup=true; shift 2 ;;
    *) echo "opción no reconocida: $1" >&2; usage ;;
  esac
done
set -- "$arg_repo"

root="$(cd "$here/.." && pwd)"
tpl="$root/templates"

if [ ! -d "$1" ]; then
  echo "error: '$1' no es un directorio" >&2
  exit 2
fi
repo="$(cd "$1" && pwd)"
if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: '$repo' no es un repositorio git" >&2
  exit 2
fi
for t in agents-kit.json CHANGELOG.md AGENTS.md; do
  [ -f "$tpl/$t" ] || { echo "error: falta la plantilla $tpl/$t" >&2; exit 2; }
done

if [ "$has_setup" = true ]; then
  kit_hook_path "$repo" "$repo" setup "$opt_setup" >/dev/null || exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "error: falta 'jq' en el PATH" >&2; exit 2; }
kit_global_init || exit 2

n=0
created() { echo "creado: $1"; n=$((n + 1)); }
changed() { echo "cambiado: $1"; n=$((n + 1)); }

copy_if_missing() { # template-name target-name
  if [ ! -e "$repo/$2" ] && [ ! -L "$repo/$2" ]; then
    cp "$tpl/$1" "$repo/$2" || exit 2
    created "$2"
  fi
}

# Marker: created from the template; --changelog/--setup written into it (a new marker counts once, as creado)
marker="$repo/.agents-kit.json"
new_marker=false
if [ -L "$marker" ]; then
  echo "error: .agents-kit.json es un symlink; no lo toco" >&2
  exit 2
fi
[ -e "$marker" ] || { cp "$tpl/agents-kit.json" "$marker" || exit 2; new_marker=true; }
jq -e 'type == "object"' "$marker" >/dev/null 2>&1 || { echo "error: .agents-kit.json no es JSON válido" >&2; exit 2; }
want="$(jq -c --arg c "$opt_changelog" --arg s "$opt_setup" --argjson hs "$has_setup" '
  (if $c == "" then . else .changelog = ($c == "true") end) | (if $hs then .setup = $s else . end)' "$marker")" || exit 2
if [ "$want" != "$(jq -c . "$marker")" ]; then
  printf '%s\n' "$want" | jq . > "$marker.tmp" && cat "$marker.tmp" > "$marker" || { rm -f "$marker.tmp"; exit 2; }
  rm -f "$marker.tmp"
  [ "$new_marker" = true ] || changed .agents-kit.json
fi
[ "$new_marker" = true ] && created .agents-kit.json

[ "$(jq -r '.changelog' "$marker")" = false ] || copy_if_missing CHANGELOG.md CHANGELOG.md
copy_if_missing AGENTS.md AGENTS.md

# An existing AGENTS.md gets at least the project rules section (the full reorder is kit-on's, with Dru's OK)
agents="$repo/AGENTS.md"
if [ -L "$agents" ]; then
  echo "aviso: AGENTS.md es un symlink; no le añado la sección '## Reglas del proyecto'." >&2
elif [ -f "$agents" ] && ! grep -qx '## Reglas del proyecto' "$agents"; then
  { [ -s "$agents" ] && [ -n "$(tail -c 1 "$agents")" ] && echo
    printf '\n## Reglas del proyecto\n\n<!-- Reglas propias de este repo. Si alguna choca con las del kit, manda esta. -->\n'
  } >> "$agents" || exit 2
  changed AGENTS.md
fi

# CLAUDE.md: must import AGENTS.md
claude="$repo/CLAUDE.md"
if [ -L "$claude" ]; then
  if [ "$claude" -ef "$repo/AGENTS.md" ]; then
    : # symlink resolving to AGENTS.md: already satisfied
  else
    echo "aviso: CLAUDE.md es un symlink que no apunta a AGENTS.md; no lo toco." >&2
  fi
elif [ ! -e "$claude" ] && [ ! -L "$claude" ]; then
  printf '@AGENTS.md\n' > "$claude" || exit 2
  created CLAUDE.md
elif ! grep -qx '@AGENTS.md' "$claude"; then
  tmp="$(mktemp)"
  { printf '@AGENTS.md\n'; cat "$claude"; } > "$tmp" && cat "$tmp" > "$claude" || { rm -f "$tmp"; exit 2; }
  rm -f "$tmp"
  changed CLAUDE.md
fi

# .agents/skills and the .claude/skills symlink
agents_ok=1
if [ -L "$repo/.agents" ]; then
  agents_ok=0
  echo "aviso: .agents es un symlink; no creo .agents/skills." >&2
elif [ ! -d "$repo/.agents/skills" ]; then
  mkdir -p "$repo/.agents/skills" || exit 2
  created .agents/skills
fi
# git does not track empty directories: keep .agents/skills alive with a .gitkeep
if [ "$agents_ok" = 1 ] && [ -d "$repo/.agents/skills" ] && [ -z "$(ls -A "$repo/.agents/skills")" ]; then
  : > "$repo/.agents/skills/.gitkeep" || exit 2
  created .agents/skills/.gitkeep
fi

link="$repo/.claude/skills"
want="../.agents/skills"
if [ -L "$repo/.claude" ]; then
  echo "aviso: .claude es un symlink; no creo .claude/skills." >&2
elif [ "$agents_ok" = 0 ]; then
  echo "aviso: sin .agents/skills válido; no creo .claude/skills." >&2
elif [ -L "$link" ]; then
  if [ "$(readlink "$link")" != "$want" ]; then
    rm "$link" && ln -s "$want" "$link" || exit 2
    changed .claude/skills
  fi
elif [ -d "$link" ]; then
  echo "aviso: .claude/skills es un directorio real; no lo toco. Muévelo a .agents/skills y reemplázalo por el symlink ($want) a mano." >&2
elif [ -e "$link" ]; then
  echo "aviso: .claude/skills existe y no es un directorio ni un symlink; no lo toco." >&2
else
  mkdir -p "$repo/.claude" && ln -s "$want" "$link" || exit 2
  created .claude/skills
fi

# Versioned git hooks need preparing in every new worktree: warn when the marker declares no setup
setup="$(jq -r 'if (.setup | type) == "string" then .setup else "" end' "$marker")"
if [ -z "$setup" ]; then
  why=()
  hp="$(git -C "$repo" config --local --get core.hooksPath 2>/dev/null)"
  [ -n "$hp" ] && why+=("core.hooksPath=$hp en el git config del repo")
  for h in .husky .githooks githooks .pre-commit-config.yaml lefthook.yml .lefthook.yml; do
    [ -n "$(git -C "$repo" ls-files -- "$h")" ] && why+=("$h versionado")
  done
  if [ ${#why[@]} -gt 0 ]; then
    printf -v list '%s; ' "${why[@]}"
    echo "aviso: el repo tiene hooks de git (${list%; }) y el marcador no declara \"setup\": los worktrees del kit no los preparan. Si hace falta un script que los instale o prepare el entorno, decláralo con --setup <ruta>." >&2
  fi
fi

echo "FIN: $n"
