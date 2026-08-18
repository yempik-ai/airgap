#!/usr/bin/env bash
# bin/run.sh — start a coding harness and point it at the model on your own Mac.
#
# Start ./bin/serve.sh in another window first. This script does not start the
# server and does not load the model.
#
# One file per harness lives in harness/. This script picks one, lets it wire
# itself, checks the server, prints what was decided, and hands over. The
# harness-specific knowledge is in the adapter; everything every harness needs
# is here, once.
#
# Every question you type goes to 127.0.0.1, which is your own Mac and nowhere
# else. No account, no key, no network.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

HARNESS_DIR="$ROOT/harness"

usage() {
  cat <<'EOF'
run.sh — run a coding harness against the model on your own Mac.

BEFORE YOU RUN IT
  ./bin/serve.sh must already be running in another window. This script checks,
  and tells you if it is not.

WHAT IT DOES
  Reads harness/<name>.sh, lets it point every one of that harness's model
  settings at your Mac, checks that the server is answering, prints what it
  decided, and starts the harness. Nothing in the harness is left pointing at
  a company's servers, and a real key in your shell cannot take priority.

WHAT IT COSTS
  No extra memory beyond the server that is already running. No money.
  Nothing leaves your Mac.

USAGE (run from the folder you want to work in)
  ./bin/run.sh                       list the harnesses this repo can start
  ./bin/run.sh claude-code           start that harness in the current folder
  ./bin/run.sh claude-code -p "hi"   ask it one question and exit
  ./bin/run.sh --probe claude-code   send one test question and report
  ./bin/run.sh --help                print this help

  Options come before the name. Everything after the name is passed to the
  harness exactly as you typed it, including --help, which is the harness's
  own flag from that point on.

WHAT --probe DOES
  Sends "Reply with exactly: AIRGAP OK" through the harness with nothing on
  its input, waits for one answer, and prints one line: whether the answer
  came back, how long it took (MEASURED, wall clock, a cold model reloading
  its weights included), and how many prompt tokens the server counted for
  that one turn — the harness's fixed cost per turn, as the server saw it.
  Exit code 0 when the answer arrived, 1 when it did not.

SETTINGS
  Everything in config.env applies. The ones this script reads itself:
  SERVE_TIMEOUT   seconds of silence before a question is given up on. The
                  client waits a minute longer, so the server is the side that
                  reports a stall, and --probe gives up at the client's limit.
                  Default: 300
  METRICS=0       do not ask the server for its token counters. --probe then
                  says the token figure is unavailable instead of guessing.
  Each harness has its own settings. Ask it:  ./bin/run.sh <name> --help

IF IT SAYS THERE IS NO SERVER
  Open another window, go to the repo root, and run ./bin/serve.sh.
  See docs/06-troubleshooting.md#no-server

READ NEXT
  docs/10-other-harnesses.md
EOF
}

# The adapters that exist, one name per line, in the order the shell lists
# them. Derived from the folder every time, so adding a file adds a harness.
harness_list() {
  for _h in "$HARNESS_DIR"/*.sh; do
    [ -f "$_h" ] || continue
    _h="$(basename "$_h")"
    printf '%s\n' "${_h%.sh}"
  done
  unset _h
}

# Say which harnesses there are and stop. $1, when given, is the name that was
# asked for and does not exist.
refuse_with_list() {
  if [ -n "${1:-}" ]; then
    echo "error: no harness called '$1' in $HARNESS_DIR" >&2
  else
    echo "error: which harness? Name one." >&2
  fi
  echo >&2
  echo "This repo can start:" >&2
  harness_list | sed 's/^/    /' >&2
  echo >&2
  # sed, not `head -1`: head closes the pipe on the first line, and under
  # `pipefail` a producer that got that far would take the script down with it.
  echo "For example:  ./bin/run.sh $(harness_list | sed -n 1p)" >&2
  exit 1
}

# --- What was asked for ------------------------------------------------------
# Options first, then the harness name, then that harness's own arguments. The
# loop stops at the first thing that is not an option of ours, so `--help`
# after the name belongs to the harness and never reaches this case.
probe=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --probe) probe=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "run.sh: I do not understand '$1'. Try: ./bin/run.sh --help" >&2; exit 2 ;;
    *) break ;;
  esac
done

if [ "$#" -eq 0 ]; then
  refuse_with_list
fi
harness="$1"; shift
case "$harness" in
  */*|"") refuse_with_list "$harness" ;;
esac
[ -f "$HARNESS_DIR/$harness.sh" ] || refuse_with_list "$harness"

# --- Let the harness wire itself ---------------------------------------------
# shellcheck source=/dev/null
source "$HARNESS_DIR/$harness.sh"

# `./bin/run.sh <name> --help` is the adapter's help, when it has one.
# Everything else, --help included, is the harness's own flag.
case "${1:-}" in
  -h|--help)
    if declare -f harness_usage >/dev/null 2>&1; then
      harness_usage
      exit 0
    fi ;;
esac

HARNESS_ARGS=()
HARNESS_NOTES=()
# Before the server check on purpose: a typo in a harness setting is refused
# whether or not the server happens to be running, and the message says which
# setting. tests/thinking-knob.sh observes this order.
harness_wire

# A dead server makes a harness fail in confusing ways much later, so check now.
if ! server_up; then
  echo "error: no server at $BASE_URL — start ./bin/serve.sh first" >&2
  echo >&2
  echo "Open another Terminal window, then type these two lines:" >&2
  echo "    cd $ROOT" >&2
  echo "    ./bin/serve.sh" >&2
  echo "Wait until it says it is listening, then run this command again." >&2
  exit 1
