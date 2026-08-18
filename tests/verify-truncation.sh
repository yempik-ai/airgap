#!/usr/bin/env bash
# Checks that bin/verify-model.sh notices an incomplete shard (AUDIT.md D1).
#
# verify-model.sh read each shard's header and counted what it declared; it
# never compared that against the file's own size. A shard cut short by a full
# disk or a killed pull keeps its header — the header is written first — so
# every count agreed and `verify PASS` was printed over weights that load as
# garbage. And a shard that never arrived at all left nothing to inspect, so
# only the checkpoint's index knows it is missing.
#
# Both shapes are built here, over 1 MB so they get past the pointer test, and
# fed to the real script.
#
# Usage, from the repo root:  bash tests/verify-truncation.sh
# Needs bash and python3. No server, no weights, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAKE="$ROOT/tests/fixtures/make-model.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

# verify <label> <expect PASS|FAIL> <expected text in the output> <make args…>
verify() {
  label="$1"; want="$2"; want_text="$3"; shift 3
  dir="$TMP/$label"
  python3 "$MAKE" "$dir" "$@" >/dev/null
  if out="$(env -i HOME="$HOME" PATH="$PATH" LOCK_DIR= MODEL_DIR="$dir" \
              bash "$ROOT/bin/verify-model.sh" 2>&1)"; then
    got=PASS
  else
    got=FAIL
  fi
  if [ "$got" = "$want" ] && [[ "$out" == *"$want_text"* ]]; then
    printf 'ok    %-22s %s — %s\n' "$label" "$got" \
      "$(printf '%s' "$out" | grep -m1 -e 'verify PASS' -e 'verify FAIL' || echo '?')"
  else
    printf 'FAIL  %-22s expected %s containing "%s"\n%s\n' "$label" "$want" "$want_text" "$out"
    failures=$((failures + 1))
  fi
}

verify "whole-1-shard"   PASS "verify PASS"  --shards 1
verify "whole-5-shards"  PASS "verify PASS"  --shards 5
verify "truncated"       FAIL "it is truncated, 4096 bytes short" --shards 1 --truncate 1
verify "truncated-of-5"  FAIL "it is truncated, 4096 bytes short" --shards 5 --truncate 3
verify "missing-of-5"    FAIL "the index names 1 shard(s) that are not here" --shards 5 --drop 4
verify "pointer-of-5"    FAIL "git-lfs pointer, not weights" --shards 5 --pointer 2

if [ "$failures" -eq 0 ]; then
  echo "verify-truncation: an incomplete shard is caught"
else
  echo "verify-truncation: $failures FAILED" >&2
  exit 1
fi
