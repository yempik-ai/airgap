#!/usr/bin/env bash
# bin/serve.sh — start the model server on this Mac.
#
# THIS IS THE ONLY SCRIPT THAT LOADS THE MODEL. It puts the weights — about
# 19.1 GB for the default 5-bit 27B — into your Mac's memory. Read
# docs/04-memory-safety.md before the first run.
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
  Checks eleven things, then loads the model and waits for questions:
     1. this Mac is Apple Silicon (MLX runs nowhere else)
     2. mlx-serve is installed, and new enough for the flags used here
     3. the conversation size fits what the model itself was built for
     4. weights plus conversation fit under Apple's GPU memory ceiling
     5. the address it will listen on is this Mac and nothing else
     6. EXTRA_ARGS contains no flag this repo refuses to pass
     7. the model folder exists
     8. every shard is a real file, not a 135-byte placeholder
     9. there is enough free disk for the cache the server is told to write
    10. nothing else on this Mac is already holding the weights
    11. there is enough free memory (it refuses rather than stall your Mac)

WHAT IT COSTS
  Memory: the size of the selected model's weights while it is loaded — about
          19.1 GB for the 5-bit 27B, 4.7 GB for the 9B. The 19.1 GB is the
          MEASURED size of the weight files; resident memory has not itself
          been observed, because the 27B has not been loaded on the test
          machine. It hands that back to macOS after IDLE_EVICT_SECS seconds
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
  A "memory" line, six lines describing the model, endpoint, context, budget,
  timeout and log, then the server's own startup output, then a line telling
  you it is listening. Leave the window open.

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

# --- Guard 0: is this an Apple Silicon Mac? ----------------------------------
# MLX runs nowhere else. Stop here rather than at a confusing load error.
if [ "${HW_APPLE_SILICON:-no}" != "yes" ]; then
  echo "REFUSING TO START — this is not an Apple Silicon Mac." >&2
  echo "  reason : ${HW_REASON:-unknown}" >&2
  echo >&2
  echo "Nothing is broken and you have done nothing wrong. Read docs/01-requirements.md." >&2
  exit 1
fi

# --- Guard 0a: is mlx-serve installed, and new enough? -----------------------
# Every flag below was verified against MLX_SERVE_MIN (bin/env.sh), and nothing
# older has been run here. A build that does not know one of them answers with
# an argparse error AFTER every other guard in this file has passed, a minute
# into a load — the exact shape of failure this script exists to pre-empt. A
# version that cannot be read is not treated as too old: it is a shape this
# repo does not know, and doctor's row says so.
if ! command -v mlx-serve >/dev/null 2>&1; then
  echo "REFUSING TO START — mlx-serve is not installed." >&2
  echo >&2
  echo "It is the server that loads the weights; nothing here works without it." >&2
  echo >&2
  echo "  install it: ./bin/setup.sh" >&2
  echo >&2
  echo "Read docs/02-install.md#mlx-serve." >&2
  exit 1
fi
_have="$(mlx_serve_version)"
if [ -n "$_have" ] && version_lt "$_have" "$MLX_SERVE_MIN"; then
  echo "REFUSING TO START — mlx-serve ${_have} is older than the ${MLX_SERVE_MIN} this repo needs." >&2
  echo "  installed : ${_have}" >&2
  echo "  needed    : ${MLX_SERVE_MIN} or newer" >&2
  echo >&2
  echo "The flags this script passes — --kv-quant turbo4, --prefix-cache-disk," >&2
  echo "--idle-evict-secs — were verified against ${MLX_SERVE_MIN}, and nothing older has" >&2
  echo "been run here. A build that does not know one of them says so a minute" >&2
  echo "from now, after every other check here has passed." >&2
  echo >&2
  echo "  update it: brew update && brew upgrade mlx-serve" >&2
  echo >&2
  echo "Read docs/02-install.md#mlx-serve." >&2
  exit 1
fi
unset _have

# --- Guard 0b: does the conversation size fit what the model was built for? --
# CTX_SIZE is not free-form: every model states its own maximum in config.json,
# and asking for more inflates MIN_FREE_GB, can trip the GPU-ceiling guard
# below for the wrong reason, and otherwise fails one request at a time once
# the server is up. Refuse here, where the number can still be changed.
#
# This runs BEFORE the ceiling guard on purpose — a wrong reason is worse than
# no reason. It stays quiet when the model is not downloaded yet or python3 is
# missing: Guard 1 refuses the first case, and doctor's "context" row is the
# advisory copy of this check for the second.
if [ -f "$MODEL_DIR/config.json" ]; then
  _max="$(model_max_ctx "$MODEL_DIR")"
  if [ -n "$_max" ] && [ "$CTX_SIZE" -gt "$_max" ] 2>/dev/null; then
    echo "REFUSING TO START — CTX_SIZE is larger than this model's own maximum." >&2
    echo "  CTX_SIZE      : ${CTX_SIZE} tokens" >&2
    echo "  model maximum : ${_max} tokens ($(basename "$MODEL_DIR")/config.json)" >&2
    echo >&2
    echo "The server would size its conversation memory for a window the model" >&2
    echo "cannot use, so this Mac would be asked for memory nothing will ever" >&2
    echo "hold, and long turns would fail one request at a time." >&2
    echo >&2
    echo "  use the model's own maximum : CTX_SIZE=${_max} ./bin/serve.sh" >&2
    echo "  or set CTX_SIZE in config.env to that number or less." >&2
    echo >&2
    echo "Read docs/07-tuning.md#2-the-one-setting-most-people-come-here-for-context-size." >&2
    exit 1
  fi
  unset _max
