#!/usr/bin/env bash
# bin/bench.sh — measure what the model's fast-answer head actually buys you,
# and keep the two other numbers mlx-serve prints while it is at it.
#
# It loads the model twice, without the server, and asks the same question both
# times with the randomness turned off:
#   1. with the two speed features on   — the normal setting
#   2. with both switched off           — one token at a time
#
# For each run it reports the three figures mlx-serve itself prints — the
# prompt-reading (prefill) speed, the writing (decode) speed and the peak
# memory — AND a short fingerprint of each answer. The two fingerprints should
# MATCH. Guessing ahead changes how fast tokens come out, never which tokens
# come out. A mismatch means something is wrong.
#
# The peak is measured under the same context size, KV format and vision
# switch that serve.sh starts the server with (LOAD_SHAPE_ARGS in env.sh) —
# and the same prefill chunk when PREFILL_CHUNK pins one; unpinned, this
# one-shot load reads at the server's ceiling while the server sizes the chunk
# down for itself, and the output says so. Either way it is a number the memory
# guard can be checked against, and the result section puts the two side by
# side.
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
  fixed. First with its speed features on, then with them off. For each run it
  prints the three figures mlx-serve reports itself — how fast it read the
  prompt (prefill), how fast it wrote the answer (decode), and the most memory
  it used — and a short fingerprint of each answer so you can see they are the
  same text. Loading the model off the disk is in none of the three figures.

  It loads the model with the same context size, KV format and vision setting
  ./bin/serve.sh uses, so the peak memory it prints is one the memory guard's
  arithmetic can be checked against. The last lines do that. One flag differs
  unless you pin it: the server sizes its own prefill chunk when it starts
  (and prints it in its log); a one-shot load like this one reads at the
  ceiling instead, so its peak is an upper bound on the server's. The output
  names the PREFILL_CHUNK= that reproduces the server's shape.

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
  ./bin/bench.sh                             200 tokens, the built-in question
  TOKENS=400 ./bin/bench.sh                  a longer answer
  PROMPT_FILE=docs/08-how-it-works.md ./bin/bench.sh
                                             a long prompt: the whole file is
                                             the question. This is how to get a
                                             prefill figure worth quoting.
  ROW_FILE=bench/my-mac.tsv ./bin/bench.sh   also append this run as one row of a
                                             tab-separated file (see below)
  ./bin/bench.sh --help                      print this help

SETTINGS
  TOKENS       how many tokens to generate. Default: 200
  ROW_FILE     a .tsv to append this run's row to; written with a header line
               when the file is new. Default: unset (the row is only printed).
  PROMPT       the question to ask. Default: a fixed one about how the model works.
  PROMPT_FILE  a file whose whole contents are the prompt. Overrides PROMPT.
               It must fit in CTX_SIZE. Anything readable will do — a document
               from docs/ is a good stand-in for the ~21,000 tokens Claude Code
               sends on every turn.

WHAT YOU SHOULD SEE AT THE END
  outputs IDENTICAL  <- byte identity, observed on this run
  a decode figure for each run with the ratio between them, the prefill figure
  next to the prompt length it was measured at, the peak memory next to the
  weights + conversation figure the memory guard counts for this load — and
  the same run as ONE ROW: tab-separated, machine, model, settings and figures,
  the form bench/ collects (bench/README.md). A run on a Mac that is not the
  M3 Max 36 GB is the contribution this repository needs most; the row is how
  to send it so it can be diffed and plotted rather than read once.

  A NOTE ABOUT THE NUMBERS: they are what mlx-serve prints after a run, and
  they describe your Mac, this model, this prompt and this token count.
  - PREFILL at the built-in ~30-token prompt is mostly fixed per-call overhead
    and understates the real rate several times over. Measured on the test
    machine with the 9B: 15 tokens gave 115 tokens/s and 4051 tokens gave 448.
    Use PROMPT_FILE= for a figure that means something, and always quote the
    prompt length next to it.
  - PEAK MEMORY is mlx-serve's own accounting of its Metal buffers. It is a
    lower bound on what the process takes: measured on the test machine, the
    whole process was about 0.5 GB above the printed peak. Unpinned, it is
    also read at the largest prefill chunk (measured on the 9B at 16,408
    tokens: 9.52 GB, against 5.63 GB pinned to the 512 the server chose).
  - The publisher's figures for the 27B are 6.81 seconds against 10.15 seconds
    with the same answer both times. Those are the model publisher's figures.
    They have NOT been reproduced on the test machine, and no tokens-per-second
    figure for the 27B has been recorded in this repository.

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

