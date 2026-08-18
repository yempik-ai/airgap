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

- **Last landed (all 2026-08-18, in order):** `E1` · bench lock release ·
  `tests/` + CI (green on GitHub; pin any new action at a Node-24 major) ·
  `E4` (thinking off, opt-in — `MAX_THINKING_TOKENS`, proven through Claude
  Code 2.1.234) · `A7` (wired ceiling labelled ARITHMETIC; doctor quotes the
  server-measured 28.1 GB) · `B3` (`IDENTICAL` = observed on this run) ·
  `B5` (`RELEASE.md`) · `B4` (`bench.sh` ends as one row; `bench/` one file
  per Mac) · **the guards-that-do-not-guard slice: `D1`+`D2` (a truncated or
  half-arrived shard is caught, and `model_state` in `env.sh` is the one
  answer to "is the model here?"), `A4` (`CTX_SIZE` refused above the model's
  own maximum), `D4` (`stop.sh` stops the lock holder and its children, and
  names a foreign port holder), `A6` (`MLX_SERVE_MIN=26.8.8`, refused),
  `A2` (`hw_disk_need_gb` — `MIN_DISK_GB` is computed and `serve.sh` refuses
  a disk that cannot hold the prefix cache), `C3` (the log rotates at 32 MB,
  and its tail is shown when a server is gone)** · `F5` (the KV figure is
  per model — `model_kv_kib` reads it from `config.json`, the catalog's new
  `kv KiB/token` column stands in before download — and per `KV_QUANT`;
  the 9B's term halved, `KV_QUANT=off` is finally seen by the guards, the
  reference budget is unchanged) · the offline halves of `E2` (`hw_kv_tokens`
  — the prefix memory tier stated in prompt tokens on the banner, doctor's row
  and `docs/07` §5, with the 32-entry cap named) and `E3` (`docs/07` §12's
  table of the hot-path flags with server defaults, all labelled unmeasured,
  none made a setting) · **`ROADMAP.md` Phase 1: `bin/run.sh <harness>`** —
  the contract, `harness/claude-code.sh` and `harness/codex.sh` both verified
  live with `--probe`, the `claude-local.sh` shim, doctor's per-adapter rows
  and `docs/10-other-harnesses.md` · **two more adapters, Pi 0.84.2 and
  Hermes Agent 0.20.4** (`harness/pi.sh`, `harness/hermes.sh`, both installed
  here now and probed live the same day; the contract gained an optional
  `harness_prepare` for Pi's models.json, Hermes's `.env`-override discovery
  became a guard, and `tests/pi-models-json.sh` plus
  `tests/hermes-env-guard.sh` hold both). Details and numbers:
  `CHANGELOG.md`; status per item: `AUDIT.md`.
  Two things a later session must not undo: the `docs/07` renumbering (a new
  §7; 7–13 → 8–14, cross-refs updated everywhere but `AUDIT.md`'s
  audit-time citations) and the `claude-local.sh` banner, now eight lines —
  the adapter and its dialect on line 1, the answer cap on an `output` line of
  its own, quoted in `docs/02`, `docs/05` and `docs/06`.
- **Roadmap position:** Phase 0.5 (the audit backlog) is complete, and so is
  every audit item that needs neither the 27B nor a measurement — 19 of 24.
  Phase 0 (credibility gaps, "before publishing") is 1 of 5 — the four left
  need hardware this machine cannot give while in use (the 27B *measured*, a
  fresh user account, a 16 GB Mac, the `A5` stall experiment on the 27B);
  the fifth, `A7`, is done. The 27B has been *loaded* once (2026-08-17, one
  turn, no figures — see the environment facts below); it is the measurement
  that is outstanding, not the load. **Phase 1 is shipped for four harnesses**
  (Claude Code, Codex CLI, Pi, Hermes Agent — all 2026-08-18); what is left
  in it is adapters for harnesses nobody here has installed — Aider,
  OpenCode, mini-swe-agent, little-coder, in the order asked (2026-08-18) —
  and rule 1 (a live `AIRGAP OK` probe) has no shortcut. Phases 2–4 are not
  started.
- **Next, in order of value:** the 27B measurement (`AUDIT.md` A3, E5,
  `ROADMAP.md` Phase 0), which every "9B only" figure in this file is
  waiting on; `B2` (a context sweep — `bench.sh` already emits the row a
  sweep would append, so it is a loop and a cap, 9B is enough to start) and
  `B6` (a quality suite, the only way `E4`'s quality cost becomes a number)
  — both need the model loaded at length, and the 9B is enough to start
  (it loads here with ~14 GB free; proven 2026-08-18). Only `A3`'s missing
  number, and `ROADMAP.md` Phase 0's first item, actually need the 27B.
  **Nothing offline is left in the audit backlog** (2026-08-18): the halves
  of `E2` and `E3` that remain are measurements (does the 32-entry cap bind
  first; does any hot-path flag move this workload), and `bench.sh` would
  need an `extra_args` column to take the second one — a `bench/` contract
  change that belongs with `B2`.
- **Blocked on memory, not on decisions:** anything needing the 27B loaded
  *for long enough to measure*. It has been served on this machine exactly
  once, for one turn (2026-08-17). `serve.sh` needs 22 GB free for
  it and a working day leaves ~14 (2026-08-18: a 3.2 GB VM, a browser,
  WhatsApp and three Claude Code sessions were the difference). An agent
  cannot free that — it means closing the user's apps — so ask, do not kill.
  `AUDIT.md` E5 and A5 both stop short of a measurement for this reason, and
  `ROADMAP.md` Phase 0 names it.

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
  not from the command line. Settings a single script reads are the one
  exception: on `ENV_KEYS`, defaulted and exported (if at all) in that script
  — `TOKENS`, `PROMPT`, `PROMPT_FILE`, `ROW_FILE` in `bench.sh`;
  `CLAUDE_CODE_MAX_OUTPUT_TOKENS` and `MAX_THINKING_TOKENS` (no default:
  unset means "as the model ships") in `harness/claude-code.sh`.
  `LOAD_SHAPE_ARGS`
  is also here — the flags
  that shape a load's memory footprint (context size, KV format, vision
  switch, and the prefill chunk only when `PREFILL_CHUNK` pins one), passed by
  both `serve.sh` and `bench.sh`; a memory-relevant flag belongs in that list,
  not in either script.
  Some things here are **not** settings and are therefore not on `ENV_KEYS`:
  `MLX_SERVE_MIN` (the oldest `mlx-serve` the flags in `serve.sh` were verified
  against — raise it in the commit that starts passing a newer flag), the
  `model_*` helpers that answer "is the model here, and is it whole?" for the
  five scripts that ask (`model_state` → `absent`/`partial`/`complete`), and
  the readers `model_max_ctx` and `model_kv_kib` (the two readers of
  `config.json`: the model's maximum context, and what one token costs in KV
  cache at 16 bits — `hw_rebudget` scales the latter by `KV_QUANT`, and
  `HW_KV_KIB` / `HW_KV_SOURCE` say what figure the budget used and whether it
  came from `config.json`, the catalog or an assumption), `mlx_serve_version`,
  `version_lt`, `log_tail` and `log_ended_cleanly`. `client_timeout_ms` is the
  milliseconds a harness waits for a silent request — a minute more than
  `SERVE_TIMEOUT`, so the server gives up first and names the reason; a floor
  or ceiling a particular binary imposes on it belongs in that harness's
  adapter, not here. `metrics_counters <name>…` reads the named counters from
  `/metrics.json` in one fetch and prints them space-separated in argument
  order (`0` for one the server does not report, nothing and exit 1 when the
  endpoint does not answer 200) — `run.sh --probe` and `doctor.sh` share it,
  and doctor asks the status code only on that failure path. A question two
  scripts ask belongs here, once.
