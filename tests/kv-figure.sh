#!/usr/bin/env bash
# Checks the per-model KV-cache figure (AUDIT.md F5): the guards used to charge
# every model the 27B's 64 KiB per token at 4 bits, whatever the checkpoint
# and whatever KV_QUANT said. Now the per-token cost is read from the model's
# own config.json (model_kv_kib in bin/env.sh), the catalog carries a verified
# copy for builds not on disk, and hw_rebudget (bin/detect-hardware.sh) scales
# it by KV_QUANT's bit-width. This holds:
#   - the KV_QUANT name -> bits map, unknown names reading as the largest
#   - the reference budget on 36 GB is unchanged (22 / 21GB / 1536MB)
#   - the reader on hybrid, dense, derived-head_dim, unfamiliar and broken shapes
#   - every catalog entry carries a numeric figure
#   - env.sh's cascade: config.json first, then the catalog, then "assumed"
#
# Usage, from the repo root:  bash tests/kv-figure.sh
# Needs bash and python3. No server, no weights, no network. The env.sh cases
# read this Mac's memory, so they run on macOS only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

check() {  # check <label> <want> <got>
  if [ "$3" = "$2" ]; then
    printf 'ok    %-30s %s\n' "$1" "$3"
  else
    printf 'FAIL  %-30s expected %s, got %s\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}

# --- the memory model on its own: bits, and the reference budget ------------
# hw_rebudget reads HW_RAM_GB and HW_KV_QUANT from the environment, so both
# are pinned here; sourcing detect-hardware.sh runs nothing.
hw() {  # hw <HW_KV_QUANT> <weights_gb> <ctx> <kib> -> "kv minfree mrm pfx"
  HW_KV_QUANT="$1" HW_RAM_GB=36 bash -c "source '$ROOT/bin/detect-hardware.sh' \
    && hw_rebudget $2 $3 $4 && printf '%s %s %s %s' \"\$HW_KV_GB\" \"\$HW_MIN_FREE_GB\" \"\$HW_MAX_RESIDENT_MEM\" \"\$HW_PREFIX_CACHE_MEM\""
}
bits() { bash -c "source '$ROOT/bin/detect-hardware.sh' && hw_kv_bits '$1'"; }

check "bits off"        16 "$(bits off)"
check "bits 8"          8  "$(bits 8)"
check "bits 4"          4  "$(bits 4)"
check "bits turbo4"     4  "$(bits turbo4)"
check "bits turbo2"     2  "$(bits turbo2)"
check "bits unknown"    16 "$(bits fancy9)"

# The committed reference configuration: 27B 5-bit on 36 GB, 65536 tokens,
# turbo4. Change a number in hw_rebudget and this is what has to still hold.
check "reference 27B turbo4"  "1.00 22 21GB 1536MB" "$(hw turbo4 19.1 65536 64)"
check "9B is half"            "0.50"                "$(hw turbo4 4.7  65536 32 | cut -d' ' -f1)"
check "off is 4x"             "4.00 24 21GB 768MB"  "$(hw off    19.1 65536 64)"
check "8 is 2x"               "2.00"                "$(hw 8      19.1 65536 64 | cut -d' ' -f1)"
check "131072 tokens, off"    "8.00"                "$(hw off    19.1 131072 64 | cut -d' ' -f1)"
check "dense 64-layer, off"   "16.00"               "$(hw off    19.1 65536 256 | cut -d' ' -f1)"
# No figure at all is a loud failure, never a silent zero-cost conversation.
got="$(HW_KV_QUANT=turbo4 HW_RAM_GB=36 bash -c "source '$ROOT/bin/detect-hardware.sh' && hw_rebudget 19.1 65536 '' 2>/dev/null; echo \"rc=\$?\"")"
check "empty figure refused"   "rc=1"                "$got"

# --- the reader ---------------------------------------------------------------
# model_kv_kib from a shell that has sourced env.sh. LOCK_DIR is emptied so
# nothing here can touch the real lock, and MODEL_DIR is pinned so env.sh's
# own discovery cannot wander into the checkout's real models.
ask() {
  env -i HOME="$HOME" PATH="$PATH" LOCK_DIR= MODEL_DIR="${2:-$TMP/none}" ${3:-} \
    bash -c "source '$ROOT/bin/env.sh' && $1"
}
shape() {  # shape <name> <json>  -> writes $TMP/<name>/config.json
  mkdir -p "$TMP/$1"; printf '%s' "$2" > "$TMP/$1/config.json"
}
types() {  # types <full> <linear> -> a JSON layer_types list
  python3 -c 'import json,sys; print(json.dumps(["full_attention"]*int(sys.argv[1]) + ["linear_attention"]*int(sys.argv[2])))' "$1" "$2"
}

