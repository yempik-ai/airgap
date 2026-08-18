#!/usr/bin/env bash
# harness/codex.sh — the Codex CLI adapter for bin/run.sh.
#
# Sourced by bin/run.sh after bin/env.sh, never run on its own. It does one
# job: point Codex's model settings at the server on this Mac. Checking that
# the server is up, printing the banner and running the probe all live in
# run.sh, once, for every harness.
#
# The wiring is `-c key=value` overrides only. Nothing under ~/.codex is read
# specially and nothing is written there by this file: an override is layered
# on top of whatever config.toml the person already has, and disappears when
# the command ends. `--oss` is deliberately not used — it puts Codex's own
# provider path in the middle, which can list and pull models by itself, and
# this repo already has one downloader.
#
# Every key below is recognised by the codex-cli 0.147.0 binary, checked with
# that binary's own validator (`--strict-config` rejects an unknown -c key by
# name; a deliberate typo beside each key was rejected). AGENT.md, "Verified
# environment facts", lists them one by one.

# The three names below are the contract: bin/run.sh reads them after sourcing
# this file, which shellcheck cannot see from here.
# shellcheck disable=SC2034

# The endpoint family this harness speaks: mlx-serve's /v1/responses.
# NOT /v1/chat/completions — 0.147.0 refuses to start on `wire_api = "chat"`
# ("`wire_api = "chat"` is no longer supported. How to fix: set
# `wire_api = "responses"`"), MEASURED on this machine. mlx-serve 26.8.8 serves
# both; only one of them is still reachable from this harness.
HARNESS_DIALECT=openai
HARNESS_BIN="$CODEX_BIN"
# bin/doctor.sh's harness row would otherwise print the openai dialect's
# default endpoint, /v1/chat/completions — a lie for this adapter, which is
# wired to wire_api="responses" above. This override, which doctor.sh prefers
# over the dialect default when set, points that row at the truth.
HARNESS_ENDPOINT=/v1/responses
# One question, one answer, then exit. The prompt is the last argument.
# --skip-git-repo-check because run.sh may be run from any folder, and
# `codex exec` otherwise stops with "Not inside a trusted directory and
# --skip-git-repo-check was not specified." (MEASURED, from a fresh temp dir).
# It is an `exec` flag, not a global one — `codex --skip-git-repo-check exec`
# is refused by the argument parser — so it can only live here, on the line
# run.sh builds itself. Somebody typing `./bin/run.sh codex exec …` by hand
# outside a git checkout adds it themselves; harness_usage says so.
HARNESS_ONESHOT=(exec --skip-git-repo-check)

# The provider this adapter invents and then selects. A name of its own, chosen
# to be unlikely in anybody's config.toml — but `-c` merges into the table, so a
# provider you already declared under this name keeps any key this adapter does
# not override. A collision is unlikely, not impossible.
CODEX_PROVIDER_ID=airgap

