#!/usr/bin/env bash
# bin/detect-hardware.sh — figure out what this Mac can actually run.
#
#   ./bin/detect-hardware.sh            human-readable report
#   ./bin/detect-hardware.sh --export   shell assignments, for eval
#   ./bin/detect-hardware.sh --help     this help
#   source bin/detect-hardware.sh       sets the variables, prints nothing
#
# Pure shell + awk + sysctl + vm_stat. No python, no bc, no jq.
# Written for bash 3.2 — the version macOS still ships. That means:
# no associative arrays, no ${var,,}, no mapfile, no <<<.
#
# VERIFIED on Apple M3 Max / 36 GB / macOS 26.5.2 under /bin/bash 3.2.57:
# reproduces bin/env.sh's committed values exactly
# (CTX_SIZE=65536, MIN_FREE_GB=22, MAX_RESIDENT_MEM=21GB, PREFIX_CACHE_MEM=1536MB).

# The model catalog: names, repositories and sizes. The ladder below picks a
# catalog key per memory tier; every size it quotes comes from that one list.
if [ -n "${BASH_VERSION:-}" ]; then
  _hw_self="${BASH_SOURCE[0]}"
else
  _hw_self="$0"
fi
# shellcheck source=bin/catalog.sh
source "$(cd "$(dirname "$_hw_self")" && pwd)/catalog.sh"
unset _hw_self

# ---------------------------------------------------------------------------
# 1. What is this machine?
# ---------------------------------------------------------------------------

hw_total_ram_gb() {
  # HW_FORCE_RAM_GB exists so the tier table can be tested on one machine.
  if [ -n "${HW_FORCE_RAM_GB:-}" ]; then echo "$HW_FORCE_RAM_GB"; return 0; fi
  # hw.memsize is exact on Apple Silicon (8 GB == 8589934592). Round to nearest
  # anyway so a vendor that shaves a few MB does not land us on 35 instead of 36.
  awk -v b="$(sysctl -n hw.memsize 2>/dev/null || echo 0)" \
    'BEGIN { g = b / 1073741824; printf "%d", int(g + 0.5) }'
}

hw_chip() {
  # "Apple M3 Max" on Apple Silicon. Intel Macs report an Intel string here,
  # which is exactly how we detect them (MLX requires Apple Silicon).
  sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown"
}

hw_is_apple_silicon() {
  case "$(hw_chip)" in
    Apple\ M*) return 0 ;;
    *)         return 1 ;;
  esac
}

hw_gpu_cores() {
  # Not present on every macOS version; absence is not an error.
  # The trailing `|| true` matters: awk's `exit` closes the pipe early, which
  # makes ioreg fail, which a caller running under `set -o pipefail` would treat
  # as a real error. It is not one.
  ioreg -rc AGXAccelerator 2>/dev/null \
    | awk -F'= ' '/"gpu-core-count"/ { gsub(/[^0-9]/, "", $2); print $2; exit }' \
    || true
}

# ---------------------------------------------------------------------------
# 2. How much RAM is available RIGHT NOW?
# ---------------------------------------------------------------------------
# Available = the pages macOS can hand to a new allocation without swapping:
#     free + inactive + speculative + purgeable
#
# Deliberately EXCLUDED:
#   wired      — kernel and drivers. Never reclaimable. Also the memory class
#                that can actually panic the machine (see wired_limit below).
#   active     — in use by running processes.
#   compressor — already-compressed pages belonging to LIVE processes. This is
#                evidence of memory pressure, not spare capacity. Counting it
#                would tell you a machine that is already thrashing has room.
#
# Counting only "Pages free" understates badly — macOS keeps free near zero by
# design and parks reclaimable memory on the inactive list.
#
# Honest caveat: purgeable-volatile pages are also counted on the active and
# inactive lists in Mach VM, so this number skews slightly optimistic. It is
# still far closer to the truth than "Pages free" alone.
#
# Page size is READ FROM vm_stat, never hardcoded: it is 4096 on Intel and
# 16384 on Apple Silicon, and hardcoding either one is a 4x error on the other.
hw_available_gb() {
  vm_stat 2>/dev/null | awk '
    # Header: "Mach Virtual Memory Statistics: (page size of 16384 bytes)"
    /page size of/ {
      if (match($0, /page size of [0-9]+/)) {
        s = substr($0, RSTART, RLENGTH); sub(/page size of /, "", s); ps = s + 0
      }
    }
    # Counts live in the last field and carry a trailing period: "402691."
    /^Pages free:/        { v = $NF; sub(/\./, "", v); free  = v + 0 }
    /^Pages inactive:/    { v = $NF; sub(/\./, "", v); inact = v + 0 }
    /^Pages speculative:/ { v = $NF; sub(/\./, "", v); spec  = v + 0 }
    /^Pages purgeable:/   { v = $NF; sub(/\./, "", v); purge = v + 0 }
    END {
      if (ps <= 0) ps = 16384   # last-resort fallback; should never fire
      printf "%.1f", (free + inact + spec + purge) * ps / 1073741824
    }'
}