- `bin/detect-hardware.sh` — the memory model. Takes a weight size and a context
  window, returns the budget the guards enforce. The disk model is here too:
  `hw_disk_need_gb download|serve` is the one place the download peak and the
  prefix cache's disk requirement are worked out, and `MIN_DISK_GB`,
  `serve.sh`'s disk refusal and doctor's `disk` row all read it.
- `bin/serve.sh` — the only script that loads the model. Ends in `exec`, so
  nothing can run after the server is up.
- `bin/run.sh` — the one dispatcher, for every harness. It sources `env.sh`,
  lists `harness/*.sh` when it is given no name or a name that is not there,
  sources the adapter, lets it wire itself, checks the server, prints the
  banner, and then either `exec`s the harness or runs `--probe`. `--probe`
  sends one question through the harness and reports the verdict, the wall
  clock and the prompt tokens the *server* counted for that turn (read through
  `metrics_counters`, so it is the harness's whole fixed cost, background
  requests included). Order matters and a test holds it: `harness_wire` runs
  **before** the server check, so a typo in a harness setting is refused
  whether or not a server is up (`tests/thinking-knob.sh`).
  `bin/claude-local.sh` is one `exec` line onto `run.sh claude-code` and stays
  that way: the name is in ~58 places in these documents.
- `harness/` — one file per harness, and the only place that knows what a
  particular harness calls anything. The contract is four names —
  `HARNESS_DIALECT` (`anthropic`/`openai`/`ollama`), `HARNESS_BIN`,
  `HARNESS_ONESHOT`, `harness_wire` — plus three optional: `harness_usage`;
  `HARNESS_ENDPOINT` for an adapter whose real endpoint disagrees with its
  dialect's usual one (`harness/codex.sh`: `/v1/responses`, because 0.147.0
  refuses `wire_api = "chat"` — only `doctor.sh` reads it); and
  `harness_prepare`, for a harness that can only be told about a provider
  through a file it reads. `run.sh` calls that last one after every refusal
  (the wiring guards, the binary check, the server check), and the wire-only
  tests never do. `harness/pi.sh` is the one adapter that defines it — Pi
  reads providers from `~/.pi/agent/models.json` and from nowhere else — and
  an adapter that can wire itself without touching a file must not. An
  adapter never checks the server, parses `run.sh`'s options, computes a
  timeout, prints the shared banner lines or runs the probe — those live once,
  in `run.sh` and `env.sh`. Each adapter carries its harness's own settings
  under that harness's own names, defaulted there and on `ENV_KEYS`:
  `CLAUDE_BIN`, `CLAUDE_CODE_MAX_OUTPUT_TOKENS` and `MAX_THINKING_TOKENS` for
  `claude-code.sh`; `CODEX_BIN` for `codex.sh`; `PI_BIN` for `pi.sh`;
  `HERMES_BIN` and `HERMES_MAX_TOKENS` for `hermes.sh` (each the ordinary
  three edits in `env.sh`, exactly as `CLAUDE_BIN` has them). No translation
  layer, and no default without a measurement behind it. The rules an adapter
  meets before it is listed are in `docs/10-other-harnesses.md`, and rule 1
  is a live `--probe` transcript.
- `bin/doctor.sh` — checks, never changes. Every row carries a fix.
- `bin/catalog.sh` — the one list of models. Seven columns; the `kv KiB/token`
  one is verified against each repository's `config.json`, and a new entry
  needs its own figure computed, not a neighbour's copied.
- `docs/01`–`10` — user-facing, in reading order (`10` is the harness page:
  the contract, the six rules, and one verified probe line per adapter).
  Contributor material does not go here.
- `bench/` — one `.tsv` per Mac, one row per `bench.sh` run, header and
  columns fixed in `bench/README.md`. Never hand-edited; a row is a run.
- `RELEASE.md` — what is re-run before a tag, on what, and what blocks it.
  Touch a guard or a figure and this file says what you owe before tagging.
