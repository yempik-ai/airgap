#!/usr/bin/env bash
# bin/download-model.sh — get the weights, correctly.
#
# The weights are the model's numbers: about 20 GB of them. They are stored
# on huggingface.co and downloaded with git, but ordinary git does NOT download
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
  2. Checks the model's address really exists, BEFORE downloading anything.
  3. Checks you have enough free disk space.
  4. Downloads about 20 GB. This is the long part.
  5. Reclaims the duplicate copy git-lfs keeps, freeing about 20 GB instantly.

WHAT IT COSTS
  Disk: about 45 GB free while it runs, about 20 GB once it finishes.
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

# --- Guard 0: can this Mac run what is about to be downloaded? ---------------
# Stopping here costs two seconds. Stopping after the download costs 20 GB and
# most of an hour, and the answer is the same either way.
if [ "${HW_VERDICT:-}" = "impossible" ] && [ "$#" -eq 0 ]; then
  echo "REFUSING TO DOWNLOAD — this Mac cannot run this model." >&2
  echo "  reason : ${HW_REASON:-unknown}" >&2
  if [ -n "${HW_ALT_MODEL:-}" ]; then
    echo "  instead: ${HW_ALT_MODEL}" >&2
  fi
  echo >&2
  echo "Nothing is broken and you have done nothing wrong. This check runs BEFORE" >&2
  echo "the download so you do not spend 20 GB finding out." >&2
  echo >&2
  echo "To download one of the smaller models named above instead, pass its" >&2
  echo "address on huggingface.co, for example:" >&2
  echo "    ./bin/download-model.sh <ORG>/<NAME>" >&2
  echo >&2
  echo "Read docs/01-requirements.md#ram-tiers." >&2
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

# --- 2. Does the model actually exist? --------------------------------------
# Two seconds here saves a 20 GB download into a wrong or misspelled name.
printf '[2/5] %-22s checking huggingface.co\n' "resolving repo"
if ! curl -fsS --max-time 15 "https://huggingface.co/api/models/${MODEL_REPO}" >/dev/null 2>&1; then
  die "repo not found on huggingface.co: ${MODEL_REPO}" \
      "open https://huggingface.co and copy the exact <org>/<repo> id, then:" \
      "MODEL_REPO=<org>/<repo> ./bin/download-model.sh"
fi
printf '[2/5] %-22s ok — huggingface.co/%s\n' "resolving repo" "$MODEL_REPO"

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
printf '[4/5] %-22s about 20 GB — this is the long part\n' "git lfs pull"
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
# modern Mac) this is instant and loses no data.
if [ "$DEDUP" != "1" ]; then
  printf '[5/5] %-22s skipped (DEDUP=0) — the model folder stays about twice its final size\n' "git lfs dedup"
else
  before="$(free_disk_gb)"
  ( cd "$MODEL_DIR" && git lfs dedup >/dev/null 2>&1 ) || true
  after="$(free_disk_gb)"
  # Print what was really reclaimed here, measured before and after. Printing a
  # fixed "40 GB -> 20 GB" would be a claim about a machine that is not yours.
  printf '[5/5] %-22s reclaimed %s GB (%s GB free before, %s GB after)\n' \
    "git lfs dedup" \
    "$(awk -v a="$after" -v b="$before" 'BEGIN { d = a - b; if (d < 0) d = 0; printf "%.1f", d }')" \
    "$before" "$after"
fi

echo
echo "download complete — next: ./bin/verify-model.sh"
