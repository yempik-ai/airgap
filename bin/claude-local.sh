#!/usr/bin/env bash
# bin/claude-local.sh — start Claude Code and point it at your own Mac.
#
# The wiring this script used to do now lives in harness/claude-code.sh, and
# bin/run.sh does the parts every harness needs. This name stays because it is
# the one in every document, and because it is the short way to say it:
# `./bin/claude-local.sh` and `./bin/run.sh claude-code` are the same command.
#
# Start ./bin/serve.sh in another window first. This script does not start the
# server and does not load the model.
#
# Every question you type goes to 127.0.0.1, which is your own Mac and nowhere
# else. No account, no key, no network.

set -euo pipefail

exec "$(dirname "${BASH_SOURCE[0]}")/run.sh" claude-code "$@"
