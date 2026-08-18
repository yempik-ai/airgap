#!/usr/bin/env bash
# Checks how bin/run.sh chooses a harness and what it does before it starts
# one: no name and an unknown name both list the adapters and refuse; a real
# name gets as far as the server check; --help after the name is the adapter's
# help and needs no server.
#
# PORT=9 (discard, closed on macOS) throughout, so "as far as the server
# check" is observable without a server, and nothing here loads a model.
#
# Usage, from the repo root:  bash tests/run-dispatch.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

# Extra settings for the NEXT run() call only, as name=value words. run() clears
# it again, so every other case keeps the same fresh environment. Written the
# ${a[@]+"${a[@]}"} way because bash 3.2, which macOS ships, treats an empty
# array as unset under `set -u`.
RUN_ENV=()

# run <label> <expected exit code> <expected stdout+stderr regex> -- <run.sh arguments…>
run() {
  label="$1"; want_code="$2"; want="$3"; shift 4
  set +e
  got="$(env -i HOME="$HOME" PATH="$PATH" PORT=9 ${RUN_ENV[@]+"${RUN_ENV[@]}"} \
    bash "$ROOT/bin/run.sh" "$@" 2>&1)"
  code=$?
  set -e
  RUN_ENV=()
  if [ "$code" = "$want_code" ] && [[ "$got" =~ $want ]]; then
    printf 'ok    %-24s exit %s, %s\n' "$label" "$code" "$(printf '%s' "$got" | head -1)"
  else
    printf 'FAIL  %-24s wanted exit %s and /%s/\n      got exit %s: %s\n' \
      "$label" "$want_code" "$want" "$code" "$(printf '%s' "$got" | head -5)"
    failures=$((failures + 1))
  fi
}

# The list run.sh prints must name every adapter that is really there, so the
# expectation is derived from harness/ rather than written out here — an
# adapter added tomorrow is covered without editing this test.
for adapter in "$ROOT"/harness/*.sh; do
  [ -f "$adapter" ] || continue
  name="$(basename "$adapter" .sh)"
  run "lists $name"        1 "$name"                    --
  run "unknown lists $name" 1 "$name"                   -- nope
done

run "no name refuses"    1 'harness'                    --
run "unknown name says so" 1 'nope'                     -- nope
# A harness that is not installed is refused by name, and refused BEFORE the
# server check: PORT=9 is closed, so an order the other way round would report
# a missing server instead of the missing app.
RUN_ENV=( CLAUDE_BIN=/nonexistent/claude-bin )
run "missing binary refuses" 1 "^error: '/nonexistent/claude-bin' is not installed" -- claude-code
RUN_ENV=( CLAUDE_BIN=/nonexistent/claude-bin )
run "missing binary names its help" 1 './bin/run.sh claude-code --help' -- claude-code

# CLAUDE_BIN=/bin/echo: exists on every machine, so the binary check (which
# now runs before the server check) passes and this case observes the server
# check instead, as intended.
RUN_ENV=( CLAUDE_BIN=/bin/echo )
run "no server"          1 '^error: no server at'       -- claude-code
run "adapter help"       0 'USAGE'                      -- claude-code --help
run "adapter help names run.sh" 0 './bin/run.sh claude-code' -- claude-code --help
run "adapter help names the shim" 0 './bin/claude-local.sh' -- claude-code --help
run "own help"           0 'run.sh'                     -- --help

if [ "$failures" -eq 0 ]; then
  echo "run-dispatch: dispatch holds"
else
  echo "run-dispatch: $failures FAILED" >&2
  exit 1
fi
