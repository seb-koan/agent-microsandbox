#!/usr/bin/env bash
# Self-check for scripts/sandbox-init.sh + the sandbox-init just recipe.
# Run from anywhere: ./scripts/test-sandbox-init.sh
# Works in a throwaway copy of the repo root so it never writes into sandboxes/.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R Justfile scripts templates "$tmp/"
cd "$tmp" || exit 1

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

i=0
for d in /tmp/test-proj '/tmp/a&b' '/tmp/my project' '/tmp/back\slash'; do
  i=$((i + 1)); n="p$i"
  ./scripts/sandbox-init.sh "$n" --dir "$d" >/dev/null 2>&1
  if grep -qF "bind: $d" "sandboxes/$n/sandbox.yaml" 2>/dev/null &&
     ! grep -qF '${PROJECT_DIR}' "sandboxes/$n/sandbox.yaml"; then
    ok "substitutes --dir $d literally"
  else
    bad "substitutes --dir $d literally"
  fi
done

before=$(cat sandboxes/p1/sandbox.yaml)
err=$(./scripts/sandbox-init.sh p1 --dir /tmp/other 2>&1); rc=$?
if [[ $rc -ne 0 && "$err" == *"already exists"* && "$(cat sandboxes/p1/sandbox.yaml)" == "$before" ]]; then
  ok "refuses to overwrite an existing sandbox.yaml"
else
  bad "refuses to overwrite an existing sandbox.yaml (rc=$rc, err=$err)"
fi

err=$(./scripts/sandbox-init.sh foo --dir 2>&1); rc=$?
if [[ $rc -ne 0 && "$err" == *"--dir <path> is required"* ]]; then
  ok "--dir with no value gives the usage error"
else
  bad "--dir with no value gives the usage error (rc=$rc, err=$err)"
fi

./scripts/sandbox-init.sh ../outside --dir /tmp/x >/dev/null 2>&1; rc=$?
if [[ $rc -ne 0 && ! -e outside && ! -e ../outside ]]; then
  ok "rejects a name that escapes sandboxes/"
else
  bad "rejects a name that escapes sandboxes/ (rc=$rc)"
fi

if command -v just >/dev/null; then
  just sandbox-init 'foo; touch PWNED #' --dir /tmp/x >/dev/null 2>&1
  [[ ! -e PWNED ]] && ok "no shell injection via recipe name arg" || bad "no shell injection via recipe name arg"

  just sandbox-init spaced --dir '/tmp/my project' >/dev/null 2>&1
  grep -qF 'bind: /tmp/my project' sandboxes/spaced/sandbox.yaml 2>/dev/null &&
    ok "recipe keeps a spaced --dir value intact" || bad "recipe keeps a spaced --dir value intact"

  : > globbed-file
  just sandbox-init globtest --dir '/tmp/glob/*' >/dev/null 2>&1
  grep -qF 'bind: /tmp/glob/*' sandboxes/globtest/sandbox.yaml 2>/dev/null &&
    ok "recipe does not glob-expand a --dir value" || bad "recipe does not glob-expand a --dir value"
else
  echo "skip: just not installed — recipe cases not run"
fi

[[ $fail -eq 0 ]] && echo "PASS" || echo "FAILED"
exit $fail
