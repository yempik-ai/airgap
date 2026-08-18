#!/usr/bin/env bash
# harness/hermes.sh — the Hermes Agent (Nous Research) adapter for bin/run.sh.
#
# Sourced by bin/run.sh after bin/env.sh, never run on its own. It does one
# job: point Hermes at the server on this Mac. Checking that the server is up,
# printing the banner and running the probe all live in run.sh, once, for
# every harness.
#
# The wiring is environment variables and two flags, for this run only.
# Nothing under ~/.hermes is written: Hermes keeps its model and endpoint in
# ~/.hermes/config.yaml, but its "custom" provider also takes the address from
# an environment variable, CUSTOM_BASE_URL, which wins over that file
# (hermes_cli/runtime_provider.py, 0.20.4). That is what this adapter sets.
#
# One thing about Hermes that the other adapters do not have to think about:
# it loads ~/.hermes/.env OVER the process environment (python-dotenv with
# override=True, hermes_cli/env_loader.py). So a CUSTOM_BASE_URL line in that
# file would silently beat this script — MEASURED, with a throwaway HERMES_HOME
# whose .env named a closed port: the run went there and failed. harness_wire
# refuses that case rather than start a harness pointed somewhere else.
#
# Every name below was checked against the installed Hermes Agent 0.20.4
# (its --help, its hermes_cli/ and agent/ sources, and its docs); AGENT.md,
# "Verified environment facts", lists them one by one.

# The three names below are the contract: bin/run.sh reads them after sourcing
# this file, which shellcheck cannot see from here.
# shellcheck disable=SC2034

# The endpoint family this harness speaks: mlx-serve's /v1/chat/completions.
# Hermes's plain "custom" provider is OpenAI chat completions unless the URL
# ends in /anthropic (then it speaks Anthropic Messages, at <url>/v1/messages —
# a path mlx-serve does not serve), so chat completions it is.
HARNESS_DIALECT=openai
HARNESS_BIN="$HERMES_BIN"
# One question, one answer, then exit. The prompt is the last argument.
# `-z` is Hermes's scripted one-shot: "single prompt in, final response text
# out, nothing else on stdout or stderr" — the shape run.sh's probe reads. It
# is not identical to an interactive turn: MEASURED on the 9B, `-z` sent
# 15,060 prompt tokens with `thinking=false` at the server, and `chat -q`
# (the interactive path) 17,402 with `thinking=true` and a longer tool list.
# Both are recorded in docs/10-other-harnesses.md.
HARNESS_ONESHOT=(-z)

# Where Hermes keeps its files: ~/.hermes, or wherever HERMES_HOME points
# (Hermes's own override, honoured here for the same reason Hermes has it).
hermes_home() {
  if [ -n "${HERMES_HOME:-}" ]; then
    printf '%s\n' "$HERMES_HOME"
  else
    printf '%s\n' "$HOME/.hermes"
  fi
}