# The same question, and the same answer, as serve.sh: this script loads the
# model too, and a half-downloaded folder is a crash a minute from now rather
# than a message (bin/env.sh, AUDIT.md D2).
case "$(model_state "$MODEL_DIR")" in
  complete) : ;;
  partial)
    echo "error: the model at $MODEL_DIR is not completely downloaded." >&2
    echo "       run: ./bin/download-model.sh      (it resumes where it stopped)" >&2
    exit 1 ;;
  *)
    echo "error: no model at $MODEL_DIR" >&2
    echo "       run: ./bin/download-model.sh" >&2
    exit 1 ;;
esac

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
: "${PROMPT_FILE:=}"
: "${ROW_FILE:=}"

# --- The prompt: a file, when one is named ------------------------------------
# The whole file becomes the prompt. This is the only way to get a prefill
# figure that is not dominated by per-call overhead — see the help text.
if [ -n "$PROMPT_FILE" ]; then
  if [ ! -r "$PROMPT_FILE" ]; then
    echo "error: PROMPT_FILE=$PROMPT_FILE is not a readable file." >&2
    echo "       name a text file, e.g. PROMPT_FILE=docs/08-how-it-works.md ./bin/bench.sh" >&2
    exit 1
  fi
  PROMPT="$(cat "$PROMPT_FILE")"
  if [ -z "$PROMPT" ]; then
    echo "error: PROMPT_FILE=$PROMPT_FILE is empty." >&2
    exit 1
  fi
fi

TMP="$(mktemp -d)"
# `trap ... EXIT` REPLACES the EXIT trap acquire_model_lock installed above,
# so the lock release has to be repeated here or a finished run leaves a stale
# lock behind (found by running it: every completed bench left one).
trap 'rm -rf "$TMP"; release_model_lock' EXIT

# mlx-serve --prompt prints the answer between two lines of "=" signs, then
# three lines of its own statistics, all of which are kept:
#     Prompt: 18 tokens, 130.792 tokens-per-sec      <- prefill
#     Generation: 6 tokens, 51.120 tokens-per-sec    <- decode, the speed figure
#     Peak memory: 4.821 GB                          <- MLX's Metal buffers
# The answer and the statistics are separated here, on purpose: comparing the
# whole output would compare two timings and always report a mismatch. The
# Generation line is the honest speed figure — decode only, no model loading.
#
# LOAD_SHAPE_ARGS is the same context/KV/prefill/vision set serve.sh passes, so
# the peak here is one reached under the guard's own settings. Anything after
# it is this run's own switch (spec-off passes --no-mtp --no-pld).
#
# One flag in that set is honest only when pinned. With PREFILL_CHUNK empty
# (the default), serve.sh lets the server size the prefill chunk itself, and
# in serve mode it does — from the memory free at load, --ctx-size and
# --max-resident-mem, printing `Prefill chunk: N tokens (memory-sized down
# from 8192; ...)` in its log. In this one-shot mode it does not: it reads at
# the 8192-token ceiling and ignores --max-resident-mem (MEASURED on the 9B:
# the same 9.52 GB peak with and without that flag, against 5.63 GB pinned to
# the 512 the server chose one run).
# So an unpinned peak here is an UPPER BOUND on the server's; the load line
# says so and names the pin that reproduces the server's shape.

# stat_tokens <raw> <Prompt|Generation> — the N in "<label>: N tokens, R tokens-per-sec".
# stat_tps    <raw> <Prompt|Generation> — the R. Both print nothing when the line is missing.
stat_tokens() { grep -m1 "^$2:" "$1" | awk '{ print $2 }'; }
stat_tps()    { grep -m1 "^$2:" "$1" | awk '{ for (i = 1; i <= NF; i++) if ($i == "tokens-per-sec") print $(i-1) }'; }

run() {
  label="$1"; shift
  raw="$TMP/$label.raw"
  echo "── $label ─────────────────────────────────"
  # shellcheck disable=SC2086
  if ! mlx-serve --model "$MODEL_DIR" \
                 --prompt "$PROMPT" \
                 --max-tokens "$TOKENS" \
                 --temp 0.0 \
                 $LOAD_SHAPE_ARGS \
                 "$@" > "$raw" 2>"$TMP/$label.err"; then
    echo "  FAILED — the last lines of the error output were:"
    tail -20 "$TMP/$label.err" || true
    return 1
  fi
  # The answer: everything between the first two "==========" lines.
  awk '/^==========/ { n++; next } n == 1 { print }' "$raw" > "$TMP/$label.txt"
  # The statistics, as printed by mlx-serve.
  ptok="$(stat_tokens "$raw" Prompt || true)";     ptps="$(stat_tps "$raw" Prompt || true)"
  ntok="$(stat_tokens "$raw" Generation || true)"; tps="$(stat_tps "$raw" Generation || true)"
  peak="$(grep -m1 '^Peak memory:' "$raw" | awk '{ print $3 }' || true)"
  printf '  prompt      : %s tokens, read at %s tokens/s   (prefill)\n' "${ptok:-?}" "${ptps:-not reported}"
  printf '  generated   : %s tokens, at %s tokens/s        (decode — the speed figure)\n' "${ntok:-?}" "${tps:-not reported}"
  printf '  peak memory : %s GB\n' "${peak:-not reported}"
  printf '  output sha  : %s\n' "$(shasum -a 256 "$TMP/$label.txt" | cut -c1-16)"
  echo "${tps:-0}"  > "$TMP/$label.tps"
  echo "${ptps:-0}" > "$TMP/$label.ptps"
  echo "${ptok:-0}" > "$TMP/$label.ptok"
  echo "${peak:-0}" > "$TMP/$label.peak"
}

