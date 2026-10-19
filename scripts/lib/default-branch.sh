#!/usr/bin/env bash
# Sourced helper: default branch of remote 'origin'. No side effects on source.

# kit_default_branch: print origin's default branch (asks the remote); prints nothing if unknown.
kit_default_branch() {
  git ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p'
}