harness_usage() {
  cat <<'EOF'
hermes — run Hermes Agent against the model on your own Mac.

BEFORE YOU RUN IT
  ./bin/serve.sh must already be running in another window. This script checks,
  and tells you if it is not.

WHAT IT DOES
  Starts Hermes on its "custom" provider, pointed at your Mac through the
  environment, for this run only. Nothing in ~/.hermes is changed: not
  config.yaml, not .env. Hermes reads the model's context size from the
  server itself (GET /v1/models, the server's own figure — the CTX_SIZE it
  was started with), so it sizes its own summarising against the truth. Its
  mid-stream reconnects are off and its stall limits are set a minute past
  the server's, so a stall is reported by the side that can name the reason.
  Its background requests — the session title after your first message, any
  summarising later — go to your Mac too (MEASURED: the title request landed
  on the server log).

WHAT IT COSTS
  No extra memory beyond the server that is already running. No money.
  No Hermes account and no key: a loopback address is sent no key at all
  (Hermes gates every key it knows on the host it belongs to).

  Everything this script sends goes to your Mac and nowhere else. What it
  cannot speak for is Hermes's own tools — web search, browser, image tools —
  which reach the internet when you have set them up with keys, exactly as
  they would under any model. And one thing Hermes does at startup that this
  script cannot switch off: `hermes` (the interactive command) runs a
  `git fetch` of its own checkout under ~/.hermes to see whether an update
  exists, once every six hours. Hermes 0.20.4 has no switch for it; this
  repository found none in its sources.

USAGE (run from the folder you want to work in)
  ./bin/run.sh hermes                  start a session in the current folder
  ./bin/run.sh hermes -z "hello"       ask one question and exit (answer only)
  ./bin/run.sh hermes chat -q "hello"  the same, with Hermes's usual screen
  ./bin/run.sh --probe hermes          ask one test question and report
  ./bin/run.sh hermes --help           print this help

  Anything else you type after the name is passed straight to Hermes. Two of
  its own flags are worth knowing here: --reasoning LEVEL (none … ultra) sets
  the thinking effort for the session, and -t/--toolsets picks which of its
  tools the model is offered.

SETTINGS
  LEAN_MCP=0      load your MCP servers, plugins and shell hooks as well.
                  1 (the default) sets HERMES_SAFE_MODE=1, which is Hermes's
                  one switch for all three at once (and for its outbound
                  webhooks); it does not touch your config.yaml or the rules
                  files it reads. What it saves is NOT measured: the test
                  machine has no MCP servers configured for Hermes, and the
                  probe read the same 15,060 prompt tokens either way.
  HERMES_BIN      the command that starts Hermes. Default: hermes
  HERMES_MAX_TOKENS   longest single answer, in tokens. Hermes's own name;
                  unset (the default) leaves it as Hermes decides.
  SERVE_TIMEOUT   seconds of silence before a question is given up on. The
                  client waits a minute longer, so the server is the side that
                  reports a stall. Default: 300

  Not a setting here: Hermes's whole-request retry (agent.api_max_retries in
  config.yaml, default 3, no flag or variable for it in 0.20.4) stays as you
  have it; only the mid-stream reconnects (HERMES_STREAM_RETRIES) are off.

WHAT YOU SHOULD SEE
  Seven or eight lines of settings, a blank line, then Hermes's own screen.

  Two lines from Hermes itself are EXPECTED and cosmetic: a "tirith security
  scanner enabled but not available" warning (its command scanner falls back
  to pattern matching), and, on a fresh install, a note that a deprecated
  TERMINAL_CWD line is in your .env — Hermes's own installer wrote it there,
  commented out. Neither stops the answer.

IF IT SAYS THERE IS NO SERVER
  Open another window, go to the repo root, and run ./bin/serve.sh.
  See docs/06-troubleshooting.md#no-server

IF IT REFUSES BECAUSE OF CUSTOM_BASE_URL IN ~/.hermes/.env
  Hermes loads that file over the environment, so a value there would win
  over this script and send your questions elsewhere. Remove the line, or set
  it to the address the message prints.

READ NEXT
  docs/10-other-harnesses.md
EOF
}

