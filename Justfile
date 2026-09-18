# agent-microsandbox — thin recipe entrypoint.
#
# Convention (matching agent-sandbox): every recipe here is a one-line
# delegation to a script under scripts/, e.g. `./scripts/<name>.sh`. No
# shell logic is inlined in this file — put it in the backing script and
# source scripts/lib.sh for shared checks.
#
# Remaining recipes (sandbox-up, sandbox-shell, sandbox-down, headroom-up,
# headroom-down) arrive with later tickets (T004-T008).

# `set positional-arguments` + `"$@"` (never `{{name}}`/`{{args}}`) is
# deliberate, not decoration: just's `{{...}}` substitution splices parameter
# text raw into the shell command line, so `&` in `/tmp/a&b` is parsed as a
# shell background operator and a name like `foo; touch PWNED #` runs as a
# second command. With positional-arguments, just passes each argument to the
# recipe's shell as a real positional parameter, so quoted `"$@"` forwards them
# one-for-one — no injection, no word splitting, no glob expansion, and
# `--dir "/tmp/my project"` keeps its boundary.
set positional-arguments := true

image-build:
    ./scripts/image-build.sh

image-test:
    ./scripts/image-test.sh

# usage: just sandbox-init <name> --dir <project-dir>
sandbox-init name *args:
    ./scripts/sandbox-init.sh "$@"
