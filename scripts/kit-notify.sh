#!/usr/bin/env bash
# Usage: scripts/kit-notify.sh <root> <titulo> <mensaje> [url]
# Envía un aviso a Dru por el canal de .agents-kit.json (notify): ntfy, claude-push o none.
# Exit: 0 ok, 1 rechazo o error de uso, 2 error de entorno (el aviso falló; quien llama sigue).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib/config.sh"
source "$here/lib/transport.sh"

[ $# -eq 3 ] || [ $# -eq 4 ] || { echo "uso: $0 <root> <titulo> <mensaje> [url]" >&2; exit 1; }
[ -d "$1" ] || { echo "error: '$1' no es un directorio" >&2; exit 2; }
root="$(cd "$1" && pwd)"
kit_require_marker "$root" || exit $?
flat() { printf '%s' "$1" | tr '\r\n' '  '; }
title="$(flat "$2")"; msg="$(flat "$3")"; url="$(flat "${4:-}")"

channel="$(kit_config "$root" '.notify')" || exit $?
# kit_transport: en la nube el HOME es desechable, así que allí no se inventa un tema (nadie estaría suscrito).
case "$channel" in
  none)
    echo "FIN: sin-aviso" ;;
  claude-push)
    echo "AVISO-CLAUDE: $title: $msg $url"
    echo "FIN: claude-push" ;;
  ntfy)
    # The topic is the only secret: it comes from the user (env or ~/.agents-kit), never from the repo.
    topic="${KIT_NTFY_TOPIC:-}"
    created=0
    if [ -z "$topic" ]; then
      dir="$HOME/.agents-kit"; file="$dir/ntfy-topic"
      if [ ! -s "$file" ] && [ "$(kit_transport)" = nube ]; then
        echo "error: en la nube define KIT_NTFY_TOPIC (el tema de tu app ntfy)" >&2
        exit 2
      fi
      if [ ! -s "$file" ]; then
        (umask 077; mkdir -p "$dir" && printf 'agents-kit-%s\n' "$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')" > "$file") 2>/dev/null \
          || { echo "error: no se pudo crear $file" >&2; exit 2; }
        created=1
      fi
      topic="$(head -n1 "$file")"
    fi
    [[ $topic =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { echo "error: tema ntfy inválido" >&2; exit 2; }
    [ "$created" -eq 1 ] && echo "tema ntfy nuevo: $topic (suscríbete en la app ntfy)"
    args=(-fsS --max-time 10 -H "Title: $title")
    [ -n "$url" ] && args+=(-H "Click: $url")
    if ! curl "${args[@]}" --data-raw "$msg" "${KIT_NTFY_SERVER:-https://ntfy.sh}/$topic" >/dev/null; then
      echo "error: no se pudo enviar el aviso por ntfy" >&2
      exit 2
    fi
    echo "FIN: ntfy" ;;
  *)
    echo "canal de aviso desconocido: $channel" >&2
    exit 1 ;;
esac
