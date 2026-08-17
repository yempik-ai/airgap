#!/usr/bin/env bash
# bin/setup.sh — install the four tools this stack needs.
#
# It does NOT download the 20 GB model, and it does NOT start the server.
# It is safe to run again at any time: every step looks before it acts.
#
# Read docs/02-install.md for the same steps done by hand, with explanations.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

usage() {
  cat <<'EOF'
setup.sh — install the tools. Not the model, and not the server.

WHAT IT DOES
  Checks the four things this stack needs, and installs the TWO it can:
    1. Homebrew    checked only. It has its own installer, which changes system
                   folders, so this script prints the address and stops.
    2. git-lfs     checked and installed. Also switched on for your account,
                   which is a separate step and the one people miss.
    3. mlx-serve   checked and installed.
    4. Claude Code checked only. It has its own installer and its own sign-in,
                   so this script prints the address and stops.
  Then, only if you ask for it, a Python environment you do not otherwise need.

  On a brand new Mac with none of this, expect to run it more than once: it
  stops at Homebrew, you install Homebrew, you run it again.

WHAT IT DOES NOT DO
  It never downloads the model (that is ./bin/download-model.sh, about 20 GB).
  It never starts the server (that is ./bin/serve.sh).
  It never installs Homebrew or Claude Code for you.

HOW LONG
  Your attention: about a minute. Waiting: a few minutes if Homebrew has to
  build or download something.

USAGE (run from the repo root)
  ./bin/setup.sh              install what is missing
  ./bin/setup.sh --help       print this help

SETTINGS (put them in config.env, or type them in front of the command)
  SKIP_BREW=1     check the tools but never install anything
  WITH_VENV=1     also build the optional Python environment
  PYTHON_BIN      which Python to use for that. Default: python3

WHAT YOU SHOULD SEE AT THE END
  setup complete — next: ./bin/doctor.sh

IF A STEP FAILS
  The last line names the step and points at docs/02-install.md.

READ NEXT
  docs/02-install.md
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") : ;;
  *) echo "setup.sh: I do not understand '$1'. Try: ./bin/setup.sh --help" >&2; exit 2 ;;
esac

: "${SKIP_BREW:=0}"

STEP=0
fail() {
  echo
  echo "setup FAILED at step ${STEP} ($1) — see docs/02-install.md" >&2
  exit 1
}

# Print in the same shape every time: "[n/5] name          message".
say() { printf '[%d/5] %-15s %s\n' "$STEP" "$1" "$2"; }

echo "airgap — setup"

# --- 0. Can this Mac run the model at all? -----------------------------------
# The earliest possible stop. Installing tools for a model that cannot load is
# a waste of the reader's evening, and this is before any of it happens.
if [ "${HW_VERDICT:-}" = "impossible" ]; then
  echo
  echo "STOP — this Mac cannot run the 27B model." >&2
  echo "  reason : ${HW_REASON:-unknown}" >&2
  if [ -n "${HW_ALT_MODEL:-}" ]; then
    echo "  instead: ${HW_ALT_MODEL}" >&2
  fi
  echo >&2
  echo "Nothing is broken and you have done nothing wrong. Read" >&2
  echo "docs/01-requirements.md#ram-tiers before installing anything." >&2
  exit 1
fi

# --- 1. Homebrew -------------------------------------------------------------
# Never installed automatically. The Homebrew installer changes system folders
# and asks for your password; you should run it yourself, having read it.
STEP=1
if command -v brew >/dev/null 2>&1; then
  say "homebrew" "ok ($(brew --version 2>/dev/null | head -1 | awk '{print $2}'))"
else
  say "homebrew" "not installed"
  echo
  echo "Homebrew is how the other three tools are installed. It is not installed"
  echo "here, and this script will not install it for you, because its installer"
  echo "changes system folders and asks for your password."
  echo
  echo "Open https://brew.sh in a browser, read the one command on that page,"
  echo "and run it yourself. Then run ./bin/setup.sh again."
  fail "homebrew"
fi

