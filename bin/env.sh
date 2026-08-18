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
LOCK_DIR API_KEY METRICS EXTRA_ARGS DEDUP LEAN_MCP CLAUDE_BIN PYTHON_BIN WITH_VENV \
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
  fi
  unset _found _n _d _w
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

  hw_rebudget "$_w" "$CTX_SIZE"
  [ -n "${_YOURS_MIN_FREE_GB:-}" ]      || MIN_FREE_GB="$HW_MIN_FREE_GB"
  [ -n "${_YOURS_MAX_RESIDENT_MEM:-}" ] || MAX_RESIDENT_MEM="$HW_MAX_RESIDENT_MEM"
  [ -n "${_YOURS_PREFIX_CACHE_MEM:-}" ] || PREFIX_CACHE_MEM="$HW_PREFIX_CACHE_MEM"

  # HW_WEIGHTS_GB now names the model in use, not the build recommended, so
  # every message that quotes it quotes the truth. The GPU wired-ceiling check
  # is redone for the same reason: it must judge the weights you really have.
  HW_WEIGHTS_GB="$_w"
  # Read by hw_report (detect-hardware.sh) and doctor.sh after this file is
  # sourced; shellcheck cannot see across files.
  # shellcheck disable=SC2034
  HW_WIRED_OK="$(hw_wired_fits "$_w" "$HW_KV_GB")"
  unset _w
fi
unset _YOURS_MIN_FREE_GB _YOURS_MAX_RESIDENT_MEM _YOURS_PREFIX_CACHE_MEM

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

# Refuse to download when less than this much disk is free. The download tool
# keeps a second copy of every file until the last step reclaims it, so the
# peak requirement is about double the final size.
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
       LOCK_DIR API_KEY METRICS EXTRA_ARGS DEDUP LEAN_MCP CLAUDE_BIN PYTHON_BIN WITH_VENV \
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
