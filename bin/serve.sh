#!/usr/bin/env bash
# bin/serve.sh — start the model server on this Mac.
#
# THIS IS THE ONLY SCRIPT THAT LOADS THE MODEL. It puts about 19.1 GB into your
# Mac's memory. Read docs/04-memory-safety.md before the first run.
#
# It stays in the foreground and keeps printing. Press Ctrl-C to stop it, or run
# ./bin/stop.sh from another window.
#
# The server answers three different question formats on one port:
#   /v1/messages          the format Claude Code speaks
#   /v1/chat/completions  the format most other tools speak
#   /api/chat             the format Ollama tools speak
# Claude Code needs the first one, and the server speaks it directly. That is
# why nothing has to sit in between translating.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

usage() {
  cat <<'EOF'
serve.sh — start the model server. This is the script that uses the memory.

BEFORE YOU RUN IT
  Close your browser, Docker Desktop, and any virtual machine. On the test
  machine (Apple M3 Max, 36 GB unified memory) the model did NOT fit until
  Docker Desktop and the browser were closed. This is normal.

  To see how much memory is free right now, run from the repo root:
      bash -c 'source bin/env.sh && echo "$(available_gb) GB available"'

WHAT IT DOES
  Checks seven things, then loads the model and waits for questions:
    1. this Mac can run the model at all
    2. weights plus conversation fit under Apple's GPU memory ceiling
    3. the address it will listen on is this Mac and nothing else
    4. EXTRA_ARGS contains no flag this repo refuses to pass
    5. the model folder exists
    6. the weights are real files, not 135-byte placeholders
    7. there is enough free memory (it refuses rather than stall your Mac)

WHAT IT COSTS
  Memory: about 19.1 GB while the 5-bit model is loaded (MEASURED on the test
          machine). It hands that back to macOS after IDLE_EVICT_SECS seconds
          of silence (default 900, so 15 minutes).
  Time:   about a minute for the first load.
  Money:  nothing. Nothing you type leaves your Mac.

IS IT REVERSIBLE
  Yes, completely. Press Ctrl-C, or run ./bin/stop.sh from another window. The
  memory comes straight back. Nothing on your Mac is changed permanently.

USAGE (run from the repo root)
  ./bin/serve.sh                    start with the settings for your Mac
  CTX_SIZE=32768 ./bin/serve.sh     start with a smaller conversation size
  ./bin/serve.sh --help             print this help

SETTINGS
  Every setting is listed in config.env.example with its default. The four that
  matter most are worked out from your Mac's memory by bin/detect-hardware.sh:
  CTX_SIZE, MIN_FREE_GB, MAX_RESIDENT_MEM, PREFIX_CACHE_MEM.
  EXTRA_ARGS is passed to the server exactly as you type it, last.

WHAT IT WILL NEVER DO
  It never passes --no-mtp or --no-pld: those two speed features are the point.
  It never passes --skip-mem-preflight: that check is what turns a stalled Mac
  into a message you can read.
  It never passes --lan-share or --lan-discover: this model stays on this Mac.

WHAT YOU SHOULD SEE
  Six lines starting with "memory", then the server's own startup output, then
  a line telling you it is listening. Leave the window open.

IF IT REFUSES TO START
  Read the message. It names the processes to close, in order of how much they
  would free. See docs/06-troubleshooting.md#not-enough-memory

READ NEXT
  docs/05-run-it.md
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

# --- Guard 0: can this Mac run it at all? ------------------------------------
# Stop an 8 GB Mac here rather than after a 20 GB download and a stalled load.
if [ "${HW_VERDICT:-}" = "impossible" ]; then
  echo "REFUSING TO START — this Mac cannot run this model." >&2
  echo "  reason : ${HW_REASON:-unknown}" >&2
  if [ -n "${HW_ALT_MODEL:-}" ]; then
    echo "  instead: ${HW_ALT_MODEL}" >&2
  fi
  echo >&2
  echo "Nothing is broken and you have done nothing wrong. Read docs/01-requirements.md." >&2
  exit 1
fi

# --- Guard 0b: do the weights fit under Apple's GPU memory ceiling? ----------
# GPU-wired memory cannot be swapped out. If the weights plus the conversation
# do not fit under the ceiling Apple picks for this Mac, loading them is the one
# thing in this stack that can leave the Mac unresponsive until you hold the
# power button. That is a refusal, not a warning.
if [ "${HW_WIRED_OK:-yes}" = "no" ]; then
  echo "REFUSING TO START — the weights do not fit under this Mac's GPU memory ceiling." >&2
  echo "  weights + conversation : ${HW_WEIGHTS_GB} + ${HW_KV_GB} GB" >&2
  echo "  GPU wired ceiling      : ${HW_WIRED_AUTO_GB} GB (the value Apple picks for ${HW_RAM_GB} GB of memory)" >&2
  echo >&2
  echo "Memory reserved for the GPU cannot be swapped out, so loading this would" >&2
  echo "make this Mac stall until you force a restart." >&2
  echo >&2
  echo "Raising iogpu.wired_limit_mb would silence this. Do not. That is the one" >&2
  echo "change in this whole setup that can hard-hang a Mac, and it is most" >&2
  echo "tempting on the Macs with the least room for it." >&2
  if [ -n "${HW_ALT_MODEL:-}" ]; then
    echo >&2
    echo "  instead: ${HW_ALT_MODEL}" >&2
  fi
  echo >&2
  echo "Read docs/04-memory-safety.md and docs/01-requirements.md#ram-tiers." >&2
  exit 1
fi

# --- Guard 0c: is the server about to listen beyond this Mac? ----------------
# This checkpoint has had its refusal behavior removed and the server has no
# password unless API_KEY is set. mlx-serve's own default address is 0.0.0.0,
# which means every network this Mac is on. This repo overrides that to
# 127.0.0.1, and the override is enforced here rather than merely documented.
# There is no flag to switch this off.
case "$HOST" in
  127.0.0.1|::1|localhost) : ;;
  *)
    echo "REFUSING TO START — HOST is '$HOST', not 127.0.0.1." >&2
    echo >&2
    echo "127.0.0.1 means 'this Mac only'. Anything else offers this model to" >&2
    echo "every device on your network. This model has had its refusal behavior" >&2
    echo "removed by its publisher, and the server has no password unless you" >&2
    echo "set API_KEY, so that is not something to do by accident." >&2
    echo >&2
    echo "Remove the HOST line from config.env, or run:  HOST=127.0.0.1 ./bin/serve.sh" >&2
    exit 1
    ;;
