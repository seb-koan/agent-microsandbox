# agent-microsandbox — thin recipe entrypoint.
#
# Convention (matching agent-sandbox): every recipe here is a one-line
# delegation to a script under scripts/, e.g. `./scripts/<name>.sh`. No
# shell logic is inlined in this file — put it in the backing script and
# source scripts/lib.sh for shared checks.
#
# Remaining recipes (sandbox-up, sandbox-shell, sandbox-down, headroom-up,
# headroom-down) arrive with later tickets (T002, T004-T008).

# `set export` + `$args` (not `{{args}}`) is deliberate, not decoration: just's
# `{{args}}` template substitution splices variadic args as raw text into the
# shell command line, so a `&` in e.g. `--dir /tmp/a&b` gets parsed as a shell
# background operator before the script ever sees it. Exporting args as a real
# env var and expanding it with `$args` avoids that text-splicing entirely.
set export := true

sandbox-init name *args:
    ./scripts/sandbox-init.sh {{name}} $args