# Pages sitting in the compressor. Not capacity — a pressure signal. If this is
# large relative to RAM, the machine was already squeezed before you showed up.
hw_compressor_gb() {
  vm_stat 2>/dev/null | awk '
    /page size of/ {
      if (match($0, /page size of [0-9]+/)) {
        s = substr($0, RSTART, RLENGTH); sub(/page size of /, "", s); ps = s + 0
      }
    }
    /^Pages occupied by compressor:/ { v = $NF; sub(/\./, "", v); comp = v + 0 }
    END { if (ps <= 0) ps = 16384; printf "%.1f", comp * ps / 1073741824 }'
}

# The GPU wired-memory ceiling that Apple would pick on its own, in GB.
# ARITHMETIC: the commonly reported rule, 2/3 of RAM at 32 GB and below, 3/4
# above. It is not read from the machine — the real number is Metal's
# recommendedMaxWorkingSetSize, which only a Metal or MLX call returns, and
# this file is Bash. mlx-serve prints that real number at every load as
# "[wired] mode=max limit=N MB"; doctor.sh quotes it beside this estimate and
# judges the selected build against both. MEASURED once, 36 GB M3 Max:
# 28753 MB = 28.1 GB against the 27.0 GB computed here, so the arithmetic
# erred on the refusing side by 1.1 GB. One machine; the rule is not corrected
# from n=1. The guards use this estimate on purpose: it exists before any load
# and cannot go stale the way a log line from another day can.
# This is the number the safety check below is measured against, ALWAYS —
# never the hand-set value. Checking against a hand-set value would make the
# check quieter exactly as the machine gets more dangerous, because raising the
# ceiling is the dangerous act.
hw_wired_auto_gb() {
  awk -v g="$(hw_total_ram_gb)" \
    'BEGIN { printf "%.1f", (g <= 32 ? g * 2 / 3 : g * 3 / 4) }'
}

# What iogpu.wired_limit_mb reads right now, in GB. 0 means "auto", in which
# case this reports the auto estimate. Display only. We never write this sysctl.
hw_wired_limit_gb() {
  _wl="$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)"
  if [ "${_wl:-0}" -gt 0 ] 2>/dev/null; then
    awk -v m="$_wl" 'BEGIN { printf "%.1f", m / 1024 }'
  else
    hw_wired_auto_gb
  fi
}

# Is the ceiling set by hand rather than left on auto? Prints yes or no.
hw_wired_is_manual() {
  _wl="$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)"
  if [ "${_wl:-0}" -gt 0 ] 2>/dev/null; then echo "yes"; else echo "no"; fi
}

# The value above which a hand-set ceiling is dangerous, in MB: 80% of RAM.
# This scales. A fixed constant is wrong in both directions — on a 16 GB Mac it
# never fires, and on a 128 GB Mac it fires on a completely safe value.
hw_wired_danger_mb() {
  awk -v g="$(hw_total_ram_gb)" 'BEGIN { printf "%d", g * 1024 * 0.8 }'
}

# The five biggest memory users right now, one per line, indented by $1 spaces.
# `ps -m` sorts by MEMORY. `ps -r` sorts by CPU, which would make the words
# "biggest wins, in order" a lie. The whole rest of the line is printed because
# `comm` holds full paths that contain spaces.
hw_top_memory_users() {
  _ind="${1:-  }"; _n="${2:-5}"
  ps -Ao rss,comm -m 2>/dev/null \
    | awk -v ind="$_ind" 'NR>1 && $1>500000 {
        rss = $1; $1 = ""; sub(/^[ \t]+/, "")
        printf "%s%5.1f GB  %s\n", ind, rss / 1048576, $0
      }' \
    | head -"$_n" || true
}

