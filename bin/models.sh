#!/usr/bin/env bash
# bin/models.sh — see which models you can run, get one, and choose which to serve.
#
#   ./bin/models.sh list          what exists, what fits, what you already have
#   ./bin/models.sh pull 27b-4bit download one
#   ./bin/models.sh use  27b-4bit serve that one from now on
#   ./bin/models.sh which         which one is selected right now
#
# Nothing here loads a model or starts the server. `pull` downloads; everything
# else only reads and writes a one-line setting.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]:-$0}")/env.sh"

# The catalog itself lives in bin/catalog.sh (one list, shared with
# bin/detect-hardware.sh and bin/env.sh). The free memory each build needs is
# not stored anywhere: it is computed below for THIS Mac by hw_rebudget, the
# same function bin/serve.sh uses to decide whether to start, so the number
# `list` prints is the number `serve.sh` will insist on.

usage() {
  cat <<'EOF'
models.sh — choose which model to run.

WHAT IT DOES
  Keeps a short list of Qwen3.8 builds in MLX format that are known to exist,
  with their real download size and the free memory each one needs on YOUR
  Mac — the same figure ./bin/serve.sh enforces before it starts. You do not
  have to go and find them on huggingface.co yourself.

WHAT IT COSTS
  list, use, which  nothing. They read, and write one line of settings.
  pull              a download, between 4.7 GB and 29.1 GB. Nothing is deleted.
                    (The sizes are in bin/catalog.sh, read from huggingface.co.)

USAGE (run from the repo root)
  ./bin/models.sh list           show the catalog, marked up for YOUR Mac
  ./bin/models.sh pull <key>     download one (safe to re-run; it resumes)
  ./bin/models.sh use <key>      serve that one from now on
  ./bin/models.sh which          show the selected model
  ./bin/models.sh --help         print this help

  <key> is the short name in the first column of `list`, e.g. 27b-4bit.

TYPICAL USE
  The 27B feels too tight on your Mac, so you drop to a smaller build:
      ./bin/stop.sh
      ./bin/models.sh pull 27b-4bit
      ./bin/models.sh use  27b-4bit
      ./bin/serve.sh

  Downloaded models are kept, so switching back is instant:
      ./bin/models.sh use 27b-5bit

A MODEL NOT ON THE LIST
  Any MLX model directory works. Download it with:
      ./bin/download-model.sh <org>/<repo>
  and select it with:
      ./bin/models.sh use <org>/<repo>

WHAT YOU SHOULD SEE
  `list` prints one row per model. The marks mean:
      ->  selected right now        ok    fits this Mac
      *   downloaded already        TIGHT close everything else first
                                    NO    serve.sh would refuse: the weights do
                                          not fit under this Mac's GPU ceiling

READ NEXT
  docs/03-get-the-model.md
EOF
}

# --- helpers -----------------------------------------------------------------

