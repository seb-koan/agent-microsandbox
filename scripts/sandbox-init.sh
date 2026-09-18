#!/usr/bin/env bash
# just sandbox-init <name> --dir <path>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="${1:?usage: sandbox-init <name> --dir <path>}"; shift
project_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) project_dir="$2"; shift 2 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$project_dir" ]] || { echo "error: --dir <path> is required" >&2; exit 1; }

require_repo_root

out="sandboxes/${name}/sandbox.yaml"
if [[ -f "$out" ]]; then
  echo "error: $out already exists — edit it directly or remove it to re-init" >&2
  exit 1
fi

mkdir -p "sandboxes/${name}"
# Escape sed replacement metacharacters (& = "insert matched text", \ = escape, # = our
# delimiter) so a --dir path containing any of them substitutes literally instead of
# corrupting the output.
escaped_dir=$(printf '%s' "$project_dir" | sed 's/[&\#]/\\&/g')
sed "s#\${PROJECT_DIR}#${escaped_dir}#g" templates/sandbox.yaml.tmpl > "$out"
echo "scaffolded $out"
