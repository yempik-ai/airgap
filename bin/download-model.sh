#!/usr/bin/env bash
# bin/download-model.sh — get the weights, correctly.
#
# The weights are the model's numbers: 4.7 GB to 29 GB of them depending on the
# build, about 20 GB for the default 5-bit 27B. They are stored on
# huggingface.co and downloaded with git, but ordinary git does NOT download
# them. It downloads 135-byte text files that point at them, and it reports
# success while doing so. This script makes that impossible.
#
# It never starts the server.
#
# Read docs/03-get-the-model.md for the same steps with the reasoning.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

usage() {
  cat <<'EOF'
download-model.sh — download the model's weights with git-lfs.

WHAT IT DOES
  1. Checks git-lfs is installed and switched on.
  2. Checks the model's address really exists, BEFORE downloading anything,
     asks huggingface.co how big it is, and refuses if those weights cannot
     fit under this Mac's GPU memory ceiling — before the download, not after.
  3. Checks you have enough free disk space.
  4. Downloads the weights. This is the long part. Size depends on the build:
     4.7 GB to 29.1 GB; it prints the real figure before it starts.
  5. Reclaims the duplicate copy git-lfs keeps, freeing roughly the model's
     own size. (MEASURED on the test machine: 20.1 GB reclaimed. It checks
     each file first, so expect a minute or two rather than an instant.)

WHAT IT COSTS
  Disk: about 45 GB free while it runs for the default 5-bit build, about
        20 GB once it finishes. Smaller builds need proportionally less.
  Time: your attention for a minute, then tens of minutes of waiting. The wait
        depends entirely on your internet connection.
  Money: nothing. No account and no key are needed.

IT IS SAFE TO STOP AND RESTART
  Press Ctrl-C at any time. Run the command again and it continues from where
  it stopped. Nothing is corrupted by interrupting it.

USAGE (run from the repo root)
  ./bin/download-model.sh                     download MODEL_REPO
  ./bin/download-model.sh <ORG>/<NAME>        download a different model
  ./bin/download-model.sh --help              print this help

  <ORG>/<NAME> is the text at the top of a model's page on huggingface.co.
  Worked example:
      ./bin/download-model.sh chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit

SETTINGS (put them in config.env, or type them in front of the command)
  MODEL_REPO    which model to download
  MODEL_DIR     the folder to download it into (a full path)
  MIN_DISK_GB   refuse to start below this much free disk. Default: 45
  DEDUP         1 reclaims the duplicate copy at the end. Default: 1

WHAT YOU SHOULD SEE AT THE END
  download complete — next: ./bin/verify-model.sh

READ NEXT
  docs/03-get-the-model.md
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

if [ "$#" -gt 1 ]; then
  echo "download-model.sh: expected at most one model address." >&2
  echo "Try: ./bin/download-model.sh --help" >&2
  exit 2
fi
die() { echo "error: $1" >&2; shift; for line in "$@"; do echo "       $line" >&2; done; exit 1; }

# A different model goes into a folder named after itself. Without this, asking
# for Qwen3-14B would clone it into a folder still called
# "...-OrcaRouter-MLX-5bit", and MODEL_ID — the name the server advertises and
# the name Claude Code sends — would then be a lie about what is inside.
# An explicit MODEL_DIR always wins.
if [ "$#" -eq 1 ]; then
  if [ "$MODEL_DIR" = "$ROOT/$(basename "$MODEL_REPO")" ]; then
    MODEL_DIR="$ROOT/$(basename "$1")"
  fi
  MODEL_REPO="$1"
  MODEL_ID="$(basename "$MODEL_DIR")"
fi

# --- Guard 0: is this an Apple Silicon Mac? ----------------------------------
# Stopping here costs nothing. Stopping after the download costs 20 GB and most
# of an hour, and the answer is the same either way. Whether the chosen build
# FITS this Mac is checked in step 2 below, once huggingface.co has said how
# big it is.
if [ "${HW_APPLE_SILICON:-no}" != "yes" ]; then
  echo "REFUSING TO DOWNLOAD — this is not an Apple Silicon Mac, and MLX runs nowhere else." >&2
  echo "  reason : ${HW_REASON:-unknown}" >&2
  echo >&2
  echo "Nothing is broken and you have done nothing wrong. Read docs/01-requirements.md." >&2
  exit 1
fi

echo "repo     $MODEL_REPO"
echo "target   $MODEL_DIR"

# --- Disk pre-flight ---------------------------------------------------------
# The peak is roughly double the final size: git-lfs writes the file into the
# folder AND keeps a copy under .git/lfs until step 5 reclaims it.
disk="$(free_disk_gb)"
echo "disk     ${disk} GB free (need ${MIN_DISK_GB} GB)"
if awk -v d="$disk" -v m="$MIN_DISK_GB" 'BEGIN { exit !(d < m) }'; then
  die "only ${disk} GB free, need ${MIN_DISK_GB} GB" \
      "git-lfs keeps a second copy under .git/lfs until step 5 reclaims it," \
      "so the peak is about double the model's final size." \
      "Free some disk space, then run this command again."
fi
echo

# --- 1. git-lfs --------------------------------------------------------------
if ! git lfs version >/dev/null 2>&1; then
  die "git-lfs not installed. Run ./bin/setup.sh first." \
      "Without git-lfs, git clone SUCCEEDS and leaves 135-byte pointer files" \
      "where the weights should be."
fi
lfs_ver="$(git lfs version 2>/dev/null | awk '{print $1}' | sed 's|^git-lfs/||')"
printf '[1/5] %-22s ok (%s)\n' "git-lfs" "$lfs_ver"

# --- 2. Does the model actually exist, and can this Mac load it? ------------
# Two seconds here saves a 20 GB download into a wrong or misspelled name, or
# into a Mac that could never load it.
printf '[2/5] %-22s checking huggingface.co\n' "resolving repo"
if ! curl -fsS --max-time 15 "https://huggingface.co/api/models/${MODEL_REPO}" >/dev/null 2>&1; then
  die "repo not found on huggingface.co: ${MODEL_REPO}" \
      "open https://huggingface.co and copy the exact <org>/<repo> id, then:" \
      "MODEL_REPO=<org>/<repo> ./bin/download-model.sh"
fi

# Ask huggingface.co how big THIS repo actually is. The catalog spans 4.7 GB to
# 29.1 GB, so a hardcoded "about 20 GB" is wrong for most of them.
# json, not awk: the API reports both "size" and a nested "lfs.size" per file,
# so a naive text scan counts every weight twice.
repo_gb="$(curl -fsS --max-time 15 "https://huggingface.co/api/models/${MODEL_REPO}?blobs=true" 2>/dev/null \
  | python3 -c '
import json,sys
try:
    d = json.load(sys.stdin)
    n = sum(s.get("size") or 0 for s in d.get("siblings", [])
            if s.get("rfilename","").endswith(".safetensors"))
    print(f"{n/2**30:.1f}" if n else "")
except Exception:
    print("")
' 2>/dev/null || true)"
printf '[2/5] %-22s ok — huggingface.co/%s%s\n' "resolving repo" "$MODEL_REPO" "${repo_gb:+ (${repo_gb} GB of weights)}"

# The one refusal that belongs BEFORE a download: weights that cannot fit under
# this Mac's GPU wired ceiling can never be loaded here, whatever you close.
# The download size is used as the weight size, which is conservative for a
# checkpoint carrying a vision tower (the tower is on disk but never loaded).
if [ -n "$repo_gb" ]; then
  fit_gb="$(catalog_loaded_gb_for_dir "$(basename "$MODEL_DIR")")"
  [ -n "$fit_gb" ] || fit_gb="$repo_gb"
  hw_rebudget "$fit_gb" "$CTX_SIZE"
  if [ "$(hw_wired_fits "$fit_gb" "$HW_KV_GB")" = "no" ]; then
    die "${MODEL_REPO} cannot be loaded on this Mac, so it is not worth downloading." \
        "weights + conversation : ${fit_gb} + ${HW_KV_GB} GB" \
        "GPU wired ceiling      : ${HW_WIRED_AUTO_GB} GB (the value Apple picks for ${HW_RAM_GB} GB of memory)" \
        "./bin/serve.sh would refuse to start it, for the reason docs/04-memory-safety.md#wired-limit gives." \
        "Pick a build that fits: ./bin/models.sh list" \
        "(To fetch it anyway, for a different Mac, clone it by hand:" \
        " GIT_LFS_SKIP_SMUDGE=1 git clone https://huggingface.co/${MODEL_REPO} && cd $(basename "$MODEL_REPO") && git lfs pull)"
  fi
fi

# --- 3. Clone the file list, not the files ----------------------------------
# GIT_LFS_SKIP_SMUDGE=1 makes the clone fast and small: it fetches the pointer
# files on purpose, so the big download in step 4 can be resumed on its own.
if [ -d "$MODEL_DIR/.git" ]; then
  printf '[3/5] %-22s already cloned — resuming at step 4\n' "cloning metadata"
elif [ -e "$MODEL_DIR" ] && [ -n "$(ls -A "$MODEL_DIR" 2>/dev/null)" ]; then
  die "$MODEL_DIR already exists and is not a clone I can resume." \
      "Move it aside or delete it, then run this command again:" \
      "mv '$MODEL_DIR' '${MODEL_DIR}.old'"
else
  printf '[3/5] %-22s GIT_LFS_SKIP_SMUDGE=1 (pointers now, weights next)\n' "cloning metadata"
  GIT_LFS_SKIP_SMUDGE=1 git clone "https://huggingface.co/${MODEL_REPO}" "$MODEL_DIR" \
    || die "the clone did not finish." \
           "Check your internet connection and run this command again."
fi

# --- 4. The actual weights ---------------------------------------------------
if [ -n "$repo_gb" ]; then
  printf '[4/5] %-22s about %s GB — this is the long part\n' "git lfs pull" "$repo_gb"
else
  printf '[4/5] %-22s the weights — this is the long part\n' "git lfs pull"
fi
echo "      Press Ctrl-C to stop. Running this command again resumes it."
( cd "$MODEL_DIR" && git lfs pull ) \
  || die "the download did not finish." \
         "Nothing is corrupted. Run this command again to continue:" \
         "./bin/download-model.sh"

# Prove it. A weights file under 1 MB is a pointer file, not weights.
bad=""
while IFS= read -r shard; do
  [ -n "$shard" ] || continue
  sz="$(stat -f%z "$shard" 2>/dev/null || echo 0)"
  if [ "$sz" -lt 1000000 ]; then
    bad="$shard"
    break
  fi
done < <(find "$MODEL_DIR" -name '*.safetensors' 2>/dev/null)

if [ -n "$bad" ]; then
  sz="$(stat -f%z "$bad" 2>/dev/null || echo 0)"
  die "$(basename "$bad") is still a git-lfs pointer (${sz} bytes, expected >1 MB)" \
      "run: cd '$MODEL_DIR' && git lfs pull"
fi
printf '[4/5] %-22s ok — no pointer files left\n' "git lfs pull"

# --- 5. Reclaim the duplicate ------------------------------------------------
# git-lfs keeps a second copy of every large file under .git/lfs. `git lfs
# dedup` replaces one with a reference to the other. On an APFS disk (every
# modern Mac) no data is copied and none is lost; it does read each file once
# to check it first, so it takes a minute or two on 20 GB, not an instant.
if [ "$DEDUP" != "1" ]; then
  printf '[5/5] %-22s skipped (DEDUP=0) — the model folder stays about twice its final size\n' "git lfs dedup"
else
  echo "      checking each file, then sharing its blocks — a minute or two on 20 GB"
  before="$(free_disk_gb)"
  ( cd "$MODEL_DIR" && git lfs dedup >/dev/null 2>&1 ) || true
  after="$(free_disk_gb)"
  # Print what was really reclaimed here, measured before and after. Printing a
  # fixed "40 GB -> 20 GB" would be a claim about a machine that is not yours.
  printf '[5/5] %-22s reclaimed %s GB (%s GB free before, %s GB after)\n' \
    "git lfs dedup" \
    "$(awk -v a="$after" -v b="$before" 'BEGIN { d = a - b; if (d < 0) d = 0; printf "%.1f", d }')" \
    "$before" "$after"
  echo "      NOTE: du still reports the folder at about twice this size. That is"
  echo "      expected. Deduplication makes the two copies share the same blocks on"
  echo "      disk; du counts shared blocks once per file, df counts them once."
  echo "      df is the one telling the truth. Check with: df -h ~"
fi

echo
echo "download complete — next: ./bin/verify-model.sh"
