#!/usr/bin/env bash
# bin/stop.sh — the stop button.
#
# Stops the model server and gives the ~19.1 GB straight back to macOS.
# Safe to run at any time, including when nothing is running.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

usage() {
  cat <<'EOF'
stop.sh — stop whatever is holding the weights and get the memory back.

WHAT IT DOES
  Finds everything on this Mac that is holding the model, stops it, waits up
  to 10 seconds for it to tidy up, and reports how much memory came back. If
  it has not stopped by then, it is stopped the hard way.

  "Everything" is three questions, not one, because one of them alone gives
  the wrong answer:
    - the model lock, which is how a ./bin/bench.sh run — it passes no --port
      at all — or a server on another port is found
    - who is listening on PORT, read with lsof
    - any mlx-serve started by this repo on PORT

  A program on PORT that is not ours is reported and left alone. It is not
  something this script may kill, and calling it "nothing running" would be
  the opposite of the truth.

  Nothing is lost when the server stops. The model on disk is untouched, and a
  conversation you are in the middle of in Claude Code is on disk too.

WHAT IT COSTS
  A few seconds. It gives memory back rather than using any.

IS IT REVERSIBLE
  Yes. Start the server again with ./bin/serve.sh whenever you want.

USAGE (run from the repo root)
  ./bin/stop.sh            stop what holds the weights (PORT defaults to 11234)
  ./bin/stop.sh --help     print this help

WHAT YOU SHOULD SEE
  Either a line per thing stopped or "nothing is holding the weights.", a line
  saying the model lock was given back, and a line showing memory before and
  after. When the server had died on its own, the last lines it wrote.

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

# --- Who is holding the weights? ---------------------------------------------
# Matching `mlx-serve --port <PORT>` was the whole answer here, and it missed
# the two cases that matter (AUDIT.md D4): bench.sh runs mlx-serve with no
# --port at all, so a bench holding ~20 GB was invisible to the stop button;
# and a foreign program on the port was reported as "nothing running" purely
# because pkill found no match. Three sources, unioned:
#
#   1. the model lock — the one thing that knows about an off-port holder.
#      Its pid is the SCRIPT that took it (serve.sh execs into mlx-serve and
#      keeps its pid; bench.sh stays a shell and runs mlx-serve as a child),
#      so the children are collected too or the child would keep the weights
#      after the parent is gone.
#   2. lsof on PORT, which doctor.sh already consults and which is the only
#      way to tell "our server" from "somebody else's program".
#   3. the old pgrep, kept for a server that is starting or shutting down and
#      is not answering lsof at this instant.
targets=""
add_target() {
  [ -n "${1:-}" ] || return 0
  case " $targets " in
    *" $1 "*) : ;;
    *) targets="$targets $1" ;;
  esac
}

lock_pid=""
if [ -n "${LOCK_DIR:-}" ] && model_lock_alive; then
  lock_pid="$(model_lock_pid)"
  add_target "$lock_pid"
  for child in $(pgrep -P "$lock_pid" 2>/dev/null || true); do
    add_target "$child"
  done
fi

port_pids="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | tr '\n' ' ' || true)"
foreign=""
for p in $port_pids; do
  comm="$(ps -o comm= -p "$p" 2>/dev/null || true)"
  case "$(basename "${comm:-unknown}")" in
    mlx-serve) add_target "$p" ;;
    *) foreign="${foreign}${foreign:+, }$(basename "${comm:-unknown}") (pid $p)" ;;
  esac
done

for p in $(pgrep -f "mlx-serve.*--port ${PORT}" 2>/dev/null || true); do
  add_target "$p"
done

any_alive() {
  for _p in $targets; do
    if kill -0 "$_p" 2>/dev/null; then return 0; fi
  done
  return 1
}

# --- Stop them ---------------------------------------------------------------
# Wait on the PROCESS, not the port. mlx-serve closes its socket before it
# exits, so a wait on /health returns while the pid — which is also the pid in
# the model lock — is still shutting down, and the lock check below would then
# find a live holder and report a stale lock as somebody else's.
if [ -n "$targets" ]; then
  for p in $targets; do
    what="$(basename "$(ps -o comm= -p "$p" 2>/dev/null || echo process)")"
    if [ "$p" = "$lock_pid" ]; then
      echo "stopping pid ${p} (${what}) — it holds the model lock: $(model_lock_what)"
    else
      echo "stopping pid ${p} (${what})"
    fi
  done
  # shellcheck disable=SC2086
  kill $targets 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    any_alive || break
    sleep 1
  done
  if any_alive; then
    echo "did not exit cleanly — sending SIGKILL"
    # shellcheck disable=SC2086
    kill -9 $targets 2>/dev/null || true
    sleep 2
  fi
  echo "stopped."
elif [ -n "$foreign" ]; then
  echo "nothing of ours is running, but port ${PORT} is held by ${foreign}."
  echo "  That is not this repo's server, so it was left alone."
  echo "  See what it is:  lsof -nP -iTCP:${PORT} -sTCP:LISTEN"
  echo "  Or move out of its way:  PORT=11235 ./bin/serve.sh"
else
  echo "nothing is holding the weights (and nothing is on port ${PORT})."
fi

# serve.sh execs into mlx-serve, so its lock always outlives it — whether it was
# stopped here or killed — and the stop button is where it gets tidied up.
if [ -n "${LOCK_DIR:-}" ] && [ -d "$LOCK_DIR" ]; then
  held_by="$(model_lock_pid || echo '?')"
  if clear_stale_model_lock; then
    echo "cleared the model lock (its holder, pid ${held_by}, is gone)."
  else
    echo "note: the model lock is still held by pid ${held_by} — $(model_lock_what)"
    echo "      it did not exit. Check it with:  ps -p ${held_by}"
  fi
fi

# The log is the only thing that says why a server is gone, and nothing used to
# show it (AUDIT.md C3). Shown only when there was nothing of ours to stop AND
# the last run did not end with the server's own goodbye line — that is the
# case where "nothing is running" is a surprise and the reason is in the log.
# After a stop we asked for, the last lines are our own shutdown and say
# nothing worth printing.
if [ -z "$targets" ] && [ -z "$foreign" ] && [ -f "$LOG_FILE" ]; then
  logpath="$(echo "$LOG_FILE" | sed "s|^$HOME|~|")"
  if log_ended_cleanly "$LOG_FILE"; then
    echo "the last server on port ${PORT} shut down cleanly (log: ${logpath})."
  else
    echo
    echo "the last server on port ${PORT} did not shut down cleanly. Its last 8 lines,"
    echo "from ${logpath} (mlx-serve rotates that file at 32 MB):"
    log_tail "$LOG_FILE" 8 "  " || true
  fi
fi

after="$(available_gb)"
echo "memory: ${before} GB -> ${after} GB available"
echo
echo "If that barely moved, nothing is wrong. macOS returns freed pages lazily,"
echo "so the memory comes back over the next few seconds rather than at once."
echo "Check again with:  bash -c 'source bin/env.sh && available_gb'"