harness_usage() {
  cat <<'EOF'
codex — run the Codex CLI against the model on your own Mac.

BEFORE YOU RUN IT
  ./bin/serve.sh must already be running in another window. This script checks,
  and tells you if it is not.

WHAT IT DOES
  Starts Codex with a provider of its own, pointed at your Mac, selected for
  this run only. Nothing in your ~/.codex is read specially and nothing there
  is changed. It also puts a placeholder in CODEX_API_KEY, because Codex
  otherwise sends your ChatGPT sign-in token to whichever address the provider
  names — on this Mac that is your own machine, but it is still your token.

WHAT IT COSTS
  No extra memory beyond the server that is already running. No money.
  No Codex account is needed: this was checked by running it, and a custom
  provider with no key requirement answers.

  Everything this script sends goes to your Mac and nowhere else. What it
  cannot speak for is the MCP servers you set up yourself in
  ~/.codex/config.toml: those are yours, some of them talk to the internet,
  and Codex 0.147.0 has no way to switch them off from the command line. The
  "mcp" line the banner prints says which ones LEAN_MCP=1 does switch off.

USAGE (run from the folder you want to work in)
  ./bin/run.sh codex                   start a session in the current folder
  ./bin/run.sh codex exec "hello"      ask one question and exit
  ./bin/run.sh --probe codex           ask one test question and report
  ./bin/run.sh codex --help            print this help

  Anything else you type after the name is passed straight to Codex, so
  `codex --help` in another window is how you read Codex's own help. One flag
  of its own is worth knowing here: outside a git checkout, `codex exec`
  refuses unless you add --skip-git-repo-check, so the one-shot form there
  reads ./bin/run.sh codex exec --skip-git-repo-check "hello". --probe adds it
  for you, which is why --probe works from any folder.

SETTINGS
  LEAN_MCP=0      load your plugins as well. They cost 935 prompt tokens per
                  turn on the test machine (MEASURED: 9,336 tokens with
                  LEAN_MCP=1 against 10,271 with LEAN_MCP=0, --probe, 9B).
                  See the "mcp" line the banner prints for what 1 does and
                  does not switch off.
  CODEX_BIN       the command that starts Codex. Default: codex
  SERVE_TIMEOUT   seconds of silence before a question is given up on. The
                  client waits slightly longer than the server, so the server
                  is the side that reports a stall. Default: 300

  Codex has no answer-length or thinking setting here. Its own
  model_reasoning_effort, from your config.toml, is left exactly as you set it:
  nothing in this repo has measured what changing it costs on a local model.

WHAT YOU SHOULD SEE
  Six or seven lines of settings, a blank line, then Codex's own screen.

  Two lines at startup are EXPECTED and cosmetic. "failed to refresh available
  models" is Codex asking the server for a model list in a shape mlx-serve
  does not send; the model still answers. "Model metadata for … not found" is
  Codex having never heard of a model name that only exists on your Mac.

IF IT SAYS THERE IS NO SERVER
  Open another window, go to the repo root, and run ./bin/serve.sh.
  See docs/06-troubleshooting.md#no-server

READ NEXT
  docs/10-other-harnesses.md
EOF
}

