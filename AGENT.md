# Agent Notes

`airgap` is a Bash and documentation kit. It ships no compiled code and no model
weights. Its whole job is to make one local model turnkey on an Apple Silicon
Mac, under guards, and point a coding harness at it.

Read this before changing anything. It exists so that facts established once are
not established again: the sections below record what has already been verified
against the installed binaries, and what has already been tried and found false.

## Where the work stands

*Keep this section to a few lines and update it when work lands. It is a pointer,
not a record — [`AUDIT.md`](AUDIT.md) holds the status of every item, and if the
two ever disagree, `AUDIT.md` is right.*

- **Last landed:** `C1` (doctor reads the `[hot-cache]` log line and the
  `/metrics.json` counters) with `C2` folded in, and an `A1` follow-up
  (`stop.sh` waits on the pid, not the port), 2026-08-17.
- **Next:** `B1` — make `bench.sh` keep prefill and peak memory. Then `D3`,
  `E1`. The ranked list with efforts is at the top of `AUDIT.md`.
- **Blocked on hardware, not on decisions:** anything needing the 27B loaded.
  It has never been served on this machine. `AUDIT.md` E5 and A5 both stop short
  of a measurement for this reason, and `ROADMAP.md` Phase 0 names it.

## Scope

- Everything shipped is shell plus Markdown. A change that wants C, Python or a
  new daemon is out of scope. The answer is nearly always a flag on the runtime
  that is already installed.
- The three principles that govern every change — **guards not warnings**,
  **measured or labelled**, **one source of truth per fact** — are stated once,
  in [`ROADMAP.md`](ROADMAP.md). They are not restated here, because restating
  them would break the third one.
- Open work and the evidence behind it live in [`AUDIT.md`](AUDIT.md). Items are
  referenced by id (`A3`, `E2`) from `ROADMAP.md`.

## Layout

- `start.sh` — first-run sequencing only. It deliberately never starts the
  server, and it never will; the two-window model is the documented contract.
- `bin/env.sh` — settings resolution and shared helpers. A new setting needs
  **three** edits here: the `ENV_KEYS` list, the default assignment, and the
  export list. Missing `ENV_KEYS` means the setting works in `config.env` but
  not from the command line.
- `bin/detect-hardware.sh` — the memory model. Takes a weight size and a context
  window, returns the budget the guards enforce.
- `bin/serve.sh` — the only script that loads the model. Ends in `exec`, so
  nothing can run after the server is up.
- `bin/doctor.sh` — checks, never changes. Every row carries a fix.
- `bin/catalog.sh` — the one list of models.
- `docs/01`–`09` — user-facing, in reading order. Contributor material does not
  go here.

## Quality rules

- A guard refuses and names the fix. It does not warn and continue. A check that
  cannot refuse belongs in `doctor.sh`, not in `serve.sh`.
- Every figure in the repository states whether it was **measured here**,
  **reported by a publisher**, or is **arithmetic**. An unlabelled number is a
  bug, and an unlabelled number derived from another unlabelled number is the
  failure this rule exists to prevent.
- Before adding a constant, check whether the runtime already computes it.
  `mlx-serve` derives its own prefill chunk, its own resident-memory cap and its
  own context size from the machine. Overriding one of those with a hardcoded
  Bash value creates a second, worse-informed source of truth.
- When a script's help text promises a behaviour, the script and the help change
  in the same commit. `bin/serve.sh` enumerates its guards in its own help; add
  a guard and the count is stale.
- Prefer a comment beside the code over a paragraph in `docs/`. The docs are
  already three times the size of the scripts.

## Verified environment facts — do not re-derive

Established 2026-08-17 on the reference machine (M3 Max, 36 GB) against
`mlx-serve 26.8.8`, `mlx 0.32.0`, `mlx_lm 0.31.3`, Claude Code `2.1.233`.
Each line carries the command that reproduces it. Re-verify only when a version
in this list moves.

**`mlx-serve` is not a Python package and is not in `.venv`.**
It is a compiled Mach-O binary installed by Homebrew — `bin/setup.sh` taps
`ddalcu/mlx-serve`, and `bin/serve.sh` ends in a bare `exec mlx-serve`.
`.venv/lib/python3.12/site-packages/` holds only `mlx/` and `mlx_lm/`.
Checking flags with `pip show` or by reading `mlx_lm` source is a dead end.
*Verify flags with `mlx-serve --help`, nothing else.*

```
$ command -v mlx-serve            # /opt/homebrew/bin/mlx-serve
$ ls .venv/lib/python3.12/site-packages/   # mlx, mlx_lm — no mlx-serve
```

