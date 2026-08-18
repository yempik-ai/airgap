#!/usr/bin/env bash
# Checks the "is the model here?" contract in bin/env.sh (AUDIT.md D2).
#
# Four scripts used to answer that question four ways, three of them from the
# first shard alone, so a five-shard download interrupted after shard 1 was
# reported as "already here" and the resume was skipped. model_state answers it
# once, over every shard the checkpoint declares, and every caller reads that
# answer. This builds the folders a real interrupted download leaves —
# shard 1 of 5 with the rest still pointers, shard 1 of 5 with the rest not
# written at all, and a whole one — and checks the verdict on each.
#
# Usage, from the repo root:  bash tests/model-state.sh
# Needs bash and python3. No server, no weights, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAKE="$ROOT/tests/fixtures/make-model.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

# The helpers under test, from a shell that has sourced env.sh. LOCK_DIR is
# emptied so nothing here can touch the real lock, and MODEL_DIR is pinned so
# env.sh's own discovery cannot wander into the checkout's real models.
ask() {
  env -i HOME="$HOME" PATH="$PATH" LOCK_DIR= MODEL_DIR="$TMP/none" \
    bash -c "source '$ROOT/bin/env.sh' && $1"
}

# state <label> <expected> <make-model.py arguments…>
state() {
  label="$1"; want="$2"; shift 2
  dir="$TMP/$label"
  python3 "$MAKE" "$dir" "$@" >/dev/null
  got="$(ask "model_state '$dir'")"
  if [ "$got" = "$want" ]; then
    printf 'ok    %-26s %s\n' "$label" "$got"
  else
    printf 'FAIL  %-26s expected %s, got %s\n' "$label" "$want" "$got"
    failures=$((failures + 1))
  fi
}

state "one-shard-whole"     complete --shards 1
state "five-shards-whole"   complete --shards 5
state "shard-1-of-5-pointer" partial --shards 5 --pointer 2
state "shard-1-of-5-missing" partial --shards 5 --drop 2
state "first-shard-pointer"  partial --shards 5 --pointer 1

# A folder with a config.json and no weights at all is not a model.
mkdir -p "$TMP/empty" && echo '{}' > "$TMP/empty/config.json"
got="$(ask "model_state '$TMP/empty'")"
if [ "$got" = "absent" ]; then
  printf 'ok    %-26s %s\n' "config-only" "$got"
else
  printf 'FAIL  %-26s expected absent, got %s\n' "config-only" "$got"
  failures=$((failures + 1))
fi

# The detail the refusals quote: which shard, and how big it is.
got="$(ask "model_pointer_shard '$TMP/shard-1-of-5-pointer'")"
if [ "$got" = "model-00002-of-00005.safetensors 132" ]; then
  printf 'ok    %-26s %s\n' "pointer named" "$got"
else
  printf 'FAIL  %-26s expected "model-00002-of-00005.safetensors 132", got "%s"\n' "pointer named" "$got"
  failures=$((failures + 1))
fi

got="$(ask "model_missing_shards '$TMP/shard-1-of-5-missing'")"
if [ "$got" = "model-00002-of-00005.safetensors" ]; then
  printf 'ok    %-26s %s\n' "missing named" "$got"
else
  printf 'FAIL  %-26s expected "model-00002-of-00005.safetensors", got "%s"\n' "missing named" "$got"
  failures=$((failures + 1))
fi

# The single-source rule: asking the question anywhere else is how the four
# answers drifted apart in the first place. bin/env.sh owns the shell answer;
# bin/verify-model.sh reads the shards themselves, in Python, which is its job.
stray="$(grep -l '\*\.safetensors' "$ROOT"/bin/*.sh "$ROOT"/start.sh \
         | grep -v -e '/env\.sh$' -e '/verify-model\.sh$' || true)"
if [ -z "$stray" ]; then
  printf 'ok    %-26s only bin/env.sh and bin/verify-model.sh\n' "shards enumerated"
else
  printf 'FAIL  %-26s also named in:\n%s\n' "shards enumerated" "$stray"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "model-state: contract holds"
else
  echo "model-state: $failures FAILED" >&2
  exit 1
fi