# Sets Hermes's environment, fills HARNESS_ARGS with the two flags it needs on
# the command line, and puts the harness-specific banner lines into
# HARNESS_NOTES. Prints nothing itself: run.sh owns the screen.
harness_wire() {
  # A whole number or nothing. Anything else is refused here rather than
  # dropped by Hermes, which reads it with int() and falls back silently.
  if [ -n "${HERMES_MAX_TOKENS:-}" ] && ! [[ "$HERMES_MAX_TOKENS" =~ ^[0-9]+$ ]]; then
    echo "error: HERMES_MAX_TOKENS=$HERMES_MAX_TOKENS is not a whole number" >&2
    echo "fix:   HERMES_MAX_TOKENS=8192 (an answer cap in tokens), or leave it unset" >&2
    exit 1
  fi

  # Hermes loads $HERMES_HOME/.env over the process environment (override=True,
  # hermes_cli/env_loader.py 0.20.4), so a CUSTOM_BASE_URL line in it beats
  # the export below and points every request wherever it says. MEASURED with
  # a throwaway HERMES_HOME whose .env named a closed port. Refuse that rather
  # than start a harness this script is not actually wiring. Same value:
  # fine.
  _hm_env="$(hermes_home)/.env"
  if [ -f "$_hm_env" ]; then
    _hm_line="$(grep -E '^[[:space:]]*(export[[:space:]]+)?CUSTOM_BASE_URL[[:space:]]*=' "$_hm_env" | tail -n 1 || true)"
    if [ -n "$_hm_line" ]; then
      _hm_val="${_hm_line#*=}"
      _hm_val="${_hm_val#"${_hm_val%%[![:space:]]*}"}"   # strip leading spaces
      _hm_val="${_hm_val%\"}"; _hm_val="${_hm_val#\"}"    # and one pair of quotes
      _hm_val="${_hm_val%\'}"; _hm_val="${_hm_val#\'}"
      if [ "${_hm_val%/}" != "$BASE_URL/v1" ]; then
        echo "error: CUSTOM_BASE_URL is set in $_hm_env ($_hm_val) — Hermes loads that file over this script, so it would win" >&2
        echo "fix:   remove that line from $_hm_env, or set it to $BASE_URL/v1" >&2
        exit 1
      fi
    fi
  fi
  unset _hm_env _hm_line _hm_val

  # The address, and the model. --provider custom is Hermes's own name for a
  # local OpenAI-compatible server (its aliases ollama, vllm and llama.cpp all
  # resolve to it); with it, the address comes from CUSTOM_BASE_URL before
  # anything in config.yaml (runtime_provider.py: explicit → CUSTOM_BASE_URL →
  # config → OpenRouter). base_url gets the /v1 suffix: Hermes appends the
  # endpoint (/chat/completions) to it, and mlx-serve serves that under /v1.
  export CUSTOM_BASE_URL="$BASE_URL/v1"
  HARNESS_ARGS+=( --provider custom -m "$MODEL_ID" )

  # OPENAI_BASE_URL is Hermes's other address variable — read only by its
  # `openai-api` provider (not the one selected above) and by its first-run
  # check, which stops `hermes chat` on a Mac where no provider is configured
  # at all and asks for `hermes setup` (hermes_cli/main.py,
  # _has_any_provider_configured: "OPENAI_BASE_URL alone counts — local
  # models often don't require an API key"). READ in the source, not
  # observed: this Mac has other credentials, so the check never fired here.
  # The value is true either way, and it is what rule 2 asks of every
  # address the harness reads.
  export OPENAI_BASE_URL="$BASE_URL/v1"

  # NOT set: a key. For a loopback address Hermes sends the placeholder
  # "no-key-required" of its own: every key variable it knows is gated on the
  # host it belongs to (OPENAI_API_KEY on openai.com, and so on), so nothing
  # in your ~/.hermes/.env is sent to this Mac either. API_KEY, when set, is
  # therefore not given to Hermes — there is no variable that would carry it
  # to a loopback custom endpoint — and the server does not ask a loopback
  # client for it (AGENT.md, --api-key exempts loopback).

  # Fail where the fault is. Hermes reconnects a broken stream up to 2 times
  # (HERMES_STREAM_RETRIES, env_int default 2 in chat_completion_helpers.py;
  # its docs say 3): off. Its whole-request retry, agent.api_max_retries
  # (default 3, floor 1), is a config.yaml key with no flag or variable in
  # 0.20.4, so it stays as the person has it; the banner says so.
  export HERMES_STREAM_RETRIES=0

  # client_timeout_ms (bin/env.sh) is a minute more than the server's own
  # limit, so the server aborts first and the side that can name the reason is
  # the side that reports it. Hermes has two stall detectors, both in seconds:
  # the streaming one, which for a loopback address takes its ceiling from
  # HERMES_LOCAL_STREAM_STALE_TIMEOUT (default 900; it applies only while
  # HERMES_STREAM_STALE_TIMEOUT is left at its default, which it is here), and
  # the non-streaming one, HERMES_API_CALL_STALE_TIMEOUT (default 90, or off
  # for a local address when unset), which its background requests use.
  # Both read in chat_completion_helpers.py / run_agent.py, 0.20.4. NOT set:
  # HERMES_API_TIMEOUT, the whole-request limit (1800 s) — a long answer is
  # not a stall.
  _hm_secs=$(( $(client_timeout_ms) / 1000 ))
  export HERMES_LOCAL_STREAM_STALE_TIMEOUT="$_hm_secs"
  export HERMES_API_CALL_STALE_TIMEOUT="$_hm_secs"
  unset _hm_secs

  # Validated above. Exported only when set: env.sh does not export it, so a
  # value from config.env would otherwise never reach Hermes. Hermes's own
  # name (cli.py: "env var override: HERMES_MAX_TOKENS").
  if [ -n "${HERMES_MAX_TOKENS:-}" ]; then
    export HERMES_MAX_TOKENS
    HARNESS_NOTES+=( "output   $HERMES_MAX_TOKENS max output tokens per answer (HERMES_MAX_TOKENS)" )
  fi

  # NOT set: a thinking level. Hermes's --reasoning is on the command line
  # already, under Hermes's own name; a setting here would only translate it.
  #
  # NOT set: a context size. Hermes asks the server (GET /v1/models, the
  # `meta.context_length` field mlx-serve fills with the --ctx-size it was
  # started with) before falling back to any default of its own
  # (agent/model_metadata.py, "Local server query"), and re-asks on each
  # start. MEASURED: the request it sent carried max_tokens=65536 with
  # CTX_SIZE=65536, and its config.yaml has no context_length line. There is
  # no environment variable for it in 0.20.4 — model.context_length is a
  # config.yaml key — and none is needed.

  HARNESS_NOTES+=( "provider custom, CUSTOM_BASE_URL (environment only; your ~/.hermes is not changed)" )
  HARNESS_NOTES+=( "context  Hermes reads it from the server's /v1/models — the CTX_SIZE it was started with" )
  HARNESS_NOTES+=( "retries  stream reconnects off (HERMES_STREAM_RETRIES=0); Hermes's own whole-request retry (config.yaml agent.api_max_retries, default 3) stays" )

  # LEAN_MCP=1 is HERMES_SAFE_MODE=1 — Hermes's one switch that skips its MCP
  # servers, plugin discovery, shell hooks and outbound webhooks
  # (tools/mcp_tool.py, hermes_cli/plugins.py, agent/shell_hooks.py,
  # agent/outbound_webhooks.py). The environment variable alone does exactly
  # that; the --safe-mode FLAG would also set --ignore-user-config and
  # --ignore-rules, which drop the person's config.yaml and AGENTS.md — so
  # the flag is not used. Not measured: the test machine has no MCP servers
  # configured for Hermes, and the probe read 15,060 prompt tokens with and
  # without it.
  if [ "$LEAN_MCP" = "1" ]; then
    export HERMES_SAFE_MODE=1
    HARNESS_NOTES+=( "mcp      MCP servers, plugins and shell hooks off (LEAN_MCP=1, HERMES_SAFE_MODE=1) — saving not measured: none configured on the test machine" )
  else
    HARNESS_NOTES+=( "mcp      your normal config (LEAN_MCP=0)" )
  fi

  HARNESS_NOTES+=( "note     Hermes may say its \"tirith\" scanner is unavailable, and mention a TERMINAL_CWD line its" )
  HARNESS_NOTES+=( "         installer left in ~/.hermes/.env — both EXPECTED and cosmetic; \`hermes\` also runs a git fetch of its own checkout at start" )
}
