#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
for spec in tests/*_spec.lua; do
  echo "== $spec"
  nvim --headless -u NONE -l "$spec" || status=1
done
exit "$status"
