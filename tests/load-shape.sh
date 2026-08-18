#!/usr/bin/env bash
# Checks the load-shape contract in bin/env.sh: LOAD_SHAPE_ARGS is the one list
# of flags that shape a load's memory footprint, shared by serve.sh and
# bench.sh, and `--prefill-chunk` is in it only when PREFILL_CHUNK pins one
# (empty or unset lets the server size the chunk itself — AUDIT.md E1).
#
# Usage, from the repo root:  bash tests/load-shape.sh
# Sources bin/env.sh, which reads this Mac's memory, so it runs on macOS only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

# shape <label> <expected LOAD_SHAPE_ARGS regex> -- <env assignments…>
shape() {
  label="$1"; want="$2"; shift 3
  # A fresh bash per case, so one case's settings cannot leak into the next.
  # A config.env in the checkout is honoured, as it would be for the scripts,
  # so the fixed parts of the list are matched loosely and only the
  # prefill-chunk pair is asserted exactly.
  got="$(env -i HOME="$HOME" PATH="$PATH" "$@" bash -c "source '$ROOT/bin/env.sh' && printf '%s' \"\$LOAD_SHAPE_ARGS\"")"
  if [[ "$got" =~ $want ]]; then
    printf 'ok    %-22s %s\n' "$label" "$got"
  else
    printf 'FAIL  %-22s expected /%s/\n      got: %s\n' "$label" "$want" "$got"
    failures=$((failures + 1))
  fi
}

shape "unset (default)"  '^--ctx-size [0-9]+ --kv-quant [a-z0-9]+( --no-vision)?$'                     --
shape "empty"            '^--ctx-size [0-9]+ --kv-quant [a-z0-9]+( --no-vision)?$'                     -- PREFILL_CHUNK=
shape "pinned 1024"      '^--ctx-size [0-9]+ --kv-quant [a-z0-9]+ --prefill-chunk 1024( --no-vision)?$' -- PREFILL_CHUNK=1024

# The single-source rule: no script but env.sh may spell the flag.
if grep -l -- '--prefill-chunk' "$ROOT"/bin/*.sh "$ROOT"/start.sh | grep -v '/env.sh$'; then
  echo "FAIL  --prefill-chunk is named outside bin/env.sh (see above); LOAD_SHAPE_ARGS is the one place"
  failures=$((failures + 1))
else
  echo "ok    --prefill-chunk        named only in bin/env.sh"
fi

if [ "$failures" -eq 0 ]; then
  echo "load-shape: contract holds"
else
  echo "load-shape: $failures FAILED" >&2
  exit 1
fi