# ---------------------------------------------------------------------------
# 3. Turn RAM into a recommendation
# ---------------------------------------------------------------------------
# Weight footprints come from bin/catalog.sh (loaded GB, text-only: the vision
# tower is skipped at run time via --no-vision, so it costs disk but not memory).
# The 27B OrcaRouter builds are 16.3 / 19.1 / 27.7 GB at 4 / 5 / 8-bit; only the
# 5-bit figure is MEASURED here, the other two are PUBLISHER-REPORTED. The
# catalog file says which is which.
#
# KV cache: what one token of conversation costs is a property of the model,
# not of this file. Only layers that keep a growing key/value record count;
# in the Qwen3.8 hybrid that is one layer in four (the other three are Gated
# DeltaNet and hold a constant-size state), and in an ordinary dense model it
# is every layer. Per token, at 16 bits per number:
#     growing layers x 2 (K,V) x kv-heads x head_dim x 2 bytes
# which is 64 KiB for the 27B (16 x 2 x 4 x 256 x 2 = 65536 B) and 32 KiB for
# the 9B (8 such layers). That figure arrives here as an argument: bin/env.sh
# reads it from the selected checkpoint's own config.json (model_kv_kib), and
# bin/catalog.sh carries a verified copy for builds not on disk yet. Until
# 2026-08-18 this file used the 27B's 64 KiB for everything (AUDIT.md F5),
# which over-charged the 9B twice over and would have under-charged a dense
# model by a factor of several while still reading as authoritative.
#
# KV_QUANT then divides it: turbo4 packs each number into 4 bits, so the 27B
# costs 16 KiB per token and a 65536-token window exactly 1.0 GiB — the
# reference configuration. `off` keeps all 16 bits, so the same window costs
# 4.0 GiB, and the guard has to know that when a user follows docs/07's
# advice to raise KV_QUANT. NOT counted: the per-group scale and bias a
# quantized cache carries. mlx-serve does not publish its group size, so that
# overhead cannot be worked out here; the guard's rounding-up absorbs it, and
# bench.sh's `gap` line is where a real load's excess over this arithmetic
# shows.

# hw_kv_bits <kv_quant>  — bits per number the KV cache is stored at, for a
# --kv-quant mode name as mlx-serve --help lists them: off, 4, 8, turbo2,
# turbo4. A name this does not know reads as 16, the largest — the guard then
# asks for more than the load will take rather than less, and mlx-serve
# refuses the unknown name itself a moment later.
hw_kv_bits() {
  case "$1" in
    4|turbo4) echo 4 ;;
    8)        echo 8 ;;
    turbo2)   echo 2 ;;
    *)        echo 16 ;;
  esac
}

