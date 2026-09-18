#!/bin/sh
# Create the non-root `agent` user at the host's UID/GID, inside the image build.
#
# This is agent-microsandbox's own file — its logic was read from agent-sandbox's
# scripts/create-agent-user.sh (a sibling, read-only reference project, never modified) and
# reimplemented here, not copied.
#
# Non-root is a hard requirement, not a convention: Claude Code's --dangerously-skip-permissions
# (bypassPermissions) mode refuses to start as root/sudo on Linux/macOS outside a fully managed
# sandbox runtime (Anthropic docs, https://code.claude.com/docs/en/permission-modes).
#
# A colliding uid/gid is never resolved destructively: a taken gid is reused as-is, and a taken
# uid is renamed (never deleted — it may be another account's primary group, which `groupdel`
# refuses to remove anyway).
set -eu

uid="$1"
gid="$2"

if [ "$uid" -eq 0 ] || [ "$gid" -eq 0 ]; then
  echo "create-agent-user: refusing HOST_UID/HOST_GID 0 — this image must run non-root" >&2
  echo "  (build as a normal user, or pass explicit non-zero --build-arg HOST_UID/HOST_GID)" >&2
  exit 1
fi

# useradd/usermod only *warn* about a missing login shell and still exit 0, which would ship an
# account whose shell doesn't exist. zsh must be apt-installed before this script runs — fail
# loud here if that ordering ever regresses instead of leaving it to a Dockerfile comment.
if [ ! -x /bin/zsh ]; then
  echo "create-agent-user: /bin/zsh missing or not executable — install zsh before this runs" >&2
  exit 1
fi

# Only the *numeric* gid matters (it's what makes bind-mounted host files writable), so a gid
# already in use is simply reused as agent's primary group — never renamed. Host gids routinely
# collide with Debian system groups (macOS's default `staff` is gid 20, which is `dialout` here),
# and renaming one would silently remove that name from the image for every later layer.
if ! getent group "$gid" >/dev/null; then
  groupadd -g "$gid" agent
fi

existing_user="$(getent passwd "$uid" | cut -d: -f1)"
if [ -n "$existing_user" ]; then
  usermod -l agent -g "$gid" -d /home/agent -m -s /bin/zsh "$existing_user"
else
  useradd -m -u "$uid" -g "$gid" -s /bin/zsh agent
fi