esac

# --- Guard 0d: is EXTRA_ARGS trying to undo one of the guards? --------------
# EXTRA_ARGS is appended last and can therefore override anything above it.
# Five flags are refused outright, because the help text above promises this
# script never passes them and a promise the code does not keep is worthless.
for _flag in $EXTRA_ARGS; do
  case "$_flag" in
    --host|--host=*|--lan-share|--lan-discover|--skip-mem-preflight|--no-mtp|--no-pld)
      echo "REFUSING TO START — EXTRA_ARGS contains '$_flag'." >&2
      echo >&2
      case "$_flag" in
        --host*)
          echo "--host would move the server off 127.0.0.1. See the note above." >&2 ;;
        --lan-share|--lan-discover)
          echo "Those two offer the model to your network. This model stays on this Mac." >&2 ;;
        --skip-mem-preflight)
          echo "That check is what turns a stalled Mac into a message you can read." >&2 ;;
        --no-mtp|--no-pld)
          echo "Those two switch off the speed features this whole setup exists for." >&2
          echo "./bin/bench.sh passes them once, deliberately, to measure the difference." >&2 ;;
      esac
      echo >&2
      echo "Remove it from EXTRA_ARGS in config.env, then run this command again." >&2
      exit 1
      ;;
  esac
done
unset _flag

# --- Guard 1: is the model there? --------------------------------------------
if [ ! -f "$MODEL_DIR/config.json" ]; then
  echo "error: no model at $MODEL_DIR" >&2
  echo "       run: ./bin/download-model.sh" >&2
  exit 1
fi

# --- Guard 2: are the weights real files? ------------------------------------
# git-lfs placeholder files are about 135 bytes of text. Ordinary git leaves
# them behind and reports success. A "weights" file under 1 MB is one of them.
while IFS= read -r shard; do
  [ -n "$shard" ] || continue
  if [ "$(stat -f%z "$shard" 2>/dev/null || echo 0)" -lt 1000000 ]; then
    echo "error: $(basename "$shard") is still a git-lfs pointer, not weights." >&2
    echo "       run: cd '$MODEL_DIR' && git lfs pull" >&2
    exit 1
  fi
done < <(find "$MODEL_DIR" -name '*.safetensors' 2>/dev/null)

# --- Guard 3: is there enough free memory? -----------------------------------
# Loading about 19 GB into a Mac that is already tight is how you get a machine
# that stalls, spins its fans, and stops responding to clicks. Refuse instead,
# and say exactly what to close.
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
    echo "Override with MIN_FREE_GB=0 if you know what you are doing." >&2
    exit 1
  fi
  echo "memory   ${avail} GB available (need ${MIN_FREE_GB} GB) — ok"