- `tests/` — offline checks, no server and no weights: `tool-call-verdict.sh`
  lifts `row`, `tool_probe_body`, `tool_call_verdict` and `tool_call_row` out
  of `doctor.sh` by their `name() {`…`}` ranges (doctor cannot be sourced; it
  runs at load), stubs `srv_curl` to print a fixture, and checks the row each
  captured shape renders; `load-shape.sh` holds the `LOAD_SHAPE_ARGS`
  contract; `thinking-knob.sh` holds `harness/claude-code.sh`'s
  `MAX_THINKING_TOKENS` guard, reached the way a person reaches it — through
  `bin/claude-local.sh` (it points `PORT` at a closed port, so "past the
  guard" shows as the no-server error); `wired-log.sh` holds doctor's
  `log_wired_gb` reader;
  `harness-contract.sh` holds the harness contract — for every `harness/*.sh`,
  that the four names are declared and of the right kind, and that
  `harness_wire` itself (not the ambient environment) names `BASE_URL` and
  `MODEL_ID`; an adapter with `harness_prepare` runs it under a scratch
  `HOME`, must print nothing, and what it wrote there counts as wiring;
  `pi-models-json.sh` holds the rules for the one file `harness/pi.sh`
  writes — created, merged around other providers, unchanged means not
  rewritten, comments refused with the block to paste printed — against a
  scratch `PI_CODING_AGENT_DIR`; `hermes-env-guard.sh` holds
  `harness/hermes.sh`'s refusal when a `CUSTOM_BASE_URL` line in
  `$HERMES_HOME/.env` would beat the wiring, reached through `run.sh` with
  `HERMES_BIN=/bin/echo` and a scratch `HERMES_HOME`;
  `run-dispatch.sh` holds `run.sh`'s dispatch — the list derived
  from the folder, the refusals, and `<name> --help` without a server;
  `model-state.sh` holds the `absent`/`partial`/`complete` contract and the
  rule that only `env.sh` and `verify-model.sh` may enumerate shards;
  `verify-truncation.sh` holds `verify-model.sh`'s byte and index checks;
  `kv-figure.sh` holds the per-model, per-`KV_QUANT` KV arithmetic — the
  bit-width map, the reference budget, `model_kv_kib` on hand-written
  `config.json` shapes, the catalog column and `env.sh`'s
  config.json → catalog → assumed cascade;
  `serve-guards.sh` fires four of `serve.sh`'s refusals with a stubbed
  `mlx-serve` on `PATH` (which is also what stops a wrongly-passing guard
  from loading 20 GB — `MIN_FREE_GB=999999` is the second backstop, so
  "refused for memory" is how that test observes "got past everything
  above"); `stop-targets.sh` gives `stop.sh` a lock holder with a child and a
  foreign listener, checks which one it kills, and holds the rule that the
  log's tail is printed only when the last run did not say goodbye. The last three build their
  model folders with `tests/fixtures/make-model.py` at test time: a shard has
  to be over 1 MB to get past the pointer test, and a 1 MB blob does not
  belong in git. Rename one of the lifted functions and the test says so by
  name. `tests/run.sh` runs all; `.github/workflows/ci.yml` runs it on a macOS
  runner and `bash -n` plus shellcheck on Ubuntu — over `start.sh`, `bin/`,
  `harness/` and `tests/` — on every push and pull request.

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
`mlx-serve 26.8.8`, `mlx 0.32.0`, `mlx_lm 0.31.3`, Claude Code `2.1.233`,
Codex CLI `0.147.0`, Pi `0.84.2` and Hermes Agent `0.20.4` (those three on
2026-08-18).
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
$ mlx-serve --version          # eight lines on stdout, one per component,
mlx-serve 26.8.8               # plus a "[mem] MLX buffer-pool cap …" line
mlx 0.32.0                     # on STDERR. The version is line 1, field 2 —
mlx-c fba4470b8907             # which is what mlx_serve_version() (env.sh)
nax off (requires M5-class GPU)  # reads, and what MLX_SERVE_MIN compares.
ggml 0.16.0 (505b1ed15)
llama.cpp b10034
gguf 3
ds4 unknown
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

**`mlx-serve --prompt` (one-shot mode) prints three stat lines on stdout, and
accepts the serve-side load flags.** After the answer, delimited by two
`==========` lines: `Prompt: N tokens, R tokens-per-sec`, `Generation: N tokens,
R tokens-per-sec`, `Peak memory: X GB`. `--ctx-size`, `--kv-quant` and
`--prefill-chunk` are honoured in this mode (`[args] kv-quant: turboquant 4-bit`
on stderr) and do not distort the decode figure (35–36 vs 37 tok/s with and
without, same prompt). **`Peak memory` is MLX's Metal-buffer accounting, not
process RSS**: `footprint(1)` on the process showed `phys_footprint 5328 MB`
with `IOAccelerator (graphics) 4946 MB` against a printed `4.822 GB` — the
whole process is ~0.5 GB above the printed peak. Treat it as a lower bound.
`bench.sh` parses all three lines; there is no `--prompt-file` flag, so
`PROMPT_FILE=` is read by the script and passed as the `--prompt` argument
(a 62 KB file is fine; ARG_MAX here is 1 MB).

```
$ mlx-serve --model ./Qwen3.8-9B-mlx-4Bit --prompt "Say hello in five words." \
    --max-tokens 20 --temp 0.0 --ctx-size 65536 --kv-quant turbo4 --prefill-chunk 4096 --no-vision
==========
Hello, how are you?
==========
Prompt: 18 tokens, 128.403 tokens-per-sec
Generation: 6 tokens, 49.204 tokens-per-sec
Peak memory: 4.805 GB
$ footprint -p <pid>          # while a one-shot run is generating
mlx-serve [35576]: 64-bit    Footprint: 5322 MB
4940 MB  IOAccelerator (graphics)   214 MB  MALLOC_LARGE   144 MB  Owned physical footprint (unmapped) (graphics)
```

**The prefill working set is chunk-bound and large; the rate is not.**
MEASURED on the 9B, single samples, `bench.sh` with
`PROMPT_FILE=docs/08-how-it-works.md` (16,377 tokens on 2026-08-17, 16,408
on 2026-08-18; the peaks are the measurement, the "+N GB" gaps were worked
out with the pre-`F5` KV term, which charged the 9B the 27B's 16 KiB/token,
so each gap here reads about 0.13 GB low against what `bench.sh` prints
today): peak 7.52 GB, i.e. **+2.56 GB** over weights + KV-used at
`PREFILL_CHUNK=4096` (7.535 / +2.58 when re-run a day later); **+1.11 GB** at
1024; **+0.72 GB** at 512 (peak 5.63); **+4.57 GB** at the 8192 one-shot
ceiling (peak 9.52). Prefill rate: 374 then 309 at 4096, 285 at 1024, 430 at
512, 594 at 8192 — it does not track the chunk and is not reproducible to
better than ~20% here, so do not quote a "speed cost" for a smaller chunk from
these. Decode after that prompt: 15.6 tok/s (7.7 on the noisier day), against
36.7 after a 41-token one. Not measured on the 27B.

**`mlx-serve` sizes the prefill chunk itself in serve mode — from the memory
free at load, `--max-resident-mem` and `--ctx-size` — and not at all in
one-shot mode.** Unpinned, the server prints `Prefill chunk: N tokens
(memory-sized down from 8192; --prefill-chunk overrides)` after `Model ready`;
pinned, it prints nothing about the chunk. Probed on the 9B (serve mode, argv
checked with `ps -o args=`, the `[preflight] … available` line as the free
figure): `--max-resident-mem 6GB` at 14.9 GB free → **512**, the same at
18.9 and 19.5 GB free → **1024**; `12GB` at 19.1 free → 1024; `24GB` at 20.1 free →
2048; flag absent (engine default 22.5 GB) at 18.9 free → 2048 — all at
`--ctx-size 65536`; `6GB` at `--ctx-size 8192`, 19.9 free → 2048. So all
three inputs move it and the exact rule is not known; do not write one down.
Under airgap's own settings on this machine (9B, `MAX_RESIDENT_MEM=6GB`,
`CTX_SIZE=65536`) it has been 512 and 1024. `mlx-serve --prompt` (what
`bench.sh` uses) prints no such line, prints no `[registry]` line, and reaches
the same 9.52 GB peak with and without `--max-resident-mem 6GB` on the
16,408-token prompt — i.e. it reads at the 8192 ceiling. So a `bench.sh` peak
with `PREFILL_CHUNK` empty is an upper bound on the server's, which is why
`bench.sh` prints a `chunk:` line naming the pin that reproduces the server's
last shape. Since `E1` (2026-08-18) airgap passes `--prefill-chunk` only when
`PREFILL_CHUNK` is set.

```
$ ./bin/serve.sh                      # unpinned; then in ~/.mlx-serve/logs/mlx-serve-11234.log:
[registry] max_resident_models=1, max_resident_mem=6.0 GB
[preflight] weights ~4.69 GB, available 14.94 GB
Prefill chunk: 512 tokens (memory-sized down from 8192; --prefill-chunk overrides)
$ ./bin/serve.sh                      # same settings, more free memory
[preflight] weights ~4.69 GB, available 19.51 GB
Prefill chunk: 1024 tokens (memory-sized down from 8192; --prefill-chunk overrides)
```

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

**`mlx-serve` accepts `tool_choice` and ignores it.** `{"type":"any"}`,
`{"type":"tool","name":…}` and no `tool_choice` at all produce the same
answer to the same prompt — the rendered prompt is byte-identical (the log
shows a `reused 283/284` cache hit across the three), and a question the tool
does not fit ("Say hello in three words", one `get_weather` tool offered)
comes back as text under all three. So a doctor row cannot use `tool_choice`
to separate *declined* from *unparsed*; it has to ask a question that needs
the tool and read *how* the answer failed. `doctor.sh` does that and does not
send `tool_choice` (the real Anthropic API also rejects a forced choice with
thinking on, so sending it would be wrong on the one server that enforces it).

```
$ curl -sS -H 'content-type: application/json' http://127.0.0.1:11234/v1/messages -d '{"model":"Qwen3.8-9B-mlx-4Bit","max_tokens":256,"temperature":0,"tool_choice":{"type":"any"},"tools":[{"name":"get_weather","description":"Get the current weather in a city.","input_schema":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}],"messages":[{"role":"user","content":"Say hello in three words."}]}'
{"content":[{"type":"text","text":"Hello, friend!"}],"stop_reason":"end_turn",…}
```

**The streamed tool-call shape is known.** With thinking on (which Claude
Code always sends), the SSE stream is: `content_block_start` index 0
`{"type":"thinking",…}` → `thinking_delta`s → `signature_delta` with
`"signature":"mlx-serve-local"` → `content_block_stop` → `content_block_start`
index 1 `{"type":"tool_use","id":"toolu_…","name":…,"input":{}}` → **one**
`input_json_delta` carrying the whole `partial_json` → `content_block_stop` →
`message_delta` with `stop_reason: tool_use` and `usage.output_tokens` →
`message_stop`. Non-streamed, the same request returns `content` with the
`thinking` block then a `tool_use` block whose `input` is already an object.
Both MEASURED on the 9B: 69 output tokens, ~1.5 s streamed on a warm server;
25 tokens / ~0.5 s with thinking off. Not measured on the 27B.

**`CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK` exists in 2.1.233** and gates
the retry that turns a failed streamed request — including one that idled
past `CLAUDE_STREAM_IDLE_TIMEOUT_MS` — into a non-streamed one
(`strings -a` shows it OR'd with `tengu_disable_streaming_to_non_streaming_fallback`
next to `"Stream idle timeout - partial response received"`).
`harness/claude-code.sh` sets it to 1, for `claude-local.sh` and
`run.sh claude-code` alike.

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

**The GPU wired ceiling on this machine is 28.1 GB, and the server prints it.**
Every `mlx-serve` load logs `[wired] mode=max limit=28753 MB` (28.08 GiB;
MLX's `mx.device_info()['max_recommended_working_set_size']` agrees), against
the 27.0 GB the 2/3–3/4 rule in `detect-hardware.sh` computes for 36 GB. The
rule is ARITHMETIC and labelled as such; it stays the guards' number (exists
before any load, cannot go stale) and doctor quotes the measured one beside
it. `sysctl iogpu.wired_limit_mb` reads `0` (auto) and does not reveal the
value. One machine — do not "correct" the rule from this sample.

```
$ grep '^\[wired\]' ~/.mlx-serve/logs/mlx-serve-11234.log | tail -1
[wired] mode=max limit=28753 MB
```

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
*The server's log contradicts this and the server is wrong about it* — every
load prints `Model: qwen3_5_moe (…)`, `Precomputing MoE layer weights...` and
`MoE routing compiled`, for the 9B and the 27B alike. Those are names on
`mlx-serve`'s loader path, not properties of the checkpoint: the 27B weight
index contains **zero** tensors matching `expert`, and `text_config` has no
MoE key at all (checked 2026-08-18, both models). Do not re-derive this from
the log.

**The 27B loads, and its in-checkpoint MTP head loads with it.** MEASURED
2026-08-17, one `serve.sh` session on the reference machine, in
`~/.mlx-serve/logs/mlx-serve-11234.log` (the third session in that file):

```
[preflight] weights ~19.97 GB, available 25.59 GB
Loaded 1874 weights from 5 file(s)
[mtp] loading in-checkpoint head from the trunk shards
[mtp] loaded native MTP head (dense-mlp; per-weight quant, fallback bits=4/gs=80)
[mtp] draft-only lm_head requantized to 3-bit/gs64
MTP head ready (depth=6).
[wired] mode=max limit=28753 MB
...
POST /v1/messages (…)  prompt=91 tokens
  mtp=enabled (streaming, depth=6)
  <- 91+1 tokens streamed [prefill: 75.4 tok/s, decode: 3.2 tok/s] [max_tokens]
```

That settles the head — `mlx-serve` 26.8.8 finds MTP tensors embedded in the
trunk shards, with no `mtp/weights.safetensors` present. It settles nothing
about speed: one token generated is not a decode figure, the 23,551-token turn
behind it was cancelled at shutdown, and `doctor.sh` and `bench.sh` have never
been run against the 27B. Do not cite `75.4`/`3.2` as measurements of
anything.

### Codex CLI 0.147.0 — every key and flag `harness/codex.sh` uses

Established 2026-08-18 against `codex-cli 0.147.0` (Homebrew cask,
`/opt/homebrew/Caskroom/codex/0.147.0/bin/codex`, a 210 MB arm64 Mach-O).
`command -v codex` on this machine can be a **cmux shim** in a temp folder
that execs `/Applications/cmux.app/…/cmux-codex-wrapper`, which injects cmux's
own hooks and `--dangerously-bypass-hook-trust` for that invocation. Resolve
the real binary before drawing conclusions from `strings`; the probe figures
below are identical through both.

**0.147.0 validates `-c` overrides itself, by name.** `codex exec
--strict-config -c <key>=<value>` refuses an unrecognised key with
``unknown configuration field `<key>` in -c/--config override`` — nested paths
included. That, not `strings`, is how every key below was checked: each one was
accepted, and a deliberate typo in the same namespace was refused. Two
subcommands do not take the flag (`Error: --strict-config is not supported for
codex mcp` / `codex debug`), so the check has to be run through `exec`; a
config error is raised before any request, so a dead `base_url` makes it cheap.

```
$ codex -c model_provider=airgap -c model_providers.airgap.name=airgap \
    -c model_providers.airgap.base_url=http://127.0.0.1:9/v1 \
    -c model_providers.airgap.wire_api=responses \
    --strict-config -c model_providers.airgap.bogus=1 exec --skip-git-repo-check x
Error loading config.toml: unknown configuration field `model_providers.airgap.bogus` in -c/--config override
```

Used by the adapter, each accepted by that validator, its typo refused:
`model_provider`, `model_providers.<id>.name`, `.base_url`, `.wire_api`,
`.request_max_retries`, `.stream_max_retries`, `.stream_idle_timeout_ms`,
`model_context_window`, `analytics.enabled`, `otel.trace_exporter`,
`check_for_update_on_startup`, `features.plugins`. Flags: `-c/--config`,
`-m/--model` (both global, before the subcommand), and `exec`'s own
`--skip-git-repo-check`.

**`wire_api = "chat"` is refused by 0.147.0 — the local wire is Responses.**
The design chose `chat` because `mlx-serve` serves `/v1/chat/completions`. The
binary does not: it stops before any request with ``Error loading config.toml:
`wire_api = "chat"` is no longer supported. How to fix: set `wire_api =
"responses"` in your provider config.`` `mlx-serve 26.8.8` also serves
`POST /v1/responses` (its own startup banner lists it), and that is the pairing
that works. Verified by running both.

**`codex exec` runs against a custom provider with no login and no key.**
MEASURED with a throwaway `CODEX_HOME` (an empty folder, so no `auth.json` and
no `config.toml`) and `CODEX_API_KEY`/`OPENAI_API_KEY` unset: the turn
completed and answered `AIRGAP OK`, and the folder afterwards still held no
`auth.json`. A provider with no `env_key` is not asked for one; adding
`env_key` would make Codex *require* the named variable, so the adapter does
not set it.

**Left alone, Codex sends the ChatGPT sign-in token to whatever `base_url`
names.** MEASURED by pointing the provider at a local Python listener that
prints request headers: with nothing set, the request to `/v1/responses`
carried `authorization: Bearer eyJhb…` (1773 bytes — the OAuth JWT from
`~/.codex/auth.json`) and `chatgpt-account-id: <uuid>`. With `CODEX_API_KEY`
exported, the same request carried exactly that value and **no**
`chatgpt-account-id`. `OPENAI_API_KEY` was ignored in both runs. That is why
`harness/codex.sh` exports `CODEX_API_KEY` (`API_KEY` when set, else the
placeholder `mlx-serve`). The same capture shows Codex sends an
`x-codex-turn-metadata` header carrying the installation id, the git remote URL
and the current commit hash — to `base_url`, which here is this Mac.

**MCP cannot be fully switched off from Codex's command line, and
`-c 'mcp_servers={}'` is a trap.** The TOML parser accepts it and then does
nothing: `-c` MERGES into a table rather than replacing it, so an empty table
changes nothing. `codex mcp list` prints the same 10 servers with and without
it. A *scalar* under the same table does apply — `-c
mcp_servers.gitnexus.enabled=false` flips that row to `disabled` — but that
needs the names out of somebody's own config.toml. What does work is
`-c features.plugins=false` (equivalently `--disable plugins`): 10 servers
become 4, and the 6 that go are every one that reaches the network. The 4 that
remain are the ones written in `~/.codex/config.toml`. `--ignore-user-config`
is not used: it would drop the person's approvals and provider trust with them.

```
$ codex mcp list | grep -cE 'enabled|disabled'                       # 10
$ codex -c 'mcp_servers={}' mcp list | grep -cE 'enabled|disabled'   # 10
$ codex -c features.plugins=false mcp list | grep -cE 'enabled|disabled'   # 4
```

**`--skip-git-repo-check` is an `exec` flag, not a global one.** Outside a git
checkout `codex exec` stops with `Not inside a trusted directory and
--skip-git-repo-check was not specified.`, and `codex --skip-git-repo-check
exec` is refused by the argument parser (`tip: 'exec --skip-git-repo-check'
exists`). It therefore lives in `HARNESS_ONESHOT`, which `run.sh` puts after
the subcommand; a hand-typed `./bin/run.sh codex exec …` outside a checkout
needs it typed too.

**`otel.trace_exporter` takes one of four values.** A bad one is answered with
``unknown variant `bogus`, expected one of `none`, `statsig`, `otlp-http`,
`otlp-grpc``. The adapter sets `none`.

**`-c` beats the profile layer, and a `config.toml` cannot select a profile by
itself.** MEASURED with a throwaway `CODEX_HOME` holding a `sneaky.config.toml`
that sets `model_provider = "other"`, read off the `provider:` line
`codex exec` prints before it sends anything (`base_url` on a closed port, so
no model server is involved):

```
$ CODEX_HOME=<tmp> codex -p sneaky exec …                    # provider: other   ← control
$ CODEX_HOME=<tmp> codex -p sneaky -c 'model_provider="airgap"' … exec …   # provider: airgap
$ CODEX_HOME=<tmp> codex -c 'model_provider="airgap"' … -p sneaky exec …   # provider: airgap
```

The control matters: without the overrides the profile really does win, so the
other two rows are evidence and not an unloaded file. The flag order does not
change the answer. And the legacy default-profile key is gone — a `config.toml`
containing `profile = "sneaky"` stops 0.147.0 at load with ``legacy
`profile = "sneaky"` config is no longer supported; use `--profile sneaky` with
`sneaky.config.toml` instead``. So `harness/codex.sh` needs nothing to
neutralise the profile layer.

**`tools.web_search` is inert, and the `web_search` tool cannot fetch
anything here.** The key is accepted by the validator and changes nothing:
MEASURED against a local listener that parses the request body, the tools array
carries the same entry with the key unset, `false` and `true` alike, on a clean
`CODEX_HOME` as well as on this machine's:

```
RAW web_search entry: {"type": "web_search", "external_web_access": false}
```

That is the provider-side Responses tool: it is offered *to* whatever
`base_url` names — here mlx-serve on loopback, which does not implement it —
and it is offered with external web access already off. The client-side variant
that would fetch by itself is gated on the `standalone_web_search` feature,
which `codex features list` reports as `under development  false` (`search_tool`
reads `removed  false`). So the adapter leaves the key unset rather than pass
one that does nothing.

**Codex's fixed cost per turn, MEASURED.** `./bin/run.sh --probe codex` on the
9B (`Qwen3.8-9B-mlx-4Bit`, `mlx-serve 26.8.8`, `CTX_SIZE=65536`, M3 Max 36 GB,
2026-08-18): **9,336 prompt tokens** with `LEAN_MCP=1` and **10,271** with
`LEAN_MCP=0` — 935 tokens per turn for the plugins. Both figures reproduced to
the token across two runs each and across the cmux shim and the Homebrew
binary. Wall clock 29.8 s cold, 3.4 s warm. Not measured on the 27B. Claude
Code's 17,000-token figure is a different harness's number and is never reused
for this one.

**Two lines at Codex startup against this server are cosmetic.**
`ERROR codex_models_manager: failed to refresh available models: … missing
field 'models'` — Codex asks `GET /v1/models?client_version=…` and mlx-serve
answers the OpenAI `{"object":"list","data":[…]}` shape, which Codex's own
catalog reader does not accept. And `warning: Model metadata for
'Qwen3.8-9B-mlx-4Bit' not found` — Codex has never heard of a model that only
exists on this Mac. Neither stops the turn.

### Pi 0.84.2 — what `harness/pi.sh` relies on

Established 2026-08-18 against Pi 0.84.2
(`npm install -g --ignore-scripts @earendil-works/pi-coding-agent`,
`/opt/homebrew/bin/pi`). Checked in the installed `dist/` sources and Pi's own
docs, then proven live with `./bin/run.sh --probe pi`.

**Providers come from `~/.pi/agent/models.json` and from nowhere else.** Pi has
no `--base-url` flag and reads no base-URL environment variable for a custom
provider (`grep` over `dist/` finds only `LLAMA_BASE_URL`, which belongs to its
bundled llama.cpp extension — a different, server-managing path this repo does
not use). Its docs' alternative is an extension, i.e. TypeScript run inside Pi.
That is why the adapter contract gained `harness_prepare`: the file is the
interface. `PI_CODING_AGENT_DIR` overrides the folder (`dist/config.js`:
`ENV_AGENT_DIR`), which is what `tests/pi-models-json.sh` uses. Pi strips
comments before parsing (`stripJsonComments` in `dist/core/model-config.js`),
so a commented file is legal for Pi and unreadable for `json.loads` — the
adapter refuses to rewrite what it cannot round-trip rather than eat comments.

**The provider shape the adapter writes was proven live.** `api:
"anthropic-messages"` with `baseUrl` set to the server root (no `/v1`; Pi's
Anthropic client appends `/v1/messages`), a placeholder `apiKey` (Pi treats a
keyless model as unavailable; its docs say local servers should keep a dummy
value), `reasoning: true`, `contextWindow` = `CTX_SIZE`. `maxTokens` is left
to Pi's default 16384. MEASURED on the 9B: `AIRGAP OK`, 2,024 prompt tokens,
identical across four probe runs; the server logged `thinking=true`, and
`--thinking off` flipped it to `thinking=false` (that one answer was wrong —
n=1). The OpenAI pairing (`api: "openai-completions"`, `baseUrl` with `/v1`)
also answered, but the server logged `sys=0b` — Pi sends the system prompt as
the `developer` role there — so the shipped dialect is Anthropic.

**`PI_OFFLINE=1` is the whole startup-network switch.** It covers the pi.dev
version check, the install/update telemetry ping, package update checks and
the built-in model-catalog refresh (README "Telemetry and update checks";
`PI_SKIP_VERSION_CHECK` and `PI_TELEMETRY=0` are each a subset). READ in
`dist/`, 27 call sites; not separately measured with a packet capture.

**Retries and the idle limit are settings.json keys, not flags.**
`retry.enabled` (default true, 3 attempts, backoff), `retry.provider.maxRetries`
(default 0) and `httpIdleTimeoutMs` (default 300000) live in
`~/.pi/agent/settings.json` (docs/settings.md). There is no per-run override
on the command line, and the adapter does not rewrite the person's
settings.json — so rule 5 is met only partially for Pi, and the banner and
docs/10 say so instead of hiding it. Pi's 300 s idle default equals
`SERVE_TIMEOUT`'s default, so both sides give up together unless the person
raises `httpIdleTimeoutMs`.

**`--no-extensions` is the whole tool-server switch.** Pi ships no MCP of its
own ("build an extension that adds MCP support"); extensions are the only
route, and the flag disables discovery of all of them (explicit `-e` paths
still load). MEASURED: probe tokens identical (2,024) with and without —
no Pi extensions are installed on this machine, so the saving is honestly
unmeasured.

### Hermes Agent 0.20.4 — what `harness/hermes.sh` relies on

Established 2026-08-18 against Hermes Agent 0.20.4 (2026.8.18, install.sh →
`~/.hermes/hermes-agent`, git 9664e386). Checked in the installed Python
sources (`hermes_cli/`, `agent/`), then proven live with
`./bin/run.sh --probe hermes`.

**The `custom` provider takes its address from `CUSTOM_BASE_URL`.** Resolution
order in `hermes_cli/runtime_provider.py`: explicit CLI value (a code path
`hermes chat` does not expose) → `CUSTOM_BASE_URL` → config.yaml `base_url` →
OpenRouter. `--provider custom` is the documented name for a local
OpenAI-compatible server, and the aliases `ollama`, `vllm`, `llama.cpp` all
resolve to it. `OPENAI_BASE_URL` is read only by the separate `openai-api`
provider and by the first-run "is anything configured?" guard
(`_has_any_provider_configured`, where it alone counts) — the adapter exports
it too, so a Mac with no other credentials does not stop at that guard
(READ in source; not observed here, this machine has other credentials).

**`~/.hermes/.env` beats the process environment.** `load_hermes_dotenv`
loads it with `override=True` (`hermes_cli/env_loader.py`). MEASURED: with a
throwaway `HERMES_HOME` whose `.env` set `CUSTOM_BASE_URL` to a closed port,
the exported value lost and the run failed against the closed port. That is
the guard in `harness_wire`, and `tests/hermes-env-guard.sh` holds it.

**No key reaches a loopback address.** Key selection is host-gated
(`runtime_provider.py`: `OPENAI_API_KEY` only for openai.com hosts,
`OPENROUTER_API_KEY` only for openrouter.ai, a `<VENDOR>_API_KEY` derived from
the hostname, explicitly "" for IPs/loopback); a keyless custom endpoint gets
the placeholder `no-key-required`. So `API_KEY` has no variable that would
carry it, and the adapter sets none.

**The context size is probed from the server.** `agent/model_metadata.py`
resolves it: config override → … → "Local server query", which asks
`GET /v1/models` and reads `context_length` out of the entry's `meta` (among
other keys). mlx-serve 26.8.8 fills `meta.context_length` with the
`--ctx-size` it was started with (checked with `curl`), and the live request
Hermes sent carried `max_tokens=65536` at `CTX_SIZE=65536` — the declared-size
rule met by the server's own answer, with nothing exported. `model.context_length`
in config.yaml exists but has no environment variable in 0.20.4.

**Timeouts and retries, by name.** Streaming stall: for a local endpoint,
`HERMES_LOCAL_STREAM_STALE_TIMEOUT` (default 900 s; applies only while
`HERMES_STREAM_STALE_TIMEOUT` stays at its 180 s default). Non-streaming
stall: `HERMES_API_CALL_STALE_TIMEOUT` (default 90 s, auto-disabled for local
when unset). Whole request: `HERMES_API_TIMEOUT` (default 1800 s — not set;
a long answer is not a stall). Mid-stream reconnects: `HERMES_STREAM_RETRIES`
(`env_int` default 2 in `agent/chat_completion_helpers.py`; the docs page says
3 — the binary wins) — set to 0. Whole-request retry:
`agent.api_max_retries`, config.yaml only, default 3, floor 1
(`agent/agent_init.py`) — no flag, no variable, left alone and said so.
Answer cap: `HERMES_MAX_TOKENS` (`cli.py`: "env var override").

**`HERMES_SAFE_MODE=1` is the LEAN_MCP switch, and the `--safe-mode` flag is
not.** The variable alone gates four things: MCP server configs
(`tools/mcp_tool.py` returns `{}`), plugin discovery (`hermes_cli/plugins.py`),
shell-hook registration (`agent/shell_hooks.py`) and outbound webhooks
(`agent/outbound_webhooks.py`). The flag additionally sets
`--ignore-user-config` and `--ignore-rules`, which would drop the person's
config.yaml and AGENTS.md — too much for LEAN_MCP. MEASURED: probe tokens
identical (15,060) with and without — no MCP servers are configured for
Hermes here, so the saving is honestly unmeasured.

**The probe figures, and what lands in them.** `-z` (the one-shot the probe
uses): 15,060 prompt tokens, `thinking=false`, 36.7 s on Hermes's first turn
(its prefix prefilled), 7.5 s warm. Hermes also sends a background
title-generation request (311 tokens, `temp=0.30`, non-streamed) that
sometimes lands inside the probe's metrics window — one run read 15,371 for
exactly that reason. An interactive `chat -q` turn is bigger: 17,402 prompt
tokens with `thinking=true` (MEASURED once each). The two entry points differ
inside Hermes itself, not in this repo's wiring.

**The update check has no switch.** Interactive `hermes` runs a scoped
`git fetch origin main` of its own checkout (cached six hours,
`hermes_cli/banner.py`); `-z` does not reach it on this machine's code path,
but no setting or variable disables it in 0.20.4 — searched for one, found
none, documented instead as the one startup network operation the adapter
cannot switch off.

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
`thinking: {type: "disabled"}`, reachable via `MAX_THINKING_TOKENS=0` —
verified through the harness on Claude Code 2.1.234 (`-p`, 9B, 2026-08-18):
the server log line reads `thinking=false` under `0`, `thinking=true` under
`1024` and unset; 3 output tokens against 33 and 47 for a one-number answer.
`grep 'thinking=' ~/.mlx-serve/logs/mlx-serve-11234.log` is the check.
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
The correct change was to stop overriding it — `E1`, shipped 2026-08-18.

**ds4 is not a viable runtime for airgap's median user.** It compiles in exactly
three model shapes (DeepSeek V4 Flash, DeepSeek V4 PRO, GLM 5.2), all 100B+ MoE,
dispatching on two architecture strings, and its own `AGENT.md` states it is
"not a generic GGUF runner". Smallest target: 81 GB on disk, recommended for
96/128 GB machines; the SSD-streaming floor is a 64 GB MacBook. airgap's tested
machine is 36 GB and its entire disk budget is 45 GB. This cannot be fixed in
Bash — the shapes are compiled constants. See `AUDIT.md` §F for the honest
framing.

## Working here from an agent harness

Small things that cost a session each the first time. None of them is a repo
fact; all of them are about the tools an agent reaches this repo through.

- **The tool shell may be zsh, which does not word-split an unquoted `$VAR`.**
  Every script here is bash and relies on splitting (`LOAD_SHAPE_ARGS`,
  `EXTRA_ARGS`). A probe that "proves" a flag is missing may be proving only
  that zsh kept the string whole — run split-dependent probes under
  `bash -c '…'`. Same for `source <(…)`: write the harness to a file and run
  it with `bash file`.
- **The server writes to `stdout` and to `LOG_FILE`; only the log survives a
  backgrounded start.** `nohup ./bin/serve.sh > <scratch>/serve.out 2>&1 &`,
  about 20 s to `/health` for the 9B, `./bin/stop.sh` to end it. Everything
  the docs quote from the server (`Prefill chunk:`, `[hot-cache]`,
  `[preflight]`, `[registry]`) is in the log, scoped past the last
  `^Logging to ` banner.
- **`doctor.sh` sends three requests when the server is up** (an 8-token
  "hi" and two 69-token tool calls). They count in `/metrics.json` and in the
  `[hot-cache]` lines, and on a fresh server they are the "biggest hit" the
  `prefix cache` row quotes until a real long prompt has been sent. Expected,
  not a bug.
- **`truncated` on the tool-call rows is a WARN by design**: a build that is
  still reasoning at the cap is slow for agent work, not broken. Revisit only
  with a 27B measurement.
- **`mlx-serve` reports the 9B as `qwen3_5_moe` in its banner.** The "not
  MoE" fact above is about the 27B's `config.json`; the 9B is a different
  checkpoint and the two statements do not conflict.

## Before you claim something works

The repository's credibility is its only feature. Nothing is "done" on the
strength of a diff.

1. Run the script. Not a dry run — the real one, on this machine.
2. Paste the output into the commit or the PR. `bench.sh` output includes the
   machine, the model, the prompt and the token count for exactly this reason.
3. If a figure changed, say which of the three labels it carries now.
4. If a change touches a guard, prove the refusal still fires. A guard that
   silently stopped refusing looks identical to one that never had to.
5. If a change touches `serve.sh`, check its help text still describes it —
   and if it touches the argv it builds, capture `ps -o args= -p <pid>` of the
   running server before and after and compare the flag/value pairs. That is
   how `B1`'s `LOAD_SHAPE_ARGS` hoist was proven a no-op.
6. Anything verified only on the 9B says so. The 27B has been loaded on this
   machine once, for one turn, and measured never; several open items exist
   precisely because of that.
7. `bash tests/run.sh` and
   `shellcheck -S warning start.sh bin/*.sh harness/*.sh tests/*.sh` pass. CI
   runs exactly those. If you change what `doctor.sh`'s tool-call
   rows say, the fixture test's expected strings change in the same commit;
   if you capture a new fixture, say which server and model it came from in
   the test's header comment.
