#!/usr/bin/env bash
# Sourced helper: detect where the session runs. No side effects on source.

# kit_transport: print "nube" if CLAUDE_CODE_REMOTE=true, else "local".
kit_transport() {
  if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then echo nube; else echo local; fi
}