# Fills HARNESS_ARGS with the -c overrides Codex needs on the command line,
# sets the one environment variable it must not be left to guess, and puts the
# harness-specific banner lines into HARNESS_NOTES. Prints nothing: run.sh owns
# the screen.
harness_wire() {
  _cx="model_providers.$CODEX_PROVIDER_ID"

  # The provider, and then the choice of it. `-c` parses the value as TOML and
  # falls back to a literal string, so every string value here is quoted as
  # TOML rather than relying on that fallback.
  #
  # base_url gets the /v1 suffix: Codex appends the endpoint (`/responses`) to
  # it, and mlx-serve serves that under /v1.
  HARNESS_ARGS+=( -c "model_provider=\"$CODEX_PROVIDER_ID\"" )
  HARNESS_ARGS+=( -c "$_cx.name=\"$CODEX_PROVIDER_ID\"" )
  HARNESS_ARGS+=( -c "$_cx.base_url=\"$BASE_URL/v1\"" )
  HARNESS_ARGS+=( -c "$_cx.wire_api=\"responses\"" )

  # Fail where the fault is. A retry against a local server hides a stall
  # behind a second, slower wait, and hides a malformed stream behind a request
  # that happens to work. client_timeout_ms (bin/env.sh) is a minute more than
  # the server's own limit, so the server aborts first and the side that can
  # name the reason is the side that reports it. Codex 0.147.0 applies this
  # value as given: it has no floor of its own that this repo has found.
  HARNESS_ARGS+=( -c "$_cx.request_max_retries=0" )
  HARNESS_ARGS+=( -c "$_cx.stream_max_retries=0" )
  HARNESS_ARGS+=( -c "$_cx.stream_idle_timeout_ms=$(client_timeout_ms)" )

  # Codex has never heard of this model, so it falls back to metadata for a
  # hosted one and would size its own compaction against that window. Tell it
  # the truth instead.
  HARNESS_ARGS+=( -c "model_context_window=$CTX_SIZE" )

  # Quiet and local: no analytics, no trace export, no update check. All three
  # keys exist in 0.147.0 ("none" is one of the four values trace_exporter
  # accepts — the binary names the other three when given a bad one).
  HARNESS_ARGS+=( -c "analytics.enabled=false" )
  HARNESS_ARGS+=( -c "otel.trace_exporter=\"none\"" )
  HARNESS_ARGS+=( -c "check_for_update_on_startup=false" )

  HARNESS_ARGS+=( -m "$MODEL_ID" )

  # A provider with no env_key needs no key at all — `codex exec` runs
  # unauthenticated against one, MEASURED. But left alone, Codex falls back to
  # the ChatGPT sign-in in ~/.codex/auth.json and sends that JWT, plus a
  # chatgpt-account-id header, to whatever base_url names. That address is this
  # Mac, so nothing leaves it; sending somebody's real token to a server that
  # never asked for one is still the wrong default. A placeholder takes
  # priority over both (MEASURED: with CODEX_API_KEY set, the Authorization
  # header carried exactly that value and no account header was sent).
  #
  # The server accepts anything here unless you set API_KEY.
  if [ -n "$API_KEY" ]; then
    export CODEX_API_KEY="$API_KEY"
  else
    export CODEX_API_KEY="mlx-serve"
  fi

  # NOT set: model_providers.<id>.env_key. The provider needs no key, and
  # naming an env var here would make Codex require one.
  #
  # NOT set: tools.web_search. The key exists in 0.147.0, and setting it is a
  # no-op: MEASURED against a listener that prints the request body, the tools
  # array carries `{"type":"web_search","external_web_access":false}` with the
  # key unset, false and true alike, on a clean CODEX_HOME as well as this
  # one. That entry is the provider-side Responses tool — it is offered TO the
  # server named by base_url, which is this Mac, and it is offered with web
  # access already off. The client-side variant that would fetch by itself
  # needs the `standalone_web_search` feature, which `codex features list`
  # reports as "under development / false". So there is nothing here to switch
  # off, and passing a key that changes nothing would be worse than saying so.
  #
  # NOT set: anything to neutralise the profile layer. -c wins over it,
  # MEASURED: with a throwaway CODEX_HOME holding a `sneaky.config.toml` that
  # names a different model_provider, `-p sneaky` alone resolves to that
  # provider, and `-p sneaky` together with the overrides above resolves to
  # `airgap` whichever side of them the flag is typed. A config.toml cannot
  # select a profile by itself either: 0.147.0 refuses the legacy
  # `profile = "name"` key outright ("no longer supported; use --profile").
  #
  # NOT set: an answer-length cap or a thinking knob. Codex's reasoning effort
  # comes from the person's own config.toml and this repo has not measured what
  # changing it costs on a local model, so it is left alone (spec, rule 4).

  HARNESS_NOTES+=( "provider $CODEX_PROVIDER_ID, wire_api responses (-c overrides only; your ~/.codex is not changed)" )
  HARNESS_NOTES+=( "retries  off — one attempt per request, so a stall is reported where it happens" )

  # LEAN_MCP=1 switches off the plugins, and only the plugins. MEASURED on this
  # machine with `codex mcp list`: 10 MCP servers with them, 4 without — the 6
  # that go are every one that reaches the network. The 4 that remain are the
  # ones written in ~/.codex/config.toml, and 0.147.0 has no command-line
  # switch for those: `-c 'mcp_servers={}'` is accepted by the TOML parser and
  # then ignored, because an override is MERGED into the table rather than
  # replacing it (MEASURED: `codex mcp list` prints the same 10 servers with
  # and without it). `--ignore-user-config` would drop them, and the person's
  # approvals and provider trust with them, so it is not used.
  if [ "$LEAN_MCP" = "1" ]; then
    HARNESS_ARGS+=( -c "features.plugins=false" )
    HARNESS_NOTES+=( "mcp      plugins off (LEAN_MCP=1), saves 935 prompt tokens per turn (measured, 9B) —" )
    HARNESS_NOTES+=( "         the MCP servers in your own config.toml stay on; 0.147.0 cannot switch those off" )
  else
    HARNESS_NOTES+=( "mcp      your normal config (LEAN_MCP=0)" )
  fi

  unset _cx
}