# hw_rebudget <weights_gb> <ctx_tokens> <kv_kib_per_token>
#
# Works out the three memory settings from a weight size, a context size and
# the model's per-token KV cost at 16 bits (see above). Sets HW_KV_GB,
# HW_MIN_FREE_GB, HW_MAX_RESIDENT_MEM, HW_PREFIX_CACHE_MEM. Needs HW_RAM_GB
# and HW_KV_QUANT (the --kv-quant mode, set by hw_recommend — one value per
# process, unlike the per-model figure, which is why it is not an argument).
# Called by hw_recommend, and again by bin/env.sh once the build actually on
# disk and the final CTX_SIZE are both known.
#
#   kv               = ctx x kv_kib x bits/16 / 1048576   (GiB)
#   reserve          = ceil(weights + kv) + 1         weights, conversation, 1 GB spare
#   PREFIX_CACHE_MEM = 256 MB per GB left after that reserve and an 8 GB macOS
#                      reserve, clamped to [512, 8192] MB
#   MIN_FREE_GB      = ceil(weights + kv + prefix cache)
#   MAX_RESIDENT_MEM = ceil(weights) + 1 GB
#
# MIN_FREE_GB includes the prefix cache on purpose. It is memory the server
# really takes, and leaving it out made the guard pass loads it could not
# satisfy — by more the more memory the Mac had, because the prefix cache grows
# with memory. The prefix cache is sized first so the two do not chase each
# other in a circle.
#
# On the 36 GB test machine with a 65536-token window this produces exactly
# MIN_FREE_GB=22, MAX_RESIDENT_MEM=21GB, PREFIX_CACHE_MEM=1536MB — the
# committed reference configuration. Change a number here and re-check that.
hw_rebudget() {
  # An empty or zero per-token figure would silently drop the conversation
  # term to nothing — the under-charge this arithmetic exists to prevent — so
  # it is a loud failure, not a quiet default. bin/env.sh's cascade always has
  # a figure (config.json, catalog, or the recommended build's); reaching
  # this means a caller was changed without it.
  if ! awk -v k="${3:-}" 'BEGIN { exit !(k > 0) }'; then
    echo "hw_rebudget: no per-token KV figure was given (third argument: '${3:-}')" >&2
    return 1
  fi
  eval "$(awk -v ram="${HW_RAM_GB:-0}" -v w="$1" -v ctx="$2" -v kib="$3" \
             -v bits="$(hw_kv_bits "${HW_KV_QUANT:-}")" 'BEGIN {
    kv      = ctx * kib * bits / 16 / 1048576
    reserve = int(w + kv) + ((w + kv) > int(w + kv) ? 1 : 0) + 1
    pfx     = (ram - reserve - 8) * 256
    if (pfx < 512)  pfx = 512
    if (pfx > 8192) pfx = 8192
    need    = w + kv + pfx / 1024
    minf    = int(need) + (need > int(need) ? 1 : 0)
    mrm     = int(w)    + (w    > int(w)    ? 1 : 0) + 1
    printf "HW_KV_GB=%.2f; HW_MIN_FREE_GB=%d; HW_MAX_RESIDENT_MEM=%dGB; HW_PREFIX_CACHE_MEM=%dMB\n",
           kv, minf, mrm, pfx
  }')"
}

# hw_kv_tokens <size> <kv_kib_per_token>  — how many tokens of conversation a
# KV budget of <size> (a settings value like 1536MB or 3GB) holds for a model
# with this per-token cost at HW_KV_QUANT. The unit PREFIX_CACHE_MEM is set in
# is bytes; the unit the user thinks in is tokens (AUDIT.md E2). Whole tokens,
# rounded down. The same reader hw_size_gb uses handles the suffix.
hw_kv_tokens() {
  awk -v gb="$(hw_size_gb "$1")" -v kib="${2:-0}" \
      -v bits="$(hw_kv_bits "${HW_KV_QUANT:-}")" 'BEGIN {
    if (kib <= 0) { print 0; exit }
    printf "%d\n", gb * 1048576 / (kib * bits / 16)
  }'
}

