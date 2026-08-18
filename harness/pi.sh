#!/usr/bin/env bash
# harness/pi.sh — the Pi (pi.dev) adapter for bin/run.sh.
#
# Sourced by bin/run.sh after bin/env.sh, never run on its own. It does one
# job: point Pi at the server on this Mac. Checking that the server is up,
# printing the banner and running the probe all live in run.sh, once, for
# every harness.
#
# Pi has no command-line or environment way to name a provider. Its one route
# is a file, ~/.pi/agent/models.json (its own docs: "Add providers via
# ~/.pi/agent/models.json"), and the only alternative it offers is an
# extension — TypeScript that runs inside Pi, which this repository does not
# ship (AGENT.md, "Scope"). So this adapter writes ONE provider, `airgap`, into
# that file — through harness_prepare, which run.sh calls after every refusal
# and never in the offline tests — and keeps everything else in the file as it
# was. That is the one file this repository changes under a home folder, and
# the banner says so on every run.
#
# Every name below was checked against the installed Pi 0.84.2 (its --help,
# its dist/ sources and its docs/models.md); AGENT.md, "Verified environment
# facts", lists them one by one.

# The three names below are the contract: bin/run.sh reads them after sourcing
# this file, which shellcheck cannot see from here.
# shellcheck disable=SC2034

# The endpoint family this harness speaks: mlx-serve's /v1/messages. Pi also
# speaks OpenAI chat completions and Responses, and the first of those was tried
# (MEASURED, 9B: it answered, 1,831 prompt tokens, but the server logged the
# system prompt as `sys=0b` — Pi sends it under the `developer` role, which
# mlx-serve does not report and this repository cannot vouch for). Anthropic
# Messages is the endpoint ./bin/doctor.sh proves tool calls on, and Pi's
# --thinking switch maps onto it exactly (`--thinking off` logged
# `thinking=false` at the server, MEASURED).
HARNESS_DIALECT=anthropic
HARNESS_BIN="$PI_BIN"
# One question, one answer, then exit. The prompt is the last argument.
HARNESS_ONESHOT=(-p)

# The provider this adapter writes and then selects. The same name as the
# Codex adapter's, for the same reason: unlikely in anybody's own file, and
# easy to find there.
PI_PROVIDER_ID=airgap

# The folder Pi reads its config from: ~/.pi/agent, or wherever
# PI_CODING_AGENT_DIR points (Pi's own override, honoured here for the same
# reason Pi has it). tests/pi-models-json.sh points it at a scratch folder.
pi_agent_dir() {
  if [ -n "${PI_CODING_AGENT_DIR:-}" ]; then
    printf '%s\n' "$PI_CODING_AGENT_DIR"
  else
    printf '%s\n' "$HOME/.pi/agent"
  fi
}

# The provider block, exactly as it is written into models.json — printed by
# the refusal below too, so a person can paste it in by hand.
pi_provider_json() {
  cat <<EOF
    "$PI_PROVIDER_ID": {
      "baseUrl": "$BASE_URL",
      "api": "anthropic-messages",
      "apiKey": "mlx-serve",
      "models": [
        { "id": "$MODEL_ID", "reasoning": true, "contextWindow": $CTX_SIZE }
      ]
    }
EOF
}

