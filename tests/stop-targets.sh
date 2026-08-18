#!/usr/bin/env bash
# Checks what ./bin/stop.sh stops and what it refuses to stop (AUDIT.md D4).
#
# stop.sh matched `mlx-serve --port <PORT>` and nothing else, which got both
# hard cases wrong: bench.sh runs mlx-serve with no --port at all, so a bench
# holding ~20 GB could not be stopped by the documented stop button; and a
# foreign program on the port was reported as "nothing running on port 11234"
# purely because pkill found no match.
#
# Both are reproduced here with ordinary processes — a lock holder that has a
# child, and a listener on the port that is not ours — so no model and no
# server are needed. The last two cases are C3's half of the same script:
# the last lines of the log are shown when a server is gone and did not say
# goodbye first, and not when it did.
#
# Usage, from the repo root:  bash tests/stop-targets.sh
# Needs bash and python3. No server, no weights, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

check() {
  label="$1"; want="$2"; got="$3"
  if [[ "$got" == *"$want"* ]]; then
    printf 'ok    %-26s %s\n' "$label" "$want"
  else
    printf 'FAIL  %-26s expected "%s"\n      got: %s\n' "$label" "$want" "$got"
    failures=$((failures + 1))
  fi
}

# A port nothing is listening on. Bound and released, so it is free right now.
free_port() {
  python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); print(p)'
}

run_stop() {
  env -i HOME="$HOME" PATH="$PATH" "$@" bash "$ROOT/bin/stop.sh" 2>&1 || true
}

# --- 1. nothing at all -------------------------------------------------------
out="$(run_stop PORT="$(free_port)" LOCK_DIR="$TMP/no-lock")"
check "nothing running" "nothing is holding the weights" "$out"

# --- 2. a bench.sh-shaped holder: the lock, off-port, with a child -----------
# bench.sh stays a shell and runs mlx-serve as a child, so the lock's pid is
# the script's. Killing only that pid would leave the child holding the weights.
bash -c 'sleep 300 & wait' &
holder=$!
# Off the job table, so bash does not print its own "Terminated" notice over
# this script's output when stop.sh does its job.
disown "$holder" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  child="$(pgrep -P "$holder" 2>/dev/null | head -1 || true)"
  [ -n "$child" ] && break
  sleep 0.2
done
mkdir -p "$TMP/lock"
echo "$holder" > "$TMP/lock/pid"
echo "bench.sh" > "$TMP/lock/what"

out="$(run_stop PORT="$(free_port)" LOCK_DIR="$TMP/lock")"
check "off-port holder named"  "it holds the model lock: bench.sh" "$out"
check "off-port holder stopped" "stopped." "$out"
check "lock given back"         "cleared the model lock" "$out"
if kill -0 "$holder" 2>/dev/null; then
  printf 'FAIL  %-26s the lock holder (pid %s) is still alive\n' "holder killed" "$holder"
  failures=$((failures + 1))
  kill -9 "$holder" 2>/dev/null || true
else
  printf 'ok    %-26s pid %s is gone\n' "holder killed" "$holder"
fi
if [ -n "${child:-}" ] && kill -0 "$child" 2>/dev/null; then
  printf 'FAIL  %-26s the child (pid %s) still holds the weights\n' "child killed" "$child"
  failures=$((failures + 1))
  kill -9 "$child" 2>/dev/null || true
else
  printf 'ok    %-26s pid %s is gone\n' "child killed" "${child:-none}"
fi
if [ -d "$TMP/lock" ]; then
  printf 'FAIL  %-26s %s is still there\n' "lock directory removed" "$TMP/lock"
  failures=$((failures + 1))
else
  printf 'ok    %-26s removed\n' "lock directory removed"
fi

# --- 3. somebody else's program on the port ---------------------------------
python3 -c 'import socket, sys, time
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(1)
print(s.getsockname()[1], flush=True)
time.sleep(60)' > "$TMP/port" &
foreign=$!
disown "$foreign" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$TMP/port" ] && break
  sleep 0.2
done
fport="$(cat "$TMP/port" 2>/dev/null || true)"
if [ -z "$fport" ]; then
  echo "FAIL  could not start the foreign listener" >&2
  failures=$((failures + 1))
else
  out="$(run_stop PORT="$fport" LOCK_DIR="$TMP/no-lock")"
  check "foreign holder reported" "port ${fport} is held by" "$out"
  check "foreign holder left alone" "left alone" "$out"
  if kill -0 "$foreign" 2>/dev/null; then
    printf 'ok    %-26s pid %s survived\n' "foreign holder alive" "$foreign"
  else
    printf 'FAIL  %-26s stop.sh killed a program that is not ours\n' "foreign holder alive"
    failures=$((failures + 1))
  fi
fi
kill "$foreign" 2>/dev/null || true

# --- 4. the log, shown only when the last run did not say goodbye ------------
# The one artifact that explains a server that is gone was printed by nothing
# (AUDIT.md C3). It is shown when there was nothing to stop AND the log does
# not end in the server's own shutdown line — otherwise "not running" is not a
# surprise and eight lines of noise would be the wrong answer.
printf 'Model ready\n\nShutting down gracefully...\n' > "$TMP/clean.log"
out="$(run_stop PORT="$(free_port)" LOCK_DIR="$TMP/no-lock" LOG_FILE="$TMP/clean.log")"
check "clean log summarised" "shut down cleanly" "$out"
if [[ "$out" == *"Model ready"* ]]; then
  printf 'FAIL  %-26s printed the log after an orderly shutdown\n' "clean log quiet"
  failures=$((failures + 1))
else
  printf 'ok    %-26s no tail printed\n' "clean log quiet"
fi

printf 'Model ready\nRuntimeError: [metal::malloc] Attempting to allocate too much memory\n' > "$TMP/crash.log"
out="$(run_stop PORT="$(free_port)" LOCK_DIR="$TMP/no-lock" LOG_FILE="$TMP/crash.log")"
check "crash log announced" "did not shut down cleanly" "$out"
check "crash log shown"     "metal::malloc" "$out"

if [ "$failures" -eq 0 ]; then
  echo "stop-targets: stops what holds the weights, leaves the rest alone"
else
  echo "stop-targets: $failures FAILED" >&2
  exit 1
fi
