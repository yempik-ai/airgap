#!/usr/bin/env bash
# Shared configuration for the local Qwen3.8-27B stack.
#
# This file is SOURCED by every other script in bin/. It is not meant to be run
# on its own, and it prints nothing when it is sourced.
#
# WHERE A SETTING COMES FROM — highest priority first:
#   1. a real environment variable   CTX_SIZE=32768 ./bin/serve.sh
#   2. ./config.env                  a plain KEY=value file you edit
#   3. this Mac's detected size      bin/detect-hardware.sh works it out
#   4. the built-in default below    the reference configuration
#
# So a value you type on the command line always wins, and a Mac with more or
# less memory than the test machine gets settings that fit it.

set -euo pipefail

# zsh has no BASH_SOURCE, and an array subscript on it is a syntax error there,
# so the bash form is kept inside a bash-only branch. macOS logs you in to zsh.
if [ -n "${BASH_VERSION:-}" ]; then
  _env_self="${BASH_SOURCE[0]}"
else
  _env_self="$0"
fi
ROOT="$(cd "$(dirname "$_env_self")/.." && pwd)"

# Every setting this stack understands. The list is written out once, here,
# because bash 3.2 (the version macOS ships) has no associative arrays.
# Anything NOT on this list can be set in config.env but cannot be overridden
# from the command line, so keep every documented setting on it.
ENV_KEYS="MODEL_QUANT MODEL_REPO MODEL_DIR MODEL_ID HOST PORT CTX_SIZE KV_QUANT NO_VISION \
PREFIX_CACHE_MEM PREFIX_CACHE_DISK MAX_RESIDENT_MODELS MAX_RESIDENT_MEM \
IDLE_EVICT_SECS SERVE_TIMEOUT PREFILL_CHUNK MIN_FREE_GB MIN_DISK_GB LOG_LEVEL LOG_FILE \
LOCK_DIR API_KEY METRICS EXTRA_ARGS DEDUP LEAN_MCP CLAUDE_BIN CODEX_BIN PYTHON_BIN WITH_VENV \
CLAUDE_CODE_MAX_OUTPUT_TOKENS MAX_THINKING_TOKENS PROBE SKIP_BREW TOKENS PROMPT PROMPT_FILE ROW_FILE"

# --- Step 1: remember exactly what the caller set ----------------------------
# "_ENVSET_x is non-empty" means the caller really set x, even if they set it
# to an empty string.
for _k in $(echo "$ENV_KEYS"); do
  eval "_ENVSET_${_k}=\${${_k}+1}; _ENVSAVE_${_k}=\"\${${_k}-}\""
done

# --- Step 2: your own settings file ------------------------------------------
# config.env holds KEY=value lines. It is listed in .gitignore because it may
# hold an API_KEY. Copy config.env.example to start one.
#
# HONEST WARNING: this line RUNS the file as a shell script. It does not merely
# read KEY=value pairs out of it. Put nothing in config.env except KEY=value
# lines and comments, and never paste a command into it.
if [ -f "$ROOT/config.env" ]; then
  # shellcheck source=/dev/null
  source "$ROOT/config.env"
fi

# --- Step 3: put the caller's own environment back on top --------------------
for _k in $(echo "$ENV_KEYS"); do
  eval "if [ -n \"\${_ENVSET_${_k}-}\" ]; then ${_k}=\"\${_ENVSAVE_${_k}}\"; fi"
  eval "unset _ENVSET_${_k} _ENVSAVE_${_k}"
done
unset _k

# --- Step 4: size this Mac ---------------------------------------------------
# Sets HW_* facts and proposes HW_CTX_SIZE, HW_MIN_FREE_GB, HW_MAX_RESIDENT_MEM
# and HW_PREFIX_CACHE_MEM for the build it recommends. It writes only HW_*
# names, so it can never overwrite something you set in step 2 or step 3. On
# the 36 GB test machine it proposes exactly the reference numbers below. On a
# different Mac it proposes numbers that fit that Mac.
#
# Remember which of the three budget settings you had already chosen, so the
# re-budget in step 6 leaves your choices alone. (CTX_SIZE needs no such note:
# `: "${CTX_SIZE:=...}"` below already leaves a chosen value untouched.)
for _k in MIN_FREE_GB MAX_RESIDENT_MEM PREFIX_CACHE_MEM; do
  eval "_YOURS_${_k}=\${${_k}+1}"
done
unset _k

# shellcheck source=bin/detect-hardware.sh
source "$ROOT/bin/detect-hardware.sh"
hw_recommend

# A machine that is not Apple Silicon gets no detected settings at all —
# HW_CTX_SIZE and the rest are 0, which is not a usable size, and MIN_FREE_GB=0
# in particular is this repo's way of switching the memory guard OFF. Fall
# through to the reference defaults instead. serve.sh, download-model.sh and
# doctor.sh all refuse on HW_APPLE_SILICON, which is the honest place to stop.
if [ "${HW_APPLE_SILICON:-no}" = "yes" ]; then
  : "${CTX_SIZE:=$HW_CTX_SIZE}"