# --- 2. git-lfs --------------------------------------------------------------
# The single most consequential tool here. Without it, `git clone` of a model
# SUCCEEDS and leaves 135-byte text files where the weights should be, and
# nothing warns you until the server fails in a confusing way.
STEP=2
lfs_version() { git lfs version 2>/dev/null | awk '{print $1}' | sed 's|^git-lfs/||'; }
if command -v git-lfs >/dev/null 2>&1 || git lfs version >/dev/null 2>&1; then
  say "git-lfs" "ok ($(lfs_version))"
else
  if [ "$SKIP_BREW" = "1" ]; then
    say "git-lfs" "missing, and SKIP_BREW=1 — not installing"
    fail "git-lfs"
  fi
  say "git-lfs" "brew install git-lfs"
  brew install git-lfs >/dev/null || fail "git-lfs"
  say "git-lfs" "ok ($(lfs_version))"
fi

# git-lfs also has to be switched on for your user account once. Installing it
# is not enough; this is the step people miss.
if git config --global --get filter.lfs.process >/dev/null 2>&1; then
  say "git-lfs" "ok (switched on for your account)"
else
  say "git-lfs" "git lfs install   <- switching it on for your account"
  git lfs install --skip-repo >/dev/null || fail "git-lfs"
  say "git-lfs" "ok (switched on for your account)"
fi

# --- 3. mlx-serve ------------------------------------------------------------
# Three commands, not one. `brew trust` is required for any tap that is not
# Homebrew's own, and skipping it produces an error that looks like a broken
# tap rather than a missing permission.
STEP=3
if command -v mlx-serve >/dev/null 2>&1; then
  say "mlx-serve" "ok ($(mlx-serve --version 2>/dev/null | awk '{print $NF}' | head -1))"
else
  if [ "$SKIP_BREW" = "1" ]; then
    say "mlx-serve" "missing, and SKIP_BREW=1 — not installing"
    fail "mlx-serve"
  fi
  say "mlx-serve" "brew tap ddalcu/mlx-serve https://github.com/ddalcu/mlx-serve"
  brew tap ddalcu/mlx-serve https://github.com/ddalcu/mlx-serve >/dev/null 2>&1 || true
  say "mlx-serve" "brew trust ddalcu/mlx-serve      <- required for third-party taps"
  brew trust ddalcu/mlx-serve >/dev/null 2>&1 || true
  say "mlx-serve" "brew install mlx-serve"
  brew install mlx-serve >/dev/null || fail "mlx-serve"
  command -v mlx-serve >/dev/null 2>&1 || fail "mlx-serve"
  say "mlx-serve" "ok ($(mlx-serve --version 2>/dev/null | awk '{print $NF}' | head -1))"
fi

# --- 4. Claude Code ----------------------------------------------------------
# Not installed here. It has its own installer and its own login.
STEP=4
if command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  say "claude code" "ok ($("$CLAUDE_BIN" --version 2>/dev/null | awk '{print $1}'))"
else
  say "claude code" "not found (looked for the command '$CLAUDE_BIN')"
  echo
  echo "Claude Code is the app you type your questions into. Install it from"
  echo "https://claude.com/claude-code and then run ./bin/setup.sh again."
  echo "If you already have it under a different name, set CLAUDE_BIN in config.env."
  fail "claude code"
fi

# --- 5. Optional Python environment -----------------------------------------
# Nothing in this repo needs it. bin/verify-model.sh uses only what Python
# ships with. This exists for people who want to load the weights themselves.
STEP=5
if [ "$WITH_VENV" != "1" ]; then
  say "python venv" "skipped (set WITH_VENV=1 to build it)"
else
  if [ -d "$ROOT/.venv" ]; then
    say "python venv" "ok (already at $ROOT/.venv)"
  else
    say "python venv" "$PYTHON_BIN -m venv .venv"
    "$PYTHON_BIN" -m venv "$ROOT/.venv" || fail "python venv"
    say "python venv" "installing mlx-lm into it"
    "$ROOT/.venv/bin/pip" install --quiet --upgrade pip >/dev/null || fail "python venv"
    "$ROOT/.venv/bin/pip" install --quiet mlx-lm >/dev/null || fail "python venv"
    say "python venv" "ok ($ROOT/.venv)"
  fi
fi

echo "setup complete — next: ./bin/doctor.sh"
