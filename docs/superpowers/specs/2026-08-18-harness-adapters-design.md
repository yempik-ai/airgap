# Harness adapters — `bin/run.sh <harness>` (ROADMAP Phase 1)

Date: 2026-08-18. Status: approved design, not implemented.

## Goal

Point any coding harness at the model on this Mac with one command, under
the same guards, settings and air-gap rules that `bin/claude-local.sh`
enforces for Claude Code today. Ship two adapters verified end to end
(Claude Code, Codex CLI) and the contract a third one is written against.

Out of scope: session control, worktrees, diff review, UIs — the layer above
the harness. `docs/10-other-harnesses.md` says so once.

## Constraints inherited from the repo

- Two-window model: `serve.sh` starts the server; nothing else does.
- Settings precedence: env var → `config.env` → detected → default
  (`bin/env.sh`). A setting is command-line-overridable only if it is on
  `ENV_KEYS`. A setting one script reads is defaulted in that script, still
  on `ENV_KEYS` (AGENT.md "Layout").
- A guard refuses and names the fix. Every figure is labelled measured /
  reported / arithmetic. Help text and behaviour change in the same commit.
- Environment-variable and config-key names are verified against the
  installed binary and listed in AGENT.md "Verified environment facts".
- Nothing documented breaks: ~70 references to `bin/claude-local.sh` in
  docs, AGENT.md, AUDIT.md, CHANGELOG.md stay true.
- Not installed here, therefore not shipped: Pi, Hermes, OpenCode, Aider.

## The contract — `harness/<name>.sh`

A bash file `bin/run.sh` sources after `bin/env.sh`. It reads `BASE_URL`,
`MODEL_ID`, `CTX_SIZE`, `LEAN_MCP`, `SERVE_TIMEOUT`, `API_KEY` and its own
`*_BIN`, and provides:

| Name | Kind | Meaning |
|---|---|---|
| `HARNESS_DIALECT` | variable | `anthropic`, `openai` or `ollama` — the mlx-serve endpoint family it will hit |
| `HARNESS_BIN` | variable | the executable, from the harness's `*_BIN` setting (`CLAUDE_BIN`, `CODEX_BIN`) |
| `HARNESS_ONESHOT` | array | the arguments that make the harness answer one prompt and exit; the prompt is always the last argument (`(-p)`, `(exec)`) |
| `harness_wire` | function | exports environment variables and/or appends flags to the `HARNESS_ARGS` array so that every request goes to `BASE_URL` for `MODEL_ID` with `CTX_SIZE` declared. Refuses (exit 1, fix named) on an invalid harness-specific setting. Prints nothing; harness-specific banner lines go into the `HARNESS_NOTES` array |
| `harness_usage` | function, optional | the harness-specific `--help` text |

An adapter does not: check the server, parse `run.sh` options, compute
timeouts, print the common banner, or run the probe. Those live once in
`run.sh` and `env.sh`.

### Rules an adapter must meet before it is listed

1. Verified: `run.sh --probe <name>` returned `AIRGAP OK` on this machine
   against a real model, with harness version, model and date recorded in
   `docs/10-other-harnesses.md`.
2. Air gap: every model-bearing setting of the harness points at `BASE_URL`;
   a real provider key present in the shell cannot win over it; telemetry,
   update checks and other non-essential traffic the harness lets you switch
   off are switched off, each key verified in the binary.
3. Token overhead: MCP/tool servers off when `LEAN_MCP=1` (the shared knob,
   default 1). The measured cost of on vs off is stated per harness or
   stated as not measured; Claude Code's 17k figure is never reused.
4. Own knobs, own names: the harness's output cap, thinking, timeout knobs
   are exposed under the harness's own names, defaulted in the adapter, on
   `ENV_KEYS`, documented in `config.env.example` under a section for that
   harness. No translation layer, no default without a measurement behind
   it. Claude Code keeps `CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192` and
   `MAX_THINKING_TOKENS`; Codex gets no output cap or thinking knob in this
   slice.
5. Fail-fast: retries and silent fallbacks the harness offers are off; the
   client-side idle timeout comes from `client_timeout_ms` (below) so the
   server, which can name the reason, reports a stall first.
6. `CTX_SIZE` is declared to the harness as its context window, unchanged.

## `bin/run.sh`

```
bin/run.sh [--probe] <harness> [harness arguments…]
bin/run.sh --help | -h
bin/run.sh                      # lists harness/*.sh and exits 1
```

Options precede the harness name. Everything after the name is passed to
the harness untouched.

Sequence:

1. `source bin/env.sh`.
2. No name / unknown name → list `harness/*.sh` (basename without `.sh`),
   exit 1.
3. `source harness/<name>.sh`.
4. `<name> --help` (first passthrough argument is `-h`/`--help` and
   `harness_usage` is defined) → print it, exit 0. Otherwise `--help` is
   passed through: it is the harness's flag.
5. `HARNESS_ARGS=()`; `HARNESS_NOTES=()`; `harness_wire`. Its guards run
   before the server check, so a typo in a harness setting is refused
   whether or not the server is up (`tests/thinking-knob.sh` relies on
   this order).