fi

# --- Is the model on disk, and is it whole? ----------------------------------
# Six scripts ask "is the model here?", three of them used to answer it from
# the first shard alone, and an interrupted download must not get six different
# answers (AUDIT.md D2). `git lfs pull` leaves every shard
# it has not reached as a ~135-byte pointer file, and a copy made by hand can
# simply be missing them, so the question is answered over EVERY shard the
# checkpoint declares — never over the first one found.
#
# These sit above the defaults rather than with the other helpers at the foot
# of this file because env.sh's own model discovery, a few lines below, is one
# of the callers.

# The shard files present in model directory $1, one per line, top level only.
model_shards() {
  for _ms in "$1"/*.safetensors; do
    if [ -f "$_ms" ]; then printf '%s\n' "$_ms"; fi
  done
  unset _ms
}

# The first shard of $1 that is not real weights, as "name bytes". A git-lfs
# pointer is about 135 bytes of text; anything under 1 MB is one. Prints
# nothing and returns 1 when every shard present is real.
model_pointer_shard() {
  for _ms in "$1"/*.safetensors; do
    if [ -f "$_ms" ]; then
      _mz="$(stat -f%z "$_ms" 2>/dev/null || echo 0)"
      if [ "$_mz" -lt 1000000 ]; then
        printf '%s %s\n' "$(basename "$_ms")" "$_mz"
        unset _ms _mz
        return 0
      fi
    fi
  done
  unset _ms _mz
  return 1
}

# The shards model.safetensors.index.json names that are not on disk at all,
# one per line. A transfer that stopped between files leaves no pointer behind
# to find, so the index is the only record of what should be there. Prints
# nothing when the checkpoint ships no index — not all of them do.
model_missing_shards() {
  _mi="$1/model.safetensors.index.json"
  if [ ! -f "$_mi" ]; then unset _mi; return 0; fi
  grep -o '"[^"]*\.safetensors"' "$_mi" 2>/dev/null | tr -d '"' | sort -u | while IFS= read -r _mn; do
    if [ ! -f "$1/$_mn" ]; then printf '%s\n' "$_mn"; fi
  done
  unset _mi
}

# absent | partial | complete, for model directory $1.
#   absent    nothing usable here: no config.json, or no shard files at all
#   partial   a download that stopped: a shard is missing or still a pointer
#   complete  config.json, and every shard the checkpoint declares is real
model_state() {
  if [ ! -f "$1/config.json" ] || [ -z "$(model_shards "$1")" ]; then
    echo absent
    return 0
  fi
  if model_pointer_shard "$1" >/dev/null || [ -n "$(model_missing_shards "$1")" ]; then
    echo partial
    return 0
  fi
  echo complete
}

# --- What the model says about itself: two readers of config.json -----------
# Both print a number or nothing — nothing when there is no model, no python3,
# or no such key — and every caller treats nothing as "cannot tell". One
# reader per fact, so no two scripts can disagree about what the model says.
# PYTHON_BIN is defaulted here rather than under Tools below because step 6
# calls model_kv_kib before the defaults section is reached.
: "${PYTHON_BIN:=python3}"

# The largest context this model was built for. serve.sh refuses a CTX_SIZE
# above it; doctor reports it.
model_max_ctx() {
  [ -f "$1/config.json" ] || return 0
  command -v "$PYTHON_BIN" >/dev/null 2>&1 || return 0
  "$PYTHON_BIN" -c '
import json, sys
try:
    c = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
t = c.get("text_config", c)
v = t.get("max_position_embeddings") or c.get("max_position_embeddings")
if isinstance(v, int) and v > 0:
    print(v)
' "$1/config.json" 2>/dev/null || true
}

# What one token of conversation costs this model in KV cache at 16 bits per
# number, in KiB (AUDIT.md F5): growing layers x 2 (K,V) x kv-heads x head_dim
# x 2 bytes / 1024. Every layer counts as growing unless its `layer_types`
# entry says linear_attention — the one constant-state kind verified here
# (Qwen3.8's Gated DeltaNet). A checkpoint with no `layer_types` at all is an
# ordinary dense model and every layer counts; a kind this has not met also
# counts, which is the direction that over-charges rather than under-charges.
# `num_key_value_heads` falls back to `num_attention_heads` (no grouped-query
# attention) and `head_dim` to hidden_size / heads, both as the transformers
# loaders do. hw_rebudget (bin/detect-hardware.sh) turns this into GB for a
# context size and a KV_QUANT; bin/catalog.sh carries a verified copy for
# builds not on disk yet.
model_kv_kib() {
  [ -f "$1/config.json" ] || return 0
  command -v "$PYTHON_BIN" >/dev/null 2>&1 || return 0
  "$PYTHON_BIN" -c '
import json, sys
try:
    c = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
t = c.get("text_config", c)
types = t.get("layer_types")
n = t.get("num_hidden_layers")
if isinstance(types, list) and types:
    grow = sum(1 for x in types if x != "linear_attention")
elif isinstance(n, int) and n > 0:
    grow = n
else:
    sys.exit(0)
heads = t.get("num_attention_heads")
kvh = t.get("num_key_value_heads") or heads
hd = t.get("head_dim")
if not hd and isinstance(heads, int) and heads > 0 and isinstance(t.get("hidden_size"), int):
    hd = t["hidden_size"] // heads
if isinstance(kvh, int) and kvh > 0 and isinstance(hd, int) and hd > 0:
    print("%g" % (grow * 2 * kvh * hd * 2 / 1024))
' "$1/config.json" 2>/dev/null || true
}

# =============================================================================
# Defaults. Each `: "${X:=y}"` means "if X has no value yet, make it y".
# Anything already set by the steps above is left alone.
# =============================================================================

# --- Model -------------------------------------------------------------------
# Which model to serve. Left alone, detection picks a build from the catalog in
# bin/catalog.sh that fits this Mac's memory: the 27B OrcaRouter build at
# 4-bit, 5-bit or 8-bit from 32 GB upward, and the 9B below that.
#
# MODEL_QUANT is the shortcut for "the 27B OrcaRouter build at this many bits":
# 4bit, 5bit, 6bit or 8bit. Set it and MODEL_REPO follows. Set MODEL_REPO
# itself to serve anything else, catalog or not.
if [ -n "${MODEL_QUANT:-}" ]; then
  : "${MODEL_REPO:=${CATALOG_ORCAROUTER_PREFIX}${MODEL_QUANT}}"
else
  : "${MODEL_REPO:=${HW_RECOMMENDED_REPO:-${CATALOG_ORCAROUTER_PREFIX}5bit}}"
fi

# Where the weights live on this Mac. The folder name follows the repository
# name, so downloading a different build never puts it in a folder that claims
# to be a different one. Listed in .gitignore: ~20 GB never goes into git.
#
# One exception, and it is the useful one: when the recommended build is not on
# disk but exactly one other model is, use the one you actually have. Otherwise
# a Mac large enough for 8-bit would report "no model" at the 5-bit weights
# sitting right next to the scripts.
# Any directory holding a config.json and shard files is a model, whoever
# published it — so a 2-bit build, a 9B, or something you fetched by hand is
# found just as readily as the default. If exactly one is present, use it. If
# several are, say nothing: ./bin/models.sh use decides, and guessing between
# them would silently serve a model you did not choose.
#
# A half-downloaded folder counts here on purpose. This step only answers
# "which folder is the model"; whether that folder is WHOLE is model_state's
# question, and the callers that must not proceed on a partial one — start.sh,
# models.sh, serve.sh, bench.sh, doctor.sh — each ask it. Skipping the folder instead
# would point everything at a build that is not there and offer to download a
# different one, when the right answer is to resume this one.
if [ -z "${MODEL_DIR:-}" ] && [ ! -d "$ROOT/$(basename "$MODEL_REPO")" ]; then
  _found=""; _n=0
  for _d in "$ROOT"/*/; do
    _d="${_d%/}"
    if [ "$(model_state "$_d")" != "absent" ]; then
      _found="$_d"; _n=$((_n + 1))
    fi
  done
  if [ "$_n" = "1" ]; then
    MODEL_DIR="$_found"
  fi
  unset _found _n _d
fi
: "${MODEL_DIR:=$ROOT/$(basename "$MODEL_REPO")}"

# The name the server answers to, and the name Claude Code must send.
# For a --model directory this is the directory's own name, nothing else.
# Rename the directory and this name changes with it. Verified.
: "${MODEL_ID:=$(basename "$MODEL_DIR")}"

# MODEL_QUANT now describes the model really selected: the bit-width of an
# OrcaRouter build, or empty for anything else. It is informational from here
# on; nothing below reads it.
case "$(basename "$MODEL_DIR")" in
  *OrcaRouter*-[0-9]bit|*OrcaRouter*-[0-9]Bit) MODEL_QUANT="$(basename "$MODEL_DIR")"; MODEL_QUANT="${MODEL_QUANT##*-}" ;;
  *) MODEL_QUANT="" ;;