**`mlx-serve` embeds three engines, one of which is antirez's ds4.**
This is the single most consequential fact in this file: the binary `airgap`
already installs can serve GGUF through llama.cpp or through the ds4 engine,
and can stream expert weights from SSD for one model family. `airgap` passes
none of it. See `AUDIT.md` §F for what that does and does not make reachable.

```
$ mlx-serve --version
mlx-serve 26.8.8 · mlx 0.32.0 · llama.cpp b10034 · gguf 3 · ds4 unknown
$ mlx-serve --help | grep -E 'engine|ssd-streaming|ds4-mtp'
  --engine {auto|ds4|llama}   Engine selector for `.gguf` inputs ONLY
  --ssd-streaming             ds4 / DeepSeek-V4-Flash only
  --no-ds4-mtp                ds4 only
```

The `ds4 unknown` slot means the embedded engine reports no version. Do not
assume it tracks any particular upstream commit.

**The server already writes the cache evidence the docs quote by hand.**
`~/.mlx-serve/logs/mlx-serve-<port>.log` contains
`[hot-cache] reused N/M tokens (matched …; entry …)` at the default log level,
plus `hybrid miss` and `evicted LRU entry` lines. The figure hand-typed into
five documents (`docs/05`, `06`, `07`, `08`, `09`) is a line already on disk.
The log has **no per-line timestamps** and is appended across restarts, so any
reader must first scope to the last `^Logging to ` banner or it will report a
run that ended days ago as current. It rotates at 32 MB.

**`/metrics.json` exists and its keys are known.** Counters live under a
`counters` object: `prefix_cache_queries_total`, `prefix_cache_hits_total`,
`prefix_cache_tokens_total`, `prompt_tokens_total`, `prefill_tokens_total`,
`generation_tokens_total`, `requests_success_total`, `requests_cancelled_total`,
with `gauges` and `histograms` siblings. `METRICS` defaults to 1, so the endpoint
is already being served. It returns **503**, not an error, when metrics are off.
Semantics, established by sending one 1212-token prompt three times to a fresh
9B: `queries` counts **every** request including the cold first one (3),
`hits` the ones that resumed (2), `prefix_cache_tokens_total` the tokens
resumed (2 × 1181 = 2362), `prompt_tokens_total` all prompt tokens (3 × 1212 =
3636), `prefill_tokens_total` the tokens actually computed (1212 + 31 + 31 =
1274). Wall time for the three: 3241, 337, 236 ms — MEASURED, single sample.
The strings *"Prefix cache hit count"* / *"Prefix cache lookup count"* are
Prometheus HELP text on the separate text-format endpoint — they are **not**
JSON keys. Do not grep for them in `/metrics.json`.

**`--api-key` gates `/metrics` and `/v1/models`, but not `/health` — and it
exempts loopback entirely.** The server's own banner says so:
`API key auth: ENABLED for non-loopback requests (localhost is trusted; /health
stays open)`, and a server started with `API_KEY=s3cret` answered 200 on
`/v1/models`, `/metrics.json` and `/v1/messages` from `127.0.0.1` with no key
and with a wrong key. So under airgap's own settings — `serve.sh` refuses a
non-loopback `HOST` — the key protects nothing doctor can reach, and there is no
loopback way to test that a header satisfies it. `bin/doctor.sh` sends the
header from one helper (`srv_curl`) anyway. See `AUDIT.md` C2.

```
$ API_KEY=s3cret ./bin/serve.sh          # then, from the same Mac:
$ curl -sS -o /dev/null -w '%{http_code}\n' -H 'x-api-key: nope' http://127.0.0.1:11234/v1/models
200
```

**`mlx-serve` binds its port *before* loading the model.** A second start on the
same port dies immediately at bind with a named error and never loads weights.
The unguarded case is therefore narrower than it looks — it is two starts on
*different* ports, or `bench.sh`, which passes no `--port` at all. See `A1`.

```
$ mlx-serve --model /tmp/not-a-model --serve --port 11299
Listening on 0.0.0.0:11299        # ← printed before the load is attempted
```

**`mlx-serve` has its own free-RAM preflight**, which refuses an over-committing
load and names `--skip-mem-preflight` as the override. `bin/serve.sh` already
refuses that flag in `EXTRA_ARGS`. A *staggered* second load is therefore
caught by the engine even off-port.

**`mlx-serve` already sends SSE keepalive frames.** Do not implement keepalive;
it exists. What is missing is a *name* for the stall limit — see `A5`.

