#!/usr/bin/env bash
# Exercises doctor.sh's tool-call reader against captured answers, offline.
#
# doctor.sh's `tool call` and `streamed call` rows read one answer from the
# server and name how it failed — answered in words, raw call passed through as
# text, torn JSON on the stream, no message_stop, and so on. Those branches
# only fire on a broken build, so a green doctor run proves nothing about them.
# This script feeds each shape from tests/fixtures/tool-call/ through the real
# reader (`tool_call_verdict`) and the real row renderer (`tool_call_row`),
# with the server call (`srv_curl`) stubbed to print the fixture, and checks
# the status and the detail each one renders.
#
# The fixtures are live captures from the 9B on mlx-serve 26.8.8 (tool_use,
# declined, truncated, error) and shapes derived from those captures by hand
# (unparsed, wrong_tool, bad_input, unassembled, unterminated, garbled, empty).
# See AGENT.md for the SSE shape they encode.
#
# Usage, from the repo root:  bash tests/tool-call-verdict.sh
# Needs bash and python3, nothing else. Does not start or need a server.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT/bin/doctor.sh"
FIX="$ROOT/tests/fixtures/tool-call"

# The functions under test, lifted out of doctor.sh by their `name() {` … `}`
# ranges. doctor.sh runs its checks at load, so it cannot simply be sourced.
# `row` counts and prints; `tool_probe_body` builds the request the stub
# ignores; the other two are the reader and the renderer.
lifted="$(sed -n \
  -e '/^row() {/,/^}/p' \
  -e '/^tool_probe_body() {/,/^}/p' \
  -e '/^tool_call_verdict() {/,/^}/p' \
  -e '/^tool_call_row() {/,/^}/p' "$DOCTOR")"
for fn in row tool_probe_body tool_call_verdict tool_call_row; do
  if ! grep -q "^${fn}() {" <<< "$lifted"; then
    echo "FAIL  could not lift ${fn}() out of bin/doctor.sh — has it been renamed?" >&2
    exit 1
  fi
done

# What doctor.sh sets before those functions run. The counters are read only
# by the lifted `row`, which shellcheck cannot see.
PROBE_TOOL=get_weather; PROBE_ARG=city; PROBE_TOOL_CAP=1024
MODEL_ID=Qwen3.8-9B-mlx-4Bit; BASE_URL=http://127.0.0.1:0; API_KEY=
# shellcheck disable=SC2034
N_PASS=0
# shellcheck disable=SC2034
N_WARN=0
# shellcheck disable=SC2034
N_FAIL=0
# shellcheck disable=SC2034
N_SKIP=0
export PROBE_TOOL PROBE_ARG PROBE_TOOL_CAP MODEL_ID BASE_URL API_KEY

eval "$lifted"

# The stub: whatever doctor.sh would have asked the server, answer with the
# fixture under test.
FIXTURE=""
srv_curl() { cat "$FIXTURE"; }

failures=0
# check <fixture> <stream:true|false> <expected status> <expected detail substring>
check() {
  FIXTURE="$FIX/$1"
  out="$(tool_call_row "$1" "$2")"
  status="${out%% *}"
  if [ "$status" = "$3" ] && [[ "$out" == *"$4"* ]]; then
    printf 'ok    %-18s %s\n' "$1" "$out"
  else
    printf 'FAIL  %-18s expected %s containing "%s"\n      got: %s\n' "$1" "$3" "$4" "$out"
    failures=$((failures + 1))
  fi
}

check tool_use.json     false PASS 'get_weather({"city":"Paris"}) in one answer, 70 tokens'
check tool_use.sse      true  PASS 'get_weather({"city":"Paris"}) reassembled from the stream, 69 tokens'
check truncated.json    false WARN 'still reasoning at the 1024-token cap'
check declined.json     false FAIL 'answered in words instead of calling the tool'
check unparsed.json     false FAIL 'the call came back as plain text, the server did not parse it'
check wrong_tool.json   false FAIL "called 'get_forecast', not the one tool it was given"
check bad_input.json    false FAIL "called get_weather with {} — the required 'city' is missing"
check unassembled.sse   true  FAIL 'the streamed call did not add up to valid JSON: {"city":"Par'
check unterminated.sse  true  FAIL 'the stream ended without message_stop (tool_use)'
check error.json        false FAIL 'the server refused the request: No valid messages found in request'
check empty.json        false FAIL 'the server did not answer'
check garbled.json      false FAIL 'the answer was not in a shape this script knows'

# The reader alone, for the two shapes the row renders under a shared label:
# `garbled` must come out of both a non-JSON body and a non-JSON SSE line.
v_json="$(tool_call_verdict json < "$FIX/garbled.json")"
v_sse="$(printf 'data: not json at all\n' | tool_call_verdict sse)"
for v in "$v_json" "$v_sse"; do
  if [[ "$v" == garbled* ]]; then
    printf 'ok    %-18s %s\n' "verdict garbled" "$v"
  else
    printf 'FAIL  %-18s expected "garbled …", got: %s\n' "verdict garbled" "$v"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -eq 0 ]; then
  echo "tool-call-verdict: all shapes read as expected"
else
  echo "tool-call-verdict: $failures FAILED" >&2
  exit 1
fi