esac

# --- Server ------------------------------------------------------------------
# 127.0.0.1 means "this Mac only". The server's own default is 0.0.0.0, which
# means "every network this Mac is on". This override is deliberate and is not
# optional: this checkpoint has had its refusal behavior removed, and the
# server has no password unless API_KEY is set. Keep it on this Mac.
: "${HOST:=127.0.0.1}"
: "${PORT:=11234}"

# How much text the model can hold at once, counted in tokens (roughly
# three quarters of a word each). The model's own maximum is 262144 tokens.
# That does not fit in 36 GB alongside the weights, and neither does 131072 if
# you want to keep using your Mac. 65536 is the safe size on the test machine:
# it costs about 1 GB of memory for the running conversation instead of about
# 2 GB, and still leaves roughly 44,000 tokens of working room after Claude
# Code's own ~21,000-token instructions. Detection raises it on a larger Mac.
: "${CTX_SIZE:=65536}"

# --- Step 6: re-work the memory budget from what is really there -------------
# Two things are only known now: which model is actually selected, and the
# context size after your own overrides. Both change how much memory the server
# will take, so the budget is worked out again from them.
#
# This is what makes `CTX_SIZE=131072 ./bin/serve.sh` safe: it raises the free
# memory the guard demands to match the larger conversation, instead of leaving
# the guard sized for a window you are no longer using. It is also what makes
# `./bin/models.sh use 9b-4bit` safe on a small Mac: the guard shrinks to the
# 9B rather than demanding room for a 27B that is not being loaded.
#
# Settings you chose yourself are never touched.
if [ "${HW_APPLE_SILICON:-no}" = "yes" ]; then
  # Weight size in memory, in GB, for the model actually selected. A catalog
  # build with a known text-only size uses that figure (bin/catalog.sh says
  # which are measured and which are publisher-reported). Anything else is
  # measured from the shards on disk, which is exact for a text-only checkpoint
  # and slightly conservative for one carrying a vision tower — the safe
  # direction to be wrong in. A model not yet downloaded and not in the
  # catalog falls back to the recommended build's figure.
  _w="$(catalog_loaded_gb_for_dir "$(basename "$MODEL_DIR")")"
  if [ -z "$_w" ]; then
    # `|| true` because a model that is not downloaded yet makes find fail,
    # and under pipefail that would end the whole script here, silently.
    _w="$( { find "$MODEL_DIR" -maxdepth 1 -name '*.safetensors' -exec stat -f%z {} + 2>/dev/null || true; } \
          | awk '{s+=$1} END { if (s>0) printf "%.1f", s/1073741824 }')"
  fi
  [ -n "$_w" ] || _w="$HW_WEIGHTS_GB"

  # The per-token KV cost of the model actually selected: its own config.json
  # when it is on disk (a metadata clone already has that file, so a download
  # in progress is judged by its true figure), the catalog's verified copy
  # when it is not, and the recommended build's figure for a model this
  # repository has never heard of and does not have yet. HW_KV_SOURCE says
  # which, so every message that quotes the number can say where it came from.
  _kv="$(model_kv_kib "$MODEL_DIR")"; _kvs="config.json"
  if [ -z "$_kv" ]; then _kv="$(catalog_kv_kib_for_dir "$(basename "$MODEL_DIR")")"; _kvs="catalog"; fi
  if [ -z "$_kv" ]; then _kv="$HW_KV_KIB"; _kvs="assumed from ${HW_RECOMMENDED_KEY}"; fi

  hw_rebudget "$_w" "$CTX_SIZE" "$_kv"
  [ -n "${_YOURS_MIN_FREE_GB:-}" ]      || MIN_FREE_GB="$HW_MIN_FREE_GB"
  [ -n "${_YOURS_MAX_RESIDENT_MEM:-}" ] || MAX_RESIDENT_MEM="$HW_MAX_RESIDENT_MEM"
  [ -n "${_YOURS_PREFIX_CACHE_MEM:-}" ] || PREFIX_CACHE_MEM="$HW_PREFIX_CACHE_MEM"

  # HW_WEIGHTS_GB now names the model in use, not the build recommended, so
  # every message that quotes it quotes the truth. The GPU wired-ceiling check
  # is redone for the same reason: it must judge the weights you really have.
  HW_WEIGHTS_GB="$_w"
  HW_KV_KIB="$_kv"
  # Read by hw_report (detect-hardware.sh), serve.sh and doctor.sh after this
  # file is sourced; shellcheck cannot see across files.
  # shellcheck disable=SC2034
  HW_KV_SOURCE="$_kvs"
  # shellcheck disable=SC2034
  HW_WIRED_OK="$(hw_wired_fits "$_w" "$HW_KV_GB")"
  unset _w _kv _kvs
