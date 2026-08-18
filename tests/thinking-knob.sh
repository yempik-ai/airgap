#!/usr/bin/env bash
# Checks the MAX_THINKING_TOKENS guard in bin/claude-local.sh (AUDIT.md E4):
# a value that is not a whole number is refused, with the fix named, before
# anything else happens; a whole number or an unset value gets past the guard.
# "Past the guard" is observed as the script's next check — the server check —
# failing, so PORT points at a closed port and no server is needed.
#
# Usage, from the repo root:  bash tests/thinking-knob.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

# knob <label> <expected stderr regex> -- <env assignments…>
knob() {
  label="$1"; want="$2"; shift 3
  # PORT=9 (discard, closed on macOS) so the server check fails at once.
  # A fresh environment per case; a config.env in the checkout still applies,
  # as it would for the script, but PORT and MAX_THINKING_TOKENS beat it.
  got="$(env -i HOME="$HOME" PATH="$PATH" PORT=9 "$@" bash "$ROOT/bin/claude-local.sh" 2>&1 >/dev/null || true)"
  if [[ "$got" =~ $want ]]; then
    printf 'ok    %-22s %s\n' "$label" "$(printf '%s' "$got" | head -1)"
  else
    printf 'FAIL  %-22s expected /%s/\n      got: %s\n' "$label" "$want" "$got"
    failures=$((failures + 1))
  fi
}

# CLAUDE_BIN=/bin/echo: bin/run.sh now checks for the harness binary before
# the server, so these three cases (which mean to observe the server check)
# need a binary that exists on every machine, CI included.
knob "unset"       '^error: no server at'                                       -- CLAUDE_BIN=/bin/echo
knob "0 (off)"     '^error: no server at'                                       -- CLAUDE_BIN=/bin/echo MAX_THINKING_TOKENS=0
knob "1024"        '^error: no server at'                                       -- CLAUDE_BIN=/bin/echo MAX_THINKING_TOKENS=1024
knob "off (typo)"  '^error: MAX_THINKING_TOKENS=off is not a whole number.*fix:' -- MAX_THINKING_TOKENS=off
knob "-1"          '^error: MAX_THINKING_TOKENS=-1 is not a whole number.*fix:'  -- MAX_THINKING_TOKENS=-1
knob "1.5"         '^error: MAX_THINKING_TOKENS=1.5 is not a whole number.*fix:' -- MAX_THINKING_TOKENS=1.5

if [ "$failures" -eq 0 ]; then
  echo "thinking-knob: guard holds"
else
  echo "thinking-knob: $failures FAILED" >&2
  exit 1
fi