harness_usage() {
  cat <<'EOF'
pi — run Pi (pi.dev) against the model on your own Mac.

BEFORE YOU RUN IT
  ./bin/serve.sh must already be running in another window. This script checks,
  and tells you if it is not.

WHAT IT DOES
  Writes one provider, "airgap", into ~/.pi/agent/models.json (or into the
  folder PI_CODING_AGENT_DIR names, if you use Pi's own override) — the file
  Pi reads custom providers from, and the only way Pi 0.84.2 can be told
  about one — then starts Pi on that provider's one model. Everything else in that
  file is kept exactly as it was, and the file is only rewritten when the
  address, model or context size changed. Pi is started offline: no update
  check, no install ping, no model-catalog refresh (PI_OFFLINE=1).

WHAT IT COSTS
  No extra memory beyond the server that is already running. No money.
  No Pi account and no key: the provider carries a placeholder.

  Everything Pi sends for the model goes to your Mac and nowhere else. What
  this script cannot speak for is the extensions you installed into Pi
  yourself: an extension is code that runs inside Pi, and some of them talk
  to the internet. LEAN_MCP=1 (the default) starts Pi with --no-extensions,
  which is Pi's own switch for all of them at once.

USAGE (run from the folder you want to work in)
  ./bin/run.sh pi                      start a session in the current folder
  ./bin/run.sh pi -p "hello"           ask one question and exit
  ./bin/run.sh --probe pi              ask one test question and report
  ./bin/run.sh pi --help               print this help

  Anything else you type after the name is passed straight to Pi. Two of Pi's
  own flags are worth knowing here: --thinking off turns the model's thinking
  off for the session (measured on the 9B: 3x faster elsewhere in this repo,
  and the one probe tried with it answered wrongly — n=1, quality cost not
  measured), and --no-session keeps the session out of ~/.pi/agent/sessions.

SETTINGS
  LEAN_MCP=0      load your Pi extensions as well. Pi has no MCP of its own;
                  extensions are how MCP and every other tool server reach
                  it. What that costs is NOT measured: the test machine has
                  no Pi extensions installed, and the probe read the same
                  2,069 prompt tokens with and without --no-extensions.
  PI_BIN          the command that starts Pi. Default: pi
  SERVE_TIMEOUT   seconds of silence before a question is given up on. The
                  server reports a stall at this limit; see the timeout note
                  below for what Pi does.

  Pi's answer cap (models.json "maxTokens", Pi's default 16384), thinking level
  (--thinking, or "defaultThinkingLevel" in settings.json), retries and idle
  timeout ("retry" and "httpIdleTimeoutMs" in ~/.pi/agent/settings.json) are
  Pi's own settings under Pi's own names, and this script does not rewrite
  your settings.json to change them. Two of them are worth knowing: Pi retries
  a failed request up to 3 times with backoff ("retry.enabled", default true),
  and gives up on a silent request after "httpIdleTimeoutMs" — 300 s by
  default, the same moment the server does at SERVE_TIMEOUT=300, so set it to
  360000 there yourself if you want the server to be the side that reports.

WHAT YOU SHOULD SEE
  Six or seven lines of settings, a blank line, then Pi's own screen.

IF IT SAYS THERE IS NO SERVER
  Open another window, go to the repo root, and run ./bin/serve.sh.
  See docs/06-troubleshooting.md#no-server

IF IT SAYS IT CANNOT READ models.json
  Pi allows comments in that file; this script does not rewrite a file it
  cannot read back exactly. The message prints the provider block — paste it
  into ~/.pi/agent/models.json under "providers" yourself, once.

READ NEXT
  docs/10-other-harnesses.md
EOF
}