hw_recommend() {
  HW_RAM_GB="$(hw_total_ram_gb)"
  HW_CHIP="$(hw_chip)"
  HW_AVAILABLE_GB="$(hw_available_gb)"
  HW_COMPRESSOR_GB="$(hw_compressor_gb)"
  HW_WIRED_LIMIT_GB="$(hw_wired_limit_gb)"
  HW_WIRED_AUTO_GB="$(hw_wired_auto_gb)"
  HW_WIRED_MANUAL="$(hw_wired_is_manual)"
  HW_GPU_CORES="$(hw_gpu_cores)"
  # The KV-cache format the budget is worked out for. bin/env.sh has already
  # put a KV_QUANT from the command line or config.env in place when it
  # sources this file, and takes this value back as the setting's default, so
  # `turbo4` — the reference configuration — is stated once, here.
  HW_KV_QUANT="${KV_QUANT:-turbo4}"
  HW_KV_KIB=0
  HW_KV_SOURCE=""
  HW_KV_GB=0
  HW_WIRED_OK="yes"
  HW_CTX_SIZE=0
  HW_MIN_FREE_GB=0
  HW_MAX_RESIDENT_MEM=0
  HW_PREFIX_CACHE_MEM=0
  HW_RECOMMENDED_KEY=""

  if ! hw_is_apple_silicon; then
    HW_APPLE_SILICON="no"
    HW_VERDICT="impossible"
    HW_QUANT="none"
    HW_WEIGHTS_GB=0
    HW_REASON="MLX requires Apple Silicon. This reports: ${HW_CHIP}."
    HW_ALT_MODEL="Use llama.cpp on the processor, or a hosted service."
    return 0
  fi
  HW_APPLE_SILICON="yes"

  # Ladder over physical RAM. Deliberately a ladder and not a smooth curve:
  # the constraints are lumpy (weights are fixed sizes, the wired ceiling is a
  # fixed fraction) and a smooth formula would invent precision we do not have.
  #
  # HW_VERDICT answers one question: how does the 27B fare on this Mac?
  # HW_RECOMMENDED_KEY names the catalog build the scripts default to, which
  # below 32 GB is not a 27B at all. The two are kept apart on purpose: a Mac
  # that cannot run the 27B is not a Mac that cannot run anything.
  if   [ "$HW_RAM_GB" -lt 24 ]; then
    HW_VERDICT="impossible"; HW_QUANT="none"; HW_RECOMMENDED_KEY="9b-4bit"; HW_CTX_SIZE=32768
    HW_REASON="The smallest 27B build (4-bit, ~16.3 GB) cannot fit under the ${HW_WIRED_AUTO_GB} GB GPU wired ceiling Apple picks for ${HW_RAM_GB} GB."
  elif [ "$HW_RAM_GB" -lt 32 ]; then
    HW_VERDICT="not-recommended"; HW_QUANT="4-bit"; HW_RECOMMENDED_KEY="9b-4bit"; HW_CTX_SIZE=32768
    HW_REASON="4-bit weights (~16.3 GB) sit at or near the ${HW_WIRED_AUTO_GB} GB GPU wired ceiling Apple picks at this size and leave macOS almost nothing. 5-bit is out of reach entirely."
  elif [ "$HW_RAM_GB" -lt 36 ]; then
    HW_VERDICT="tight"; HW_QUANT="4-bit"; HW_RECOMMENDED_KEY="27b-4bit"; HW_CTX_SIZE=32768
    HW_REASON="4-bit fits with room to work. 5-bit (~19.1 GB) sits close to the wired ceiling and needs a quiet machine."
  elif [ "$HW_RAM_GB" -lt 48 ]; then
    HW_VERDICT="workable"; HW_QUANT="5-bit"; HW_RECOMMENDED_KEY="27b-5bit"; HW_CTX_SIZE=65536
    HW_REASON="The reference configuration. Fits, but you must close memory-hungry apps first."
  elif [ "$HW_RAM_GB" -lt 64 ]; then
    HW_VERDICT="comfortable"; HW_QUANT="5-bit"; HW_RECOMMENDED_KEY="27b-5bit"; HW_CTX_SIZE=131072
    HW_REASON="5-bit plus a 131072-token window fits without closing your browser."
  elif [ "$HW_RAM_GB" -lt 96 ]; then
    HW_VERDICT="comfortable"; HW_QUANT="8-bit"; HW_RECOMMENDED_KEY="27b-8bit"; HW_CTX_SIZE=131072
    HW_REASON="Enough spare memory to stop trading quality for memory. Use 8-bit weights."
  else
    HW_VERDICT="comfortable"; HW_QUANT="8-bit"; HW_RECOMMENDED_KEY="27b-8bit"; HW_CTX_SIZE=262144
    HW_REASON="Full 262144-token context at 8-bit, with room for a large prefix cache."
  fi

  # The recommended build's own facts, from the catalog. HW_WEIGHTS_GB is the
  # loaded size (blank in the catalog means "use the download size").
  HW_RECOMMENDED_REPO="$(catalog_field "$HW_RECOMMENDED_KEY" 2)"
  HW_WEIGHTS_GB="$(catalog_field "$HW_RECOMMENDED_KEY" 4)"
  [ -n "$HW_WEIGHTS_GB" ] || HW_WEIGHTS_GB="$(catalog_field "$HW_RECOMMENDED_KEY" 3)"
  # The recommended build's per-token KV cost, from the catalog: nothing is on
  # disk yet at this point. bin/env.sh replaces both with the selected model's
  # own figures once it knows which model that is.
  HW_KV_KIB="$(catalog_field "$HW_RECOMMENDED_KEY" 5)"
  HW_KV_SOURCE="catalog"

  hw_rebudget "$HW_WEIGHTS_GB" "$HW_CTX_SIZE" "$HW_KV_KIB"

  # Sanity check against the wired ceiling, which is the one that can stall the
  # whole Mac rather than merely swap. Weights + KV must fit UNDER it.
  # Measured against the AUTO ceiling always, never against a hand-set one:
  # raising the ceiling by hand is the dangerous act, so validating against the
  # raised value would silence the check exactly when it matters most.
  HW_WIRED_OK="$(hw_wired_fits "$HW_WEIGHTS_GB" "$HW_KV_GB")"

  # What else fits, in the words of the catalog: every build whose weights fit
  # under the GPU ceiling and whose free-memory demand is at most 65% of RAM.
  # Empty when the 27B is comfortable and there is nothing to add.
  HW_ALT_MODEL=""
  case "$HW_VERDICT" in
    impossible|not-recommended|tight)
      HW_ALT_MODEL="$(hw_catalog_fits "$HW_CTX_SIZE")"
      if [ -n "$HW_ALT_MODEL" ]; then
        HW_ALT_MODEL="These catalog builds fit this Mac: ${HW_ALT_MODEL}. See ./bin/models.sh list."
      else
        HW_ALT_MODEL="No build in the catalog fits this Mac comfortably. ./bin/models.sh list shows the numbers."
      fi
      ;;
  esac
}