echo "model:  $(basename "$MODEL_DIR") (~${HW_WEIGHTS_GB} GB)"
if [ -n "$PROMPT_FILE" ]; then
  echo "prompt: the whole of $PROMPT_FILE ($(wc -c < "$PROMPT_FILE" | tr -d ' ') bytes)"
else
  echo "prompt: $(echo "$PROMPT" | cut -c1-70)..."
fi
echo "tokens: $TOKENS, temp 0.0 (greedy — required for an exact-match comparison)"
echo "load:   $LOAD_SHAPE_ARGS   (the same as serve.sh)"
if [ -z "$PREFILL_CHUNK" ]; then
  # The chunk the server chose in its LAST run, from its own log. Scoped past
  # the last "Logging to" banner: the log spans restarts and has no timestamps.
  # Empty when the server has never run unpinned (a pinned run prints no line).
  srv_chunk="$( { [ -r "$LOG_FILE" ] && awk '
      /^Logging to /   { n = "" }
      /^Prefill chunk: [0-9]+ tokens/ { n = $3 }
      END { print n }' "$LOG_FILE"; } || true )"
  echo "chunk:  not pinned. A one-shot load reads at the server's 8192-token ceiling;"
  echo "        the server itself sizes the chunk down to what is free, so the peak"
  if [ -n "$srv_chunk" ]; then
    echo "        below is an upper bound on its. Its last run chose ${srv_chunk} (from its log);"
    echo "        PREFILL_CHUNK=${srv_chunk} ./bin/bench.sh measures that shape."
  else
    echo "        below is an upper bound on its. Its log has no 'Prefill chunk:' line from"
    echo "        its last run (not started yet, or started pinned): start ./bin/serve.sh"
    echo "        unpinned once, read that line in $LOG_FILE,"
    echo "        then PREFILL_CHUNK=<that number> ./bin/bench.sh measures that shape."
  fi
fi
echo "This loads the model twice. Expect a wait with no output while it reads the disk."
echo "The figures per run are the ones mlx-serve prints itself; the load is not in them."
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

# What this line may claim: identity on THIS run. In exact arithmetic the
# algorithm keeps only guesses the full model would have written itself; a real
# implementation verifies in batches and can drift in floating point, and
# mlx-serve is a closed binary — so identity is observed per run, not
# guaranteed by the repository (AUDIT.md B3).
if cmp -s "$TMP/spec-on.txt" "$TMP/spec-off.txt"; then
  echo "  outputs IDENTICAL  <- byte identity, observed on this run"
  identical=yes
else
  echo "  outputs DIFFER     <- unexpected at temp 0; investigate before trusting the speeds"
  echo "  (the two answers are in $TMP — kept until this window closes)"
  trap 'release_model_lock' EXIT
  identical=no
fi

on="$(cat "$TMP/spec-on.tps")"
off="$(cat "$TMP/spec-off.tps")"
awk -v on="$on" -v off="$off" 'BEGIN {
  if (on > 0 && off > 0)
    printf "  speed-up ~ %.2fx  (%s tokens/s with the speed features on, %s off)\n", on / off, on, off
  else
    print "  no speed figure: mlx-serve did not print a Generation line for one of the runs"
}'

# Prefill, quoted with the prompt length it was measured at — the rate alone is
# not a figure. Taken from the spec-on run: it is the setting serve.sh uses.
ptps="$(cat "$TMP/spec-on.ptps")"
ptok="$(cat "$TMP/spec-on.ptok")"
if [ "$ptps" != "0" ]; then
  echo "  prefill    ${ptps} tokens/s at ${ptok} prompt tokens (speed features on)"
  if [ -z "$PROMPT_FILE" ]; then
    echo "             ^ at a prompt this short that is mostly per-call overhead, several"
    echo "               times under the real rate. PROMPT_FILE=<file> measures a real one."
  fi
else
  echo "  prefill    not reported: mlx-serve did not print a Prompt line"
