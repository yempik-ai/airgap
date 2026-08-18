#!/usr/bin/env bash
# harness/claude-code.sh — the Claude Code adapter for bin/run.sh.
#
# Sourced by bin/run.sh after bin/env.sh, never run on its own. It does one
# job: point every one of Claude Code's model settings at the server on this
# Mac. Checking that the server is up, printing the banner and running the
# probe all live in run.sh, once, for every harness.
#
# This is bin/claude-local.sh's wiring, moved here unchanged. Every variable
# name below was verified against the Claude Code 2.1.233 binary (AGENT.md,
# "Verified environment facts"); the probe recorded in docs/10-other-harnesses.md
# ran on 2.1.234, which changed none of them.

# The three names below are the contract: bin/run.sh reads them after sourcing
# this file, which shellcheck cannot see from here.
# shellcheck disable=SC2034

# The endpoint family this harness speaks: mlx-serve's /v1/messages.
HARNESS_DIALECT=anthropic
HARNESS_BIN="$CLAUDE_BIN"
# One question, one answer, then exit. The prompt is the last argument.
HARNESS_ONESHOT=(-p)

harness_usage() {
  cat <<'EOF'
claude-code — run Claude Code against the model on your own Mac.

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

  The same thing, written the long way, which is what the short way runs:
  ./bin/run.sh claude-code             start a session in the current folder
  ./bin/run.sh --probe claude-code     ask one test question and report

  Anything you type after the script name is passed straight to Claude Code.
  You can run this script from any folder. Use its full path, for example:
      ~/dev/local-llms/airgap/bin/claude-local.sh

SETTINGS
  LEAN_MCP=0      load your normal extra tool servers. They cost about 17,000
                  prompt tokens on every turn, so the default is 1 (off).
  CLAUDE_BIN      the command that starts Claude Code. Default: claude
  CLAUDE_CODE_MAX_OUTPUT_TOKENS   longest single answer. Default: 8192
  MAX_THINKING_TOKENS   0 turns the model's thinking off; unset (the default)
                  leaves it on, as the model ships. Off is 3x fewer output
                  tokens and 3x faster on the one prompt measured (9B, n=1);
                  what it costs in answer quality has NOT been measured. A
                  positive number caps only the thinking text stored per turn,
                  not the time — measured: 128, 1024 and unset all took ~21 s.
  SERVE_TIMEOUT   seconds of silence before a question is given up on. The
                  client waits slightly longer than the server, so the server
                  is the side that reports a stall. Default: 300

WHAT YOU SHOULD SEE
  Eight lines of settings, then a blank line, then Claude Code's own screen.
  The first line starts with "claude-code"; the last two are one "note" that
  wraps. A ninth line appears only when SERVE_TIMEOUT is low enough that
  Claude Code's own 300-second floor overrides it, and says so.

  After that: one line about an "unrecognized_model", and possibly one saying
  claude.ai connectors are disabled because an auth source is set. Both are
  EXPECTED. Neither is an error and nothing is wrong. Claude Code has simply
  never heard of a model name that only exists on your Mac, and the "auth
  source" is the placeholder token this script sets so nothing reaches
  claude.ai.

IF IT SAYS THERE IS NO SERVER
  Open another window, go to the repo root, and run ./bin/serve.sh.
  See docs/06-troubleshooting.md#no-server

READ NEXT
  docs/05-run-it.md
EOF
}

