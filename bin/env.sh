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
ENV_KEYS="MODEL_REPO MODEL_DIR MODEL_ID HOST PORT CTX_SIZE KV_QUANT NO_VISION \
PREFIX_CACHE_MEM PREFIX_CACHE_DISK MAX_RESIDENT_MODELS MAX_RESIDENT_MEM \
IDLE_EVICT_SECS PREFILL_CHUNK MIN_FREE_GB MIN_DISK_GB LOG_LEVEL LOG_FILE \
API_KEY METRICS EXTRA_ARGS DEDUP LEAN_MCP CLAUDE_BIN PYTHON_BIN WITH_VENV \
CLAUDE_CODE_MAX_OUTPUT_TOKENS PROBE SKIP_BREW TOKENS PROMPT"

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
# and HW_PREFIX_CACHE_MEM. It writes only HW_* names, so it can never overwrite
# something you set in step 2 or step 3. On the 36 GB test machine it proposes
# exactly the reference numbers below. On a different Mac it proposes numbers
# that fit that Mac.
#
# Remember which of the four budget settings you had already chosen, so the
# re-budget in step 6 leaves your choices alone.
for _k in CTX_SIZE MIN_FREE_GB MAX_RESIDENT_MEM PREFIX_CACHE_MEM; do
  eval "_YOURS_${_k}=\${${_k}+1}"
done
unset _k

# shellcheck source=bin/detect-hardware.sh
source "$ROOT/bin/detect-hardware.sh"
hw_recommend

# An impossible machine gets no detected settings at all — HW_CTX_SIZE and the
# rest are 0, which is not a usable size, and MIN_FREE_GB=0 in particular is
# this repo's way of switching the memory guard OFF. Fall through to the
# reference defaults instead. serve.sh, download-model.sh, setup.sh and
# doctor.sh all refuse on HW_VERDICT, which is the honest place to stop.
if [ "${HW_VERDICT:-}" != "impossible" ]; then
  : "${CTX_SIZE:=$HW_CTX_SIZE}"
fi

# =============================================================================
# Defaults. Each `: "${X:=y}"` means "if X has no value yet, make it y".
# Anything already set by the steps above is left alone.
# =============================================================================

# --- Model -------------------------------------------------------------------
# Which build of the checkpoint to use: 4bit, 5bit or 8bit. All three exist on
# huggingface.co. Detection picks the largest one this Mac has memory for.
: "${MODEL_QUANT:=${HW_QUANT_SUFFIX:-5bit}}"

# The HuggingFace repository that bin/download-model.sh clones. download-model.sh
# checks the name against huggingface.co before it downloads anything, and fails
# in about two seconds with a copy-paste fix if the name is wrong.
: "${MODEL_REPO:=chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-${MODEL_QUANT}}"

