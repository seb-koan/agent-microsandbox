# Launch helpers for the agent user's Claude Code setup. Sourced from ~/.zshrc.
# Ported from agent-sandbox's claude-config/aliases.sh, with deliberate divergences noted inline
# (see T002 ticket Outcome for the full list).

# Both `claude` and `claude-headroom` bake in --dangerously-skip-permissions by default here,
# unlike agent-sandbox's separate bypass-flag opt-in aliases (dropped below). This project's
# sandboxes are network-allowlisted and filesystem-scoped by design (design spec, ### Image), the
# precondition Anthropic's own docs list bypassPermissions as "best for" (isolated containers/VMs
# only). Self-referential expansion (`claude` aliased to a command starting with `claude`) is a
# standard, safe shell idiom (same shape as `alias ls='ls --color=auto'`) — shells expand an
# alias's own name only once, so this does not recurse. Do not "fix" this.
alias claude='claude --dangerously-skip-permissions'

# headroom itself is never installed in this image (one shared host-side instance only, per the
# design spec and standing rules) — this alias only redirects ANTHROPIC_BASE_URL at it.
# HEADROOM_URL is intentionally unset here: the real proxy address is injected by a project's
# sandbox.yaml (T003+), not baked into the shared image. Wiring the auth token headroom expects
# from its clients is deferred to T006/the credentials ticket.
alias claude-headroom='ANTHROPIC_BASE_URL="${HEADROOM_URL:?HEADROOM_URL unset - the headroom proxy URL is injected by sandbox.yaml, see T006}" claude --dangerously-skip-permissions'

alias claude-opus='claude --model opus'
alias claude-sonnet='claude --model sonnet'
alias claude-haiku='claude --model haiku'
alias claude-continue='claude --continue'     # resume the most recent conversation here
alias claude-resume='claude --resume'          # interactive picker, or --resume <session-id>
alias claude-safe='claude --safe-mode'         # disable CLAUDE.md/skills/plugins/hooks -
                                                # troubleshooting aid for this project's own
                                                # curated config, not a generic Claude Code tip

# /home/agent/project is this image's one mount point (design spec's sandbox.yaml template) —
# NOT agent-sandbox's /workspace/project, which this image never mounts.
alias cdproj='cd /home/agent/project'

# cdkb (agent-sandbox's knowledge-base mount) is dropped: this project's spec has exactly one
# mount, the project dir — no knowledge-base mount exists to cd into.
