#!/usr/bin/env bash
# Usage: scripts/kit-activate.sh <repo_root>
# Local, file-only, idempotent activation of the kit in a repo. Does not commit.
# Exit: 0 ok, 1 usage, 2 environment error.
set -u

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "uso: $0 <repo_root>" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

n=0
created() { echo "creado: $1"; n=$((n + 1)); }
changed() { echo "cambiado: $1"; n=$((n + 1)); }

copy_if_missing() { # template-name target-name
  if [ ! -e "$repo/$2" ] && [ ! -L "$repo/$2" ]; then
    cp "$tpl/$1" "$repo/$2" || exit 2
    created "$2"
  fi
}

copy_if_missing agents-kit.json .agents-kit.json
copy_if_missing CHANGELOG.md CHANGELOG.md
copy_if_missing AGENTS.md AGENTS.md

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

echo "FIN: $n"