# Sets Pi's environment, fills HARNESS_ARGS with the flags it needs on the
# command line, and puts the harness-specific banner lines into HARNESS_NOTES.
# Writes nothing and prints nothing: the file goes through harness_prepare,
# and run.sh owns the screen.
harness_wire() {
  # No startup network at all: no version check against pi.dev, no install
  # ping, no package update check, and no model-catalog refresh for the
  # built-in providers (Pi's own switch for all four; PI_TELEMETRY=0 and
  # PI_SKIP_VERSION_CHECK=1 are each a subset of it). Read in Pi 0.84.2's
  # dist/main.js and dist/core/model-runtime.js.
  export PI_OFFLINE=1

  # If PI_CODING_AGENT_DIR is set (Pi's own override, which pi_agent_dir
  # honours), Pi must see the same value, or the file would be written in one
  # place and read from another. A value from config.env is not exported by
  # env.sh, so it is exported here.
  if [ -n "${PI_CODING_AGENT_DIR:-}" ]; then
    export PI_CODING_AGENT_DIR
  fi

  # Pi's `provider/id` model pattern: the provider harness_prepare writes, and
  # the one model in it. Nothing in ~/.pi/agent/settings.json
  # (defaultProvider, defaultModel) is read for this choice.
  HARNESS_ARGS+=( --model "$PI_PROVIDER_ID/$MODEL_ID" )

  # NOT set: an API key. The provider carries the placeholder "mlx-serve" so
  # Pi lists the model as usable (its docs: keyless local servers "should keep
  # a dummy value"). API_KEY, when set, is not written into models.json: the
  # server does not ask a loopback client for it (AGENT.md, --api-key exempts
  # loopback), and a real key does not belong in a file this repository
  # rewrites.
  #
  # NOT set: an answer cap. Pi's own default for a custom model is 16384
  # tokens ("maxTokens", docs/models.md), and this repository has not measured
  # a reason to change it for this harness.
  #
  # NOT set: a thinking level. Pi's --thinking is on the command line already,
  # under Pi's own name; a setting here would only translate it (rule 4).
  #
  # NOT set: retries and the idle timeout. Both live in ~/.pi/agent/
  # settings.json ("retry.*", "httpIdleTimeoutMs"), which is your global Pi
  # configuration for every provider you use, and this script does not
  # rewrite it. Pi's defaults there: 3 agent-level retries with backoff, and
  # 300 s of idle before it gives up — which is SERVE_TIMEOUT's default too,
  # so both sides give up together. The banner says so.

  HARNESS_NOTES+=( "provider $PI_PROVIDER_ID in $(pi_agent_dir)/models.json — the one file this script writes; your other providers there are kept" )
  HARNESS_NOTES+=( "retries  Pi's own (settings.json \"retry\", default 3) — not changed by this script; idle limit is Pi's httpIdleTimeoutMs (default 300s)" )

  # LEAN_MCP=1 is Pi's own --no-extensions. Pi has no MCP of its own —
  # "build an extension that adds MCP support" is its answer — so extensions
  # are the whole of what this switch can reach, and it reaches all of them
  # (explicit -e paths still load). Not measured: the test machine has no Pi
  # extensions installed, and the probe read 2,069 prompt tokens with and
  # without the flag.
  if [ "$LEAN_MCP" = "1" ]; then
    HARNESS_ARGS+=( --no-extensions )
    HARNESS_NOTES+=( "mcp      extensions off (LEAN_MCP=1, Pi's --no-extensions) — saving not measured: none installed on the test machine" )
  else
    HARNESS_NOTES+=( "mcp      your extensions on (LEAN_MCP=0)" )
  fi
}

# Writes the `airgap` provider into models.json, keeping everything else in the
# file, and only when the block there differs from what would be written. Runs
# after every refusal in run.sh and before the banner; never in the tests
# except tests/pi-models-json.sh, which points PI_CODING_AGENT_DIR at a scratch
# folder. Refuses, naming the block to paste, when the file cannot be read
# back exactly — Pi accepts comments in it, and a file this cannot round-trip
# is not rewritten.
harness_prepare() {
  _pi_dir="$(pi_agent_dir)"
  _pi_file="$_pi_dir/models.json"

  if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "error: '$PYTHON_BIN' is not installed — this script needs it to write $_pi_file" >&2
    echo "fix:   set PYTHON_BIN in config.env, or add this block to \"providers\" in $_pi_file yourself:" >&2
    pi_provider_json >&2
    exit 1
  fi

  mkdir -p "$_pi_dir"
  # The Python reads the existing file (or none), upserts the one provider,
  # and writes atomically beside it. Exit 0: written or unchanged; exit 2: the
  # file is there and is not plain JSON this can read back.
  if ! "$PYTHON_BIN" - "$_pi_file" "$PI_PROVIDER_ID" "$BASE_URL" "$MODEL_ID" "$CTX_SIZE" <<'PY'
import json, os, sys, tempfile
path, pid, base_url, model_id, ctx = sys.argv[1:6]
entry = {
    "baseUrl": base_url,
    "api": "anthropic-messages",
    "apiKey": "mlx-serve",
    "models": [{"id": model_id, "reasoning": True, "contextWindow": int(ctx)}],
}
data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if text.strip():
        try:
            data = json.loads(text)
        except ValueError:
            sys.exit(2)
        if not isinstance(data, dict):
            sys.exit(2)
providers = data.get("providers")
if not isinstance(providers, dict):
    providers = {}
    data["providers"] = providers
if providers.get(pid) == entry:
    sys.exit(0)
providers[pid] = entry
fd, tmp = tempfile.mkstemp(prefix=".models.json.", dir=os.path.dirname(path) or ".")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
  then
    echo "error: cannot read $_pi_file back as plain JSON, so this script will not rewrite it" >&2
    echo "fix:   add this block under \"providers\" in that file yourself (Pi allows comments there; this script does not rewrite a file it cannot round-trip):" >&2
    pi_provider_json >&2
    exit 1
  fi
  unset _pi_dir _pi_file
}
