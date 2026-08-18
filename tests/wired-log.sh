#!/usr/bin/env bash
# Checks doctor.sh's log_wired_gb: the GPU wired ceiling the server measured,
# read from the "[wired] mode=max limit=N MB" line of the log's CURRENT run
# (everything after the last "Logging to" banner). The lines are the ones
# mlx-serve 26.8.8 wrote on the 36 GB test machine (AUDIT.md A7).
#
# Usage, from the repo root:  bash tests/wired-log.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lifted="$(sed -n '/^log_wired_gb() {/,/^}/p' "$ROOT/bin/doctor.sh")"
if [ -z "$lifted" ]; then
  echo "FAIL  could not lift log_wired_gb() out of bin/doctor.sh — has it been renamed?" >&2
  exit 1
fi
eval "$lifted"

failures=0
# case <label> <expected> <log text…>
case_() {
  label="$1"; want="$2"; shift 2
  got="$(printf '%s\n' "$@" | log_wired_gb /dev/stdin)"
  if [ "$got" = "$want" ]; then
    printf 'ok    %-28s %s\n' "$label" "'${got}'"
  else
    printf 'FAIL  %-28s expected %s got %s\n' "$label" "'$want'" "'$got'"
    failures=$((failures + 1))
  fi
}

banner='Logging to /Users/x/.mlx-serve/logs/mlx-serve-11234.log (rotates at 32 MB)'
case_ "one run"            "28.1" "$banner" "[wired] mode=max limit=28753 MB" "Hot prefix cache: ENABLED"
case_ "latest run wins"    "20.0" "$banner" "[wired] mode=max limit=28753 MB" "$banner" "[wired] mode=max limit=20480 MB"
case_ "current run has none" ""   "$banner" "[wired] mode=max limit=28753 MB" "$banner" "Hot prefix cache: ENABLED"
case_ "empty log"          ""

if [ "$failures" -eq 0 ]; then
  echo "wired-log: reader reads"
else
  echo "wired-log: $failures FAILED" >&2
  exit 1
fi
