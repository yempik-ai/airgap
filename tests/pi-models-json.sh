#!/usr/bin/env bash
# Checks how harness/pi.sh writes the one file Pi reads a provider from,
# models.json — the only file this repository changes under a home folder, so
# the rules are held here: a missing file is created; a file with other
# providers keeps them; an `airgap` block already there is replaced; a file
# whose block already matches is not rewritten at all; a file that is not
# plain JSON (Pi allows comments) is refused, and the refusal prints the block
# to paste. Every case points PI_CODING_AGENT_DIR (Pi's own override, which
# the adapter honours) at a scratch folder, so nothing near ~/.pi is touched.
#
# PORT=9 (discard, closed on macOS) throughout: harness_prepare sends nothing,
# so nothing here needs a server or the weights.
#
# Usage, from the repo root:  bash tests/pi-models-json.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0
scratch="$(mktemp -d -t airgap-pi-models)"
trap 'rm -rf "$scratch"' EXIT

# prepare <dir>: source env.sh and the adapter in a fresh environment, run
# harness_wire and then harness_prepare against that folder. Prints what the
# two said; exit code is harness_prepare's.
prepare() {
  env -i HOME="$scratch/home" PATH="$PATH" PORT=9 PI_CODING_AGENT_DIR="$1" bash -c '
    set -euo pipefail
    source "$1/bin/env.sh"
    source "$1/harness/pi.sh"
    HARNESS_ARGS=(); HARNESS_NOTES=()
    harness_wire
    harness_prepare
  ' pi-models "$ROOT" 2>&1
}

# say <label> <got> <want>
say() {
  if [ "$2" = "$3" ]; then
    printf 'ok    %-34s %s\n' "$1" "$2"
  else
    printf 'FAIL  %-34s wanted "%s", got "%s"\n' "$1" "$3" "$2"
    failures=$((failures + 1))
  fi
}

# The values the adapter will write, read the same way it reads them.
setting() {
  env -i HOME="$scratch/home" PATH="$PATH" PORT=9 bash -c 'source "$1/bin/env.sh"; printf "%s" "${!2}"' x "$ROOT" "$1"
}
BASE_URL="$(setting BASE_URL)"; MODEL_ID="$(setting MODEL_ID)"; CTX_SIZE="$(setting CTX_SIZE)"

# json_get <file> <key>…: walk the keys (a number indexes a list) and print the
# value; "<unreadable>" when the file or the path is not there. A "len" key
# prints the length of what is there instead.
json_get() {
  python3 - "$@" <<'PY' 2>/dev/null || echo "<unreadable>"
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    if k == "len":
        d = len(d)
    elif isinstance(d, list):
        d = d[int(k)]
    else:
        d = d[k]
print(d)
PY
}

# --- 1. no folder, no file: both are created ---------------------------------
d="$scratch/fresh"
out="$(prepare "$d")"; code=$?
say "fresh: exit"                 "$code" 0
say "fresh: said nothing"         "${#out}" 0
say "fresh: baseUrl"              "$(json_get "$d/models.json" providers airgap baseUrl)" "$BASE_URL"
say "fresh: api"                  "$(json_get "$d/models.json" providers airgap api)" "anthropic-messages"
say "fresh: model id"             "$(json_get "$d/models.json" providers airgap models 0 id)" "$MODEL_ID"
say "fresh: contextWindow"        "$(json_get "$d/models.json" providers airgap models 0 contextWindow)" "$CTX_SIZE"
say "fresh: no key written"       "$(json_get "$d/models.json" providers airgap apiKey)" "mlx-serve"

# --- 2. unchanged: the file is not rewritten ---------------------------------
before="$(stat -f %m "$d/models.json" 2>/dev/null || stat -c %Y "$d/models.json")"
sleep 1
prepare "$d" >/dev/null; code=$?
after="$(stat -f %m "$d/models.json" 2>/dev/null || stat -c %Y "$d/models.json")"
say "unchanged: exit"             "$code" 0
say "unchanged: mtime kept"       "$after" "$before"

# --- 3. other providers are kept; an old airgap block is replaced ------------
d="$scratch/existing"; mkdir -p "$d"
cat > "$d/models.json" <<'EOF'
{
  "providers": {
    "ollama": { "baseUrl": "http://localhost:11434/v1", "api": "openai-completions", "apiKey": "ollama", "models": [ { "id": "llama3.1:8b" } ] },
    "airgap": { "baseUrl": "http://127.0.0.1:1/stale", "api": "anthropic-messages", "apiKey": "mlx-serve", "models": [ { "id": "old-model" } ] }
  },
  "unrelatedTopLevelKey": true
}
EOF
prepare "$d" >/dev/null; code=$?
say "existing: exit"              "$code" 0
say "existing: ollama kept"       "$(json_get "$d/models.json" providers ollama models 0 id)" "llama3.1:8b"
say "existing: top-level key kept" "$(json_get "$d/models.json" unrelatedTopLevelKey)" "True"
say "existing: airgap replaced"   "$(json_get "$d/models.json" providers airgap baseUrl)" "$BASE_URL"
say "existing: one airgap model"  "$(json_get "$d/models.json" providers airgap models len)" "1"

# --- 4. a file with comments is refused, and the block is printed ------------
d="$scratch/comments"; mkdir -p "$d"
cat > "$d/models.json" <<'EOF'
{
  // pi strips this, python does not
  "providers": {}
}
EOF
set +e; out="$(prepare "$d")"; code=$?; set -e
say "comments: refused"           "$code" 1
say "comments: names the file"    "$(printf '%s' "$out" | grep -c "cannot read $d/models.json")" 1
say "comments: prints the block"  "$(printf '%s' "$out" | grep -c "\"baseUrl\": \"$BASE_URL\"")" 1
say "comments: file untouched"    "$(grep -c '// pi strips this' "$d/models.json")" 1

if [ "$failures" -eq 0 ]; then
  echo "pi-models-json: the one file this repository writes is written by the rules"
else
  echo "pi-models-json: $failures FAILED" >&2
  exit 1
fi