fi

# Peak memory, next to the arithmetic the memory guard is built on. hw_rebudget
# counts the weights plus a conversation term sized for the FULL context window
# (HW_KV_GB at CTX_SIZE: this model's own per-token figure at this KV_QUANT —
# 16 KiB per token for the 27B at turbo4, 8 for the 9B), plus the prefix
# cache — which a one-shot run never fills, so it is left out here. A run this
# size uses only prompt + answer tokens of that window, so the honest comparison
# is peak minus weights minus the conversation actually used: what is left is
# the working set (prefill activations, the fixed SSM state) that the arithmetic
# does not line-item and that the guard's rounding-up must absorb.
peak_on="$(cat "$TMP/spec-on.peak")"
peak_off="$(cat "$TMP/spec-off.peak")"
ntok="$(stat_tokens "$TMP/spec-on.raw" Generation || true)"
awk -v on="$peak_on" -v off="$peak_off" -v w="$HW_WEIGHTS_GB" -v kv="${HW_KV_GB:-0}" \
    -v ctx="$CTX_SIZE" -v minfree="$MIN_FREE_GB" -v used="$(( ptok + ${ntok:-0} ))" \
    -v chunk="$PREFILL_CHUNK" 'BEGIN {
  peak = (on > off) ? on : off
  if (peak <= 0) { print "  peak       not reported: mlx-serve did not print a Peak memory line"; exit }
  kv_used = (ctx > 0) ? kv * used / ctx : 0
  printf "  peak       %.2f GB, the higher of the two runs — mlx-serve\047s own figure for its\n", peak
  printf "             Metal buffers, a lower bound on the process (about 0.5 GB under it, measured)\n"
  printf "  guard      counts weights ~%s GB + a full %s-token conversation %.2f GB = %.2f GB\n", w, ctx, kv, w + kv
  printf "             for a load like this (arithmetic; MIN_FREE_GB=%s adds the prefix cache,\n", minfree
  printf "             which a one-shot run never fills). This run used %d of those tokens: %.2f GB.\n", used, kv_used
  printf "  gap        %+.2f GB — peak minus weights minus the conversation actually used: the\n", peak - w - kv_used
  printf "             working set the arithmetic does not line-item. It grows with the prompt;\n"
  printf "             a longer PROMPT_FILE= is how to see by how much.\n"
  if (chunk == "")
    printf "             Read at the 8192-token ceiling chunk (see the chunk line above): an\n" \
           "             upper bound on the server, which reads in smaller pieces.\n"
}'
echo
echo "This measured YOUR Mac, this model, this prompt and ${TOKENS} tokens. It is not a"
echo "benchmark of anything else. Speed features here means the MTP head (if this"
echo "checkpoint ships one) and prompt-lookup decoding."

# The same run as one row. Every value above, plus what it was measured on and
# with, tab-separated in a fixed column order, so runs from different Macs can
# be diffed, plotted and used as a baseline (AUDIT.md B4). bench/README.md
# holds the same header and says where a row goes. Nothing here is derived:
# each field is either printed above or read from the machine right now.
row_header='date	commit	chip	gpu_cores	ram_gb	macos	mlx_serve	model	ctx_size	kv_quant	prefill_chunk	prompt	prompt_tokens	gen_tokens	decode_on_tps	decode_off_tps	prefill_on_tps	peak_on_gb	peak_off_gb	identical'
row="$(printf '%s\t' \
  "$(date +%F)" \
  "$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo -)" \
  "${HW_CHIP:--}" "${HW_GPU_CORES:--}" "${HW_RAM_GB:--}" "$(sw_vers -productVersion 2>/dev/null || echo -)" \
  "$(mlx-serve --version 2>/dev/null | awk '/^mlx-serve /{ print $2; exit }')" \
  "$(basename "$MODEL_DIR")" "$CTX_SIZE" "$KV_QUANT" "${PREFILL_CHUNK:-auto}" \
  "$( [ -n "$PROMPT_FILE" ] && basename "$PROMPT_FILE" || echo default )" \
  "$ptok" "${ntok:-0}" "$on" "$off" "$ptps" "$peak_on" "$peak_off" "$identical")"
row="${row%	}"
echo
echo "── row ─────────────────────────────────────"
echo "$row_header"
echo "$row"
if [ -n "$ROW_FILE" ]; then
  [ -s "$ROW_FILE" ] || echo "$row_header" > "$ROW_FILE"
  echo "$row" >> "$ROW_FILE"
  echo "appended to $ROW_FILE — see bench/README.md for where it goes from here"
else
  echo "(ROW_FILE=bench/<chip>-<ram>gb.tsv ./bin/bench.sh appends it to a file — bench/README.md)"
fi
