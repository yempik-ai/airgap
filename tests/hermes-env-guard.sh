#!/usr/bin/env bash
# Holds harness/hermes.sh's one guard: Hermes loads $HERMES_HOME/.env OVER the
# process environment, so a CUSTOM_BASE_URL line in that file would beat the
# adapter's export and send every request wherever it says (MEASURED against
# Hermes 0.20.4 with a throwaway HERMES_HOME — see the adapter's header). The
# adapter refuses that case before anything else, and accepts the file when
# the line is absent, commented out, or names the same address.
#
# Reached the way a person reaches it — through bin/run.sh — with PORT=9 (a
# closed port), so "past the guard" shows as the no-server error, and with
# HERMES_HOME pointed at a scratch folder, so nothing near ~/.hermes is read.
# HERMES_BIN=/bin/echo, so run.sh's binary check passes on any machine.
#
# Usage, from the repo root:  bash tests/hermes-env-guard.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0
scratch="$(mktemp -d -t airgap-hermes-env)"
trap 'rm -rf "$scratch"' EXIT

# run <label> <expected exit> <expected regex> <.env contents or "-" for no file>
run() {
  label="$1"; want_code="$2"; want="$3"; dotenv="$4"
  home="$scratch/$RANDOM$RANDOM"; mkdir -p "$home"
  [ "$dotenv" = "-" ] || printf '%s\n' "$dotenv" > "$home/.env"
  set +e
  got="$(env -i HOME="$scratch" PATH="$PATH" PORT=9 HERMES_HOME="$home" HERMES_BIN=/bin/echo \
    bash "$ROOT/bin/run.sh" hermes 2>&1)"
  code=$?
  set -e
  if [ "$code" = "$want_code" ] && [[ "$got" =~ $want ]]; then
    printf 'ok    %-32s exit %s, %s\n' "$label" "$code" "$(printf '%s' "$got" | head -1)"
  else
    printf 'FAIL  %-32s wanted exit %s and /%s/\n      got exit %s: %s\n' \
      "$label" "$want_code" "$want" "$code" "$(printf '%s' "$got" | head -3)"
    failures=$((failures + 1))
  fi
}

# Past the guard, the next thing run.sh does with PORT=9 is refuse for the
# server — so that message is what "accepted" looks like here.
run "no .env at all"          1 '^error: no server at'  "-"
run "unrelated line"          1 '^error: no server at'  "OPENAI_API_KEY=sk-not-real"
run "commented out"           1 '^error: no server at'  "# CUSTOM_BASE_URL=http://elsewhere:1/v1"
run "same address, quoted"    1 '^error: no server at'  'CUSTOM_BASE_URL="http://127.0.0.1:9/v1"'
run "different address"       1 '^error: CUSTOM_BASE_URL is set in .*\.env \(http://elsewhere:1/v1\)' "CUSTOM_BASE_URL=http://elsewhere:1/v1"
run "different, export form"  1 '^error: CUSTOM_BASE_URL is set in' "export CUSTOM_BASE_URL=http://elsewhere:1/v1"
run "refusal names the fix"   1 'fix:   remove that line from .*\.env, or set it to http://127.0.0.1:9/v1' "CUSTOM_BASE_URL=http://elsewhere:1/v1"

# The other guard in the same adapter: HERMES_MAX_TOKENS is a whole number or
# nothing, refused before the server check like every setting typo.
set +e
got="$(env -i HOME="$scratch" PATH="$PATH" PORT=9 HERMES_HOME="$scratch/none" HERMES_BIN=/bin/echo HERMES_MAX_TOKENS=lots \
  bash "$ROOT/bin/run.sh" hermes 2>&1)"; code=$?
set -e
if [ "$code" = 1 ] && [[ "$got" =~ ^error:\ HERMES_MAX_TOKENS=lots\ is\ not\ a\ whole\ number ]]; then
  printf 'ok    %-32s exit %s, %s\n' "HERMES_MAX_TOKENS typo" "$code" "$(printf '%s' "$got" | head -1)"
else
  printf 'FAIL  %-32s got exit %s: %s\n' "HERMES_MAX_TOKENS typo" "$code" "$(printf '%s' "$got" | head -2)"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "hermes-env-guard: the .env override is refused, and only when it would win"
else
  echo "hermes-env-guard: $failures FAILED" >&2
  exit 1
fi
