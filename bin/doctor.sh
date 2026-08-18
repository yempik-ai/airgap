#!/usr/bin/env bash
# bin/doctor.sh — check everything, change nothing.
#
# This is the script to run when something is wrong, and the script to run
# before you ask anyone for help. It looks at your Mac, your tools, your model
# folder, the server, and Claude Code's settings, and prints one line per check.
#
# It NEVER starts anything, stops anything, installs anything, or edits
# anything. If the server is not running, it says so and skips those checks
# instead of failing them.
#
# Read docs/06-troubleshooting.md for what each failure means.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

usage() {
  cat <<'EOF'
doctor.sh — check the whole setup and tell you what to fix.

WHAT IT DOES
  Prints one line per check, in five groups:
    environment       your Mac: version, chip, memory, disk
    tools             homebrew, git-lfs, mlx-serve, Claude Code
    model             the folder of weights, and whether they are real files
    server            whether the server is running, answering correctly,
                      whether its prefix cache is doing its job (read from the
                      server's own log and counters — see docs/07-tuning.md §5),
                      and whether the model can make a tool call — plainly and
                      streamed, the way Claude Code needs it
    harness wiring    one row per harness/*.sh — installed, and which endpoint
                      it targets — plus whether Claude Code specifically will
                      be pointed at your Mac

  Each line starts with one of four words:
    PASS   this is fine
    WARN   this works, but it is not what is recommended
    FAIL   this must be fixed. The line ends with the page that fixes it.
    SKIP   this could not be checked yet, usually because the server is off

WHAT IT DOES NOT DO
  It never starts the server, never stops it, never installs anything, and
  never changes a setting. Running it cannot break anything.

WHAT IT COSTS
  A few seconds. No memory. Nothing leaves your Mac, except three short
  requests to your own server if it happens to be running: an 8-token
  question and two small tool calls, one plain and one streamed (about 70
  output tokens each — MEASURED on the 9B; a longer wait on a bigger model
  is that model thinking first, which is what it will do in a session too).

USAGE (run from the repo root)
  ./bin/doctor.sh            run every check
  ./bin/doctor.sh --help     print this help

SETTINGS
  PROBE=0    do not send the three small test requests to a running server.
             Default is 1. They go to your own Mac and nowhere else. Set 0 if
             the server has handed its memory back and you do not want to make
             it reload the model.

EXIT CODE
  0 when nothing FAILED (warnings do not fail). 1 when something FAILED.
  So you can paste the whole output into a support request.

READ NEXT
  docs/06-troubleshooting.md
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") : ;;
  *) echo "doctor.sh: I do not understand '$1'. Try: ./bin/doctor.sh --help" >&2; exit 2 ;;
esac

: "${PROBE:=1}"

N_PASS=0; N_WARN=0; N_FAIL=0; N_SKIP=0

row() {
  _st="$1"; _name="$2"; _detail="$3"; _ptr="${4:-}"
  case "$_st" in
    PASS) N_PASS=$((N_PASS + 1)) ;;
    WARN) N_WARN=$((N_WARN + 1)) ;;
    FAIL) N_FAIL=$((N_FAIL + 1)) ;;
    SKIP) N_SKIP=$((N_SKIP + 1)) ;;
  esac
  if [ -n "$_ptr" ]; then
    printf '%-6s%-18s%s  -> %s\n' "$_st" "$_name" "$_detail" "$_ptr"
  else
    printf '%-6s%-18s%s\n' "$_st" "$_name" "$_detail"
  fi
}

# Header rule, padded so every section line is the same 45 characters wide as
# the closing rule at the bottom of the report.
section() {
  printf '\xe2\x94\x80\xe2\x94\x80 %s ' "$1"
  _n=$((41 - ${#1}))
  while [ "$_n" -gt 0 ]; do printf '\xe2\x94\x80'; _n=$((_n - 1)); done
  printf '\n'
}

# Shorten a long path so the line still fits a normal terminal.
shortpath() { echo "$1" | sed "s|^$HOME|~|"; }

# The last lines the server wrote. Printed under a failed check rather than as
# a row of its own, because it is evidence for the row above it, not a verdict.
# mlx-serve rotates this file at 32 MB, so it is never the whole history.
# $1 = "always" prints them even when the last server said goodbye; without it
# a log that ends in an orderly shutdown gets one line instead of eight, because
# then "not running" is not a surprise and there is nothing to explain.
show_log_tail() {
  if [ ! -f "$LOG_FILE" ]; then
    echo "                        no log at $(shortpath "$LOG_FILE") — was the server started by ./bin/serve.sh?"
    return 0
  fi
  if [ "${1:-}" != "always" ] && log_ended_cleanly "$LOG_FILE"; then
    echo "                        the last server on this port shut down cleanly."
    return 0
  fi
  echo "                        the last 8 lines of $(shortpath "$LOG_FILE"):"
  log_tail "$LOG_FILE" 8 "                          " || true
}

# Every request to our own server goes through here. --api-key gates every
# endpoint but /health — for non-loopback clients; the server trusts localhost
# (see AGENT.md) — so the key is added in one place rather than remembered at
# one call site and forgotten at the others. $1 is the curl time limit; the
# rest is passed on. Two branches rather than an optional array: an empty
# array cannot be expanded under `set -u` in the bash 3.2 that macOS ships.
srv_curl() {
  _t="$1"; shift
  if [ -n "$API_KEY" ]; then
    curl -sS --max-time "$_t" -H "x-api-key: $API_KEY" "$@"
  else
    curl -sS --max-time "$_t" "$@"
  fi
}

# What the server's own log says about the prefix cache in the CURRENT run.
# The log is appended across restarts and has no per-line timestamps, so it is
# scoped to everything after the last "Logging to" banner first — an unscoped
# read would report a run that ended days ago as current. Prints three lines:
# the cache state from the startup banner, the "[hot-cache] reused N/M" line
# with the largest N, and how many such lines the run contains. The largest
# rather than the latest: doctor's own 8-token probe below is itself a hit on
# the second run, and the line that evidences the claim is the 20,000-token
# one, which must not be displaced by it. A missing line prints empty.
cache_log_evidence() {
  awk '
    BEGIN                   { best = -1 }
    /^Logging to /          { state = ""; hit = ""; hits = 0; best = -1 }
    /^Hot prefix cache: /   { state = $0; sub(/^Hot prefix cache: /, "", state) }
    /\[hot-cache\] reused / {
      hits++
      n = $0; sub(/^.*\[hot-cache\] reused /, "", n); sub(/\/.*$/, "", n); n += 0
      if (n >= best) { best = n; hit = $0; sub(/^.*\[hot-cache\] /, "", hit) }
    }
    END                     { print state; print hit; print hits }
  ' "$1"
}

# The GPU wired ceiling the server measured at its last load, in GB, from the
# "[wired] mode=max limit=N MB" line of the log's most recent run (scoped past
# the last "Logging to" banner, like the cache reader above). This is Metal's
# own number; the figure detect-hardware.sh computes is arithmetic that only
# estimates it. Prints nothing when there is no log or no such line.
log_wired_gb() {
  awk '
    /^Logging to /                    { v = "" }
    /^\[wired\] .*limit=[0-9]+ MB/  { v = $0; sub(/^.*limit=/, "", v); sub(/ MB.*$/, "", v) }
    END                               { if (v != "") printf "%.1f", v / 1024 }
  ' "$1"
}

# The one capability Claude Code cannot do without is a tool call the server
# hands back as a tool_use block — and it must arrive that way on the STREAMED
# path, which is the one Claude Code uses, and which is assembled by different
# code from the plain one. Nothing else in this file proves either; a build
# that answers "hi" perfectly can still hand every tool call back as prose.
#
# The request is a miniature of a real turn: one tool, a question that plainly
# needs it, thinking on (Claude Code always sends it, so the tool_use block
# arrives after a thinking block, exactly as it will in a session) and
# temperature 0 so the row is the same on every run. The cap of 1024 tokens is
# there so a build that reasons at length reports as "still reasoning", not as
# "cannot call a tool". `tool_choice` is NOT sent: mlx-serve 26.8.8 accepts it
# and ignores it (see AGENT.md), so the question has to earn the call by itself.
PROBE_TOOL="get_weather"
PROBE_ARG="city"
PROBE_TOOL_CAP=1024
tool_probe_body() {
  printf '{"model":"%s","max_tokens":%s,"temperature":0,"stream":%s,' "$MODEL_ID" "$PROBE_TOOL_CAP" "$1"
  printf '"thinking":{"type":"enabled","budget_tokens":512},'
  printf '"tools":[{"name":"%s","description":"Get the current weather in a city.",' "$PROBE_TOOL"
  printf '"input_schema":{"type":"object","properties":{"%s":{"type":"string","description":"City name"}},"required":["%s"]}}],' "$PROBE_ARG" "$PROBE_ARG"
  printf '"messages":[{"role":"user","content":"What is the weather in Paris?"}]}'
}

# Reads one answer on stdin — the JSON body ($1 = json) or the raw SSE text
# ($1 = sse) — and prints one line: OUTCOME OUTPUT_TOKENS DETAIL. The SSE
# reader reassembles the tool_use block from its input_json_delta pieces, the
# way a client has to, so "the pieces do not add up to JSON" is an outcome of
# its own rather than a mystery two steps later.
tool_call_verdict() {
  python3 -c '
import json, sys
mode, tool, arg = sys.argv[1:4]
raw = sys.stdin.read().strip()

def out(kind, tokens="-", detail=""):
    print(kind, tokens, detail)
    sys.exit(0)

def api_error(obj):
    if isinstance(obj, dict) and obj.get("type") == "error":
        out("error", "-", obj.get("error", {}).get("message", "unnamed error"))

if not raw:
    out("empty")
if mode == "sse":
    events = []
    for line in raw.splitlines():
        if line.startswith("data:"):
            try:
                events.append(json.loads(line[5:].strip()))
            except ValueError:
                out("garbled", "-", line[:80])
    if not events:
        try:
            api_error(json.loads(raw))
        except ValueError:
            pass
        out("garbled", "-", raw[:80])
    blocks, stop, tokens, stopped = {}, None, "?", False
    for e in events:
        t = e.get("type")
        api_error(e)
        if t == "content_block_start":
            b = e.get("content_block", {})
            blocks[e.get("index", 0)] = {"type": b.get("type"), "name": b.get("name"), "json": "", "text": b.get("text", "")}
        elif t == "content_block_delta":
            b = blocks.get(e.get("index", 0))
            d = e.get("delta", {})
            if b is None:
                continue
            if d.get("type") == "input_json_delta":
                b["json"] += d.get("partial_json", "")
            elif d.get("type") == "text_delta":
                b["text"] += d.get("text", "")
        elif t == "message_delta":
            stop = e.get("delta", {}).get("stop_reason", stop)
            tokens = e.get("usage", {}).get("output_tokens", tokens)
        elif t == "message_stop":
            stopped = True
    if not stopped:
        out("unterminated", tokens, stop or "no stop_reason")
    content = []
    for i in sorted(blocks):
        b = blocks[i]
        if b["type"] == "tool_use":
            try:
                inp = json.loads(b["json"]) if b["json"] else {}
            except ValueError:
                out("unassembled", tokens, b["json"][:80])
            content.append({"type": "tool_use", "name": b["name"], "input": inp})
        else:
            content.append({"type": b["type"], "text": b["text"]})
else:
    try:
        r = json.loads(raw)
    except ValueError:
        out("garbled", "-", raw[:80])
    api_error(r)
    stop = r.get("stop_reason")
    tokens = r.get("usage", {}).get("output_tokens", "?")
    content = r.get("content", [])

calls = [b for b in content if b.get("type") == "tool_use"]
text = " ".join(b.get("text", "") for b in content if b.get("type") == "text").strip()
if calls:
    c = calls[0]
    if c.get("name") != tool:
        out("wrong_tool", tokens, str(c.get("name")))
    inp = c.get("input")
    if not isinstance(inp, dict) or not isinstance(inp.get(arg), str):
        out("bad_input", tokens, json.dumps(inp))
    out("tool_use", tokens, json.dumps(inp, separators=(",", ":")))
if stop == "max_tokens":
    out("truncated", tokens)
if tool in text or "tool_call" in text or "<function" in text:
    out("unparsed", tokens, text[:60])
out("declined", tokens, text[:60])
' "$1" "$PROBE_TOOL" "$PROBE_ARG" 2>/dev/null || echo "garbled - the answer could not be read"
}

# One row per path. $1 is the row name, $2 "true" or "false" for stream. The
# body is built once and only that flag differs, so when the two rows disagree
# the difference is streaming and nothing else. Captured to a variable and read
# afterwards on purpose: `curl | grep -q` under pipefail dies of SIGPIPE on the
# first match and would report a working server as a broken one.
tool_call_row() {
  _name="$1"; _stream="$2"
  if [ "$_stream" = "true" ]; then _mode=sse; _how="reassembled from the stream"; else _mode=json; _how="in one answer"; fi
  _fix="docs/06-troubleshooting.md#tool-calls"
  _out="$(srv_curl 120 -N -H "content-type: application/json" -H "anthropic-version: 2023-06-01" \
            -d "$(tool_probe_body "$_stream")" "$BASE_URL/v1/messages" 2>/dev/null || true)"
  read -r _kind _tokens _detail <<< "$(printf '%s' "$_out" | tool_call_verdict "$_mode")"
  case "$_kind" in
    tool_use)     row PASS "$_name" "${PROBE_TOOL}(${_detail}) ${_how}, ${_tokens} tokens" ;;
    truncated)    row WARN "$_name" "still reasoning at the ${PROBE_TOOL_CAP}-token cap, no tool call yet — this build thinks too long for agent work. See docs/06-troubleshooting.md#tool-calls" ;;
    declined)     row FAIL "$_name" "answered in words instead of calling the tool: \"${_detail}\" — pick another build: ./bin/models.sh list" "$_fix" ;;
    unparsed)     row FAIL "$_name" "the call came back as plain text, the server did not parse it: \"${_detail}\"" "$_fix" ;;
    wrong_tool)   row FAIL "$_name" "called '${_detail}', not the one tool it was given" "$_fix" ;;
    bad_input)    row FAIL "$_name" "called ${PROBE_TOOL} with ${_detail} — the required '${PROBE_ARG}' is missing" "$_fix" ;;
    unassembled)  row FAIL "$_name" "the streamed call did not add up to valid JSON: ${_detail}" "$_fix" ;;
    unterminated) row FAIL "$_name" "the stream ended without message_stop (${_detail})" "$_fix" ;;
    error)        row FAIL "$_name" "the server refused the request: ${_detail}" "$_fix" ;;
    empty)        row FAIL "$_name" "the server did not answer" "docs/06-troubleshooting.md#no-server" ;;
    *)            row FAIL "$_name" "the answer was not in a shape this script knows: ${_detail}" "$_fix" ;;
  esac
}

echo "airgap doctor"

# =============================================================================
section "environment"
# =============================================================================

if [ "$(uname -s)" = "Darwin" ]; then
  row PASS "macos" "$(sw_vers -productVersion 2>/dev/null || echo unknown) ($(uname -m))"
else
  row FAIL "macos" "this is $(uname -s), not macOS" "docs/01-requirements.md#apple-silicon"
fi

if [ "${HW_APPLE_SILICON:-no}" = "yes" ]; then
  row PASS "apple silicon" "${HW_CHIP}${HW_GPU_CORES:+, ${HW_GPU_CORES} GPU cores}"
else
  row FAIL "apple silicon" "this Mac reports ${HW_CHIP:-unknown}" "docs/01-requirements.md#apple-silicon"
fi

# The tier is about the 27B: whether it fits, and which build is the default
# here. It never FAILs on its own — whether the SELECTED model fits is the next
# two rows, "gpu ceiling" and "memory", which judge the weights really chosen.
case "${HW_VERDICT:-unknown}" in
  comfortable|workable)
    row PASS "ram tier" "${HW_RAM_GB} GB total — ${HW_VERDICT}, default build ${HW_RECOMMENDED_KEY} at ${CTX_SIZE} tokens" ;;
  tight)
    row WARN "ram tier" "${HW_RAM_GB} GB total — tight for a 27B. Default build ${HW_RECOMMENDED_KEY}. Close apps before running." ;;
  not-recommended|impossible)
    row WARN "ram tier" "${HW_RAM_GB} GB total — the 27B does not fit here; default build ${HW_RECOMMENDED_KEY}. ${HW_ALT_MODEL}" ;;
  *)
    row WARN "ram tier" "could not work out this Mac's memory size" ;;
esac

# The ceiling the guards enforce is arithmetic (detect-hardware.sh says why).
# When the server has run here, its log holds the number Metal actually gave,
# so the row shows both and judges the build against both: the estimate can
# err in either direction, and admitting a build the real ceiling cannot hold
# is the failure that stalls a Mac.
# The conversation term is per model and per KV_QUANT (AUDIT.md F5); the row
# says where its per-token figure came from, so a guess never reads as a fact.
kv_note=" — ${CTX_SIZE} tokens at kv-quant ${KV_QUANT}, ${HW_KV_KIB} KiB/token at 16-bit, ${HW_KV_SOURCE}"
wired_measured=""
[ -f "$LOG_FILE" ] && wired_measured="$(log_wired_gb "$LOG_FILE")"
if [ -n "$wired_measured" ]; then
  ceiling_note="Apple's ${HW_WIRED_AUTO_GB} GB ceiling (arithmetic; the server measured ${wired_measured} GB at its last load)"
else
  ceiling_note="Apple's ${HW_WIRED_AUTO_GB} GB ceiling (arithmetic — the server logs the real one at load)"
fi
if [ "${HW_WIRED_OK:-yes}" = "no" ]; then
  row FAIL "gpu ceiling" "$(basename "$MODEL_DIR"): weights + conversation (${HW_WEIGHTS_GB} + ${HW_KV_GB} GB${kv_note}) do not fit under ${ceiling_note}. Pick a smaller build: ./bin/models.sh list" "docs/04-memory-safety.md#wired-limit"
elif [ -n "$wired_measured" ] && ! awk -v w="$HW_WEIGHTS_GB" -v kv="$HW_KV_GB" -v lim="$wired_measured" 'BEGIN { exit !(w + kv <= lim) }'; then
  row FAIL "gpu ceiling" "$(basename "$MODEL_DIR"): weights + conversation (${HW_WEIGHTS_GB} + ${HW_KV_GB} GB${kv_note}) fit the ${HW_WIRED_AUTO_GB} GB estimate but not the ${wired_measured} GB the server measured at its last load. Pick a smaller build: ./bin/models.sh list" "docs/04-memory-safety.md#wired-limit"
else
  row PASS "gpu ceiling" "weights + conversation (${HW_WEIGHTS_GB} + ${HW_KV_GB} GB${kv_note}) fit under ${ceiling_note}"
fi

avail="$(available_gb)"
if awk -v a="$avail" -v m="$MIN_FREE_GB" 'BEGIN { exit !(a >= m) }'; then
  row PASS "memory" "${HW_RAM_GB} GB total, ${avail} GB available (need ${MIN_FREE_GB})"
else
  row FAIL "memory" "${avail} GB available, need ${MIN_FREE_GB}" "docs/04-memory-safety.md#free-memory"
  echo "                        EXPECTED before you free memory. Close these, then run this again:"
  hw_top_memory_users "                        " 4
fi

# The dangerous value is a fraction of THIS Mac's memory, not a fixed number:
# 14336 MB on a 16 GB Mac is dangerous, 30720 MB on a 128 GB Mac is not.
wired="$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)"
danger="$(hw_wired_danger_mb)"
if [ "$wired" = "0" ]; then
  row PASS "wired limit" "iogpu.wired_limit_mb=0 (auto — about ${HW_WIRED_AUTO_GB} GB by arithmetic) — recommended"
elif [ "$wired" -gt "$danger" ] 2>/dev/null; then
  row FAIL "wired limit" "iogpu.wired_limit_mb=${wired} — over 80% of ${HW_RAM_GB} GB. Run: sudo sysctl iogpu.wired_limit_mb=0" "docs/04-memory-safety.md#wired-limit"
else
  row WARN "wired limit" "iogpu.wired_limit_mb=${wired} (set by hand) — recommend 0 (auto). Reverts on restart."
fi

# Two different questions, one function (hw_disk_need_gb, detect-hardware.sh).
# Before the download: the peak, about twice the weights. After it: the prefix
# cache the server is told it may write, which is what serve.sh refuses on.
# The cache goes under ~/.mlx-serve, so that volume is the one measured once
# the model is here.
cache_gb="$(hw_size_gb "$PREFIX_CACHE_DISK")"
if [ -f "$MODEL_DIR/config.json" ]; then
  disk="$(free_disk_gb "$HOME")"
  need_disk="$(hw_disk_need_gb serve "$HW_WEIGHTS_GB" "$cache_gb")"
  disk_what="for the ${PREFIX_CACHE_DISK} prefix cache + ${HW_DISK_SPARE_GB} GB spare"
else
  disk="$(free_disk_gb)"
  need_disk="$MIN_DISK_GB"
  disk_what="to download ${MODEL_REPO}"
fi
if awk -v d="$disk" -v m="$need_disk" 'BEGIN { exit !(d >= m) }'; then
  row PASS "disk" "${disk} GB free (need ${need_disk} ${disk_what})"
else
  row FAIL "disk" "${disk} GB free, need ${need_disk} ${disk_what}" "docs/06-troubleshooting.md#disk-space"
fi

# =============================================================================
section "tools"
# =============================================================================

if command -v brew >/dev/null 2>&1; then
  row PASS "homebrew" "$(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
else
  row FAIL "homebrew" "not installed" "docs/02-install.md#homebrew"
fi

if git lfs version >/dev/null 2>&1; then
  row PASS "git-lfs" "$(git lfs version 2>/dev/null | awk '{print $1}' | sed 's|^git-lfs/||')"
  # Installed is not enough. It must also be switched on for your account, or
  # git clone quietly leaves 135-byte pointer files instead of weights.
  if git config --global --get filter.lfs.process >/dev/null 2>&1; then
    row PASS "git-lfs enabled" "switched on for your account"
  else
    row FAIL "git-lfs enabled" "installed but not switched on. Run: git lfs install" "docs/06-troubleshooting.md#lfs-pointers"
  fi
else
  row FAIL "git-lfs" "not installed. Run: ./bin/setup.sh" "docs/02-install.md#git-lfs"
  row SKIP "git-lfs enabled" "cannot check until git-lfs is installed"
fi

# Installed is not enough: every flag serve.sh passes was verified against
# MLX_SERVE_MIN, and an older build answers one of them with an argparse error
# a minute into a load. serve.sh refuses on the same comparison; this is the
# row that says so before you get there.
if command -v mlx-serve >/dev/null 2>&1; then
  mlx_ver="$(mlx_serve_version)"
  if [ -z "$mlx_ver" ]; then
    row WARN "mlx-serve" "installed, but it does not report its version in a shape this script knows (needs ${MLX_SERVE_MIN} or newer)"
  elif version_lt "$mlx_ver" "$MLX_SERVE_MIN"; then
    row FAIL "mlx-serve" "${mlx_ver} — older than the ${MLX_SERVE_MIN} this repo's flags need. Run: brew update && brew upgrade mlx-serve" "docs/02-install.md#mlx-serve"
  else
    row PASS "mlx-serve" "${mlx_ver} (needs ${MLX_SERVE_MIN} or newer)"
  fi
else
  row FAIL "mlx-serve" "not installed. Run: ./bin/setup.sh" "docs/02-install.md#mlx-serve"
fi

if command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  row PASS "claude code" "$("$CLAUDE_BIN" --version 2>/dev/null | awk '{print $1}')"
else
  row FAIL "claude code" "the command '$CLAUDE_BIN' was not found" "docs/02-install.md#claude-code"
fi

# =============================================================================
section "model"
# =============================================================================

model_ok=0
if [ -f "$MODEL_DIR/config.json" ]; then
  row PASS "model dir" "$(shortpath "$MODEL_DIR")"
  model_ok=1
else
  row FAIL "model dir" "nothing at $(shortpath "$MODEL_DIR"). Run: ./bin/download-model.sh" "docs/03-get-the-model.md"
fi

if [ "$model_ok" = "1" ]; then
  n_shards=0; bytes=0
  while IFS= read -r shard; do
    [ -n "$shard" ] || continue
    n_shards=$((n_shards + 1))
    bytes=$((bytes + $(stat -f%z "$shard" 2>/dev/null || echo 0)))
  done <<EOF
$(model_shards "$MODEL_DIR")
EOF

  # Both halves of "is it whole?", asked over every shard by the same helpers
  # serve.sh, start.sh and models.sh use: a shard still a git-lfs pointer, and
  # a shard the checkpoint's index names that never arrived.
  pointer="$(model_pointer_shard "$MODEL_DIR" || true)"
  missing="$(model_missing_shards "$MODEL_DIR" | tr '\n' ' ')"
  gb="$(awk -v b="$bytes" 'BEGIN { printf "%.1f", b / 1073741824 }')"
  if [ "$n_shards" = "0" ]; then
    row FAIL "weights" "no .safetensors files found" "docs/03-get-the-model.md"
  elif [ -n "$pointer" ]; then
    row FAIL "weights" "${pointer% *} is a ${pointer##* }-byte pointer, not weights" "docs/06-troubleshooting.md#lfs-pointers"
  elif [ -n "${missing// /}" ]; then
    row FAIL "weights" "${n_shards} shards here, but the index names ${missing% } as well — the download stopped part way. Run: ./bin/download-model.sh" "docs/03-get-the-model.md"
  else
    if [ "$n_shards" = "1" ]; then shard_word="shard"; else shard_word="shards"; fi
    row PASS "weights" "${n_shards} ${shard_word}, no pointers, ${gb} GB on disk (about ${HW_WEIGHTS_GB} GB is loaded)"
  fi

  row PASS "model id" "$MODEL_ID"
else
  row SKIP "weights" "cannot check until the model is downloaded"
  row SKIP "model id" "cannot check until the model is downloaded"
fi

# =============================================================================
section "server"
# =============================================================================

# What is holding the port? Three cases: our server, somebody else's program,
# or nothing at all.
port_pids="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | tr '\n' ' ' || true)"
port_cmd=""
if [ -n "$port_pids" ]; then
  port_cmd="$(ps -o comm= -p ${port_pids%% *} 2>/dev/null || true)"
fi

# The address the socket is REALLY listening on, read from the system rather
# than from this script's own settings. Reading $HOST here would report what
# the server was asked for, not what it did, and would say "this Mac only"
# about a server another window started on every network interface.
bound_addr=""
if [ -n "$port_pids" ]; then
  bound_addr="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null \
    | awk 'NR > 1 { n = $(NF - 1); sub(/:[0-9]+$/, "", n); print n; exit }' || true)"
fi

check_bind() {
  # Two separate facts, and both must hold: what this repo is configured to ask
  # for, and what is actually listening right now.
  case "$HOST" in
    127.0.0.1|::1|localhost) : ;;
    *)
      row FAIL "bind setting" "HOST is set to ${HOST} — that is every network this Mac is on" "docs/06-troubleshooting.md#exposed-server"
      return ;;
  esac
  if [ -z "$bound_addr" ]; then
    row PASS "bind setting" "HOST=${HOST} — serve.sh will listen on this Mac only"
    return
  fi
  case "$bound_addr" in
    127.0.0.1|\[::1\]|localhost)
      row PASS "bind address" "${bound_addr}:${PORT} (loopback only)" ;;
    *)
      row FAIL "bind address" "${bound_addr}:${PORT} — reachable from your network" "docs/06-troubleshooting.md#exposed-server" ;;
  esac
}

# Only one process on this Mac may hold the weights. A lock still standing after
# its holder is gone is the one failure mode this adds, so it gets its own row
# rather than being discovered as a refusal the next time serve.sh is run.
if [ -z "${LOCK_DIR:-}" ]; then
  row SKIP "model lock" "switched off (LOCK_DIR is empty)"
elif [ ! -d "$LOCK_DIR" ]; then
  row PASS "model lock" "free — nothing is holding the weights"
elif model_lock_alive; then
  row PASS "model lock" "held by pid $(model_lock_pid) — $(model_lock_what)"
else
  row WARN "model lock" "left behind by pid $(model_lock_pid || echo '?'), which is gone — ./bin/stop.sh clears it"
fi

if server_up; then
  check_bind
  row PASS "/health" "up"

  models_json="$(srv_curl 5 -f "$BASE_URL/v1/models" 2>/dev/null || true)"
  if echo "$models_json" | grep -q -- "$MODEL_ID"; then
    row PASS "/v1/models" "advertises $MODEL_ID"
  elif [ -n "$models_json" ]; then
    advertised="$(echo "$models_json" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    row FAIL "/v1/models" "server offers '${advertised:-nothing}', Claude Code will send '$MODEL_ID'" "docs/06-troubleshooting.md#model-id"
  else
    row WARN "/v1/models" "the server did not answer this question"
  fi

  health_json="$(curl -fsS --max-time 5 "$BASE_URL/health" 2>/dev/null || true)"
  probe_src="${health_json}${models_json}"
  # A checkpoint that ships no MTP head cannot have it loaded, and that is not
  # a warning about anything. The weight index says whether it ships one.
  ships_mtp="unknown"
  if [ -f "$MODEL_DIR/model.safetensors.index.json" ]; then
    if grep -q '\.mtp\.' "$MODEL_DIR/model.safetensors.index.json" 2>/dev/null; then ships_mtp="yes"; else ships_mtp="no"; fi
  fi
  if echo "$probe_src" | grep -q '"mtp_loaded"[[:space:]]*:[[:space:]]*true'; then
    row PASS "mtp_loaded" "true"
  elif echo "$probe_src" | grep -q '"mtp_loaded"[[:space:]]*:[[:space:]]*false'; then
    if [ "$ships_mtp" = "no" ]; then
      row PASS "mtp_loaded" "false — expected: this checkpoint ships no MTP head"
    else
      row WARN "mtp_loaded" "false — the checkpoint ships an MTP head and the server did not load it. See docs/08-how-it-works.md"
    fi
  else
    row SKIP "mtp_loaded" "this server version does not report it"
  fi

  # The prefix cache is the repository's central speed claim, and the server
  # writes the evidence for it on every request. These two rows read that
  # evidence: first the log, then the counters. Both come BEFORE the probe
  # below, so doctor's own 8-token question cannot become the "last hit".
  if [ ! -f "$LOG_FILE" ]; then
    row SKIP "prefix cache" "no log at $(shortpath "$LOG_FILE") — was the server started by ./bin/serve.sh?"
  else
    { read -r cache_state; read -r cache_hit; read -r cache_hits; } <<< "$(cache_log_evidence "$LOG_FILE")"
    # The memory tier in tokens (AUDIT.md E2): the byte budget the setting
    # names, converted at this model's per-token KV cost. An upper bound —
    # SSM checkpoints share it, and the server's own 32-entry cap may bind
    # first (docs/07 §5).
    cache_tokens="${PREFIX_CACHE_MEM} holds at most $(hw_kv_tokens "$PREFIX_CACHE_MEM" "$HW_KV_KIB") prompt tokens (arithmetic)"
    case "$cache_state" in
      "")
        row SKIP "prefix cache" "this server version does not report it in the log" ;;
      ENABLED*)
        if [ -n "$cache_hit" ]; then
          row PASS "prefix cache" "log: ${cache_hit} — the biggest of ${cache_hits} hit(s) this run; ${cache_tokens}"
        else
          row PASS "prefix cache" "log: ${cache_state}; no repeated prompt served yet this run; ${cache_tokens}"
        fi ;;
      *)
        row WARN "prefix cache" "the server reports '${cache_state}' — every turn re-reads the whole prompt. See docs/07-tuning.md §5" ;;
    esac
  fi

  # One fetch on the happy path (metrics_counters, bin/env.sh). Only when that
  # comes back empty is a second request worth making, to say WHY: a 503 is the
  # server saying metrics are switched off, not a failure.
  if counters="$(metrics_counters prefix_cache_hits_total prefix_cache_queries_total \
                                  prefix_cache_tokens_total prompt_tokens_total)"; then
    read -r m_hits m_queries m_cached m_prompt <<< "$counters"
    if [ "$m_queries" = "0" ]; then
      row PASS "/metrics.json" "answering; no requests counted yet this run"
    else
      row PASS "/metrics.json" "${m_hits} of ${m_queries} lookups hit the cache; ${m_cached} of ${m_prompt} prompt tokens were reused"
    fi
  else
    metrics_code="$(srv_curl 5 -o /dev/null -w '%{http_code}' "$BASE_URL/metrics.json" 2>/dev/null || true)"
    case "$metrics_code" in
      200)
        row WARN "/metrics.json" "answered, but not in the shape this script knows" ;;
      503)
        row SKIP "/metrics.json" "switched off (METRICS=0)" ;;
      ""|000)
        row WARN "/metrics.json" "the server did not answer this question" ;;
      *)
        row WARN "/metrics.json" "the server answered HTTP ${metrics_code}" ;;
    esac
  fi

  if [ "$PROBE" = "1" ]; then
    body='{"model":"'"$MODEL_ID"'","max_tokens":8,"messages":[{"role":"user","content":"hi"}]}'
    if srv_curl 120 -f -H "content-type: application/json" -H "anthropic-version: 2023-06-01" \
         -d "$body" "$BASE_URL/v1/messages" >/dev/null 2>&1; then
      row PASS "/v1/messages" "round trip ok (8 tokens)"
    else
      row FAIL "/v1/messages" "the server did not answer a small test question" "docs/06-troubleshooting.md#no-server"
      show_log_tail always
    fi
    # After the round trip, so a cold server has already reloaded the model
    # by the time these are timed against a real answer.
    tool_call_row "tool call" false
    tool_call_row "streamed call" true
  else
    row SKIP "/v1/messages" "not sent (PROBE=0)"
    row SKIP "tool call" "not sent (PROBE=0)"
    row SKIP "streamed call" "not sent (PROBE=0)"
  fi
elif [ -n "$port_pids" ]; then
  check_bind
  row FAIL "port ${PORT}" "in use by '${port_cmd:-another program}' (pid ${port_pids%% *}), which is not our server" "docs/06-troubleshooting.md#port-in-use"
  row SKIP "server" "cannot check while something else holds the port"
else
  check_bind
  row SKIP "server" "not running — start ./bin/serve.sh"
  # The cache rows need a live server to say which run they describe, but the
  # last run's evidence is still on disk, and this is the one place that names it.
  if [ -f "$LOG_FILE" ]; then
    row SKIP "prefix cache" "the last run's log is at $(shortpath "$LOG_FILE") — look for [hot-cache] lines"
  fi
  # Why it is not running is written in the log and was shown by nothing
  # (AUDIT.md C3). A server that was stopped on purpose ends quietly here; one
  # that died says so in these lines.
  show_log_tail
fi

# =============================================================================
section "harness wiring"
# =============================================================================

# The endpoint family HARNESS_DIALECT names, for the harness rows below — the
# dialect's one consumer besides run.sh's own banner. An adapter whose real
# endpoint disagrees with its dialect's default (harness/codex.sh: dialect
# openai, but wired to /v1/responses, not /v1/chat/completions) says so itself
# through an optional HARNESS_ENDPOINT, which the loop below prefers when set.
harness_endpoint() {
  case "$1" in
    anthropic) echo "/v1/messages" ;;
    openai)    echo "/v1/chat/completions" ;;
    ollama)    echo "/api/chat" ;;
    *)         echo "" ;;
  esac
}

# One row per harness/*.sh — everything ./bin/run.sh can start, not just
# Claude Code. Each adapter is sourced in a subshell so that HARNESS_DIALECT,
# HARNESS_BIN and the rest, which every adapter sets at file scope, never leak
# into doctor's own variables or into the next adapter's row; harness_wire is
# never called, so nothing runs. env.sh is already sourced above, and its
# variables reach the subshell without sourcing it again.
for _h in "$ROOT"/harness/*.sh; do
  [ -f "$_h" ] || continue
  _hname="$(basename "$_h" .sh)"
  read -r _dialect _bin _endpoint <<< "$(
    (
      # shellcheck source=/dev/null
      source "$_h"
      printf '%s\t%s\t%s\n' "$HARNESS_DIALECT" "$HARNESS_BIN" "${HARNESS_ENDPOINT:-}"
    )
  )"
  [ -n "$_endpoint" ] || _endpoint="$(harness_endpoint "$_dialect")"
  if command -v "$_bin" >/dev/null 2>&1; then
    row PASS "$_hname" "$("$_bin" --version 2>/dev/null | awk '{print $1}') -> ${BASE_URL}${_endpoint}"
  else
    row WARN "$_hname" "'${_bin}' not found — run.sh will refuse" "docs/10-other-harnesses.md"
  fi
done
unset _h _hname _dialect _bin _endpoint

# A real key in your shell would take priority over the local server and send
# your questions to Anthropic instead. claude-local.sh blanks it, but if you
# run `claude` by hand it would win.
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  row PASS "ANTHROPIC_API_KEY" "not set in this shell"
else
  row WARN "ANTHROPIC_API_KEY" "set in this shell. ./bin/claude-local.sh blanks it, plain 'claude' does not."
fi

if [ -z "${ANTHROPIC_BASE_URL:-}" ] || [ "${ANTHROPIC_BASE_URL:-}" = "$BASE_URL" ]; then
  row PASS "base url" "claude-local.sh will point at $BASE_URL"
else
  row WARN "base url" "ANTHROPIC_BASE_URL is already set to ${ANTHROPIC_BASE_URL}; claude-local.sh overrides it"
fi

# CTX_SIZE is what the server is asked to hold and what Claude Code is told it
# may send. It must not exceed what the model itself was built for, which is
# written in the model's own config.json.
if [ "$model_ok" = "1" ]; then
  model_max="$(model_max_ctx "$MODEL_DIR")"
  if [ -z "$model_max" ]; then
    row WARN "context" "CTX_SIZE=${CTX_SIZE}; the model's config.json does not state its maximum"
  elif [ "$CTX_SIZE" -le "$model_max" ] 2>/dev/null; then
    row PASS "context" "CTX_SIZE=${CTX_SIZE} declared to server and Claude Code, within the model's ${model_max}"
  else
    row FAIL "context" "CTX_SIZE=${CTX_SIZE} is more than the model's own maximum of ${model_max}" "docs/07-tuning.md#2-the-one-setting-most-people-come-here-for-context-size"
  fi
else
  row SKIP "context" "cannot check against the model until it is downloaded (CTX_SIZE=${CTX_SIZE})"
fi

if [ "$LEAN_MCP" = "1" ]; then
  row PASS "mcp mode" "strict (LEAN_MCP=1) — saves about 17,000 prompt tokens per turn"
else
  row WARN "mcp mode" "your normal config (LEAN_MCP=0) — costs about 17,000 prompt tokens per turn"
fi

# =============================================================================
printf '\xe2\x94\x80%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
  21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45; printf '\n'

summary="${N_PASS} pass, ${N_WARN} warn, ${N_FAIL} fail"
if [ "$N_SKIP" -gt 0 ]; then summary="${summary}, ${N_SKIP} skipped"; fi
echo "$summary"

if [ "$N_FAIL" -gt 0 ]; then
  echo "doctor: ${N_FAIL} FAILURE(S) — fix these first, see docs/06-troubleshooting.md"
  exit 1
elif [ "$N_WARN" -gt 0 ]; then
  echo "doctor: ${N_WARN} WARNING(S) — safe to continue, see the lines above"
else
  if [ "$model_ok" = "1" ]; then
    echo "doctor: OK — next: ./bin/serve.sh"
  else
    echo "doctor: OK — next: ./bin/download-model.sh"
  fi
fi
exit 0
