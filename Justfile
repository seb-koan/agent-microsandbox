# agent-microsandbox — thin recipe entrypoint.
#
# Convention (matching agent-sandbox): every recipe here is a one-line
# delegation to a script under scripts/, e.g. `./scripts/<name>.sh`. No
# shell logic is inlined in this file — put it in the backing script and
# source scripts/lib.sh for shared checks.
#
# This file is scaffolding only (T001): zero recipes yet. Real recipes
# (sandbox-init, sandbox-up, sandbox-shell, sandbox-down, headroom-up,
# headroom-down) arrive with later tickets (T002-T008).