fi

# --- Guard 0c: do the weights fit under Apple's GPU memory ceiling? ----------
# GPU-wired memory cannot be swapped out. If the weights plus the conversation
# do not fit under the ceiling Apple picks for this Mac, loading them is the one
# thing in this stack that can leave the Mac unresponsive until you hold the
# power button. That is a refusal, not a warning.
if [ "${HW_WIRED_OK:-yes}" = "no" ]; then
  echo "REFUSING TO START — the weights do not fit under this Mac's GPU memory ceiling." >&2
  echo "  weights + conversation : ${HW_WEIGHTS_GB} + ${HW_KV_GB} GB" >&2
  echo "  GPU wired ceiling      : ${HW_WIRED_AUTO_GB} GB (arithmetic — the rule Apple applies to ${HW_RAM_GB} GB of memory)" >&2
  echo >&2
  echo "Memory reserved for the GPU cannot be swapped out, so loading this would" >&2
  echo "make this Mac stall until you force a restart." >&2
  echo >&2
  echo "Raising iogpu.wired_limit_mb would silence this. Do not. That is the one" >&2
  echo "change in this whole setup that can hard-hang a Mac, and it is most" >&2
  echo "tempting on the Macs with the least room for it." >&2
  echo >&2
  echo "  instead: a smaller build. ./bin/models.sh list marks the ones that fit," >&2
  echo "           and ./bin/models.sh use <key> selects one." >&2
  if [ -n "${HW_ALT_MODEL:-}" ]; then
    echo "           ${HW_ALT_MODEL}" >&2
  fi
  echo >&2
  echo "Read docs/04-memory-safety.md and docs/01-requirements.md#ram-tiers." >&2
  exit 1
fi

# --- Guard 0d: is the server about to listen beyond this Mac? ----------------
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

# --- Guard 0e: is EXTRA_ARGS trying to undo one of the guards? --------------
# EXTRA_ARGS is appended last and can therefore override anything above it.
# Six flags are refused outright, because the help text above promises this
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

# --- Guard 2: is every shard a real file? ------------------------------------
# git-lfs placeholder files are about 135 bytes of text. Ordinary git leaves
# them behind and reports success. A "weights" file under 1 MB is one of them,
# and a transfer that stopped between files leaves no file at all — which the
# checkpoint's own index is the only record of. model_state (bin/env.sh) asks
# both questions over every shard; the same answer is what start.sh, models.sh
# and doctor report, so an interrupted download cannot be "already here" in one
# script and missing in the next.
if [ "$(model_state "$MODEL_DIR")" = "partial" ]; then
  pointer="$(model_pointer_shard "$MODEL_DIR" || true)"
  missing="$(model_missing_shards "$MODEL_DIR" | tr '\n' ' ')"
  echo "error: the model at $MODEL_DIR is not completely downloaded." >&2
  if [ -n "$pointer" ]; then
    echo "       ${pointer% *} is still a git-lfs pointer (${pointer##* } bytes), not weights." >&2
  fi
  if [ -n "${missing// /}" ]; then
    echo "       missing shards: ${missing% }" >&2
  fi
  echo "       run: ./bin/download-model.sh      (it resumes where it stopped)" >&2
  echo "       or:  cd '$MODEL_DIR' && git lfs pull" >&2
  exit 1
fi