# hw_wired_fits <weights_gb> <kv_gb>  — "yes" if they fit under the auto ceiling.
hw_wired_fits() {
  awk -v w="$1" -v kv="$2" -v lim="$HW_WIRED_AUTO_GB" \
    'BEGIN { print (w + kv <= lim) ? "yes" : "no" }'
}

# hw_fit_mark <weights_gb> <ctx_tokens> <kv_kib_per_token>
# Sets HW_FIT_MARK to "NO", "TIGHT" or "ok" for one build on this Mac, using
# the same arithmetic bin/serve.sh enforces: NO when weights + KV cache do not
# fit under the GPU wired ceiling (serve.sh refuses), TIGHT when the free
# memory it demands is more than 65% of RAM (close everything first), ok
# otherwise. Also leaves HW_MIN_FREE_GB etc. set for that build, so callers can
# print them. A variable rather than output so it works outside a subshell.
hw_fit_mark() {
  hw_rebudget "$1" "$2" "$3"
  if [ "$(hw_wired_fits "$1" "$HW_KV_GB")" = "no" ]; then
    HW_FIT_MARK="NO"
  elif awk -v n="$HW_MIN_FREE_GB" -v r="$HW_RAM_GB" 'BEGIN { exit !(n > r * 0.65) }'; then
    HW_FIT_MARK="TIGHT"
  else
    HW_FIT_MARK="ok"
  fi
}

# hw_catalog_fits <ctx_tokens>  — comma-separated "key (N GB)" for every
# catalog build marked ok on this Mac. Restores the caller's budget afterwards.
hw_catalog_fits() {
  _save="HW_KV_GB=$HW_KV_GB HW_MIN_FREE_GB=$HW_MIN_FREE_GB HW_MAX_RESIDENT_MEM=$HW_MAX_RESIDENT_MEM HW_PREFIX_CACHE_MEM=$HW_PREFIX_CACHE_MEM"
  _out=""
  while IFS='|' read -r _k _repo _dl _ld _kv _abl _note; do
    [ -n "$_k" ] || continue
    [ -n "$_ld" ] || _ld="$_dl"
    hw_fit_mark "$_ld" "$1" "$_kv"
    if [ "$HW_FIT_MARK" = "ok" ]; then
      _out="${_out:+$_out, }${_k} (${_dl} GB)"
    fi
  done <<EOF
$CATALOG
EOF
  eval "$_save"
  printf '%s\n' "$_out"
  unset _save _out _k _repo _dl _ld _kv _abl _note
}

# ---------------------------------------------------------------------------
# 4. Disk
# ---------------------------------------------------------------------------
# Disk was the one resource with no refusal covering it (AUDIT.md A2): a Mac
# with 6 GB free passed every check and then started a server told to write a
# 10 GB prefix cache. The arithmetic lives here, once, and both refusals
# (download-model.sh, serve.sh) and doctor's row read it from this function.