# Sets Claude Code's environment, fills HARNESS_ARGS with the flags it needs on
# the command line, and puts the three harness-specific banner lines into
# HARNESS_NOTES. Prints nothing itself: run.sh owns the screen.
harness_wire() {
  # Thinking is on by default in every catalog build (the 27B at "xhigh"
  # effort), and Claude Code sends a thinking budget on every request.
  # MAX_THINKING_TOKENS is Claude Code's own name for that budget: 0 sends
  # thinking:{type:"disabled"}; a positive value caps the thinking TEXT the
  # harness stores and replays, but not the tokens the model generates before
  # answering (MEASURED, 9B: 128, 1024 and unset all produced 1156 tokens in
  # ~21 s; 0 produced 376 in 7.2 s). Unset leaves the model as it ships.
  # Anything else is a typo, refused here rather than silently ignored by
  # Claude Code.
  if [ -n "${MAX_THINKING_TOKENS:-}" ] && ! [[ "$MAX_THINKING_TOKENS" =~ ^[0-9]+$ ]]; then
    echo "error: MAX_THINKING_TOKENS=$MAX_THINKING_TOKENS is not a whole number" >&2
    echo "fix:   MAX_THINKING_TOKENS=0 (thinking off), a positive number, or leave it unset (on)" >&2
    exit 1
  fi

  # Point every model setting at your Mac. Claude Code chooses a small, fast
  # model on its own for background work such as naming a conversation, and
  # other models for subagents, the auto-mode classifier and its background
  # classifier. Every name below exists in the Claude Code 2.1.233 binary; they
  # are all set because different versions read different ones, and one left
  # pointing at Anthropic would quietly reach for the internet.
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

  # Empty, not removed. A real key in your shell would otherwise take priority
  # and send your questions to Anthropic instead of to your Mac.
  export ANTHROPIC_API_KEY=""

  # Keep the session quiet and local: no usage reporting, no crash reporting,
  # no update check, no marketplace auto-install and no background tasks in the
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

  # Validated above. Exported only when set: env.sh does not export it, so a
  # value from config.env would otherwise never reach Claude Code.
  if [ -n "${MAX_THINKING_TOKENS:-}" ]; then
    export MAX_THINKING_TOKENS
  fi

  # client_timeout_ms (bin/env.sh) is a minute more than the server's own
  # limit, so the server aborts first and the side that can name the reason is
  # the side that reports it.
  #
  # Below 300000 has no effect: Claude Code 2.1.233 resolves these variables
  # through Math.max(value, 300000), so it can only ever raise the limit, never
  # lower it. That floor is a fact about this binary, which is why it is here
  # and not in env.sh — and when it bites, the banner would otherwise state a
  # wait this harness will not honour, so it says so.
  _cc_timeout_ms="$(client_timeout_ms)"
  if [ "$_cc_timeout_ms" -lt 300000 ]; then
    HARNESS_NOTES+=( "timeout  Claude Code 2.1.233 raises anything under 300s to 300s, so it waits 300s, not $((_cc_timeout_ms / 1000))s" )
    _cc_timeout_ms=300000
  fi
  export CLAUDE_STREAM_IDLE_TIMEOUT_MS="$_cc_timeout_ms"
  export API_TIMEOUT_MS="$_cc_timeout_ms"
  # NOT set: CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS. It exists in the 2.1.233
  # binary and takes precedence over the stream limit when set, but whether the
  # server's SSE keepalive frames feed that watchdog has not been established
  # here. Setting it on a guess would be a number this repo could not explain.

  # The answer cap is Claude Code's own knob, not something every harness has,
  # so it is a note here rather than part of run.sh's common context line.
  HARNESS_NOTES+=( "output   $CLAUDE_CODE_MAX_OUTPUT_TOKENS max output tokens per answer (CLAUDE_CODE_MAX_OUTPUT_TOKENS)" )

  HARNESS_ARGS+=( --model "$MODEL_ID" )
  if [ "$LEAN_MCP" = "1" ]; then
    HARNESS_ARGS+=( --strict-mcp-config )
    HARNESS_NOTES+=( "mcp      strict (LEAN_MCP=1) — MCP servers off, saves ~17k prompt tokens per turn" )
  else
    HARNESS_NOTES+=( "mcp      your normal config (LEAN_MCP=0)" )
  fi

  if [ "${MAX_THINKING_TOKENS:-}" = "0" ]; then
    HARNESS_NOTES+=( "thinking OFF (MAX_THINKING_TOKENS=0) — 3x fewer output tokens on the one prompt measured; quality cost not measured" )
  elif [ -n "${MAX_THINKING_TOKENS:-}" ]; then
    HARNESS_NOTES+=( "thinking on, stored text capped at $MAX_THINKING_TOKENS tokens (MAX_THINKING_TOKENS) — measured no speed change; 0 turns it off" )
  else
    HARNESS_NOTES+=( "thinking on, as the model ships — MAX_THINKING_TOKENS=0 turns it off (measured 3x faster on the 9B; quality cost not measured)" )
  fi

  HARNESS_NOTES+=( "note     an \"unrecognized_model\" line at startup is EXPECTED and cosmetic; so is" )
  HARNESS_NOTES+=( "         \"claude.ai connectors are disabled\" — that is this script keeping it local" )

  unset _cc_timeout_ms
}