# Resolve a key OR a raw <org>/<repo> into a repo id.
resolve_repo() {
  case "$1" in
    */*) printf '%s\n' "$1"; return 0 ;;
  esac
  line="$(catalog_line "$1")"
  if [ -z "$line" ]; then
    echo "models.sh: '$1' is not in the catalog." >&2
    echo "           Run './bin/models.sh list' to see the keys," >&2
    echo "           or pass a full address like chimingw/Qwen3.8-27B-...-MLX-4bit" >&2
    exit 1
  fi
  printf '%s\n' "$line" | cut -d'|' -f2
}

# Is a model directory present and actually populated (not lfs pointers)?
is_downloaded() {
  d="$ROOT/$(basename "$1")"
  [ -f "$d/config.json" ] || return 1
  for f in "$d"/*.safetensors; do
    [ -f "$f" ] || return 1
    [ "$(stat -f%z "$f" 2>/dev/null || echo 0)" -gt 1000000 ] && return 0
    return 1
  done
  return 1
}

# --- subcommands -------------------------------------------------------------

cmd_list() {
  ram="${HW_RAM_GB:-0}"
  echo "Qwen3.8 for Apple Silicon, in MLX format. Abliterated unless marked [stock]."
  echo "Your Mac has ${ram} GB of memory. \"needs\" is the free memory ./bin/serve.sh will"
  echo "insist on for that build at a ${CTX_SIZE}-token window, worked out for this Mac:"
  echo "     ok = comfortable      TIGHT = close everything first      NO = will not fit under the GPU ceiling"
  echo

  printf '%s\n' "$CATALOG" | while IFS='|' read -r k repo gb loaded abl note; do
    [ -z "$k" ] && continue

    mark="   "
    is_downloaded "$repo" && mark="  *"
    [ "$(basename "$MODEL_DIR")" = "$(basename "$repo")" ] && mark=" ->"

    # The same arithmetic serve.sh enforces, for this build on this Mac.
    [ -n "$loaded" ] || loaded="$gb"
    hw_fit_mark "$loaded" "$CTX_SIZE"
    fit="$HW_FIT_MARK"; need="$HW_MIN_FREE_GB"

    tag=""; [ "$abl" = "no" ] && tag="  [stock]"
    printf '%s %-14s %5s GB   needs %2s GB free   %-5s%s\n' \
           "$mark" "$k" "$gb" "$need" "$fit" "$tag"
    printf '    %s\n\n' "$note"
  done

  echo "  -> selected now      * already downloaded"
  echo
  echo "  ./bin/models.sh pull <key>     download one"
  echo "  ./bin/models.sh use  <key>     serve it from now on"
}

cmd_pull() {
  [ $# -ge 1 ] || { echo "models.sh: pull needs a key, e.g. ./bin/models.sh pull 27b-4bit" >&2; exit 2; }
  repo="$(resolve_repo "$1")"
  echo "pulling $repo"
  echo
  MODEL_REPO="$repo" MODEL_DIR="$ROOT/$(basename "$repo")" "$ROOT/bin/download-model.sh" "$repo"
  echo
  echo "next: ./bin/models.sh use $1"
}

cmd_use() {
  [ $# -ge 1 ] || { echo "models.sh: use needs a key, e.g. ./bin/models.sh use 27b-4bit" >&2; exit 2; }
  repo="$(resolve_repo "$1")"
  dir="$ROOT/$(basename "$repo")"

  if ! is_downloaded "$repo"; then
    echo "models.sh: '$1' is not downloaded yet." >&2
    echo "           get it first:  ./bin/models.sh pull $1" >&2
    exit 1
  fi

  cfg="$ROOT/config.env"
  [ -f "$cfg" ] || { echo "# Written by ./bin/models.sh. Safe to edit by hand." > "$cfg"; }

  # Replace any existing MODEL_REPO line, then append ours. Keeps the rest of
  # config.env untouched, so your other settings survive a model switch.
  # MODEL_DIR and MODEL_QUANT lines are dropped too: either one would override
  # the selection and make `use` a silent no-op.
  dropped=""
  if grep -q '^[[:space:]]*MODEL_DIR=' "$cfg" 2>/dev/null;   then dropped="${dropped} MODEL_DIR"; fi
  if grep -q '^[[:space:]]*MODEL_QUANT=' "$cfg" 2>/dev/null; then dropped="${dropped} MODEL_QUANT"; fi
  tmp="$(mktemp)"
  grep -v -e '^[[:space:]]*MODEL_REPO=' -e '^[[:space:]]*MODEL_DIR=' -e '^[[:space:]]*MODEL_QUANT=' "$cfg" > "$tmp" 2>/dev/null || true
  printf 'MODEL_REPO=%s\n' "$repo" >> "$tmp"
  mv "$tmp" "$cfg"

  echo "selected $(basename "$repo")"
  echo "  repo   $repo"
  echo "  folder $dir"
  echo "  saved  config.env${dropped:+ (removed the${dropped} line(s), which would have overridden this)}"
  echo
  if server_up; then
    echo "The server is still running the OLD model. To switch:"
    echo "    ./bin/stop.sh && ./bin/serve.sh"
  else
    echo "next: ./bin/serve.sh"
  fi
}

cmd_which() {
  echo "selected  $(basename "$MODEL_DIR")"
  echo "repo      $MODEL_REPO"
  echo "folder    $MODEL_DIR"
  if is_downloaded "$MODEL_REPO"; then
    echo "state     downloaded"
  else
    echo "state     NOT downloaded — ./bin/models.sh pull $MODEL_REPO"
  fi
}

case "${1:-list}" in
  -h|--help|help) usage ;;
  list)  cmd_list ;;
  pull)  shift; cmd_pull "$@" ;;
  use)   shift; cmd_use "$@" ;;
  which) cmd_which ;;
  *) echo "models.sh: I do not understand '$1'. Try: ./bin/models.sh --help" >&2; exit 2 ;;
esac
