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

Each project gets its own named, persistent (`detached`) microsandbox instance defined by its own
checked-in `sandbox.yaml`. One shared `headroom` process runs on the host, not sandboxed itself —
it's the thing holding the real credential, not the thing being isolated. Every project's sandbox
reaches it over an explicitly allowlisted network entry, never the open internet by default.

## Components

### `sandbox.yaml` template

```yaml
image: agent-microsandbox:latest
workdir: /home/agent/project
mounts:
  - bind: ${PROJECT_DIR}
    to: /home/agent/project        # rw — the agent needs to edit this
network:
  policy: none
  allow:
    - host: 127.0.0.1:8787         # the shared headroom proxy; nothing else by default
secrets:
  - name: CLAUDE_CODE_OAUTH_TOKEN
    from: secrets/claude.env
resources:
  cpus: 2
  memory: 2G
```

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

- **`claude` (direct)**: each project's `sandbox.yaml` injects this token via microsandbox's
  `secrets:` field (named credential, with an allowlist/violation action per microsandbox's
  secrets model) as `CLAUDE_CODE_OAUTH_TOKEN`. Claude Code picks it up per its documented
  credential precedence. No `claude login` ever runs inside a sandbox.
- **`claude-headroom`**: the shared host-side headroom process holds this same token and performs
  the authenticated upstream call; the sandbox's alias points `ANTHROPIC_BASE_URL` at headroom
  with a local `ANTHROPIC_AUTH_TOKEN` headroom expects from its clients — the real Anthropic
  credential never enters the sandbox on this path either.

Caveat carried from Anthropic's docs: this token can only make model requests — no Remote
Control sessions, no claude.ai connectors, from inside a sandbox. Acceptable for a coding-agent
sandbox. Renewal is yearly, not per-session.

### headroom (shared, single instance)

One instance, not one per sandbox: it loads real ML models into memory and keeps a cross-agent
memory/dedup store explicitly designed to compound across sessions — spinning up a fresh instance
per sandbox would reload models every time and defeat the dedup design. Started/stopped via
`just headroom-up` / `just headroom-down`, running as a host process (not sandboxed).

**Verify during implementation, not assumed:** headroom's cross-agent memory/dedup isn't
documented as namespaced per project/client — if it pools context across all agents by default,
that leaks one project's content into another's cache, which cuts against the least-privilege
goal. Check headroom's config for per-client scoping before trusting it across sandboxes with
different trust levels.

## Data flow

1. One-time host setup: `just headroom-up`; `claude setup-token` → paste into `secrets/claude.env`.
2. New project: `just sandbox-init <name> --dir /path/to/project` → scaffolds
   `sandboxes/<name>/sandbox.yaml` from the template.
3. `just sandbox-up <name>` → `msb create --conf sandboxes/<name>/sandbox.yaml` (first run) or
   `msb start <name>` (subsequent runs) — detached, persists.
4. `just sandbox-shell <name>` → `msb exec` into it, lands in zsh as the agent user; run `claude`
   or `claude-headroom`.
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

- Exact microsandbox `secrets:` field syntax (allowlist/violation-action config) against
  `docs.microsandbox.dev` at build time — the schema fields are confirmed to exist, exact syntax
  wasn't pulled in full.
- Whether headroom's proxy mode actually performs credential injection (attaching the real
  token to the upstream request) as opposed to only rewriting the API base URL — confirm against
  headroom's own docs before wiring the `claude-headroom` alias.
- headroom's per-project/per-client memory scoping (see above).
