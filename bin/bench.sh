#!/usr/bin/env bash
# bin/bench.sh — measure what the model's fast-answer head actually buys you.
#
# It loads the model twice, without the server, and asks the same question both
# times with the randomness turned off:
#   1. with the two speed features on   — the normal setting
#   2. with both switched off           — one token at a time
#
# It reports the time for each AND a short fingerprint of each answer. The two
# fingerprints should MATCH. Guessing ahead changes how fast tokens come out,
# never which tokens come out. A mismatch means something is wrong.
#
# THIS LOADS ABOUT 20 GB, TWICE. Stop the server first.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

usage() {
  cat <<'EOF'
bench.sh — time the model with and without its speed features.

BEFORE YOU RUN IT
  Stop the server: ./bin/stop.sh
  This script loads its own copy of the model, about 20 GB. Two copies do not
  fit on a 36 GB Mac, so it refuses to run while the server holds the port.

WHAT IT DOES
  Asks the model the same question twice, with randomness off so the answer is
  fixed. First with its speed features on, then with them off. Prints how long
  each took, and a short fingerprint of each answer so you can see they are the
  same text.

WHAT IT COSTS
  Memory: about 19.1 GB, twice, one after the other. This script loads the
          model itself, so the SAME free-memory rule that ./bin/serve.sh
          enforces applies here: it refuses to run below MIN_FREE_GB, and it
          names the apps to close. Close your browser and Docker Desktop first.
          To see how much is free right now, run from the repo root:
              bash -c 'source bin/env.sh && echo "$(available_gb) GB available"'
  Time: a couple of minutes. Most of that is reading the model off the disk.
  Nothing leaves your Mac.

IS IT REVERSIBLE
  There is nothing to reverse. It reads the model and prints numbers.

USAGE (run from the repo root)
  ./bin/bench.sh                 200 tokens, the built-in question
  TOKENS=400 ./bin/bench.sh      a longer answer
  ./bin/bench.sh --help          print this help

SETTINGS
  TOKENS   how many tokens to generate. Default: 200
  PROMPT   the question to ask. Default: a fixed one about how the model works.

WHAT YOU SHOULD SEE AT THE END
  outputs IDENTICAL  <- speculative decoding is exact, as expected
  and a speed-up figure.

  A NOTE ABOUT THE NUMBERS: the times include reading 20 GB off the disk both
  times, which makes the difference look smaller than it is. The published
  figures for this checkpoint are 6.81 seconds against 10.15 seconds with the
  same answer both times. Those are the model publisher's figures. They have
  NOT been reproduced on the test machine, and no tokens-per-second figure for
  this model has been measured in this repo.

READ NEXT
  docs/07-tuning.md
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") : ;;
  *) echo "bench.sh: I do not understand '$1'. Try: ./bin/bench.sh --help" >&2; exit 2 ;;
esac

# --- Guard: two copies of the model will not fit -----------------------------
if server_up || lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "error: serve.sh is running on port ${PORT} — stop it first (./bin/stop.sh)." >&2
  echo "       bench.sh loads its own ~20 GB copy; two will not fit." >&2
  exit 1
fi

if [ ! -f "$MODEL_DIR/config.json" ]; then
  echo "error: no model at $MODEL_DIR" >&2
  echo "       run: ./bin/download-model.sh" >&2
  exit 1
fi

# --- Guard: is there enough free memory? -------------------------------------
# This script loads the model, so it needs the same protection serve.sh has.
# Without it, the one script presented as a harmless curiosity is the one that
# stalls the Mac. Same rule, same number, same list of what to close.
if [ "${MIN_FREE_GB}" != "0" ]; then
  avail="$(available_gb)"
  if awk -v a="$avail" -v m="$MIN_FREE_GB" 'BEGIN { exit !(a < m) }'; then
    echo "REFUSING TO START — not enough free memory." >&2
    echo "  available : ${avail} GB" >&2
    echo "  required  : ${MIN_FREE_GB} GB (weights ~${HW_WEIGHTS_GB} GB + conversation + prefix cache)" >&2
    echo >&2
    echo "Free some memory, then retry. Biggest wins, in order:" >&2
    hw_top_memory_users "    " 6 >&2
    echo >&2
    echo "Docker Desktop is a common one — 'docker desktop stop' frees its whole VM." >&2
    exit 1
  fi
  echo "memory   ${avail} GB available (need ${MIN_FREE_GB} GB) — ok"
fi

: "${TOKENS:=200}"
: "${PROMPT:=Explain why speculative decoding produces output identical to standard autoregressive decoding, then describe how a gated linear attention layer differs from full self-attention.}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run() {
  label="$1"; shift
  out="$TMP/$label.txt"
  echo "── $label ─────────────────────────────────"
  start="$(date +%s)"
  if ! mlx-serve --model "$MODEL_DIR" \
                 --prompt "$PROMPT" \
                 --max-tokens "$TOKENS" \
                 --temp 0.0 \
                 --no-vision \
                 "$@" > "$out" 2>"$TMP/$label.err"; then
    echo "  FAILED — the last lines of the error output were:"
    tail -20 "$TMP/$label.err" || true
    return 1
  fi
  end="$(date +%s)"
  secs=$((end - start))
  printf '  wall clock : %ss (includes ~20GB model load)\n' "$secs"
  printf '  output sha : %s\n' "$(shasum -a 256 "$out" | cut -c1-16)"
  echo "$secs" > "$TMP/$label.secs"
}

echo "prompt: $(echo "$PROMPT" | cut -c1-70)..."
echo "tokens: $TOKENS, temp 0.0 (greedy — required for an exact-match comparison)"
echo "This loads about 20 GB twice. Expect a couple of minutes with no output."
echo

ok=1
run "spec-on" || ok=0
# Switching both speed features off. serve.sh never passes these two flags; this
# script does, once, only so there is something to compare against.
run "spec-off" --no-mtp --no-pld || ok=0

echo
echo "── result ──────────────────────────────────"
if [ "$ok" != "1" ]; then
  echo "  one of the two runs failed — the timings above are not comparable."
  exit 1
fi

if cmp -s "$TMP/spec-on.txt" "$TMP/spec-off.txt"; then
  echo "  outputs IDENTICAL  <- speculative decoding is exact, as expected"
else
  echo "  outputs DIFFER     <- unexpected at temp 0; investigate before trusting timings"
fi

on="$(cat "$TMP/spec-on.secs")"
off="$(cat "$TMP/spec-off.secs")"
awk -v on="$on" -v off="$off" 'BEGIN {
  if (on > 0) printf "  speedup ~ %.2fx (load time dilutes this; the decode-only gain is larger)\n", off / on
}'
