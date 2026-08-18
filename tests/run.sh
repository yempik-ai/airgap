#!/usr/bin/env bash
# Runs every test under tests/. Each one is a plain bash script that exits
# non-zero on failure and needs no server and no model weights.
#
# Usage, from the repo root:  bash tests/run.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
failed=0
for t in tests/*.sh; do
  [ "$t" = "tests/run.sh" ] && continue
  echo "── $t"
  if bash "$t"; then :; else failed=$((failed + 1)); fi
  echo
done
if [ "$failed" -eq 0 ]; then echo "tests: all passed"; else echo "tests: $failed script(s) FAILED" >&2; exit 1; fi
