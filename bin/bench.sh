#!/usr/bin/env bash
# bin/bench.sh — measure what the model's fast-answer head actually buys you.
#
# It loads the model twice, without the server, and asks the same question both
# times with the randomness turned off:
#   1. with the two speed features on   — the normal setting
#   2. with both switched off           — one token at a time
#
# It reports the tokens-per-second mlx-serve itself measured for each run AND a
# short fingerprint of each answer. The two fingerprints should MATCH. Guessing
# ahead changes how fast tokens come out, never which tokens come out. A
# mismatch means something is wrong.
#
# THIS LOADS THE MODEL TWICE. Stop the server first.

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
  fixed. First with its speed features on, then with them off. Prints the
  tokens per second mlx-serve reports for each — the writing speed only, so
  loading the model off the disk does not blur it — and a short fingerprint of
  each answer so you can see they are the same text.

WHAT IT COSTS
  Memory: about 19.1 GB, twice, one after the other. This script loads the
          model itself, so the SAME free-memory rule that ./bin/serve.sh
          enforces applies here: it refuses to run below MIN_FREE_GB, and it
          names the apps to close. Close your browser and Docker Desktop first.
          To see how much is free right now, run from the repo root:
              bash -c 'source bin/env.sh && echo "$(available_gb) GB available"'
  Time: a couple of minutes for the 27B. Most of that is reading the model off
        the disk, twice.
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
  and a tokens-per-second figure for each run, with the ratio between them.

  A NOTE ABOUT THE NUMBERS: they are what mlx-serve prints after a run, and
  they describe your Mac, this model, this prompt and this token count. The
  publisher's figures for the 27B are 6.81 seconds against 10.15 seconds with
  the same answer both times. Those are the model publisher's figures. They
  have NOT been reproduced on the test machine, and no tokens-per-second figure
  for the 27B has been recorded in this repository.

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
# The port probe stays because its message is the specific one: it names the
# port and it names serve.sh. The lock below catches everything the port cannot
# — another bench.sh (which passes no --port at all, so it is invisible here),
# and a server someone started on a different port.
if server_up || lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "error: serve.sh is running on port ${PORT} — stop it first (./bin/stop.sh)." >&2
  echo "       bench.sh loads its own ~20 GB copy; two will not fit." >&2
  exit 1
fi

if ! acquire_model_lock "bench.sh"; then
  echo "error: something else on this Mac is already holding the weights." >&2
  echo "       holder: pid $(model_lock_pid || echo '?') — $(model_lock_what)" >&2
  echo "       bench.sh loads its own ~20 GB copy; two will not fit." >&2
  echo "       stop it first (./bin/stop.sh), then run this again." >&2
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

# mlx-serve --prompt prints the answer between two lines of "=" signs, then a
# few lines of its own statistics:
#     Prompt: 18 tokens, 130.792 tokens-per-sec
#     Generation: 6 tokens, 51.120 tokens-per-sec
#     Peak memory: 4.821 GB
# The answer and the statistics are separated here, on purpose: comparing the
# whole output would compare two timings and always report a mismatch, and the
# Generation line is the honest speed figure — decode only, no model loading.
run() {
  label="$1"; shift
  raw="$TMP/$label.raw"
  echo "── $label ─────────────────────────────────"
  if ! mlx-serve --model "$MODEL_DIR" \
                 --prompt "$PROMPT" \
                 --max-tokens "$TOKENS" \
                 --temp 0.0 \
                 --no-vision \
                 "$@" > "$raw" 2>"$TMP/$label.err"; then
    echo "  FAILED — the last lines of the error output were:"
    tail -20 "$TMP/$label.err" || true
    return 1
  fi
  # The answer: everything between the first two "==========" lines.
  awk '/^==========/ { n++; next } n == 1 { print }' "$raw" > "$TMP/$label.txt"
  # The statistics, as printed by mlx-serve.
  gen_line="$(grep -m1 '^Generation:' "$raw" || true)"
  tps="$(printf '%s\n' "$gen_line" | awk '{ for (i = 1; i <= NF; i++) if ($i == "tokens-per-sec") print $(i-1) }')"
  ntok="$(printf '%s\n' "$gen_line" | awk '{ print $2 }')"
  printf '  generated  : %s tokens\n' "${ntok:-?}"
  printf '  speed      : %s tokens/s (mlx-serve\x27s own figure, decode only)\n' "${tps:-not reported}"
  printf '  output sha : %s\n' "$(shasum -a 256 "$TMP/$label.txt" | cut -c1-16)"
  echo "${tps:-0}" > "$TMP/$label.tps"
}

echo "model:  $(basename "$MODEL_DIR") (~${HW_WEIGHTS_GB} GB)"
echo "prompt: $(echo "$PROMPT" | cut -c1-70)..."
echo "tokens: $TOKENS, temp 0.0 (greedy — required for an exact-match comparison)"
echo "This loads the model twice. Expect a wait with no output while it reads the disk."
echo

ok=1
run "spec-on" || ok=0
# Switching both speed features off. serve.sh never passes these two flags; this
# script does, once, only so there is something to compare against.
run "spec-off" --no-mtp --no-pld || ok=0

echo
echo "── result ──────────────────────────────────"
if [ "$ok" != "1" ]; then
  echo "  one of the two runs failed — the figures above are not comparable."
  exit 1
fi

if cmp -s "$TMP/spec-on.txt" "$TMP/spec-off.txt"; then
  echo "  outputs IDENTICAL  <- speculative decoding is exact, as expected"
else
  echo "  outputs DIFFER     <- unexpected at temp 0; investigate before trusting the speeds"
  echo "  (the two answers are in $TMP — kept until this window closes)"
  trap - EXIT
fi

on="$(cat "$TMP/spec-on.tps")"
off="$(cat "$TMP/spec-off.tps")"
awk -v on="$on" -v off="$off" 'BEGIN {
  if (on > 0 && off > 0)
    printf "  speed-up ~ %.2fx  (%s tokens/s with the speed features on, %s off)\n", on / off, on, off
  else
    print "  no speed figure: mlx-serve did not print a Generation line for one of the runs"
}'
echo
echo "This measured YOUR Mac, this model, this prompt and ${TOKENS} tokens. It is not a"
echo "benchmark of anything else. Speed features here means the MTP head (if this"
echo "checkpoint ships one) and prompt-lookup decoding."
