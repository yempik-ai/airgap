#!/usr/bin/env bash
# bin/claude-local.sh — start Claude Code and point it at your own Mac.
#
# Start ./bin/serve.sh in another window first. This script does not start the
# server and does not load the model.
#
# Every question you type goes to 127.0.0.1, which is your own Mac and nowhere
# else. No account, no key, no network.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

usage() {
  cat <<'EOF'
claude-local.sh — run Claude Code against the model on your own Mac.

BEFORE YOU RUN IT
  ./bin/serve.sh must already be running in another window. This script checks,
  and tells you if it is not.

WHAT IT DOES
  Starts Claude Code with every one of its model settings pointed at your Mac,
  including the small background one it uses for its own housekeeping. If that
  background one still pointed at Anthropic, Claude Code would quietly try to
  reach the internet. It also blanks any real key in your shell, so a key you
  already have cannot take priority and send your questions away.

WHAT IT COSTS
  No extra memory beyond the server that is already running. No money.
  Nothing leaves your Mac.

USAGE (run from the folder you want to work in)
  ./bin/claude-local.sh                start a session in the current folder
  ./bin/claude-local.sh -p "hello"     ask one question and exit
  ./bin/claude-local.sh --help         print this help

  Anything you type after the script name is passed straight to Claude Code.
  You can run this script from any folder. Use its full path, for example:
      ~/dev/local-llms/airgap/bin/claude-local.sh

SETTINGS
  LEAN_MCP=0      load your normal extra tool servers. They cost about 17,000
                  prompt tokens on every turn, so the default is 1 (off).
  CLAUDE_BIN      the command that starts Claude Code. Default: claude
  CLAUDE_CODE_MAX_OUTPUT_TOKENS   longest single answer. Default: 8192

WHAT YOU SHOULD SEE
  Four lines starting with "claude", then Claude Code's normal startup, then
  one line about an "unrecognized_model". That line is EXPECTED. It is not an
  error and nothing is wrong. Claude Code has simply never heard of a model
  name that only exists on your Mac.

IF IT SAYS THERE IS NO SERVER
  Open another window, go to the repo root, and run ./bin/serve.sh.
  See docs/06-troubleshooting.md#no-server

READ NEXT
  docs/05-run-it.md
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

# A dead server makes Claude Code fail in confusing ways much later, so check now.
if ! server_up; then
  echo "error: no server at $BASE_URL — start ./bin/serve.sh first" >&2
  echo >&2
  echo "Open another Terminal window, then type these two lines:" >&2
  echo "    cd $ROOT" >&2
  echo "    ./bin/serve.sh" >&2
  echo "Wait until it says it is listening, then run this command again." >&2
  exit 1
fi

# Point every model setting at your Mac. Claude Code chooses a small, fast model
# on its own for background work such as naming a conversation. All of these
# names are set because different versions of Claude Code read different ones.
export ANTHROPIC_BASE_URL="$BASE_URL"
export ANTHROPIC_MODEL="$MODEL_ID"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL_ID"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL_ID"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL_ID"
export ANTHROPIC_SMALL_FAST_MODEL="$MODEL_ID"
export CLAUDE_CODE_SUBAGENT_MODEL="$MODEL_ID"

# The server accepts anything here unless you set API_KEY, but Claude Code
# insists on being given something.
if [ -n "$API_KEY" ]; then
  export ANTHROPIC_AUTH_TOKEN="$API_KEY"
else
  export ANTHROPIC_AUTH_TOKEN="mlx-serve"
fi

# Empty, not removed. A real key in your shell would otherwise take priority and
# send your questions to Anthropic instead of to your Mac.
export ANTHROPIC_API_KEY=""

# Keep the session quiet and local: no usage reporting, no crash reporting, no
# update check in the middle of your work.
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_TELEMETRY=1
export DISABLE_ERROR_REPORTING=1
export DISABLE_AUTOUPDATER=1

# A 27B model is much weaker than Sonnet or Opus at long chains of tool use.
# Keeping the answer budget modest stops it talking past a tool call.
: "${CLAUDE_CODE_MAX_OUTPUT_TOKENS:=8192}"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS

# Claude Code has never heard of this model, so it assumes the 200,000-token
# window the hosted models have, and sizes its own summarising against that.
# Left alone, it cheerfully builds a question the server has to reject with
# "Prompt exceeds maximum context length". Tell it the truth instead.
export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$CTX_SIZE"

extra=()
if [ "$LEAN_MCP" = "1" ]; then
  extra+=( --strict-mcp-config )
  mcp_line="strict (LEAN_MCP=1) — MCP servers off, saves ~17k prompt tokens per turn"
else
  mcp_line="your normal config (LEAN_MCP=0)"
fi

echo "claude   -> $BASE_URL   model $MODEL_ID"
echo "context  $CTX_SIZE tokens declared to the harness, $CLAUDE_CODE_MAX_OUTPUT_TOKENS max output"
echo "mcp      $mcp_line"
echo "note     a one-line \"unrecognized_model\" warning at startup is EXPECTED and cosmetic"
echo

# ${extra[@]+"${extra[@]}"} rather than "${extra[@]}": under `set -u`, bash 3.2
# (the version macOS ships) treats an EMPTY array as an unset variable and stops.
exec "$CLAUDE_BIN" --model "$MODEL_ID" ${extra[@]+"${extra[@]}"} "$@"