fi

# --- Guard 4: has Apple's GPU memory ceiling been raised? --------------------
# This is a warning, not a refusal. GPU-wired memory cannot be swapped out, so
# raising this ceiling is the one change in this whole stack that can leave a
# Mac unresponsive until you hold the power button. Apple's automatic value is
# the safe choice, and the setting returns to it when you restart.
#
# The dangerous threshold is 80% of THIS Mac's memory, not a fixed number. A
# fixed number is wrong in both directions: 14336 MB on a 16 GB Mac is the
# classic freeze recipe and would slip under a 28672 constant, while 30720 MB on
# a 128 GB Mac is entirely safe and would trip it.
wired="$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)"
danger="$(hw_wired_danger_mb)"
if [ "$wired" != "0" ]; then
  if [ "$wired" -gt "$danger" ] 2>/dev/null; then
    echo "warning  iogpu.wired_limit_mb=${wired} — that is over 80% of this Mac's ${HW_RAM_GB} GB." >&2
    echo "         Memory reserved this way cannot be swapped out, so this lets the model" >&2
    echo "         squeeze macOS itself, which is how a Mac stops responding to clicks." >&2
  else
    echo "warning  iogpu.wired_limit_mb=${wired} — Apple's GPU memory ceiling was set by hand." >&2
    echo "         This setup does not need it changed, and Apple's own value is safer." >&2
  fi
  echo "         To put it back:" >&2
  echo "         sudo sysctl iogpu.wired_limit_mb=0    (it also resets when you restart)" >&2
fi

# --- Build the command -------------------------------------------------------
args=(
  --model "$MODEL_DIR"
  --serve
  --host "$HOST"
  --port "$PORT"
  --ctx-size "$CTX_SIZE"
  --kv-quant "$KV_QUANT"
  --prefix-cache-mem "$PREFIX_CACHE_MEM"
  --prefix-cache-disk "$PREFIX_CACHE_DISK"
  --max-resident-models "$MAX_RESIDENT_MODELS"
  --max-resident-mem "$MAX_RESIDENT_MEM"
  --prefill-chunk "$PREFILL_CHUNK"
  --log-level "$LOG_LEVEL"
  --log-file "$LOG_FILE"
)

# These are `if` blocks rather than `[ ... ] && ...` one-liners on purpose:
# under `set -e` a one-liner whose test is false ends the whole script.
if [ "$METRICS" = "1" ]; then
  args+=( --metrics )
fi

# Hand the weights back to macOS after a quiet period. The single most useful
# setting for running this on a Mac you are also working on.
if [ "$IDLE_EVICT_SECS" != "0" ]; then
  args+=( --idle-evict-secs "$IDLE_EVICT_SECS" )
fi

# The image-reading part costs memory and Claude Code sends text.
if [ "$NO_VISION" = "1" ]; then
  args+=( --no-vision )
fi

# A password for the server. Empty is correct while HOST is 127.0.0.1.
#
# HONEST LIMIT: a key given this way is visible to every other account on this
# Mac, because anything on a command line shows up in `ps`. It is a second lock
# on a door that is already inside your house, not a secret.
if [ -n "$API_KEY" ]; then
  args+=( --api-key "$API_KEY" )
fi

# Two speed features are ON by default in the server and we deliberately leave
# them on. The model's own extra head guesses several next tokens at once; the
# other feature notices when the model is repeating text you already sent, which
# happens constantly while editing files. The server picks per question.
# Passing --no-mtp or --no-pld here would remove the reason this repo exists.

# EXTRA_ARGS last, so it can override anything above. Split on spaces on
# purpose: it is a place to type flags, not a place to pass file names.
if [ -n "$EXTRA_ARGS" ]; then
  # shellcheck disable=SC2206
  args+=( $EXTRA_ARGS )
fi

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

echo "model    $MODEL_DIR"
echo "endpoint $BASE_URL   (Anthropic: $BASE_URL/v1/messages)"
echo "context  $CTX_SIZE tokens, kv-quant $KV_QUANT"
echo "budget   weights<=$MAX_RESIDENT_MEM, prefix $PREFIX_CACHE_MEM, idle-evict ${IDLE_EVICT_SECS}s"
echo "log      $(echo "$LOG_FILE" | sed "s|^$HOME|~|")"
echo
echo "Loading about ${HW_WEIGHTS_GB} GB. The first load takes about a minute."
echo "Leave this window open. Press Ctrl-C to stop, or run ./bin/stop.sh elsewhere."
echo "Next: open another window and run ./bin/claude-local.sh"
echo

exec mlx-serve "${args[@]}"
