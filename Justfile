# agent-microsandbox — thin recipe entrypoint.
#
# Convention (matching agent-sandbox): every recipe here is a one-line
# delegation to a script under scripts/, e.g. `./scripts/<name>.sh`. No
# shell logic is inlined in this file — put it in the backing script and
# source scripts/lib.sh for shared checks.
#
# Remaining recipes (sandbox-up, sandbox-shell, sandbox-down, headroom-up,
# headroom-down) arrive with later tickets (T002, T004-T008).

# `set export` + quoted `"$name"`/`"$dir"` (never `{{name}}`/`{{dir}}`) is
# deliberate, not decoration: just's `{{...}}` substitution splices parameter
# text raw into the shell command line, so `&` in `/tmp/a&b` is parsed as a
# shell background operator and a name like `foo; touch PWNED #` runs as a
# second command. Exporting parameters as real env vars and expanding them
# *quoted* makes each one exactly one literal argument — no injection, no word
# splitting, no glob expansion.
#
# Named `dir` rather than a variadic `*args`: just joins variadic args with
# spaces, which permanently destroys the boundary in `--dir "/tmp/my project"`.
# So the recipe takes the path positionally and the script keeps its own
# `--dir <path>` flag for direct invocation.
set export := true

# usage: just sandbox-init <name> <project-dir>
sandbox-init name dir:
    ./scripts/sandbox-init.sh "$name" --dir "$dir"