fi
unset _YOURS_MIN_FREE_GB _YOURS_MAX_RESIDENT_MEM _YOURS_PREFIX_CACHE_MEM

# --- Efficiency --------------------------------------------------------------
# How the running conversation is stored in memory. turbo4 packs it to four
# bits per number after a rotation that spreads out the extreme values first,
# so it costs the same as plain 4-bit storage and loses less accuracy. The
# default is taken from hw_recommend, which is `turbo4` unless you set it, and
# is where it is stated: the memory budget in step 6 was worked out for this
# exact value, and the two must not be able to drift apart. `off` and `8` cost
# four and two times the memory, and the budget follows (docs/07 §3).
: "${KV_QUANT:=$HW_KV_QUANT}"

# The image-reading part of the model costs memory, and Claude Code sends text.
# Set NO_VISION=0 to load it anyway (only needed to feed the model pictures).
: "${NO_VISION:=1}"

# Claude Code resends almost the same block of instructions on every turn.
# Keeping that block's processed form in memory is the single biggest speed win.
# 1536MB rather than 3GB because memory is the scarce resource on a 36 GB Mac;
# the disk tier below recovers most of the benefit for free.
: "${PREFIX_CACHE_MEM:=1536MB}"
# Same thing on the SSD, so it survives a server restart instead of being
# recomputed. Costs disk space, not memory.
: "${PREFIX_CACHE_DISK:=10GB}"