# hw_size_gb <size> — a settings value like 10GB, 512MB, 2G, off or 0, as GB.
# Prints a decimal (four places: every caller either rounds up or converts
# on, and 1000MB must not read as 1.0). Anything unrecognised reads as 0,
# which is the safe direction: it never inflates a requirement out of a value
# nobody understands.
hw_size_gb() {
  awk -v s="${1:-0}" 'BEGIN {
    t = tolower(s)
    if (t == "" || t == "off" || t == "none") { printf "0.0"; exit }
    n = t + 0
    if (t ~ /kb?$/) n = n / 1048576
    else if (t ~ /mb?$/) n = n / 1024
    else if (t ~ /tb?$/) n = n * 1024
    printf "%.4f", n
  }'
}

# hw_disk_need_gb <download|serve> <weights_gb> <cache_disk_gb> — the free disk
# that phase needs, in whole GB, rounded up.
#
#   download : the peak, plus what the server will want afterwards. git-lfs
#              keeps a second copy of every shard until dedup reclaims it, so
#              the peak is 2 x weights; after dedup the steady state is
#              weights + the cache tier. The larger of the two governs, because
#              the download must survive both. (They never coexist: dedup runs
#              before any server does.)
#   serve    : the cache tier the server is configured to write. The weights
#              are already on disk and are not written again.
#
# Both add HW_DISK_SPARE_GB. macOS itself needs room — swap, snapshots, log
# rotation — and a disk driven to zero by our own cache is a worse failure than
# a refusal. It is a policy number, not a measurement, and this is its one
# statement.
HW_DISK_SPARE_GB=5
hw_disk_need_gb() {
  awk -v phase="$1" -v w="${2:-0}" -v c="${3:-0}" -v spare="$HW_DISK_SPARE_GB" 'BEGIN {
    if (phase == "download") { peak = 2 * w; steady = w + c; need = (peak > steady ? peak : steady) }
    else                     { need = c }
    need += spare
    printf "%d", int(need) + (need > int(need) ? 1 : 0)
  }'
}

# ---------------------------------------------------------------------------
# 5. Output
# ---------------------------------------------------------------------------

hw_report() {
  hw_recommend
  echo "chip           ${HW_CHIP}${HW_GPU_CORES:+ (${HW_GPU_CORES} GPU cores)}"
  echo "memory         ${HW_RAM_GB} GB total, ${HW_AVAILABLE_GB} GB available now"
  echo "compressor     ${HW_COMPRESSOR_GB} GB  (pressure signal, NOT free memory)"
  if [ "$HW_WIRED_MANUAL" = "yes" ]; then
    echo "wired ceiling  ${HW_WIRED_LIMIT_GB} GB  SET BY HAND (Apple would pick ${HW_WIRED_AUTO_GB} GB)"
  else
    echo "wired ceiling  ${HW_WIRED_LIMIT_GB} GB  (auto — arithmetic; the server logs the real one at load)"
  fi
  echo
  echo "verdict        ${HW_VERDICT}  --  ${HW_REASON}"
  if [ -n "$HW_ALT_MODEL" ]; then
    echo "instead        ${HW_ALT_MODEL}"
  fi
  if [ "${HW_APPLE_SILICON:-no}" != "yes" ]; then
    echo
    echo "This is not an Apple Silicon Mac, so nothing here can run. Read docs/01-requirements.md."
    return 0
  fi
  if [ "$HW_VERDICT" = "impossible" ]; then
    echo
    echo "The 27B does not fit this Mac. Nothing is broken: the scripts default to a"
    echo "smaller build here (see below), and ./bin/models.sh list shows every option."
  fi
  echo
  echo "recommended settings for this Mac:"
  echo "  build             ${HW_RECOMMENDED_KEY}  (${HW_RECOMMENDED_REPO}, ~${HW_WEIGHTS_GB} GB of weights, text-only)"
  echo "  CTX_SIZE          ${HW_CTX_SIZE}   (KV cache ${HW_KV_GB} GB at kv-quant ${HW_KV_QUANT}: ${HW_KV_KIB} KiB/token at 16-bit, ${HW_KV_SOURCE})"
  echo "  MIN_FREE_GB       ${HW_MIN_FREE_GB}"
  echo "  MAX_RESIDENT_MEM  ${HW_MAX_RESIDENT_MEM}"
  echo "  PREFIX_CACHE_MEM  ${HW_PREFIX_CACHE_MEM}"
  echo
  echo "These are predictions about whether the model FITS. They say nothing"
  echo "about how fast it will feel. Speed follows GPU cores, not memory, and"
  echo "no speed figure has been measured on any machine, including the test machine."
  if [ "$HW_WIRED_OK" = "no" ]; then
    echo
    echo "WARNING  weights + KV cache (${HW_WEIGHTS_GB} + ${HW_KV_GB} GB) do not fit under"
    echo "         the ${HW_WIRED_AUTO_GB} GB GPU wired ceiling Apple picks on this Mac."
    echo "         bin/serve.sh REFUSES to start a build in this state. Raising"
    echo "         iogpu.wired_limit_mb is the one change that can make this Mac stall"
    echo "         until you force a restart, so use a smaller build instead."
  fi
  if [ "$HW_WIRED_MANUAL" = "yes" ]; then
    echo
    echo "WARNING  iogpu.wired_limit_mb was set by hand to ${HW_WIRED_LIMIT_GB} GB."
    echo "         Memory reserved that way cannot be swapped out. Apple's automatic"
    echo "         value is the recommended setting. To put it back:"
    echo "         sudo sysctl iogpu.wired_limit_mb=0    (a restart also resets it)"
  fi
  if awk -v a="$HW_AVAILABLE_GB" -v m="$HW_MIN_FREE_GB" 'BEGIN { exit (a >= m) }'; then
    echo
    echo "NOTE     only ${HW_AVAILABLE_GB} GB is available right now, ${HW_MIN_FREE_GB} GB is needed."
    echo "         Close apps before starting. Biggest consumers:"
    hw_top_memory_users "           " 5
  fi
  return 0
}

