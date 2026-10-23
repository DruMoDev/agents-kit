#!/usr/bin/env bash
# Sourced helper: axis locks for issues labelled serializa:<eje> (a resource no two issues may touch at once, such as
# a sequence of numbered migrations). No side effects on source; git runs in the current directory (a clone of origin).
#
# The lock is a git ref, refs/locks/<eje>, not a label: labels give no compare-and-swap and GitHub lists them seconds
# late, so two agents could both read "free". A push that CREATES a ref is compare-and-swap on the server: the second
# one is rejected. The commit is an orphan with an empty tree: a normal push is fast-forward, not create-only, so a
# descendant of the lock would be accepted over a taken ref; with no common ancestor that cannot happen. Its message,
# "agente:<id> issue:<N> eje:<eje>", is the same format as tiktok-editor's own flow, so locks survive the switch.
# A cloud session cannot push refs/locks (403): kit-issue.sh never picks an issue with an axis there.

# lock_valid <eje>: true if the axis name can be a lock ref (lowercase, digits, . _ -; no "..", no "/": a ref
# refs/locks/db next to refs/locks/db/x would make one of them impossible to create).
lock_valid() {
  local e="${1#serializa:}"
  [[ $e =~ ^[a-z0-9][a-z0-9._-]*$ ]] && [[ $e != *..* ]] && [[ $e != *. ]] && [[ $e != *.lock ]]
}

# lock_ref <eje>: the ref of the axis (with or without the serializa: prefix).
lock_ref() { printf 'refs/locks/%s\n' "${1#serializa:}"; }

# lock_take <eje> <id> <N>: take the axis for issue <N>. Return 0 taken, 1 held by someone else, 2 network or git error.
lock_take() {
  local ref sha
  ref="$(lock_ref "$1")"
  sha="$(git commit-tree "$(git hash-object -t tree /dev/null)" -m "agente:$2 issue:$3 eje:${1#serializa:}")" || return 2
  git push -q origin "$sha:$ref" >/dev/null 2>&1 && return 0
  # tell "someone has it" from "the network failed": if the ref exists, it is the first
  [ -n "$(git ls-remote origin "$ref" 2>/dev/null)" ] && return 1
  return 2
}

# lock_owner <eje>: print the lock's message ("agente:<id> issue:<N> eje:<eje>"). Return 1 if free, 2 if unreadable.
lock_owner() {
  local ref out sha
  ref="$(lock_ref "$1")"
  out="$(git ls-remote origin "$ref" 2>/dev/null)" || return 2
  sha="$(printf '%s' "$out" | cut -f1)"
  [ -n "$sha" ] || return 1
  git fetch -q --no-write-fetch-head origin "$ref" 2>/dev/null || return 2
  git log -1 --format=%B "$sha" 2>/dev/null | sed -n 1p | grep . || return 2
}

# lock_release <eje> <N>: release the axis if issue <N> holds it, printing "candado soltado: <ref>". Return 0 released, free, or held for another issue
# (not ours: nothing to release, and not a failure); 2 if it could not be read or deleted.
# The delete is conditional on the SHA read (--force-with-lease): if the lock changed hands meanwhile, it is not touched.
lock_release() {
  local ref out sha msg
  ref="$(lock_ref "$1")"
  out="$(git ls-remote origin "$ref" 2>/dev/null)" || return 2
  sha="$(printf '%s' "$out" | cut -f1)"
  [ -n "$sha" ] || return 0
  msg="$(lock_owner "$1")"
  case $? in 0) ;; 1) return 0 ;; *) return 2 ;; esac
  case " $msg " in *" issue:$2 "*) ;; *) return 0 ;; esac
  git push -q --force-with-lease="$ref:$sha" origin ":$ref" >/dev/null 2>&1 || return 2
  echo "candado soltado: $ref"
}