**Stall timeouts collide at exactly 300 s on both ends.**
Server: `--timeout` default 300 s ("abort a request after n seconds WITHOUT
producing a token"). Client: Claude Code's `CLAUDE_STREAM_IDLE_TIMEOUT_MS`
resolves through `Math.max(env, 300000)` — so a value *below* 300000 has no
effect, the variable can only raise. `API_TIMEOUT_MS` defaults to 300000
locally (600000 in SDK client construction). A related
`CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS` takes precedence when set. All read from
`~/.local/share/claude/versions/2.1.233` with `strings -a`.

**`/tmp/ds4.lock` is taken.** The `mlx-serve` binary embeds ds4's instance-lock
code, including the literal path `/tmp/ds4.lock` and the refusal string
`ds4: another ds4 process is already running (pid %ld)`. airgap's own lock must
not use that path. `flock(1)` does not exist on macOS; `/usr/bin/shlock` does.

**Claude Code always sends `thinking.budget_tokens`.** It derives one from
`max_tokens` and clamps it. Confirmed both in the binary and in live traffic:
`~/.mlx-serve/logs/` shows `POST /v1/messages (… thinking=true, tools=…)`.
This is why the server-side `--reasoning-budget` flag is inert — see below.

**The 27B is thinking-by-default at `xhigh` effort.** Its `tokenizer_config.json`
chat template sets `reasoning_effort|default('xhigh')` when thinking is
undefined. The 9B is thinking-on-by-default too. Disabling thinking is a large
behavioural change, not a tuning nudge.

**The default checkpoint is hybrid-SSM but not MoE.** `config.json` reports
`model_type: qwen3_5_text`, `full_attention_interval: 4`, and no `num_experts`.
Consequently: expert-streaming techniques have nothing to stream, and
`--ssm-checkpoint-stride`'s MoE caveat does not apply to this build.

## Falsified — do not retry

**`--reasoning-budget` does not reduce latency or generated tokens.**
It looked like the largest available performance lever. It was measured on two
`mlx-serve 26.8.8` instances (9B, temp 0, `max_tokens` 3000) and it is inert:

| `--reasoning-budget` | output tokens | wall | answer |
|:--|--:|--:|:--|
| unset | 1156 | 20.9 s | identical |
| 8 | 1156 | 20.8 s | identical |

Two independent reasons. **(1)** A request-level `thinking.budget_tokens`
overrides the server flag, and Claude Code always sends one — so the flag is a
no-op on every real turn. **(2)** Even when it does apply, it truncates the
returned `thinking` *string* after the fact; generation is unaffected. Request-
side budgets behave identically (128 → 501 chars, 1024 → 2238 chars, both at
1156 tokens / ~20.8 s). At `max_tokens=500` the answer block was empty with and
without the flag — capping the budget does not rescue a truncated answer.

The real lever is client-side and is an on/off switch, not a budget:
`thinking: {type: "disabled"}`, reachable via `MAX_THINKING_TOKENS=0`.
Measured on the same server, same prompt: **376 output tokens, 7.2 s, complete
answer** against 1156 tokens and 20.9 s — 3.1× fewer tokens, 2.9× faster.
*(MEASURED, single sample, Qwen3.8-9B-mlx-4Bit, M3 Max 36 GB, `mlx-serve`
26.8.8. Not measured on the 27B. The quality cost is not measured on either.)*
That is `E4` in `AUDIT.md`.

**ds4 does not size its prefill chunk from host memory.** A proposal to derive
`PREFILL_CHUNK` from RAM cited ds4 as precedent. It is not one: ds4 varies the
chunk by *model variant, prompt length and multi-GPU topology*, never by RAM.
And `mlx-serve` already memory-sizes the chunk itself, printing
`Prefill chunk: N tokens (memory-sized down from M; --prefill-chunk overrides)`.
The correct change is to stop overriding it — see `E1`.

**ds4 is not a viable runtime for airgap's median user.** It compiles in exactly
three model shapes (DeepSeek V4 Flash, DeepSeek V4 PRO, GLM 5.2), all 100B+ MoE,
dispatching on two architecture strings, and its own `AGENT.md` states it is
"not a generic GGUF runner". Smallest target: 81 GB on disk, recommended for
96/128 GB machines; the SSD-streaming floor is a 64 GB MacBook. airgap's tested
machine is 36 GB and its entire disk budget is 45 GB. This cannot be fixed in
Bash — the shapes are compiled constants. See `AUDIT.md` §F for the honest
framing.

## Before you claim something works

The repository's credibility is its only feature. Nothing is "done" on the
strength of a diff.

1. Run the script. Not a dry run — the real one, on this machine.
2. Paste the output into the commit or the PR. `bench.sh` output includes the
   machine, the model, the prompt and the token count for exactly this reason.
3. If a figure changed, say which of the three labels it carries now.
4. If a change touches a guard, prove the refusal still fires. A guard that
   silently stopped refusing looks identical to one that never had to.
5. If a change touches `serve.sh`, check its help text still describes it.
6. Anything verified only on the 9B says so. The 27B has never been loaded on
   this machine, and several open items exist precisely because of that.
