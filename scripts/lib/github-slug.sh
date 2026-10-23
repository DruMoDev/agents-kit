#!/usr/bin/env bash
# Sourced helper: derive the "owner/repo" slug of a GitHub origin. No side effects on source.

# kit_parse_github_url <url>: print owner/repo, or nothing if the URL is not a github.com one.
# Accepts https/ssh/scp-like forms, optional user, ssh/https port, trailing slash and .git, any host case.
kit_parse_github_url() (
  shopt -s nocasematch
  url="$1"
  re_scheme='^(https?://|ssh://)([^@/]+@)?github\.com(:[0-9]+)?/+([^/]+)/([^/]+)/*$'
  re_scp='^[^@/:]+@github\.com:/*([^/]+)/([^/]+)/*$'
  if [[ $url =~ $re_scheme ]]; then
    owner="${BASH_REMATCH[4]}"; repo="${BASH_REMATCH[5]}"
  elif [[ $url =~ $re_scp ]]; then
    owner="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
  else
    exit 0
  fi
  repo="${repo%.git}"; repo="${repo%.GIT}"
  [ -n "$owner" ] && [ -n "$repo" ] && printf '%s/%s\n' "$owner" "$repo"
  exit 0
)

# kit_origin_slug: slug of remote 'origin' of the current repo. Falls back to the
# insteadOf-resolved URL when the raw configured one does not parse.
kit_origin_slug() {
  local s
  s="$(kit_parse_github_url "$(git config --get remote.origin.url 2>/dev/null)")"
  [ -n "$s" ] || s="$(kit_parse_github_url "$(git remote get-url origin 2>/dev/null)")"
  [ -z "$s" ] || printf '%s\n' "$s"
}
