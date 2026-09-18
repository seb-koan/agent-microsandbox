# agent-microsandbox shared OCI image: non-root `agent` user, zsh default shell, mise-first
# on-demand language tooling, git, Claude Code CLI, aliases.sh. One image for every project,
# never rebuilt per project — see docs/specs/2026-09-18-agent-microsandbox-design.md, ### Image.
#
# Base digest re-resolved live at implementation time (2026-09-18) via
# `docker buildx imagetools inspect debian:bookworm-slim --format '{{.Manifest.Digest}}'` (the
# multi-arch index digest, not a per-platform one) — re-check before rebuilding much later.
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

ARG MISE_VERSION=v2026.9.7
ARG CLAUDE_CODE_VERSION=2.1.274
# Placeholders only — never baked as real values. scripts/image-build.sh substitutes the real
# host uid/gid at build time.
ARG HOST_UID=1000
ARG HOST_GID=1000

# ca-certificates/curl are build deps (fetching the mise installer) and stay in the final image
# (the agent needs curl and TLS trust too). git and zsh have no working mise backend (probed live
# against agent-sandbox's own findings: `mise ls-remote github:git/git` -> no versions found;
# `mise registry | grep -i zsh` -> no match), so both stay on apt, matching agent-sandbox's
# apt-get convention. zsh must land before create-agent-user.sh below, which requires
# /bin/zsh to already exist and refuses to run otherwise.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      zsh \
    && rm -rf /var/lib/apt/lists/*

# --- mise itself (root, before user creation) ---
ENV MISE_VERSION=${MISE_VERSION}
RUN curl -fsSL https://mise.run -o /tmp/install-mise.sh \
    && MISE_INSTALL_PATH=/usr/local/bin/mise sh /tmp/install-mise.sh \
    && rm /tmp/install-mise.sh

# --- non-root `agent` user matching host UID/GID (this repo's own script, see file header) ---
COPY create-agent-user.sh /tmp/create-agent-user.sh
RUN sh /tmp/create-agent-user.sh "$HOST_UID" "$HOST_GID" && rm /tmp/create-agent-user.sh

USER agent
WORKDIR /home/agent
ENV PATH="/home/agent/.local/share/mise/shims:${PATH}"

# Claude Code CLI, version-pinned. Mechanism: mise's aqua-backed `claude-code` registry entry
# (mise registry | grep -i claude -> `claude-code aqua:anthropics/claude-code`), spiked live
# against this same base image before writing this Dockerfile — it resolves a native
# linux-arm64 binary with no Node/npm toolchain required, so it costs nothing against the
# mise-first / on-demand-language-tooling rule (Claude Code is CLI infrastructure, not a project
# language). Chosen over `npm install -g @anthropic-ai/claude-code@<pin>` (agent-sandbox's
# method), which would require baking a global Node runtime this image otherwise never needs.
# `mise use -g` here is the one deliberate, pre-authorized exception to "no baked -g tools" — it
# pins CLI infrastructure, not a per-project language toolchain.
RUN mise use -g claude-code@${CLAUDE_CODE_VERSION} \
    && mise reshim

# zsh is the agent user's default login shell (set by create-agent-user.sh above) — this
# activates mise's shell integration and sources aliases.sh for every interactive session.
RUN printf '%s\n' \
      'eval "$(mise activate zsh)"' \
      'source /home/agent/.claude/aliases.sh' \
    > /home/agent/.zshrc

# COPY does not inherit ownership from the preceding USER agent directive; --chown makes the
# destination directory (and file) agent:agent instead of root:root.
COPY --chown=agent:agent aliases.sh /home/agent/.claude/aliases.sh

# Matches the design spec's sandbox.yaml mount target (${PROJECT_DIR}:/home/agent/project).
WORKDIR /home/agent/project
