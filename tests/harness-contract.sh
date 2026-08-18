#!/usr/bin/env bash
# Checks that every adapter under harness/ meets the contract bin/run.sh is
# written against (docs/10-other-harnesses.md §7): HARNESS_DIALECT,
# HARNESS_BIN, HARNESS_ONESHOT and harness_wire are there, harness_wire prints
# nothing, and the wiring it does points the harness at this Mac. An adapter
# with the optional harness_prepare (harness/pi.sh: the one file its harness
# reads) is judged on that file too: prepare runs under a scratch HOME, must
# print nothing, and what it wrote there counts as wiring.
#
# Each adapter is sourced in a fresh environment (env -i) with PORT=9, a closed
# port on macOS, so nothing here needs a server: harness_wire only sets
# variables and fills arrays, it sends no request. HOME is a scratch folder,
# so a harness_prepare writes there and nowhere near a real ~/.pi, and an
# adapter that reads a file under HOME (harness/hermes.sh: ~/.hermes/.env)
# sees the same empty home on every machine.
#
# Usage, from the repo root:  bash tests/harness-contract.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

# What runs inside the fresh environment: source env.sh, source the adapter,
# and report the contract surface as key=value lines. The wiring check is made
# in here, where BASE_URL and MODEL_ID are the ones the adapter actually saw.
#
# harness_wire's own output goes to a file rather than through a command
# substitution: a substitution would run it in a subshell, and everything it
# exports would be thrown away before the check below could see it.
#
# The wiring is judged on what harness_wire ITSELF added, never on the
# environment as a whole: env.sh exports BASE_URL and MODEL_ID before any
# adapter is sourced, so an adapter that wires nothing at all would pass a
# check made against `env`. The exports are snapshotted either side of the
# call and only the lines that appear or change count, together with whatever
# went into HARNESS_ARGS — and, when harness_prepare exists, whatever it wrote
# under the scratch HOME.
inner='
set -euo pipefail
source "$2/bin/env.sh"
source "$2/harness/$1.sh"
echo "dialect=${HARNESS_DIALECT:-}"
echo "bin=${HARNESS_BIN:-}"
echo "oneshot=${#HARNESS_ONESHOT[@]}"
if declare -f harness_wire >/dev/null 2>&1; then echo "wire=function"; else echo "wire=missing"; fi
said="$(mktemp)"; was="$(mktemp)"; now="$(mktemp)"
HARNESS_ARGS=(); HARNESS_NOTES=()
# `declare -x _=` is bash noting the last argument of the previous command,
# not an adapter exporting anything, so it is never evidence.
export -p | grep -v "^declare -x _=" > "$was"
harness_wire > "$said" 2>&1
export -p | grep -v "^declare -x _=" > "$now"
echo "printed=$(wc -c < "$said" | tr -d " ")"
if declare -f harness_prepare >/dev/null 2>&1; then
  echo "prepare=function"
  harness_prepare > "$said" 2>&1
  echo "prepared=$(wc -c < "$said" | tr -d " ")"
  written="$(find "$HOME" -type f -exec cat {} + 2>/dev/null || true)"
else
  echo "prepare=none"; echo "prepared=0"; written=""
fi
wired="$( { printf "%s\n" ${HARNESS_ARGS[@]+"${HARNESS_ARGS[@]}"}; grep -Fxv -f "$was" "$now" || true; printf "%s\n" "$written"; } )"
rm -f "$said" "$was" "$now"
case "$wired" in *"$BASE_URL"*) echo "url=yes" ;; *) echo "url=no" ;; esac
case "$wired" in *"$MODEL_ID"*) echo "id=yes" ;; *) echo "id=no" ;; esac
'

# say <adapter> <got> <want> <what it means in words>
say() {
  if [ "$2" = "$3" ]; then
    printf 'ok    %-12s %s\n' "$1" "$4"
  else
    printf 'FAIL  %-12s %s\n      wanted "%s", got "%s"\n' "$1" "$4" "$3" "$2"
    failures=$((failures + 1))
  fi
}

found=0
for adapter in "$ROOT"/harness/*.sh; do
  [ -f "$adapter" ] || continue
  name="$(basename "$adapter" .sh)"
  found=$((found + 1))

  # stderr is kept: an adapter that refuses here has failed the contract, and
  # its message is the evidence.
  scratch_home="$(mktemp -d -t airgap-contract-home)"
  if ! out="$(env -i HOME="$scratch_home" PATH="$PATH" PORT=9 bash -c "$inner" contract "$name" "$ROOT" 2>&1)"; then
    rm -rf "$scratch_home"
    printf 'FAIL  %-12s sourcing it and calling harness_wire failed\n      %s\n' \
      "$name" "$(printf '%s' "$out" | head -3)"
    failures=$((failures + 1))
    continue
  fi

  rm -rf "$scratch_home"

  dialect=""; bin=""; oneshot=0; wire=""; printed=""; prepare=""; prepared=""; url=""; id=""
  while IFS='=' read -r k v; do
    case "$k" in
      dialect)  dialect="$v" ;;
      bin)      bin="$v" ;;
      oneshot)  oneshot="$v" ;;
      wire)     wire="$v" ;;
      printed)  printed="$v" ;;
      prepare)  prepare="$v" ;;
      prepared) prepared="$v" ;;
      url)      url="$v" ;;
      id)       id="$v" ;;
    esac
  done <<< "$out"

  case "$dialect" in
    anthropic|openai|ollama) say "$name" "$dialect" "$dialect" "HARNESS_DIALECT=$dialect" ;;
    *) say "$name" "${dialect:-<unset>}" "anthropic|openai|ollama" "HARNESS_DIALECT" ;;
  esac
  say "$name" "$([ -n "$bin" ] && echo set || echo empty)" set "HARNESS_BIN=${bin:-<empty>}"
  say "$name" "$([ "$oneshot" -ge 1 ] 2>/dev/null && echo yes || echo no)" yes \
      "HARNESS_ONESHOT carries $oneshot argument(s)"
  say "$name" "$wire" function "harness_wire is a function"
  say "$name" "$printed" 0 "harness_wire printed ${printed:-?} bytes"
  if [ "$prepare" = "function" ]; then
    say "$name" "$prepared" 0 "harness_prepare printed ${prepared:-?} bytes"
    say "$name" "$url" yes "harness_wire or what harness_prepare wrote names BASE_URL"
    say "$name" "$id" yes "harness_wire or what harness_prepare wrote names MODEL_ID"
  else
    say "$name" "$url" yes "harness_wire itself names BASE_URL"
    say "$name" "$id" yes "harness_wire itself names MODEL_ID"
  fi
done

if [ "$found" -eq 0 ]; then
  echo "harness-contract: no adapters under $ROOT/harness — nothing was checked" >&2
  exit 1
fi

if [ "$failures" -eq 0 ]; then
  echo "harness-contract: $found adapter(s) meet the contract"
else
  echo "harness-contract: $failures FAILED" >&2
  exit 1
fi