# Where the weights live on this Mac. The folder name follows the repository
# name, so downloading a different build never puts it in a folder that claims
# to be a different one. Listed in .gitignore: ~20 GB never goes into git.
#
# One exception, and it is the useful one: when the recommended build is not on
# disk but exactly one other build of this checkpoint is, use the one you
# actually have. Otherwise a Mac large enough for 8-bit would report "no model"
# at the 5-bit weights sitting right next to the scripts.
# Any directory holding a config.json and a real (non-pointer) .safetensors is a
# usable model, whoever published it — so a 2-bit build, a 9B, or something you
# fetched by hand is found just as readily as the default. If exactly one is
# present, use it. If several are, say nothing: ./bin/models.sh use decides, and
# guessing between them would silently serve a model you did not choose.
if [ -z "${MODEL_DIR:-}" ] && [ ! -d "$ROOT/$(basename "$MODEL_REPO")" ]; then
  _found=""; _n=0
  for _d in "$ROOT"/*/; do
    _d="${_d%/}"
    [ -f "$_d/config.json" ] || continue
    for _w in "$_d"/*.safetensors; do
      [ -f "$_w" ] || continue
      if [ "$(stat -f%z "$_w" 2>/dev/null || echo 0)" -gt 1000000 ]; then
        _found="$_d"; _n=$((_n + 1))
      fi
      break
    done
  done
  if [ "$_n" = "1" ]; then
    MODEL_DIR="$_found"
    case "$(basename "$_found")" in
      *-[0-9]bit|*-[0-9]Bit) MODEL_QUANT="$(basename "$_found")"; MODEL_QUANT="${MODEL_QUANT##*-}" ;;
    esac
  fi
  unset _found _n _d _w
fi
: "${MODEL_DIR:=$ROOT/$(basename "$MODEL_REPO")}"

# The name the server answers to, and the name Claude Code must send.
# For a --model directory this is the directory's own name, nothing else.
# Rename the directory and this name changes with it. Verified.
: "${MODEL_ID:=$(basename "$MODEL_DIR")}"

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
# Two things are only known now: which build of the weights is actually on disk,
# and the context size after your own overrides. Both change how much memory the
# server will take, so the budget is worked out again from them.
#
# This is what makes `CTX_SIZE=131072 ./bin/serve.sh` safe: it raises the free
# memory the guard demands to match the larger conversation, instead of leaving
# the guard sized for a window you are no longer using.
#
# Settings you chose yourself are never touched.
if [ "${HW_VERDICT:-}" != "impossible" ]; then
  # Weight size in memory, in GB. Taken from the build that is really on disk,
  # named by the last part of the folder name, so the budget follows the weights
  # you have rather than the ones this Mac was advised to get. The figures are
  # text-only: the image-reading part is on disk but is not loaded.
  # Add up the shards on disk instead and you would over-count by that part.
  case "$(basename "$MODEL_DIR")" in
    *-4bit|*-4BIT) _w="$HW_WEIGHTS_GB_4BIT" ;;
    *-5bit|*-5BIT) _w="$HW_WEIGHTS_GB_5BIT" ;;
    *-8bit|*-8BIT) _w="$HW_WEIGHTS_GB_8BIT" ;;
    *)             _w="${HW_WEIGHTS_GB:-$HW_WEIGHTS_GB_5BIT}" ;;
  esac

  hw_rebudget "$_w" "$CTX_SIZE"
  [ -n "${_YOURS_MIN_FREE_GB:-}" ]      || MIN_FREE_GB="$HW_MIN_FREE_GB"
  [ -n "${_YOURS_MAX_RESIDENT_MEM:-}" ] || MAX_RESIDENT_MEM="$HW_MAX_RESIDENT_MEM"
  [ -n "${_YOURS_PREFIX_CACHE_MEM:-}" ] || PREFIX_CACHE_MEM="$HW_PREFIX_CACHE_MEM"

  # HW_WEIGHTS_GB now names the build in use, not the build recommended, so
  # every message that quotes it quotes the truth. The GPU wired-ceiling check
  # is redone for the same reason: it must judge the weights you really have.
  HW_WEIGHTS_GB="$_w"
  HW_WIRED_OK="$(awk -v w="$_w" -v kv="$HW_KV_GB" -v lim="$HW_WIRED_AUTO_GB" \
    'BEGIN { print (w + kv <= lim) ? "yes" : "no" }')"
  unset _w
fi
unset _YOURS_CTX_SIZE _YOURS_MIN_FREE_GB _YOURS_MAX_RESIDENT_MEM _YOURS_PREFIX_CACHE_MEM

# --- Efficiency --------------------------------------------------------------
# How the running conversation is stored in memory. turbo4 packs it to four
# bits per number after a rotation that spreads out the extreme values first,
# so it costs the same as plain 4-bit storage and loses less accuracy.
: "${KV_QUANT:=turbo4}"

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

# How much of your text the server reads at a time on the first pass. A smaller
# number means a smaller temporary memory spike, at a small speed cost.
: "${PREFILL_CHUNK:=4096}"

# Refuse to start the server when less than this much memory is free. This turns
# what would be a stalled Mac into a clear message. Set 0 to bypass (not advised).
: "${MIN_FREE_GB:=22}"

# Refuse to download when less than this much disk is free. The download tool
# keeps a second copy of every file until the last step reclaims it, so the
# peak requirement is about double the final size.
: "${MIN_DISK_GB:=45}"

: "${LOG_LEVEL:=info}"
: "${LOG_FILE:=$HOME/.mlx-serve/logs/mlx-serve-$PORT.log}"

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

# 1 starts Claude Code with its extra tool servers switched off. Measured on the
# test machine: Claude Code's instructions are 20,909 tokens that way and 38,054
# tokens with every tool server loaded. Those schemas cost about 17,000 tokens
# on EVERY turn. Set LEAN_MCP=0 to load your normal configuration instead.
: "${LEAN_MCP:=1}"

# --- Tools -------------------------------------------------------------------
: "${CLAUDE_BIN:=claude}"
: "${PYTHON_BIN:=python3}"
# 1 makes setup.sh build the optional Python environment. Nothing in this repo
# needs it; it exists for people who want to poke at the weights themselves.
: "${WITH_VENV:=0}"

# --- Derived -----------------------------------------------------------------
BASE_URL="http://${HOST}:${PORT}"

export MODEL_QUANT
export ROOT MODEL_REPO MODEL_DIR MODEL_ID HOST PORT CTX_SIZE KV_QUANT NO_VISION \
       PREFIX_CACHE_MEM PREFIX_CACHE_DISK MAX_RESIDENT_MODELS MAX_RESIDENT_MEM \
       IDLE_EVICT_SECS PREFILL_CHUNK MIN_FREE_GB MIN_DISK_GB LOG_LEVEL LOG_FILE \
       API_KEY METRICS EXTRA_ARGS DEDUP LEAN_MCP CLAUDE_BIN PYTHON_BIN WITH_VENV \
       BASE_URL

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

# Free space on the disk holding this repo, in GB.
free_disk_gb() {
  df -k "$ROOT" 2>/dev/null | awk 'NR==2 { printf "%.1f", $4 / 1048576 }'
}

# Is the server answering on this port right now? Returns success or failure,
# prints nothing.
server_up() {
  curl -fsS --max-time 2 "$BASE_URL/health" >/dev/null 2>&1
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
