#!/usr/bin/env bash
# bin/stop.sh — the stop button.
#
# Stops the model server and gives the ~19.1 GB straight back to macOS.
# Safe to run at any time, including when nothing is running.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

usage() {
  cat <<'EOF'
stop.sh — stop the model server and get the memory back.

WHAT IT DOES
  Stops the server that ./bin/serve.sh started, waits up to 10 seconds for it
  to finish tidying up, and then reports how much memory came back.
  If it has not stopped after 10 seconds, it is stopped the hard way.

  Nothing is lost when the server stops. The model on disk is untouched, and a
  conversation you are in the middle of in Claude Code is on disk too.

WHAT IT COSTS
  A few seconds. It gives memory back rather than using any.

IS IT REVERSIBLE
  Yes. Start the server again with ./bin/serve.sh whenever you want.

USAGE (run from the repo root)
  ./bin/stop.sh            stop the server on PORT (default 11234)
  ./bin/stop.sh --help     print this help

WHAT YOU SHOULD SEE
  Either "stopped." or "nothing running on port 11234.", and then a line
  showing memory before and after. If a previous run was killed rather than
  asked to stop, one more line saying its model lock was cleared.

EXIT CODE
  Always 0. There is no failure case: nothing running is a fine outcome.

READ NEXT
  docs/05-run-it.md
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") : ;;
  *) echo "stop.sh: I do not understand '$1'. Try: ./bin/stop.sh --help" >&2; exit 2 ;;
esac

before="$(available_gb)"

if pkill -f "mlx-serve.*--port ${PORT}" 2>/dev/null; then
  # Give it a moment to release the weights, then be firm if it is stuck.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    server_up || break
    sleep 1
  done
  if server_up; then
    echo "did not exit cleanly — sending SIGKILL"
    pkill -9 -f "mlx-serve.*--port ${PORT}" 2>/dev/null || true
    sleep 2
  fi
  echo "stopped."
else
  echo "nothing running on port ${PORT}."
fi

# The lock outlives a process that was killed rather than asked to stop, so the
# stop button is where it gets tidied up. A lock whose holder is still alive is
# never touched: that is a bench.sh run, or a server on another port, and both
# are things this script did not stop and must not pretend it did.
if [ -n "${LOCK_DIR:-}" ] && [ -d "$LOCK_DIR" ]; then
  if clear_stale_model_lock; then
    echo "cleared a model lock left behind by a process that is gone."
  else
    echo "note: the model lock is still held by pid $(model_lock_pid || echo '?') — $(model_lock_what)"
    echo "      that is not the server on port ${PORT}. Nothing was stopped for it."
  fi
fi

after="$(available_gb)"
echo "memory: ${before} GB -> ${after} GB available"
echo
echo "If that barely moved, nothing is wrong. macOS returns freed pages lazily,"
echo "so the memory comes back over the next few seconds rather than at once."
echo "Check again with:  bash -c 'source bin/env.sh && available_gb'"
