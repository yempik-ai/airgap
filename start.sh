#!/usr/bin/env bash
# start.sh — the only command you need to remember.
#
#   ./start.sh
#
# Runs everything that can be automated, in the right order, and stops with a
# plain-English fix the moment something needs you. Safe to run again at any
# time: every step checks whether it is already done and skips it if so.
#
# It deliberately does NOT start the server. The server holds ~19 GB and has to
# stay in its own window, so the last thing this script does is tell you the two
# commands to run and in which window.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
start.sh — get from a fresh clone to ready-to-run.

WHAT IT DOES, in order
  1. setup            installs git-lfs and mlx-serve, checks Homebrew and Claude Code
  2. download         the model, if you do not have one yet (about 20 GB)
  3. verify           proves the weights are real files and not placeholders
  4. doctor           checks the whole setup and prints PASS/FAIL per item
  Then it tells you the two commands that actually run it.

WHAT IT COSTS
  A 20 GB download the first time, and nothing after that. It asks before
  downloading. It never starts the server, so it never loads the model into
  memory.

IS IT REVERSIBLE
  Yes. It installs two command-line tools and downloads one folder.
  "How to undo everything" at the end of docs/02-install.md removes both.

USAGE
  ./start.sh              run it
  ./start.sh --yes        do not ask before the 20 GB download
  ./start.sh --help       print this help

IF A STEP FAILS
  It stops there and prints the fix. Correct it and run ./start.sh again — the
  steps you already finished are skipped.
EOF
}

ASSUME_YES=0
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  -y|--yes)  ASSUME_YES=1 ;;
  "") : ;;
  *) echo "start.sh: I do not understand '$1'. Try: ./start.sh --help" >&2; exit 2 ;;
esac

step()  { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
fail()  { printf '\n\033[1mStopped at: %s\033[0m\n' "$1" >&2
          shift; for l in "$@"; do printf '  %s\n' "$l" >&2; done
          printf '\nFix that, then run ./start.sh again.\n' >&2; exit 1; }

echo "airgap — getting you ready"
echo "This does not start the server and does not load the model."

# --- 1. tools ---------------------------------------------------------------
step "1 of 4: tools"
./bin/setup.sh || fail "installing the tools" \
  "bin/setup.sh could not finish. Its last lines above say which tool is missing." \
  "Homebrew and Claude Code have their own installers; it prints the addresses."

# --- 2. the model -----------------------------------------------------------
# env.sh finds a model if one is already on disk, whichever build it is.
step "2 of 4: the model"
# shellcheck source=bin/env.sh
source ./bin/env.sh

have_weights=0
if [ -f "$MODEL_DIR/config.json" ]; then
  for w in "$MODEL_DIR"/*.safetensors; do
    [ -f "$w" ] || continue
    [ "$(stat -f%z "$w" 2>/dev/null || echo 0)" -gt 1000000 ] && have_weights=1
    break
  done
fi

if [ "$have_weights" = "1" ]; then
  echo "already here: $(basename "$MODEL_DIR")"
  echo "to use a different build:  ./bin/models.sh list"
else
  echo "No model on disk yet."
  echo "About to download: $MODEL_REPO"
  echo "Size: about 20 GB. It resumes if interrupted, so this is safe to stop."
  echo
  if [ "$ASSUME_YES" != "1" ] && [ -t 0 ]; then
    printf 'Download it now? [y/N] '
    read -r answer
    case "$answer" in
      y|Y|yes|YES) : ;;
      *) echo
         echo "Nothing downloaded."
         echo "  smaller options:  ./bin/models.sh list"
         echo "  when ready:       ./start.sh"
         exit 0 ;;
    esac
  fi
  ./bin/download-model.sh || fail "downloading the model" \
    "Nothing is corrupted and nothing is lost." \
    "Run ./start.sh again and it picks up where it stopped."
fi

# --- 3. prove the weights are real ------------------------------------------
step "3 of 4: checking the model files"
./bin/verify-model.sh || fail "verifying the model" \
  "The files on disk are not what they should be." \
  "Most often this is git-lfs: cd '$MODEL_DIR' && git lfs pull" \
  "See docs/06-troubleshooting.md"

# --- 4. check the whole setup -----------------------------------------------
# doctor exits non-zero when something FAILs. The usual failure at this point is
# free memory, which is not something to fix by editing a file — you close apps.
# So this is reported, not treated as a crash.
step "4 of 4: checking your Mac"
if ./bin/doctor.sh; then
  doctor_ok=1
else
  doctor_ok=0
fi

# --- what now ---------------------------------------------------------------
printf '\n\033[1m== ready ==\033[0m\n'
if [ "$doctor_ok" != "1" ]; then
  cat <<EOF

The doctor above reported at least one FAIL. Read its lines: each one names the
fix. If the failure is "memory", that is expected until you close some apps —
the model needs ${MIN_FREE_GB} GB free on this Mac and the doctor tells you what is
holding it.

EOF
fi

cat <<EOF
Two commands, in TWO separate Terminal windows.

  Window 1 — the server. Leave it open.
      cd $ROOT
      ./bin/serve.sh

  Window 2 — Claude Code, pointed at your Mac.
      cd $ROOT
      ./bin/claude-local.sh

  To stop, in either window:
      ./bin/stop.sh

New to this? docs/05-run-it.md walks through both windows slowly.
EOF