# One model, one copy. Stops an accidental second load from filling memory.
: "${MAX_RESIDENT_MODELS:=1}"

# Hard ceiling on the memory the loaded weights may occupy. Without this the
# server picks 80% of Apple's GPU memory ceiling, which moves whenever that
# setting moves. Pinning it makes the budget explicit.
: "${MAX_RESIDENT_MEM:=21GB}"

# THE setting that makes this usable on a Mac you are also working on. After
# this many seconds with no requests, the server hands the ~19.1 GB back to
# macOS. The next request pays a reload of about a minute. Set 0 to keep the
# model in memory permanently.
: "${IDLE_EVICT_SECS:=900}"

# Seconds the server will wait for a question that is producing NOTHING before
# it gives up on it. A request that keeps generating never times out, however
# long it runs — this is a stall limit, not a length limit.
#
# 300 is the server's own default. It is named here rather than inherited
# because the failure it produces needs a name: Claude Code's own idle limit is
# also 300 seconds, so a first turn that stalls trips both ends at once, and an
# unnamed limit on both sides is indistinguishable from a dead server. Set 0 for
# no limit. See docs/06-troubleshooting.md#slow-first-response.
: "${SERVE_TIMEOUT:=300}"

# How much of your text the server reads at a time on the first pass. A smaller
# number means a smaller temporary memory spike (MEASURED on the 9B: 2.6 GB at
# 4096, 1.1 GB at 1024, 0.7 GB at 512; the read rate did not track the chunk).
# Empty, the default, means the server sizes it when it starts — from the
# memory free at that moment, the context size and the resident cap — and
# prints `Prefill chunk: N tokens (memory-sized down from 8192; ...)` in its
# log: 512 or 1024 on the test machine with the 9B, by what was free. Set a
# number to pin it instead; the server treats that as a ceiling and still caps
# it lower when one layer's attention scores would not fit. Only serve mode
# sizes it: bench.sh's one-shot load reads at the 8192 ceiling unless this is
# set, and says so.
: "${PREFILL_CHUNK:=}"

# Refuse to start the server when less than this much memory is free. This turns
# what would be a stalled Mac into a clear message. Set 0 to bypass (not advised).
: "${MIN_FREE_GB:=22}"

# Refuse to download when less than this much disk is free, worked out for the
# build actually selected by hw_disk_need_gb (bin/detect-hardware.sh), which is
# also where serve.sh's own disk refusal comes from — one function, so the two
# cannot drift. The download peak is about double the final size, because
# git-lfs keeps a second copy of every shard until the last step reclaims it.
# 45 GB for the 5-bit 27B (2 x its 20.0 GB download + 5 spare); 20 GB for the
# 9B, where the 10 GB cache tier the server writes afterwards is the larger of
# the two figures. The DOWNLOAD size is the input here, not the loaded size the
# memory guards use: the vision tower and the tokenizer files land on disk even
# though the server never loads them. Falls back to the reference number on a
# Mac detection cannot size.
if [ "${HW_APPLE_SILICON:-no}" = "yes" ]; then
  _dl="$(catalog_download_gb_for_dir "$(basename "$MODEL_DIR")")"
  [ -n "$_dl" ] || _dl="$HW_WEIGHTS_GB"
  : "${MIN_DISK_GB:=$(hw_disk_need_gb download "$_dl" "$(hw_size_gb "$PREFIX_CACHE_DISK")")}"
  unset _dl
fi
: "${MIN_DISK_GB:=45}"

: "${LOG_LEVEL:=info}"
: "${LOG_FILE:=$HOME/.mlx-serve/logs/mlx-serve-$PORT.log}"

# Where the model lock lives. Only one process on this Mac may hold the weights
# at a time, and this directory is how that is enforced. Not tied to PORT on
# purpose: the danger is two copies of ~19.1 GB in memory, and memory does not
# care which port each one is listening on.
#
# Set this to an empty string to switch the lock off, the way MIN_FREE_GB=0
# switches the memory guard off. Both are for people who know why they want it.
#
# `=` and not `:=` on purpose, and it is the only setting in this file written
# that way: `:=` substitutes on empty as well as on unset, so with a colon here
# `LOCK_DIR= ./bin/serve.sh` would silently get the default back and the guard
# could not be switched off at all.
: "${LOCK_DIR=$HOME/.airgap/model.lock}"

