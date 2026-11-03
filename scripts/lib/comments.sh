#!/usr/bin/env bash
# Sourced helper: comments of an issue or PR by REST, shared by kit-issue.sh and kit-pr.sh. No side effects on source.
# A valid answer of Dru, in both gates (an answered kit-decision, an approved kit-regla): a comment of the gh account
# ($me) without any <!-- kit- marker (every comment the kit posts carries one), created after the kit comment it answers.

# kit_rest_comments <slug> <N>: print the comments of issue or PR <N> as one JSON array of {id, login, body,
# created_at}, in posting order; return 1 if gh fails or its answer is unreadable.
kit_rest_comments() {
  local raw
  raw="$(gh api "repos/$1/issues/$2/comments?per_page=100" --paginate)" || return 1
  printf '%s' "$raw" | jq -cs '[(add // [])[] | {id, login: .user.login, body: (.body // ""), created_at}]'
}

# KIT_ANSWER_JQ: jq definition to prepend to a program; kit_answer($me) is true for a comment of kit_rest_comments
# that can be Dru's answer (the time check stays with each gate).
KIT_ANSWER_JQ='def kit_answer($me): .login == $me and (.body | contains("<!-- kit-") | not);'