6. `server_up` or refuse with the message `claude-local.sh` prints today
   (open another window, `cd $ROOT`, `./bin/serve.sh`).
7. Common banner, from `env.sh` values only:
   `<name>  -> BASE_URL  model MODEL_ID  (DIALECT)`, `context CTX_SIZE
   tokens declared`, `timeout` line (client vs server, as today); then
   each line of `HARNESS_NOTES`; then a blank line.
8. Without `--probe`: `exec "$HARNESS_BIN" "${HARNESS_ARGS[@]}" "$@"`.
9. With `--probe`: see below.

`bin/claude-local.sh` becomes:
`exec "$(dirname "${BASH_SOURCE[0]}")/run.sh" claude-code "$@"` under a
comment saying so. Its documented behaviour (`--help`, `-p`, the
`MAX_THINKING_TOKENS` guard message, the six banner lines) is unchanged.

### `--probe`

One implementation, harness-agnostic:

1. If `METRICS=1`: read `prompt_tokens_total` from `BASE_URL/metrics.json`
   via `metrics_counters` (below).
2. Run `"$HARNESS_BIN" "${HARNESS_ARGS[@]}" "${HARNESS_ONESHOT[@]}" 'Reply
   with exactly: AIRGAP OK'` with stdin closed, stdout+stderr captured, wall
   clock measured, bounded by `client_timeout_ms` (a cold first turn reloads
   the weights; no new number). macOS ships no `timeout` binary: the bound
   is a background run polled with `sleep`, killed on expiry.
3. Read the counter again. Delta = prompt tokens the harness sent for one
   turn, all requests included.
4. Print one line and exit with the verdict:
   `probe  claude-code  AIRGAP OK  4.1 s  1,204 prompt tokens` /
   `probe  codex  AIRGAP OK  3.2 s  prompt tokens n/a (METRICS=0)` /
   `probe  codex  FAIL after 12.0 s` followed by the last 20 lines captured.
   Match: stdout contains `AIRGAP OK` (case-sensitive).

The probe measures the harness's fixed cost as the server saw it. It does
not parse any harness's output format.

## `bin/env.sh`

- `client_timeout_ms`: `SERVE_TIMEOUT=0` → `3600000`; else
  `(SERVE_TIMEOUT + 60) * 1000`. Moved from `claude-local.sh`; the
  `300000` floor stays in the Claude Code adapter (a `Math.max` fact of the
  2.1.233 binary, not a rule).
- `metrics_counters <name>…`: one fetch of `/metrics.json`; prints the
  named counters' values space-separated in argument order (`0` for a
  counter the server does not report); prints nothing and returns 1 when
  the endpoint does not answer 200. Doctor's inline Python moves here;
  doctor keeps its own status-code diagnosis only on the failure path (one
  fetch on the happy path).
- `CODEX_BIN` (default `codex`): on `ENV_KEYS`, defaulted, exported — the
  three edits AGENT.md names. `LEAN_MCP` and `CLAUDE_BIN` unchanged.
- `LEAN_MCP` comment reworded harness-neutral: "starts the harness with its
  MCP/tool servers off. Measured for Claude Code on the test machine: …".

## `harness/claude-code.sh`

`bin/claude-local.sh` minus what moved to `run.sh`/`env.sh`. Byte-for-byte
the same exports, the same `MAX_THINKING_TOKENS` guard, the same
`CLAUDE_CODE_MAX_OUTPUT_TOKENS` default, `--model "$MODEL_ID"` and
`--strict-mcp-config` under `LEAN_MCP=1` in `HARNESS_ARGS`. `HARNESS_ONESHOT=(-p)`.
`harness_usage` is today's `usage()`, with `USAGE` lines showing both
`./bin/claude-local.sh` and `./bin/run.sh claude-code`. `HARNESS_NOTES`
carries today's `mcp`, `thinking` and `note` lines (the rest are common).

## `harness/codex.sh`

`HARNESS_DIALECT=openai`, `HARNESS_BIN="$CODEX_BIN"`,
`HARNESS_ONESHOT=(exec --skip-git-repo-check)` (the probe may run from any
folder; the flag is exec-only, so a hand-typed `run.sh codex exec …` outside
a checkout types it too — documented, not a contract gap).
Wiring is `-c key=value` overrides only — no file under `~/.codex` is
written or read differently, no login required, `--oss` not used (Codex's
own provider path can list and pull models by itself, which is a second
actor in the middle).

What the 0.147.0 binary was measured to accept (2026-08-18; each key checked
with `codex exec --strict-config`, with a deliberate typo refused as the
negative control; recorded in AGENT.md "Verified environment facts"):

- `model_provider`, `model_providers.<id>.base_url` (`$BASE_URL/v1`),
  `model_providers.<id>.wire_api = "responses"` — `"chat"` is **refused**
  by 0.147.0 ("no longer supported"); mlx-serve 26.8.8 serves
  `/v1/responses`, and that pairing is what the probe verified.
  `-m "$MODEL_ID"`.