# A password for the server. Empty means no password, which is correct when the
# server only listens on this Mac. Set it if you have a reason to.
: "${API_KEY:=}"

# 1 publishes speed and cache-hit counters at /metrics.
: "${METRICS:=1}"

# Anything you type here is passed to the server exactly as written, after every
# other setting. An escape hatch for a flag this repo has not given a name to.
: "${EXTRA_ARGS:=}"

# 1 makes the download tool reclaim the duplicate copy at the end (~19 GB back).
: "${DEDUP:=1}"

# 1 starts the harness with its MCP/tool servers switched off. What that costs
# is a fact about each harness, so each adapter states its own figure; no
# harness reuses another's. Measured on the test machine: Claude Code's own
# instructions are 20,909 tokens with LEAN_MCP=1 and 38,054 tokens with every
# tool server loaded, so those schemas cost it about 17,000 tokens on EVERY
# turn; the Codex CLI's plugins cost it 935 prompt tokens per turn (9,336
# against 10,271, run.sh --probe on the 9B). Set LEAN_MCP=0 to load your normal
# configuration instead.
: "${LEAN_MCP:=1}"

# --- Tools -------------------------------------------------------------------
# The oldest mlx-serve this repository is known to work with. Not a setting:
# it is a fact about the flags serve.sh passes. Every flag in serve.sh was
# verified against 26.8.8 (AGENT.md, "Verified environment facts"), and an
# older brew build answers an unknown flag with an argparse error after every
# guard has already passed. serve.sh refuses below it and doctor reports it.
# Raise it in the same commit that starts passing a newer flag.
MLX_SERVE_MIN="26.8.8"

: "${CLAUDE_BIN:=claude}"
: "${CODEX_BIN:=codex}"
# PYTHON_BIN (default python3) is set above, with the config.json readers.
# 1 makes setup.sh build the optional Python environment. Nothing in this repo
# needs it; it exists for people who want to poke at the weights themselves.
: "${WITH_VENV:=0}"

# --- Derived -----------------------------------------------------------------
BASE_URL="http://${HOST}:${PORT}"

# The flags that decide how much memory a load takes beyond the weights: the
# context size, the KV format, the prefill chunk (only when pinned), and whether
# the vision tower is loaded. serve.sh passes them to the server and bench.sh
# passes the very same ones to its one-shot load, so the peak memory bench.sh
# reports is a peak reached under the settings the memory guard is sized for.
# One list, here, so the two cannot drift apart. Split on spaces where it is
# used, like EXTRA_ARGS; every value in it is a single word.
LOAD_SHAPE_ARGS="--ctx-size $CTX_SIZE --kv-quant $KV_QUANT"
if [ -n "$PREFILL_CHUNK" ]; then
  LOAD_SHAPE_ARGS="$LOAD_SHAPE_ARGS --prefill-chunk $PREFILL_CHUNK"
fi
if [ "$NO_VISION" = "1" ]; then
  LOAD_SHAPE_ARGS="$LOAD_SHAPE_ARGS --no-vision"
fi

export MODEL_QUANT
export ROOT MODEL_REPO MODEL_DIR MODEL_ID HOST PORT CTX_SIZE KV_QUANT NO_VISION \
       PREFIX_CACHE_MEM PREFIX_CACHE_DISK MAX_RESIDENT_MODELS MAX_RESIDENT_MEM \
       IDLE_EVICT_SECS SERVE_TIMEOUT PREFILL_CHUNK MIN_FREE_GB MIN_DISK_GB LOG_LEVEL LOG_FILE \
       LOCK_DIR API_KEY METRICS EXTRA_ARGS DEDUP LEAN_MCP CLAUDE_BIN CODEX_BIN PYTHON_BIN WITH_VENV \
       BASE_URL MLX_SERVE_MIN

# =============================================================================
# Helpers the other scripts use. You can also call them yourself:
#   bash -c 'source bin/env.sh && echo "$(available_gb) GB available"'
# =============================================================================

# Memory macOS could hand to a new program right now, in GB.
# free + inactive + speculative + purgeable pages. Deliberately leaves out
# wired pages (the kernel's own, never reclaimable) and compressed pages
# (they belong to running programs — a sign of pressure, not spare room).
# Full explanation and the honest caveat live in bin/detect-hardware.sh.
available_gb() { hw_available_gb; }

# Free space on the volume holding $1, in GB. Default: this repository, which
# is where the weights go. The prefix cache's disk tier does not live there —
# it goes under ~/.mlx-serve — so serve.sh asks about $HOME instead. On most
# Macs that is the same volume; on a checkout kept on an external disk it is
# not, and a check against the wrong one would be worthless.
free_disk_gb() {
  df -k "${1:-$ROOT}" 2>/dev/null | awk 'NR==2 { printf "%.1f", $4 / 1048576 }'
}

