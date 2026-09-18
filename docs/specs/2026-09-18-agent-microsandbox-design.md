# agent-microsandbox: terminal-native, least-privilege sandboxes for coding agents

## Context

`agent-sandbox` (a sibling project) isolates a coding agent from the host using a single
long-lived Docker container plus a privileged nested `dind` sidecar, with code-server and ttyd
providing browser-based access. Investigation during design showed the browser access was never
a real requirement — it was a workaround for getting into the container — and the isolation model
gives the agent more reach than "only what the job needs": a full nested Docker daemon with no
network allowlist, and secrets loaded as raw environment variables with no enforcement.

The actual goal is to work safely with an agent by giving it exactly the access a given project
needs and nothing more, driven entirely from the terminal. `microsandbox`
(https://github.com/superradcompany/microsandbox) already provides the primitives this needs
natively — per-directory bind mounts (including read-only), network allowlisting, resource
limits, and named/secret-scoped credentials with enforcement — confirmed against its own docs
during design, not just its marketing pitch. This project does not touch or depend on
`agent-sandbox`; it's a new, separate replacement for the same underlying need.

## Goals

- Per-project sandboxes with least-privilege access: only the project's own directory, only the
  network hosts that project needs, nothing else by default.
- Fully terminal-driven — no browser component of any kind.
- Persistent per project (long-lived, like today's workflow), not spun up fresh per task.
- Agent-agnostic in principle; Claude Code is the first and primary target.
- Log in once: no per-sandbox `claude login`, for either credential path below.
- Reuse microsandbox's and agent-sandbox's existing primitives instead of building new ones —
  this project is intentionally a thin wrapper, not a platform.

## Non-goals

- Not a Docker/dind replacement inside agent-sandbox — that project is untouched.
- Not building a custom sandboxing engine, secrets vault, or network proxy — microsandbox and
  headroom already provide these.
- Not ephemeral/per-task sandboxes (rejected in favor of persistent-per-project; could be added
  later as a different sandbox profile if a concrete need shows up).

## Architecture

One repo (this one), same shape as agent-sandbox's `Justfile` → `scripts/` convention:

```
agent-microsandbox/
├── Justfile                  # thin recipes, delegate to scripts/
├── scripts/
│   ├── headroom-up.sh        # start the ONE shared headroom proxy (host process)
│   ├── headroom-down.sh
│   ├── sandbox-init.sh       # scaffold sandboxes/<name>/sandbox.yaml from template
│   ├── sandbox-up.sh         # msb create (first run) / msb start --conf sandboxes/<name>/sandbox.yaml
│   ├── sandbox-shell.sh      # msb exec into the named sandbox, drop into zsh
│   └── sandbox-down.sh       # msb stop <name>
├── templates/
│   └── sandbox.yaml.tmpl     # default per-project template
├── image/
│   └── Dockerfile            # shared OCI image: git + mise + claude code + aliases.sh
├── secrets/
│   └── claude.env.example    # CLAUDE_CODE_OAUTH_TOKEN=... (real file gitignored)
└── sandboxes/
    └── <project-name>/
        └── sandbox.yaml      # persisted, git-shareable, one per project
```

Each project gets its own named, persistent microsandbox instance (persistence is the default for
a named sandbox created via `msb create --name <name>` — no separate "detached" flag exists on
`create`/`start`; `-d`/`--detach` is a `msb run`-only flag for backgrounding a foreground command,
confirmed against microsandbox's CLI docs) defined by its own checked-in `sandbox.yaml`. One
shared `headroom` process runs on the host, not sandboxed itself, as a token-compression proxy —
every project's sandbox reaches it over an explicitly allowlisted network entry, never the open
internet by default. (Headroom does **not** broker Anthropic credentials — see Credentials below,
corrected from an earlier assumption.)

## Components

### `sandbox.yaml` template

```yaml
image: agent-microsandbox:latest
workdir: /home/agent/project
cpus: 2
memory: 2G
mounts:
  - "${PROJECT_DIR}:/home/agent/project"   # rw — the agent needs to edit this
network:
  allow: ["headroom-host-placeholder"]     # a non-empty allow list implies deny-by-default egress
secrets:
  CLAUDE_CODE_OAUTH_TOKEN:
    allow: ["api.anthropic.com"]           # exact Anthropic host(s) to confirm at implementation time
```

Corrected against microsandbox's actual config docs (an earlier draft of this template used syntax
that doesn't exist): there is no `resources:` wrapper — `cpus`/`memory` are flat top-level keys.
There is no `policy: none` + `allow` combination — `policy: none` is an absolute deny with no
allow-list override; the real least-privilege idiom is a non-empty `allow` list on its own, which
implies deny-by-default egress. `allow` entries are hostnames, not `host:port` pairs. `secrets:` is
a map keyed by secret name, not a list, and every secret requires its own `allow` (destination)
list — see Credentials below for what that list actually gates.

Least-privilege by default: no network except headroom, one read-write mount (the project dir).
A project that needs npm/PyPI/GitHub access adds those hosts explicitly to its own `sandbox.yaml`
— visible, reviewable, per project, never a global default.

### Image

One shared image for every project, not rebuilt per project — mise for on-demand language
toolchains (installed at first use inside a project's sandbox rather than baked in per
language), Claude Code CLI, and `aliases.sh` ported from agent-sandbox (`claude-yolo`, `cdproj`,
etc.), plus two additions:
- `claude` — direct to Anthropic, authenticated via the injected `CLAUDE_CODE_OAUTH_TOKEN` secret.
- `claude-headroom` — routed through the shared headroom proxy for token compression.

Both aliases bake in `--dangerously-skip-permissions` (`bypassPermissions` mode) by default — the
agent runs fully unattended inside the sandbox, no per-tool confirmation prompts. This is a
deliberate default here, not just an opt-in extra like agent-sandbox's separate `claude-yolo`
alias: Anthropic's own docs list `bypassPermissions`'s "best for" as **"Isolated containers and
VMs only,"** and agent-sandbox's own alias comment notes the flag's `--help` text says
"Recommended only for sandboxes with no internet access" — agent-sandbox kept it opt-in
specifically because its container has full outbound internet. This project's sandboxes are
network-allowlisted and filesystem-scoped by design, which is much closer to that precondition,
so bypass-by-default is the intended behavior, not a shortcut. Two things this depends on,
carried as hard requirements rather than conventions:
- The `agent` user inside the image must be non-root (Anthropic's own requirement for this mode
  outside a fully managed sandbox runtime).
- **`bypassPermissions` offers no protection against prompt injection or unintended actions**
  (Anthropic's own docs, verbatim) — the sandbox's mount/network scoping is the only real safety
  boundary in this design; Claude Code's own permission checks are deliberately off, not a
  backstop. This is the core tradeoff the whole project is built around, not an incidental detail.

### Credentials (one login, two paths)

`claude setup-token` mints a one-year OAuth token against the actual subscription (confirmed:
works with Pro, Max, Team, and Enterprise — not just Enterprise, and not a separate
Console/API-key credential; it's the same subscription login as `/login`, just long-lived and
non-interactive). Run once on the host, stored in `secrets/claude.env` (gitignored, same
convention as agent-sandbox's `secrets/agent.env`).

**Corrected from an earlier assumption:** headroom does not broker Anthropic credentials for
Claude. Its own docs document real credential exchange only for Copilot and Kimi CLIs; for Claude,
`headroom wrap`/`headroom proxy` is a compression pass-through in front of an already-authenticated
`claude` process, nothing more. So **both** aliases need the real credential — the two paths differ
only in whether traffic is compressed, not in how they authenticate:

- **`claude`**: each project's `sandbox.yaml` injects the token via microsandbox's `secrets:`
  field as `CLAUDE_CODE_OAUTH_TOKEN`, talking to Anthropic directly.
- **`claude-headroom`**: gets the *same* injected `CLAUDE_CODE_OAUTH_TOKEN`, with
  `ANTHROPIC_BASE_URL` pointed at the shared headroom proxy for token-compression savings.

This is still "log in once" (one `claude setup-token` run covers every sandbox) and still keeps
the real value out of the guest's own memory space: microsandbox's `secrets:` mechanism gives the
guest only a placeholder (`$MSB_<name>`, confirmed live) — the real token is substituted in only
at the network boundary, into requests to hosts on that secret's own `allow` list (headers, by
default). This means the secret's `allow` list must name the exact host(s) Claude Code's traffic
actually goes to (`api.anthropic.com`, to be confirmed exactly at implementation time) — the
credential is never resolved in the guest's own environment at all, a stronger guarantee than
"injected safely" implied.

Caveat carried from Anthropic's docs: this token can only make model requests — no Remote
Control sessions, no claude.ai connectors, from inside a sandbox. Acceptable for a coding-agent
sandbox. Renewal is yearly, not per-session.

### headroom (shared, single instance)

One instance, not one per sandbox: a compression-only proxy (`headroom proxy --port 8787`, no
`--memory`/`--learn` flags — see below), started/stopped via `just headroom-up` / `just
headroom-down`, running as a host process (not sandboxed). It does not hold or broker Anthropic
credentials (see Credentials above) — its only job is reducing tokens sent to the model.

**Confirmed, not just suspected, during implementation research:** headroom's cross-agent
memory/dedup store is off by default (`--memory` defaults to `false`) and, when enabled, is scoped
to the *proxy process's own working directory* — a single shared instance serving every project
would pool all of them into one unscoped store, with isolation only available via either a
distinct `--memory-db-path` per instance (which contradicts "one shared instance") or a per-request
`x-headroom-user-id` header that a plain `ANTHROPIC_BASE_URL`-pointed Claude Code never sends. **Do
not enable `--memory`/`--learn` on the shared instance** until a follow-up ticket builds real
per-project scoping — this is a deliberate deferral (the feature is off by default anyway), not an
accepted leak.

## Data flow

1. One-time host setup: `just headroom-up`; `claude setup-token` → paste into `secrets/claude.env`.
2. New project: `just sandbox-init <name> --dir /path/to/project` → scaffolds
   `sandboxes/<name>/sandbox.yaml` from the template.
3. `just sandbox-up <name>` → `msb create --name <name> --conf sandboxes/<name>/sandbox.yaml`
   (first run — `--conf` is a `create`-only flag) or `msb start <name>` (subsequent runs — takes
   no `--conf`, resumes from the persisted config) — named sandboxes persist by default, no
   detach flag needed.
4. `just sandbox-shell <name>` → `msb exec <name> -- zsh` (or the agent's shell), lands in an
   interactive prompt as the agent user; run `claude` or `claude-headroom`.
5. Stop/resume across days: `just sandbox-down <name>` / `just sandbox-up <name>` — filesystem
   state persists per microsandbox's lifecycle guarantees (confirmed: stop preserves the VM's
   disk state for the next start).

## Error handling

- `sandbox-init` refuses to overwrite an existing `sandboxes/<name>/sandbox.yaml` — must edit or
  explicitly re-init.
- `sandbox-up` / `sandbox-shell` check `msb` is installed, and (for the headroom path) that
  `headroom-up` has been run, before erroring — same "fail gracefully with an actionable message"
  convention as agent-sandbox's `compose_ready`.
- Missing `secrets/claude.env` → a clear error pointing at the `claude setup-token` step, not a
  cryptic auth failure surfacing from inside the sandbox.

## Verification

On a throwaway test project:
1. `sandbox-init` + `sandbox-up` + `sandbox-shell` — confirm both `claude` and `claude-headroom`
   authenticate with no login prompt.
2. Confirm the mount: `pwd`/project files show only the bound project directory, nothing else of
   the host filesystem is reachable.
3. Confirm the network allowlist: a request to a non-allowlisted host fails from inside the
   sandbox; a request to the allowlisted headroom host succeeds.
4. `sandbox-down` then `sandbox-up` again — confirm a file written before the stop still exists
   after the restart (persistence proof).

## Open items to verify during implementation

All items originally listed here were resolved during ticket-creation research (T002–T008); one
new, narrower item replaces them:

- The exact Anthropic host(s) Claude Code's traffic actually goes to, for the
  `CLAUDE_CODE_OAUTH_TOKEN` secret's `allow` list (`api.anthropic.com` is the working assumption,
  not yet confirmed against live Claude Code network traffic).