- `model_context_window=$CTX_SIZE`.
- Per-provider retry and stream-idle keys → 0 retries, `client_timeout_ms`
  idle.
- Auth: `exec` runs with no credentials, but left alone Codex sends the
  ChatGPT OAuth token and account id to `base_url`. The adapter exports
  `CODEX_API_KEY` (`$API_KEY`, or the placeholder `mlx-serve`), measured to
  win; `OPENAI_API_KEY` is ignored by 0.147.0.
- `LEAN_MCP=1` → `-c features.plugins=false` (10 → 4 MCP servers on the
  test machine; the 4 declared in the user's `config.toml` cannot be
  switched off from the command line — the banner, help and AGENT.md say
  so). `-c 'mcp_servers={}'` parses and is ignored (overrides merge into
  tables). `--ignore-user-config` is not used: it drops the user's approvals
  too. Measured: 9,336 prompt tokens with `LEAN_MCP=1` vs 10,271 with
  `LEAN_MCP=0` on the probe turn (935 per turn, 9B, two runs).
- Telemetry/update-check keys, where 0.147.0 has them.

Unknown or unverifiable keys are left unset with a comment saying so.

`config.env.example` gains a `# --- Codex CLI ---` section with
`#CODEX_BIN=codex`; `LEAN_MCP` moves to a harness-neutral `# --- Harnesses
---` section with the Claude Code and Codex measurements each labelled.

## `bin/doctor.sh`

Section "claude code wiring" is renamed "harness wiring". Existing rows
stay. One new row per `harness/*.sh`, evaluated in a subshell that sources
`env.sh` and the adapter (no `harness_wire` call — nothing runs):

- `PASS <name>  <version>  → BASE_URL/<endpoint>` where endpoint is
  `/v1/messages`, `/v1/chat/completions` or `/api/chat` by `HARNESS_DIALECT`
  (a `case` in doctor, the dialect's one consumer besides the banner);
- `WARN <name>  '<bin>' not found — run.sh will refuse` otherwise.

The `claude code` row under "tools" is unchanged.

## Docs

- New `docs/10-other-harnesses.md`: what a harness is here; the contract
  table above; the six rules; `run.sh` usage and `--probe` output; a section
  per shipped adapter with its verified line (harness version, mlx-serve
  version, model, date, probe time, prompt tokens); "adding one" (copy an
  adapter, meet the six rules, send the probe output with the PR); one
  paragraph on the layer boundary (control planes such as t3code drive
  harnesses over ACP/app-server and sit above this repo; they compose with
  it, and their features are not this repo's).
- `README.md` "Pick your path": one line, `"I use Codex / another harness,
  not Claude Code." → docs/10-other-harnesses.md`.
- `docs/05-run-it.md`: one sentence, `claude-local.sh` is `run.sh
  claude-code`.
- `ROADMAP.md` Phase 1: shipped items marked, unshipped adapters still
  listed as not shipped.
- `CHANGELOG.md` entry. `AGENT.md`: Layout (`harness/`, `run.sh`,
  `client_timeout_ms`, `metrics_counter`, `CODEX_BIN`) and Verified
  environment facts (Codex 0.147.0 keys).
- Proof that nothing else changed: `git diff --stat` on `docs/0[1-9]*.md`
  shows only 05.

## Tests (`tests/`, no server, no weights)

- `harness-contract.sh`: for each `harness/*.sh`, in `env -i` with
  `PORT=9`, source `env.sh` and the adapter; assert `HARNESS_DIALECT` is
  one of the three values, `HARNESS_BIN` non-empty, `HARNESS_ONESHOT` has
  ≥1 element, `harness_wire` is a function. Then call `harness_wire` and
  assert `HARNESS_ARGS` or the exported environment mentions `BASE_URL` and
  `MODEL_ID` (the wiring points at loopback).
- `run-dispatch.sh`: `run.sh` with no name and with `nope` prints the
  adapter list and exits 1; the list names every `harness/*.sh` present
  (derived, not hardcoded in the test); `run.sh claude-code` with `PORT=9`
  refuses with `error: no server at`; `run.sh claude-code --help` prints
  the adapter's usage and exits 0 without a server.
- `thinking-knob.sh`: unchanged, green through the shim.
- Live, by hand before the commit and pasted into docs/10:
  `run.sh --probe claude-code`, `run.sh --probe codex`, both on the 9B.

## Commit series

1. `env.sh` helpers + `harness/claude-code.sh` + `run.sh` + shim + tests.
   Behaviour of `claude-local.sh` identical; `tests/run.sh` green.
2. `harness/codex.sh` + `CODEX_BIN` + config.env.example section + AGENT.md
   facts; probe output recorded.
3. `doctor.sh` rows.
4. docs/10, README, docs/05, ROADMAP, CHANGELOG, AGENT.md layout.

## Not reversible

`harness/`, the names `claude-code` and `codex`, `CODEX_BIN`, and the
contract surface. Kept minimal (two variables, one array, one function, one
optional function) so it can grow without breaking adapters written against it.
