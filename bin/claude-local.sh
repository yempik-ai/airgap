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
  SERVE_TIMEOUT   seconds of silence before a question is given up on. Read
                  here so the client waits slightly longer than the server and
                  the server is the side that reports a stall. Default: 300

WHAT YOU SHOULD SEE
  Five lines starting with "claude", then Claude Code's normal startup, then
  one line about an "unrecognized_model", and possibly one saying claude.ai
  connectors are disabled because an auth source is set. Both are EXPECTED.
  Neither is an error and nothing is wrong. Claude Code has simply never heard
  of a model name that only exists on your Mac, and the "auth source" is the
  placeholder token this script sets so nothing reaches claude.ai.

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
# on its own for background work such as naming a conversation, and other
# models for subagents, the auto-mode classifier and its background classifier.
# Every name below exists in the Claude Code 2.1.233 binary; they are all set
# because different versions read different ones, and one left pointing at
# Anthropic would quietly reach for the internet.
export ANTHROPIC_BASE_URL="$BASE_URL"
export ANTHROPIC_MODEL="$MODEL_ID"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL_ID"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL_ID"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL_ID"
export ANTHROPIC_DEFAULT_FABLE_MODEL="$MODEL_ID"
export ANTHROPIC_SMALL_FAST_MODEL="$MODEL_ID"
export CLAUDE_CODE_SUBAGENT_MODEL="$MODEL_ID"
export CLAUDE_CODE_AUTO_MODE_MODEL="$MODEL_ID"
export CLAUDE_CODE_BG_CLASSIFIER_MODEL="$MODEL_ID"

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
# update check, no marketplace auto-install and no background tasks in the
# middle of your work. Every one of these names exists in the 2.1.233 binary.
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_TELEMETRY=1
export DISABLE_ERROR_REPORTING=1
export DISABLE_AUTOUPDATER=1
export CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1
export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1

# When a streamed request breaks — including when it idles past the limit
# below — Claude Code quietly retries it non-streamed. Against a local server
# that hides two things: a streamed tool call the server assembles wrongly
# (which ./bin/doctor.sh's "streamed call" row exists to catch), and a stall,
# which then reappears as a second, slower wait under a different timeout.
# Fail where the fault is instead. Name verified in the 2.1.233 binary.
export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1

# A 27B model is much weaker than Sonnet or Opus at long chains of tool use.
# Keeping the answer budget modest stops it talking past a tool call.
: "${CLAUDE_CODE_MAX_OUTPUT_TOKENS:=8192}"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS

# Claude Code has never heard of this model, so it assumes the 200,000-token
# window the hosted models have, and sizes its own summarising against that.
# Left alone, it cheerfully builds a question the server has to reject with
# "Prompt exceeds maximum context length". Tell it the truth instead.
export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$CTX_SIZE"

# Both ends of this stack give up on a silent request after 300 seconds, and
# they do it under two different names nobody set. A first turn on a cold model
# has to reload ~19.1 GB and then read ~21,000 tokens before it produces a
# single token, so it is the turn most likely to reach that limit — and when it
# does, the two limits expire together and the failure looks like a dead server.
#
# Give the client a MINUTE MORE than the server, so the server aborts first and
# the side that can name the reason is the side that reports it.
#
# Below 300000 has no effect: Claude Code 2.1.233 resolves this variable through
# Math.max(value, 300000), so it can only ever raise the limit, never lower it.
if [ "${SERVE_TIMEOUT:-300}" = "0" ]; then
  _client_timeout_ms=3600000
else
  _client_timeout_ms=$(( (SERVE_TIMEOUT + 60) * 1000 ))
  [ "$_client_timeout_ms" -ge 300000 ] || _client_timeout_ms=300000
fi
export CLAUDE_STREAM_IDLE_TIMEOUT_MS="$_client_timeout_ms"
export API_TIMEOUT_MS="$_client_timeout_ms"
# NOT set: CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS. It exists in the 2.1.233 binary
# and takes precedence over the stream limit when set, but whether the server's
# SSE keepalive frames feed that watchdog has not been established here. Setting
# it on a guess would be a number this repo could not explain.

extra=()
if [ "$LEAN_MCP" = "1" ]; then
  extra+=( --strict-mcp-config )
  mcp_line="strict (LEAN_MCP=1) — MCP servers off, saves ~17k prompt tokens per turn"
else
  mcp_line="your normal config (LEAN_MCP=0)"
fi

echo "claude   -> $BASE_URL   model $MODEL_ID"
echo "context  $CTX_SIZE tokens declared to the harness, $CLAUDE_CODE_MAX_OUTPUT_TOKENS max output"
if [ "${SERVE_TIMEOUT:-300}" = "0" ]; then
  echo "timeout  client gives up after $((_client_timeout_ms / 1000))s of silence; the server never does (SERVE_TIMEOUT=0)"
else
  echo "timeout  client gives up after $((_client_timeout_ms / 1000))s of silence, the server after ${SERVE_TIMEOUT}s — so the server reports it"
fi
echo "mcp      $mcp_line"
echo "note     an \"unrecognized_model\" line at startup is EXPECTED and cosmetic; so is"
echo "         \"claude.ai connectors are disabled\" — that is this script keeping it local"
echo

# ${extra[@]+"${extra[@]}"} rather than "${extra[@]}": under `set -u`, bash 3.2
# (the version macOS ships) treats an EMPTY array as an unset variable and stops.
exec "$CLAUDE_BIN" --model "$MODEL_ID" ${extra[@]+"${extra[@]}"} "$@"
