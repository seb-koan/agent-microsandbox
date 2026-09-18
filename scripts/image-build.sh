#!/usr/bin/env bash
# Build the one shared OCI image every project's sandbox references. Keeps the real host
# uid/gid out of the committed Dockerfile (which only carries placeholder ARG defaults).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

require_repo_root
require_docker

docker build -t agent-microsandbox:latest \
  --build-arg HOST_UID="$(id -u)" \
  --build-arg HOST_GID="$(id -g)" \
  image/