fi

# --- What was decided --------------------------------------------------------
client_ms="$(client_timeout_ms)"
printf '%-8s -> %s   model %s  (%s)\n' "$harness" "$BASE_URL" "$MODEL_ID" "$HARNESS_DIALECT"
echo "context  $CTX_SIZE tokens declared to the harness"
if [ "${SERVE_TIMEOUT:-300}" = "0" ]; then
  echo "timeout  client gives up after $((client_ms / 1000))s of silence; the server never does (SERVE_TIMEOUT=0)"
else
  echo "timeout  client gives up after $((client_ms / 1000))s of silence, the server after ${SERVE_TIMEOUT}s — so the server reports it"
fi
if [ "${#HARNESS_NOTES[@]}" -gt 0 ]; then
  printf '%s\n' "${HARNESS_NOTES[@]}"
fi
echo

# --- Hand over, or probe -----------------------------------------------------
if [ "$probe" = "0" ]; then
  # ${HARNESS_ARGS[@]+"${HARNESS_ARGS[@]}"} rather than "${HARNESS_ARGS[@]}":
  # under `set -u`, bash 3.2 (the version macOS ships) treats an EMPTY array as
  # an unset variable and stops.
  exec "$HARNESS_BIN" ${HARNESS_ARGS[@]+"${HARNESS_ARGS[@]}"} "$@"
fi

# Milliseconds since the epoch. macOS's date(1) has no %N, so this asks the
# same python3 env.sh's config.json readers use, and falls back to whole
# seconds without one — which costs the probe line its tenth of a second and
# nothing else.
now_ms() {
  "$PYTHON_BIN" -c 'import time; print(int(time.time() * 1000))' 2>/dev/null \
    || echo $(( $(date +%s) * 1000 ))
}

# 1204 -> 1,204. bash's built-in printf has no thousands flag, so group by hand.
group_digits() {
  printf '%s' "$1" | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'
}

probe_out="$(mktemp -t airgap-probe-out)"
probe_err="$(mktemp -t airgap-probe-err)"
trap 'rm -f "$probe_out" "$probe_err"' EXIT

# The server's own count of prompt tokens, before and after. The difference is
# what this one turn cost, every request the harness made included — which is
# the number no harness reports about itself honestly.
tokens_before=""
if [ "$METRICS" = "1" ]; then
  tokens_before="$(metrics_counters prompt_tokens_total || true)"
fi

# Run it in the background and poll: macOS ships no timeout(1). Input is
# closed, so a harness that would rather have a conversation gives up instead
# of waiting for a person who is not there.
# bash announces a job it had to kill on the SHELL's own stderr ("Terminated:
# 15", with the whole command line), which would land in the middle of the
# report; `2>/dev/null` on `wait` does not catch it, because the notice is not
# that builtin's output. So the shell's own stderr is put aside for exactly as
# long as this job exists, and restored the moment it has been reaped.
exec 3>&2 2>/dev/null

started_ms="$(now_ms)"
"$HARNESS_BIN" ${HARNESS_ARGS[@]+"${HARNESS_ARGS[@]}"} "${HARNESS_ONESHOT[@]}" \
  'Reply with exactly: AIRGAP OK' >"$probe_out" 2>"$probe_err" </dev/null &
probe_pid=$!

# The same bound the harness itself was given: a cold first turn reloads the
# weights before it produces a token, and that is not a new number.
deadline=$(( client_ms / 1000 ))
waited=0
timed_out=0
while kill -0 "$probe_pid" 2>/dev/null; do
  if [ "$waited" -ge "$deadline" ]; then
    timed_out=1
    kill -TERM "$probe_pid" 2>/dev/null || true
    sleep 2
    kill -KILL "$probe_pid" 2>/dev/null || true
    break
  fi
  sleep 1
  waited=$((waited + 1))
done
wait "$probe_pid" || true
exec 2>&3 3>&-
elapsed_ms=$(( $(now_ms) - started_ms ))
took="$(awk -v ms="$elapsed_ms" 'BEGIN { printf "%.1f", ms / 1000 }')"

# The token figure is only honest when both readings worked.
tokens="prompt tokens n/a (METRICS=$METRICS)"
if [ "$METRICS" = "1" ]; then
  tokens="prompt tokens n/a (the server did not answer /metrics.json)"
  tokens_after="$(metrics_counters prompt_tokens_total || true)"
  if [ -n "$tokens_before" ] && [ -n "$tokens_after" ]; then
    tokens="$(group_digits "$(( tokens_after - tokens_before ))") prompt tokens"
  fi
fi

# Match on stdout only, case-sensitive: stderr is where a harness writes its
# own chatter, and a harness that echoes the question back there must not read
# as an answer.
if [ "$timed_out" = "0" ] && grep -q 'AIRGAP OK' "$probe_out"; then
  printf 'probe  %s  AIRGAP OK  %s s  %s\n' "$harness" "$took" "$tokens"
  exit 0
fi

if [ "$timed_out" = "1" ]; then
  printf 'probe  %s  FAIL after %s s — killed at the %ss client limit\n' "$harness" "$took" "$deadline"
else
  printf 'probe  %s  FAIL after %s s\n' "$harness" "$took"
fi
cat "$probe_out" "$probe_err" | tail -n 20 | sed 's/^/  /'
exit 1