# The two catalog architectures, as their config.json files state them.
shape qwen27b "{\"text_config\":{\"num_hidden_layers\":64,\"layer_types\":$(types 16 48),\"num_attention_heads\":24,\"num_key_value_heads\":4,\"head_dim\":256}}"
shape qwen9b  "{\"text_config\":{\"num_hidden_layers\":32,\"layer_types\":$(types 8 24),\"num_attention_heads\":16,\"num_key_value_heads\":4,\"head_dim\":256}}"
# An ordinary dense model: no layer_types, so every layer grows a cache.
shape dense   '{"num_hidden_layers":64,"num_attention_heads":24,"num_key_value_heads":4,"head_dim":256}'
# No head_dim and no grouped-query heads: hidden/heads and heads, as loaders do.
shape derived '{"num_hidden_layers":32,"num_attention_heads":32,"hidden_size":4096}'
# A layer kind this repository has not met counts as growing (over-charges).
shape unknown "{\"text_config\":{\"num_hidden_layers\":4,\"layer_types\":[\"sliding_attention\",\"linear_attention\",\"full_attention\",\"linear_attention\"],\"num_attention_heads\":8,\"num_key_value_heads\":2,\"head_dim\":128}}"
# Nothing to compute from, and not JSON at all: both print nothing.
shape bare    '{"model_type":"qwen3_5"}'
shape broken  'not json {'

check "27B shape"           64   "$(ask "model_kv_kib '$TMP/qwen27b'")"
check "9B shape"            32   "$(ask "model_kv_kib '$TMP/qwen9b'")"
check "dense, no layer_types" 256 "$(ask "model_kv_kib '$TMP/dense'")"
check "derived head_dim"    512  "$(ask "model_kv_kib '$TMP/derived'")"
check "unknown kind grows"  2    "$(ask "model_kv_kib '$TMP/unknown'")"
check "no shape keys"       ""   "$(ask "model_kv_kib '$TMP/bare'")"
check "not json"            ""   "$(ask "model_kv_kib '$TMP/broken'")"
check "no such directory"   ""   "$(ask "model_kv_kib '$TMP/absent'")"

# --- the catalog ------------------------------------------------------------
# Every entry carries a per-token figure, and it is a number. (The values were
# verified against each repository's config.json on huggingface.co on
# 2026-08-18; that check needs the network and is not repeated here.)
bad="$(bash -c "source '$ROOT/bin/catalog.sh' && printf '%s\n' \"\$CATALOG\"" \
       | awk -F'|' 'NF > 1 && $5 !~ /^[0-9]+(\.[0-9]+)?$/ { print $1 }')"
check "catalog kv column"   ""   "$bad"

# --- the cascade through env.sh -----------------------------------------------
# HW_KV_KIB and HW_KV_SOURCE are what every message quotes. A dense 64-layer
# checkpoint on disk is read from its config.json, at 16 bits it costs 16 GB
# for the default window; a catalog build not on disk gets the catalog figure;
# a folder this repository has never heard of gets the recommended build's,
# and says so.
show='printf "%s %s %s" "$HW_KV_KIB" "$HW_KV_GB" "$HW_KV_SOURCE"'
check "on disk: config.json"   "256 16.00 config.json" "$(ask "$show" "$TMP/dense" "KV_QUANT=off CTX_SIZE=65536")"
check "not on disk: catalog"   "32 0.50 catalog"       "$(ask "$show" "$TMP/Qwen3.8-9B-mlx-4Bit" "KV_QUANT=turbo4 CTX_SIZE=65536")"
check "unknown folder: assumed" "assumed"              "$(ask "$show" "$TMP/Nobody-Knows-This" "" | awk '{print $3}')"
# And KV_QUANT's default is the value the budget was worked out for.
check "KV_QUANT default"       "turbo4"                "$(ask 'printf "%s" "$KV_QUANT"')"

if [ "$failures" -eq 0 ]; then
  echo "kv-figure: per-model, per-KV_QUANT"
else
  echo "kv-figure: $failures FAILED" >&2
  exit 1
fi
