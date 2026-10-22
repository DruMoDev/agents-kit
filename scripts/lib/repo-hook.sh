#!/usr/bin/env bash
# Sourced helper: scripts that a repo declares in .agents-kit.json (setup, checks.pre-merge).
# The marker is project-controlled: only relative paths inside the repo are accepted.
# Env: KIT_HOOK_TIMEOUT (s, default 1800).

# kit_hook_rel <clave> <valor>: return 2 with a message unless <valor> is a non-empty relative path without '..'.
kit_hook_rel() {
  local key="$1" val="$2"
  case "$val" in
    "") echo "error: '$key' en .agents-kit.json está vacío" >&2; return 2 ;;
    /*) echo "error: '$key' debe ser una ruta relativa al repo, no absoluta: $val" >&2; return 2 ;;
  esac
  case "/$val/" in
    */../*) echo "error: '$key' no puede contener '..': $val" >&2; return 2 ;;
  esac
}

# kit_hook_path <root> <wt> <clave> <valor>: print the validated absolute script path; return 2 with a message if unsafe.
kit_hook_path() {
  local root="$1" wt="$2" key="$3" val="$4" real top
  kit_hook_rel "$key" "$val" || return 2
  [ -f "$wt/$val" ] || { echo "error: '$key' apunta a un script que no existe: $val" >&2; return 2; }
  real="$(cd "$(dirname "$wt/$val")" && pwd -P)/$(basename "$val")" || return 2
  top="$(cd "$wt" && pwd -P)" || return 2
  case "$real" in
    "$top"/*) ;;
    *) echo "error: '$key' sale del repo (enlace simbólico): $val" >&2; return 2 ;;
  esac
  printf '%s\n' "$wt/$val"
}

# kit_hook_run <wt> <script>: run `bash <script>` from <wt> in its own process group with a timeout.
# Full stdout+stderr in $KIT_HOOK_OUT. Returns the script's code, 142 on timeout.
kit_hook_run() {
  local wt="$1" script="$2" t="${KIT_HOOK_TIMEOUT:-1800}"
  [[ $t =~ ^[1-9][0-9]*$ ]] || { echo "error: KIT_HOOK_TIMEOUT debe ser un número de segundos" >&2; return 2; }
  KIT_HOOK_OUT="$(
    cd "$wt" || exit 2
    perl -e '
      my ($t, @cmd) = @ARGV;
      my $pid = fork; defined $pid or exit 126;
      if (!$pid) { setpgrp(0, 0); exec @cmd or exit 127; }
      setpgrp($pid, $pid);
      my $stop = sub { kill "TERM", -$pid; select(undef, undef, undef, 1); kill "KILL", -$pid; };
      $SIG{ALRM} = sub { $stop->(); exit 142 };
      alarm $t; waitpid($pid, 0); my $st = $?; alarm 0; kill "KILL", -$pid;
      exit($st & 127 ? 128 + ($st & 127) : $st >> 8);
    ' "$t" bash "$script" </dev/null 2>&1
    echo "rc=$?"
  )"
  local rc="${KIT_HOOK_OUT##*rc=}"
  KIT_HOOK_OUT="${KIT_HOOK_OUT%rc=*}"
  return "$rc"
}
