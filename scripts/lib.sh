#!/usr/bin/env bash
# Sourced by scripts/*.sh — not meant to be run directly.
#
# Pattern (matching agent-sandbox's compose_ready() shape): one small
# function per hardcoded prerequisite check, not a generic parameterized
# helper. Each check looks like:
#
#   check_thing() {
#     if <thing missing>; then
#       echo "error: <what's wrong> — <actionable next step>" >&2
#       return 1
#     fi
#     return 0
#   }
#
# Never `exit` here — this file is sourced, so a failed check must `return`
# and let the caller decide what to do.
#
# Later tickets add checks following this same shape as they need them,
# e.g. require_msb, require_secrets_env, require_headroom.

require_repo_root() {
  if [[ ! -f Justfile ]]; then
    echo "error: Justfile not found — run this from the agent-microsandbox repo root" >&2
    return 1
  fi
  return 0
}