# The mlx-serve version, e.g. 26.8.8. `mlx-serve --version` prints one line per
# component — "mlx-serve 26.8.8", "mlx 0.32.0", "llama.cpp b10034", … — plus a
# "[mem]" line on stderr; the number is the first line's second field. Prints
# nothing when mlx-serve is missing or answers in a shape this does not know,
# and every caller treats "nothing" as "cannot tell", never as "too old".
mlx_serve_version() {
  command -v mlx-serve >/dev/null 2>&1 || return 0
  mlx-serve --version 2>/dev/null \
    | awk 'NR == 1 { if ($2 ~ /^[0-9]+(\.[0-9]+)*$/) print $2; exit }'
}

# Is version $1 older than version $2? Dot-separated numbers, compared left to
# right, a missing part reading as 0 — so 26.8 is older than 26.8.1. Returns
# success when $1 is older, failure when it is the same or newer.
version_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    n = split(a, x, "."); m = split(b, y, ".")
    k = (n > m ? n : m)
    for (i = 1; i <= k; i++) {
      p = (i <= n ? x[i] + 0 : 0); q = (i <= m ? y[i] + 0 : 0)
      if (p < q) exit 0
      if (p > q) exit 1
    }
    exit 1
  }'
}

# The last $2 (default 12) lines of log file $1, indented by $3. Returns 1 when
# there is no log, so a caller can say so instead of printing a blank heading.
# mlx-serve rotates this file at 32 MB, so it is the tail of the current file,
# not of everything the server has ever written.
log_tail() {
  [ -f "$1" ] || return 1
  tail -n "${2:-12}" "$1" 2>/dev/null | sed "s/^/${3:-  }/"
}

# Did the server that wrote log $1 stop on purpose? "Shutting down gracefully"
# is mlx-serve's own goodbye line. This is what decides whether "nothing is
# running" is an ordinary state or a surprise that needs the log explaining it,
# in stop.sh and in doctor.sh alike.
log_ended_cleanly() {
  [ -f "$1" ] || return 1
  tail -n 5 "$1" 2>/dev/null | grep -q 'Shutting down gracefully'
}

# Is the server answering on this port right now? Returns success or failure,
# prints nothing.
server_up() {
  curl -fsS --max-time 2 "$BASE_URL/health" >/dev/null 2>&1
}

# How long a harness should wait for a silent request, in milliseconds: a
# MINUTE MORE than the server's own SERVE_TIMEOUT, so the server gives up
# first and the side that can name the reason is the side that reports it.
# SERVE_TIMEOUT=0 means the server never gives up; an hour is the client's
# bound then, not a promise about the server.
#
# This is the number, not the way a harness is told about it: a harness that
# floors or ceilings it does that in its own adapter (Claude Code 2.1.233
# resolves its variable through Math.max(value, 300000), so it can only ever
# raise the limit — a fact about that binary, not a rule of this stack).
client_timeout_ms() {
  if [ "${SERVE_TIMEOUT:-300}" = "0" ]; then
    echo 3600000
  else
    echo $(( (SERVE_TIMEOUT + 60) * 1000 ))
  fi
}

# The counters named in $@, read from $BASE_URL/metrics.json in ONE fetch and
# printed space-separated in the order they were asked for. A counter the
# server does not report reads as 0, because "the server has never done this"
# and "this server does not count it" are the same answer to a caller adding
# up tokens.
#
# Prints nothing and returns 1 when the endpoint does not answer 200 at all,
# or answers in a shape this cannot read. WHY it did not answer — metrics
# switched off (503), no server (000), something else — is a second question,
# and only bin/doctor.sh asks it, on this failure path, so the happy path
# stays at one request.
metrics_counters() {
  [ "$#" -gt 0 ] || return 1
  command -v "$PYTHON_BIN" >/dev/null 2>&1 || return 1

  if [ -n "${API_KEY:-}" ]; then
    _mc_out="$(curl -sS --max-time 5 -w '\n%{http_code}' -H "x-api-key: $API_KEY" "$BASE_URL/metrics.json" 2>/dev/null || true)"
  else
    _mc_out="$(curl -sS --max-time 5 -w '\n%{http_code}' "$BASE_URL/metrics.json" 2>/dev/null || true)"
  fi
  _mc_code="${_mc_out##*$'\n'}"
  _mc_json="${_mc_out%$'\n'*}"
  if [ "$_mc_code" != "200" ]; then
    unset _mc_out _mc_code _mc_json
    return 1
  fi

  printf '%s' "$_mc_json" | "$PYTHON_BIN" -c '
import json, sys
try:
    c = json.load(sys.stdin).get("counters", {})
except Exception:
    sys.exit(1)
print(" ".join(str(c.get(n, 0)) for n in sys.argv[1:]))
' "$@" 2>/dev/null || { unset _mc_out _mc_code _mc_json; return 1; }
  unset _mc_out _mc_code _mc_json
}

