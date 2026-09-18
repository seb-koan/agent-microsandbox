#!/usr/bin/env bash
# Publish the shared image to GHCR (not Docker Hub), so `msb create` can pull it directly on any
# machine without a local `docker build` first. `docker login ghcr.io` must already be done
# (e.g. `gh auth token | docker login ghcr.io -u <user> --password-stdin`).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

require_repo_root
require_docker

docker push ghcr.io/seb-koan/agent-microsandbox:latest