hw_export() {
  hw_recommend
  # A non-Apple-Silicon machine has no usable settings, and MIN_FREE_GB=0 is
  # this repo's documented way to switch the memory guard OFF. Emitting it here
  # would hand the least capable machine the most dangerous setting, so emit
  # nothing.
  if [ "${HW_APPLE_SILICON:-no}" != "yes" ]; then
    echo "# this is not an Apple Silicon Mac, so there are no settings to export" >&2
    echo "# reason:  ${HW_REASON}" >&2
    echo "# read docs/01-requirements.md" >&2
    return 1
  fi
  echo "export CTX_SIZE=${HW_CTX_SIZE}"
  echo "export MIN_FREE_GB=${HW_MIN_FREE_GB}"
  echo "export MAX_RESIDENT_MEM=${HW_MAX_RESIDENT_MEM}"
  echo "export PREFIX_CACHE_MEM=${HW_PREFIX_CACHE_MEM}"
  echo "export HW_RAM_GB=${HW_RAM_GB} HW_VERDICT=${HW_VERDICT} HW_QUANT=${HW_QUANT} HW_RECOMMENDED_KEY=${HW_RECOMMENDED_KEY}"
}

hw_help() {
  cat <<'EOF'
detect-hardware.sh — tell you what this Mac can run, before you download 20 GB.

WHAT IT DOES
  Reads how much memory this Mac has, how much is free right now, and what
  Apple's GPU memory ceiling is. Turns that into a recommendation. It only
  reads. It changes nothing and it downloads nothing.

USAGE (run from the repo root)
  ./bin/detect-hardware.sh            print the report
  ./bin/detect-hardware.sh --export   print shell assignments instead
  ./bin/detect-hardware.sh --help     print this help

ENVIRONMENT
  HW_FORCE_RAM_GB   pretend the Mac has this many GB. For testing the advice
                    table on one machine. Example: HW_FORCE_RAM_GB=64

READ NEXT
  docs/01-requirements.md   what the verdict means, in plain words.
EOF
}

# Run the report only when EXECUTED, stay silent when SOURCED.
# bash: BASH_SOURCE[0] != $0 while sourcing.
# zsh:  BASH_SOURCE does not exist, and an array subscript on it is a syntax
#       error, so the whole expression is kept inside a bash-only branch.
#       zsh reports sourcing through ZSH_EVAL_CONTEXT instead.
_hw_sourced=0
if [ -n "${ZSH_EVAL_CONTEXT:-}" ]; then
  case "$ZSH_EVAL_CONTEXT" in *:file) _hw_sourced=1 ;; esac
elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
  _hw_sourced=1
fi

if [ "$_hw_sourced" = "0" ]; then
  case "${1:-}" in
    --help|-h) hw_help ;;
    --export)  hw_export ;;
    *)         hw_report ;;
  esac
fi