# --- The model lock ----------------------------------------------------------
# Only one process on this Mac may hold the weights. Every other concurrency
# check in this repo is scoped to a PORT, and a port cannot see the thing that
# actually hurts: mlx-serve binds its socket BEFORE it loads, so a second server
# started on a different port passes every check and then puts a second ~19.1 GB
# into a 36 GB Mac. bench.sh passes no --port at all, so two bench runs cannot
# see each other either.
#
# mkdir is the mutex. It is atomic on every filesystem macOS mounts, and
# flock(1) does not exist here. The holder's pid goes inside, so a lock left by
# a crash can be told apart from a lock held by a live process.
#
# Deliberately NOT /tmp/ds4.lock: the mlx-serve binary embeds ds4's own instance
# lock and that literal path. Two locks fighting over one directory would be
# worse than no lock at all.

# The pid recorded in the lock, or nothing.
model_lock_pid() {
  [ -n "${LOCK_DIR:-}" ] || return 1
  cat "$LOCK_DIR/pid" 2>/dev/null
}

# What the holder said it was doing, or a neutral phrase.
model_lock_what() {
  [ -n "${LOCK_DIR:-}" ] || return 1
  cat "$LOCK_DIR/what" 2>/dev/null || echo "a model process"
}

# Is the recorded holder still running? `kill -0` signals nothing; it only asks.
model_lock_alive() {
  _lp="$(model_lock_pid || true)"
  [ -n "${_lp:-}" ] || return 1
  kill -0 "$_lp" 2>/dev/null
}

# Take the lock, or fail. $1 describes the caller, for the refusal message.
#
# A lock whose holder is gone is reclaimed rather than obeyed: a SIGKILL during
# a load must never leave this Mac unable to start a server again. The reclaim
# is not atomic against a second process reclaiming the same stale lock at the
# same instant — that is a two-Terminal-windows race measured in microseconds,
# and the cost of losing it is the memory guard doing its job one step later.
acquire_model_lock() {
  [ -n "${LOCK_DIR:-}" ] || return 0
  mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true

  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    model_lock_alive && return 1
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || return 1
  fi

  echo "$$" > "$LOCK_DIR/pid" 2>/dev/null || true
  printf '%s\n' "${1:-a model process}" > "$LOCK_DIR/what" 2>/dev/null || true
  LOCK_HELD=1

  # serve.sh ends in `exec`, which keeps this same pid, so the lock stays
  # correct for the whole life of the server and this trap never fires there.
  # It matters for every other caller, and for a guard below that exits.
  trap 'release_model_lock' EXIT INT TERM
  return 0
}

# Give the lock back, but only if this process is really the one holding it.
release_model_lock() {
  [ "${LOCK_HELD:-0}" = "1" ] || return 0
  [ -n "${LOCK_DIR:-}" ] || return 0
  if [ "$(cat "$LOCK_DIR/pid" 2>/dev/null || echo)" = "$$" ]; then
    rm -rf "$LOCK_DIR" 2>/dev/null || true
  fi
  LOCK_HELD=0
}

# Remove a lock whose holder is gone. Never touches a live one. Returns success
# only when something was actually cleared, so callers can report it.
clear_stale_model_lock() {
  [ -n "${LOCK_DIR:-}" ] || return 1
  [ -d "$LOCK_DIR" ] || return 1
  model_lock_alive && return 1
  rm -rf "$LOCK_DIR" 2>/dev/null || return 1
  return 0
}

# If somebody runs this file directly, explain what it is instead of doing
# nothing silently.
_env_sourced=0
if [ -n "${ZSH_EVAL_CONTEXT:-}" ]; then
  case "$ZSH_EVAL_CONTEXT" in *:file) _env_sourced=1 ;; esac
elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
  _env_sourced=1
fi

if [ "$_env_sourced" = "0" ]; then
  cat <<EOF
env.sh — shared settings. You do not run this file; the other scripts read it.

To change a setting, do one of these:
  once      CTX_SIZE=32768 ./bin/serve.sh
  always    copy config.env.example to config.env and edit that file

To see what this Mac was measured as:
  ./bin/detect-hardware.sh

Current values on this Mac:
  MODEL_DIR         $MODEL_DIR
  MODEL_ID          $MODEL_ID
  HOST:PORT         $HOST:$PORT
  CTX_SIZE          $CTX_SIZE
  MIN_FREE_GB       $MIN_FREE_GB
  MAX_RESIDENT_MEM  $MAX_RESIDENT_MEM
  PREFIX_CACHE_MEM  $PREFIX_CACHE_MEM

Read next: docs/07-tuning.md
EOF
fi
