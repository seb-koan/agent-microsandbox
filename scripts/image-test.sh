#!/usr/bin/env bash
# Regression check for create-agent-user.sh's gid-collision branch.
#
# A host gid can collide with a Debian *system* group — macOS's default primary group `staff`
# is gid 20, which is `dialout` in debian:bookworm-slim. The script must reuse that group for
# the agent user, never rename it away (which would make `getent group dialout` return nothing
# for every later layer and every T003+ ticket built on this image).
#
# Runs against the plain base image, not the built one, so it exercises the collision branch
# regardless of what this host's own gid happens to be.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

require_repo_root
require_docker

# ponytail: /bin/zsh is stubbed rather than apt-installed — the script only needs the path to
# exist, and this keeps the check a single fast `docker run` with no network.
docker run --rm -v "$PWD/image:/image:ro" debian:bookworm-slim sh -euc '
  cp /bin/sh /bin/zsh
  sh /image/create-agent-user.sh 501 20
  getent group dialout >/dev/null || { echo "FAIL: system group dialout was renamed away"; exit 1; }
  [ "$(id -g agent)" = 20 ] || { echo "FAIL: agent primary gid is $(id -g agent), want 20"; exit 1; }
  [ "$(getent passwd agent | cut -d: -f7)" = /bin/zsh ] || { echo "FAIL: agent shell is not /bin/zsh"; exit 1; }
  echo PASS
'