# --- Guard 3: is there enough free disk for the cache the server writes? -----
# PREFIX_CACHE_DISK tells the server it may keep up to that much of the prefix
# cache on the SSD, under ~/.mlx-serve/kv-cache. Nothing used to check that the
# disk could hold it: 6 GB free passed every guard and then a server was told
# to write 10 GB (AUDIT.md A2). The requirement comes from hw_disk_need_gb, the
# same function MIN_DISK_GB comes from, and it is measured on the volume the
# cache really goes to, which is $HOME and not always this checkout's volume.
cache_gb="$(hw_size_gb "$PREFIX_CACHE_DISK")"
need_disk="$(hw_disk_need_gb serve "$HW_WEIGHTS_GB" "$cache_gb")"
free_home="$(free_disk_gb "$HOME")"
if awk -v d="$free_home" -v m="$need_disk" 'BEGIN { exit !(d < m) }'; then
  echo "REFUSING TO START — not enough free disk for the prefix cache." >&2
  echo "  available : ${free_home} GB on the volume holding ~/.mlx-serve" >&2
  echo "  required  : ${need_disk} GB (PREFIX_CACHE_DISK ${PREFIX_CACHE_DISK} + ${HW_DISK_SPARE_GB} GB spare for macOS)" >&2
  echo >&2
  echo "The server would be told it may write ${cache_gb} GB of cache onto a disk that" >&2
  echo "cannot hold it. A Mac driven to zero free disk fails in ways a refusal" >&2
  echo "here does not." >&2
  echo >&2
  echo "  smaller cache : PREFIX_CACHE_DISK=2GB ./bin/serve.sh" >&2
  echo "  no disk cache : PREFIX_CACHE_DISK=0 ./bin/serve.sh   (the memory tier still works)" >&2
  echo "  or free some disk and run this again." >&2
  echo >&2
  echo "Read docs/06-troubleshooting.md#disk-space." >&2
  exit 1
fi

# --- Guard 4: is something else already holding the weights? -----------------
# This comes BEFORE the memory guard on purpose. The memory guard is a snapshot,
# and a snapshot is blind to a second server that is about to load but has not
# allocated anything yet — and blinder still after the first server has
# idle-evicted its weights, which by default it does after 15 minutes, because
# then the memory really is free right up until it is not.
#
# The port cannot cover this: mlx-serve binds its socket before it loads, so a
# second server on another port passes every other check in this file.
if ! acquire_model_lock "serve.sh, port $PORT"; then
  echo "REFUSING TO START — something else on this Mac is already holding the weights." >&2
  echo "  holder : pid $(model_lock_pid || echo '?') — $(model_lock_what)" >&2
  echo "  lock   : $LOCK_DIR" >&2
  echo >&2
  echo "Loading a second copy would put another ~${HW_WEIGHTS_GB} GB on top of the one" >&2
  echo "already in memory. That is the stalled Mac every other check here exists" >&2
  echo "to prevent, and it is reached by simply forgetting a window is open." >&2
  echo >&2
  echo "  stop the other one : ./bin/stop.sh" >&2
  echo "  see what it is     : ps -p \$(cat '$LOCK_DIR/pid')" >&2
  echo >&2
  echo "If you are certain nothing is running, ./bin/doctor.sh reports a lock left" >&2
  echo "behind by a crash and ./bin/stop.sh clears it." >&2
  exit 1
fi

# --- Guard 5: is there enough free memory? -----------------------------------
# Loading the weights into a Mac that is already tight is how you get a machine
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

# --- Guard 6: has Apple's GPU memory ceiling been raised? --------------------
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
# LOAD_SHAPE_ARGS below is split on spaces on purpose (see env.sh); the
# directive has to sit here, ahead of the array, for shellcheck to honour it.
# shellcheck disable=SC2206
args=(
  --model "$MODEL_DIR"
  --serve
  --host "$HOST"
  --port "$PORT"
  # Context size, KV format, prefill chunk (only when PREFILL_CHUNK pins it)
  # and the vision switch come from one list in env.sh that bench.sh passes
  # too, so the peak it measures is reached under these same settings. Split on
  # spaces on purpose; see env.sh.
  $LOAD_SHAPE_ARGS
  --prefix-cache-mem "$PREFIX_CACHE_MEM"
  --prefix-cache-disk "$PREFIX_CACHE_DISK"
  --max-resident-models "$MAX_RESIDENT_MODELS"
  --max-resident-mem "$MAX_RESIDENT_MEM"
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

# How long the server waits on a question producing nothing before it gives up.
# Passed explicitly even though 300 is also the server's own default, so that
# the number has one name, appears in the banner, and can be raised by someone
# whose first cold turn on a big context legitimately needs longer.
if [ "$SERVE_TIMEOUT" != "0" ]; then
  args+=( --timeout "$SERVE_TIMEOUT" )
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
if [ "$SERVE_TIMEOUT" = "0" ]; then
  echo "timeout  none — a stalled question is never given up on"
else
  echo "timeout  ${SERVE_TIMEOUT}s without a token before a question is given up on"
fi
echo "log      $(echo "$LOG_FILE" | sed "s|^$HOME|~|")"
echo
echo "Loading about ${HW_WEIGHTS_GB} GB of weights. The first load can take a minute."
echo "Leave this window open. Press Ctrl-C to stop, or run ./bin/stop.sh elsewhere."
echo "Next: open another window and run ./bin/claude-local.sh"
echo

exec mlx-serve "${args[@]}"
