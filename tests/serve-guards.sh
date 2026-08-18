#!/usr/bin/env bash
# Checks three of serve.sh's refusals, offline (AUDIT.md A6, A4, A2, D2).
#
# Each of them used to be absent, and each failed later and worse: an older
# mlx-serve answered an unknown flag with an argparse error a minute into a
# load; a CTX_SIZE above the model's own maximum inflated MIN_FREE_GB and could
# trip the GPU-ceiling guard for the wrong reason; a disk with no room for the
# prefix cache passed every check and then a server was told to write 10 GB
# onto it; and a half-downloaded folder got as far as the loader.
#
# mlx-serve is stubbed on PATH so the version can be dictated, and so that a
# guard which wrongly passes reaches a stub rather than a 20 GB load. The model
# is a synthetic folder from tests/fixtures/make-model.py. MIN_FREE_GB is set
# absurdly high as a second backstop: the memory guard is the last one, so a
# refusal from it is how this test observes "got past everything above". The
# disk guard sits just before it and answers the same way on a machine with
# less than 5 GB free, so either counts as "got past".
#
# Usage, from the repo root:  bash tests/serve-guards.sh
# Needs bash and python3. No server, no weights, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

python3 "$ROOT/tests/fixtures/make-model.py" "$TMP/model" --shards 2 --max-ctx 8192 >/dev/null
python3 "$ROOT/tests/fixtures/make-model.py" "$TMP/half"  --shards 5 --max-ctx 8192 --pointer 2 >/dev/null

# stub_version <version> — put a fake mlx-serve on PATH reporting that version.
# It prints the same first line the real one does: "mlx-serve <version>".
stub_version() {
  mkdir -p "$TMP/bin"
  printf '#!/bin/sh\ncase "$1" in\n  --version) echo "mlx-serve %s"; echo "mlx 0.32.0"; exit 0 ;;\nesac\necho "STUB SERVER STARTED"\n' \
    "$1" > "$TMP/bin/mlx-serve"
  chmod +x "$TMP/bin/mlx-serve"
}

# guard <label> <expected text, or "" for "none of the refusals above"> <env…>
guard() {
  label="$1"; want="$2"; shift 2
  out="$(env -i HOME="$HOME" PATH="$TMP/bin:$PATH" LOCK_DIR= \
           MODEL_DIR="$TMP/model" CTX_SIZE=4096 PREFIX_CACHE_DISK=0 \
           MIN_FREE_GB=999999 "$@" bash "$ROOT/bin/serve.sh" 2>&1 || true)"
  if [[ "$out" == *"$want"* ]]; then
    printf 'ok    %-22s %s\n' "$label" "$(printf '%s' "$out" | head -1)"
  else
    printf 'FAIL  %-22s expected "%s"\n      got: %s\n' "$label" "$want" "$(printf '%s' "$out" | head -3)"
    failures=$((failures + 1))
  fi
  if [[ "$out" == *"STUB SERVER STARTED"* ]]; then
    printf 'FAIL  %-22s reached the server: no guard stopped it\n' "$label"
    failures=$((failures + 1))
  fi
}

stub_version 26.8.7
guard "old mlx-serve" "REFUSING TO START — mlx-serve 26.8.7 is older than the 26.8.8"

stub_version 26.8.8
# past() — the last guard, whichever of the two it is (see the note above).
past="REFUSING TO START — not enough free"

guard "current mlx-serve" "$past"
guard "ctx over the model"  "CTX_SIZE is larger than this model's own maximum" CTX_SIZE=262144
guard "ctx at the model's"  "$past"                                           CTX_SIZE=8192
guard "no room for cache"   "not enough free disk for the prefix cache"       PREFIX_CACHE_DISK=100000GB
guard "half a download"     "is not completely downloaded"                    MODEL_DIR="$TMP/half"

stub_version 26.9.0
guard "newer mlx-serve" "$past"

if [ "$failures" -eq 0 ]; then
  echo "serve-guards: every refusal fires, and names its fix"
else
  echo "serve-guards: $failures FAILED" >&2
  exit 1
fi
