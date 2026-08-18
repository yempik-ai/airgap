# Changelog

All notable changes to this project. Dates are the day the change landed.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Figures are labelled MEASURED, PUBLISHER-REPORTED or NOT MEASURED throughout, and
that convention is treated as part of the contract — see
[`AI-CITATION.md`](AI-CITATION.md).

## [0.1.0] — 2026-08-17

First public release.

### Added

- `start.sh` — one entry point. Installs the tools, downloads a model that fits
  the Mac it runs on, verifies the weights, runs the health checks, then names
  the two commands that run it. Idempotent, and it stops with a plain fix on any
  failure.
- `bin/catalog.sh` — the single list of models the scripts know about: nine
  Qwen3.8 MLX builds from 4.7 GB to 29.1 GB, each with its repository, download
  size (the real `.safetensors` total from the Hugging Face API), loaded
  (text-only) size where known, and whether it is abliterated. Every other
  script reads sizes and names from here; none carries its own copy. Includes
  the OrcaRouter 27B at 4/5/6/8-bit (the only builds that ship the MTP head,
  checked against each weight index), a 2-bit and an AEON abliterated 27B, the
  stock `mlx-community` 27B at 4-bit and 8-bit, and a 9B (a community
  distillation of Qwen3.8 into the Qwen3.5-9B architecture — Qwen published no
  9B) which is the default under 32 GB.
- `bin/models.sh` — `list`, `pull`, `use` and `which` over that catalog. `list`
  prints, for each build, the free memory `serve.sh` will insist on **on this
  Mac**, computed by the same arithmetic the server guard uses rather than typed
  into a table, and marks each build `ok`, `TIGHT` or `NO` (would not fit under
  the GPU wired ceiling).
- `bin/detect-hardware.sh` — reads the host Mac and derives `CTX_SIZE`,
  `MIN_FREE_GB`, `MAX_RESIDENT_MEM` and `PREFIX_CACHE_MEM` for the model
  actually selected. Covers 8 GB to 128 GB; where a 27B cannot fit it names the
  catalog builds that do, and the scripts default to one of them instead of
  refusing.
- `bin/doctor.sh` — 22 checks with a fix per failure (29 with the server up),
  including whether git-lfs is *enabled* rather than merely installed, whether
  the weights are real files or 135-byte pointers, whether the selected model
  fits under the GPU wired ceiling, whether `CTX_SIZE` is within the model's own
  maximum, whether a real `ANTHROPIC_API_KEY` is set in the shell, and whether
  the listening socket is reachable from off the machine.
- **Doctor reads the cache evidence the server already writes.** Two rows,
  `prefix cache` and `/metrics.json`: the first quotes the biggest
  `[hot-cache] reused N/M` line of the *current* run from the server's own log
  (scoped past the last `Logging to` banner, because the log has no timestamps
  and spans restarts), the second reads `hits/queries` and reused/total prompt
  tokens from the counters. A 503 is "metrics off", not a failure. Every
  server probe now goes through one `srv_curl` that adds `x-api-key` when
  `API_KEY` is set. Closes `AUDIT.md` C1 and C2.
- **Doctor proves the model can call a tool — plainly and streamed.** Two
  rows, `tool call` and `streamed call`: one tool, a question that needs it,
  thinking on (as Claude Code sends it), the same body with only `stream`
  toggled, so a difference between the rows is streaming and nothing else. The
  streamed answer is reassembled from its `input_json_delta` pieces the way a
  client must. Every failure has a name — answered in words, a raw call passed
  through as text, torn JSON on the stream, a stream that never ended, still
  reasoning at the cap — and points at `docs/06` §24. `mlx-serve 26.8.8`
  ignores `tool_choice`, so it is not sent (recorded in `AGENT.md`).
  MEASURED on the 9B: 69 output tokens per row, both PASS, whole doctor 4.3 s.
  `bin/claude-local.sh` now sets `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1`
  so Claude Code cannot paper over a broken stream by retrying non-streamed.
  Closes `AUDIT.md` D3.
- **The prefill chunk is the server's to size.** `PREFILL_CHUNK` now defaults
  to empty and `--prefill-chunk` is passed only when it is set, by `serve.sh`
  and `bench.sh` alike (one list, `LOAD_SHAPE_ARGS`). The server sizes the
  chunk when it starts — from the memory free at that moment, the context size
  and the resident cap — and prints what it chose; airgap's pinned 4096 was a
  second, worse-informed source of truth. MEASURED on the test machine with
  the 9B: the server picks 512 or 1024 by what is free, and the working set
  while reading a 16,408-token prompt is 0.7–1.1 GB there against 2.6 GB at 4096, with
  no read-rate cost the samples could show (single samples; the rate did not
  track the chunk). Found by running it: one-shot mode does not memory-size,
  so an unpinned `bench.sh` reads at the 8192 ceiling (peak 9.52 GB, +4.57 GB)
  and now prints a `chunk:` line saying so, quoting the figure the server chose
  in its last run and the pin that reproduces it. Closes `AUDIT.md` E1.
- **`bench.sh` gives the model lock back after a full run.** Its own
  `trap 'rm -rf "$TMP"' EXIT` had replaced the release trap the lock installs,
  so every completed bench left a stale lock behind (reclaimed by the next
  start, reported by `doctor.sh` in between). Found while running E1; the
  refuse paths were already fine.
- **`tests/`** — offline checks that need no server and no weights:
  `tool-call-verdict.sh` feeds twelve captured and derived answer shapes
  (live `tool_use` plain and streamed, `declined`, `truncated`, an API error;
  derived `unparsed`, `wrong_tool`, `bad_input`, torn `partial_json`, no
  `message_stop`, garbled, empty) through doctor's real reader and row
  renderer and checks the status and detail each renders — the failure
  branches a green doctor run never exercises; `load-shape.sh` holds the
  `LOAD_SHAPE_ARGS` contract (the prefill-chunk flag only when pinned, and
  named nowhere but `env.sh`). `tests/run.sh` runs both.
- **CI** (`.github/workflows/ci.yml`): `bash -n` and `shellcheck -S warning`
  over every script on Ubuntu, `tests/run.sh` on a macOS runner, on every
  push and pull request (the repository is public, where hosted runners are
  free); each job capped at ten minutes, superseded runs cancelled. Every
  script is clean at that level;
  the four cross-file "unused" notes shellcheck cannot see through are
  annotated in place. Green on its first real run, MEASURED at 17 s (lint)
  and 11 s (tests); `actions/checkout` is pinned at `@v5`, the first major
  that declares Node 24, since `@v4` declares the Node 20 that GitHub-hosted
  runners have deprecated.
- `bin/serve.sh` — refuses, rather than warns, on a non-Apple-Silicon Mac, on a
  build that does not fit under the GPU wired ceiling, on a non-loopback host, on
  `--host`, `--lan-share`, `--lan-discover`, `--skip-mem-preflight`, `--no-mtp`
  or `--no-pld` in `EXTRA_ARGS`, and below the free-memory floor. Hands memory
  back after `IDLE_EVICT_SECS`.
- `bin/download-model.sh` — asks Hugging Face how big the build is and refuses,
  before downloading, one that cannot fit under this Mac's GPU ceiling. Resumable,
  pointer-verified, de-duplicated (MEASURED: 20.1 GB reclaimed on the test
  machine).
- `bin/claude-local.sh` — points every model slot the Claude Code 2.1.233 binary
  reads at the local server (main, Opus/Sonnet/Haiku/Fable defaults, small-fast,
  subagent, auto-mode and background-classifier), blanks `ANTHROPIC_API_KEY` so a
  key already in the shell cannot take priority, declares the real context
  window, and switches off telemetry, error reporting, the auto-updater,
  marketplace auto-install and background tasks.
- **`bench.sh` ends every run as one row, and `bench/` collects them.** The
  last block is the run tab-separated in a fixed column order (machine,
  runtime, model, load shape, prompt, every figure, `identical`);
  `ROW_FILE=bench/<chip>-<ram>gb.tsv` appends it, header first when new.
  `bench/README.md` fixes the format; `bench/m3-max-36gb.tsv` holds the
  reference machine's first two rows (9B; MEASURED 2026-08-18: 27.4 tok/s
  decode at 41 tokens, 11.9 at 16,458 with prefill 269 tok/s and 1.25× from
  prompt lookup, peak 9.55 GB unpinned). Closes `AUDIT.md` B4.
- `RELEASE.md` — the release gate: eight runs with pass and block conditions,
  the one-line record each manual run leaves in the release notes, and what
  0.1.0 still owes. Closes `AUDIT.md` B5.
- **`outputs IDENTICAL` now says what it proves.** Byte identity observed on
  this run — the algorithm's promise in exact arithmetic, checked every run
  because a batched floating-point implementation in a closed binary can drift;
  it has held on every 9B run so far (MEASURED). `bench.sh`, `docs/07`,
  `docs/08` and the glossary. Closes `AUDIT.md` B3.
- **The GPU wired ceiling is labelled, and doctor quotes the measured one.**
  The 2/3-of-RAM (to 32 GB) / 3/4-above rule behind the stack's hardest
  refusal was stated as fact; it is now labelled ARITHMETIC in
  `detect-hardware.sh`, both refusals, doctor's rows, `docs/04` §8, `docs/01`
  and the glossary. `mlx-serve` prints Metal's real number at every load
  (`[wired] mode=max limit=N MB`); `doctor.sh`'s `gpu ceiling` row reads it
  from the current run's log, shows it beside the estimate, and FAILs a build
  that fits the estimate but not the measurement. MEASURED on the test
  machine: 28753 MB = 28.1 GB against 27.0 estimated (n=1; the rule is not
  changed). The guards keep the estimate, which exists before any load.
  `tests/wired-log.sh` holds the reader. Closes `AUDIT.md` A7.
- **Thinking can be turned off, opt-in** (`MAX_THINKING_TOKENS=0`, Claude
  Code's own name; `claude-local.sh` passes it through, refuses anything that
  is not a whole number, and reports it on a new `thinking` banner line).
  Unset leaves every build as it ships — thinking on, the 27B at `xhigh`.
  MEASURED on the 9B, one prompt: off is 376 vs 1156 output tokens, 7.2 s vs
  20.9 s; through Claude Code 2.1.234 the server log shows `thinking=false`.
  A positive value caps only the stored thinking text, not the time (128, 1024
  and unset all ~21 s). The quality cost is NOT MEASURED, on any build, which
  is why it is opt-in. The server-side `--reasoning-budget` flag was measured
  inert and is not exposed. `tests/thinking-knob.sh` holds the guard. Closes
  `AUDIT.md` E4.
- `bin/bench.sh` — loads the selected model twice, speed features on and off,
  compares the two answers byte for byte, and reports the three figures mlx-serve
  prints for each: prefill rate, decode rate and peak memory. It loads under the
  same context/KV/prefill-chunk/vision flags `serve.sh` uses (one list,
  `LOAD_SHAPE_ARGS` in `env.sh`), and puts the peak next to the memory guard's
  own arithmetic. `PROMPT_FILE=` makes a whole file the prompt, which is the
  only way to a prefill figure worth quoting. MEASURED on the test machine with
  the 9B: identical output; 36.7 tokens/s decode after a 41-token prompt, 15.6
  after 16,377; prefill 374 tokens/s at 16,377 tokens; peak 7.52 GB there, of
  which 2.6 GB is working set above weights + KV. Closes `AUDIT.md` B1.
- **A model lock** (`LOCK_DIR`, default `~/.airgap/model.lock`). Only one process
  on this Mac may hold the weights. Every other concurrency check in the repo is
  scoped to a port, and a port cannot see what actually hurts: `mlx-serve` claims
  its socket *before* it loads, so a second server on a different port passed
  every check, and `bench.sh` passes no port at all. `serve.sh` and `bench.sh`
  take it, `doctor.sh` reports it, `stop.sh` clears one left by a crash — and
  never one whose holder is alive. A lock whose process is gone is reclaimed
  rather than obeyed, so a SIGKILL cannot leave a Mac unable to start a server.
  Closes `AUDIT.md` A1.
- **A named stall timeout** (`SERVE_TIMEOUT`, default 300). The server gives up
  on a request producing nothing after 300 seconds; Claude Code's own idle limit
  is also 300, so the two expired together under names nobody had set and the
  result was indistinguishable from a dead server. `serve.sh` now passes it and
  prints it; `bin/claude-local.sh` reads the same setting and gives the client a
  minute more, so the server aborts first and the side that can name the reason
  is the side that reports it. Claude Code 2.1.233 floors its own value at 300
  seconds, which is documented rather than worked around. Closes `AUDIT.md` A5.
- **One answer to "is the model here?"** (`model_state` in `bin/env.sh`:
  `absent`, `partial` or `complete`). Three of the four checks that asked it
  looked at the first shard only, so a five-shard download interrupted after
  shard 1 reported "already here", was accepted by `models.sh use`, and had its
  resume skipped — the user met the problem two steps later in
  `verify-model.sh`. It is now asked over every shard, and over the shards
  `model.safetensors.index.json` names that never arrived at all. `start.sh`
  offers the resume, `models.sh` marks `~` and refuses `use`, `serve.sh` names
  the shard, `doctor.sh` reports it, `download-model.sh` checks the same two
  things. `tests/model-state.sh`. Closes `AUDIT.md` D2.
- **`verify-model.sh` now measures each shard against its own header.**
  `8 + header + the last tensor's end offset` is where the file has to end; one
  shorter than that is truncated, by exactly the bytes it names. The header is
  written first, so it survives a full disk or a killed transfer intact — every
  count in the report agreed and `verify PASS` was printed over weights that
  load as garbage. It also fails on a shard the index names and that is not
  there. `tests/verify-truncation.sh`, over folders built at test time by
  `tests/fixtures/make-model.py`. Closes `AUDIT.md` D1.
- **`CTX_SIZE` is refused above the model's own maximum** (`serve.sh`, from
  `max_position_embeddings` in the checkpoint's `config.json` — one reader,
  `model_max_ctx`, shared with doctor's `context` row). It was validated only
  in the advisory script, so `CTX_SIZE=262144` on a model with a lower ceiling
  inflated `MIN_FREE_GB`, could trip the GPU-ceiling guard for a reason that
  was not the real one, and otherwise failed one request at a time. The guard
  runs before that ceiling check, so the reason given is the true one. Closes
  `AUDIT.md` A4.
- **A minimum `mlx-serve` version** (`MLX_SERVE_MIN=26.8.8`, `bin/env.sh`).
  Every flag `serve.sh` passes was verified against that build; an older one
  answered with an argparse error a minute into a load, after every other guard
  had passed. `serve.sh` refuses, `doctor.sh` FAILs the row, `setup.sh` says it
  at install time. A version that cannot be parsed is a WARN, never "too old".
  Closes `AUDIT.md` A6.
- **A disk refusal for the prefix cache** (`serve.sh`), and `MIN_DISK_GB` is now
  computed rather than typed. Disk was the one resource with no refusal
  covering it: 6 GB free passed every check and then the server was told it
  could write a 10 GB cache. Both numbers come from one function,
  `hw_disk_need_gb` in `bin/detect-hardware.sh` — the download's peak (two
  copies of the download until `git lfs dedup` reclaims one, or the weights
  plus the cache tier, whichever is larger) and the server's need (the cache
  tier), each plus 5 GB of spare for macOS. That leaves `MIN_DISK_GB` at 45 for
  the 5-bit 27B, where it was, and lowers it to 20 for the 9B, where 45 was
  simply wrong. The server's check is measured on the volume holding
  `~/.mlx-serve`, which is where the cache goes, and names the fix that is
  usually right: a smaller `PREFIX_CACHE_DISK`, or `0` to keep only the memory
  tier. Closes `AUDIT.md` A2.
- **`stop.sh` stops what holds the weights, not what matches a port.** It
  matched `mlx-serve --port <PORT>`, so a `bench.sh` run — which passes no
  `--port` at all — could not be stopped by the documented stop button while
  holding about 20 GB, and a foreign program on the port was reported as
  "nothing running on port 11234". It now takes the union of the model lock's
  holder and its children, the `lsof` listeners on the port that are ours, and
  the old pattern; a holder that is not ours is named and left alone.
  `tests/stop-targets.sh`. Closes `AUDIT.md` D4.
- **The server's log is described, and shown when it matters.** `mlx-serve`
  rotates it at 32 MB — stated in `docs/07` §11, `config.env.example` and
  `docs/06` — and when there was nothing to stop and the last run did not shut
  down cleanly, `stop.sh` prints its last 8 lines. `doctor.sh` prints them
  under a failed `/v1/messages` and under `server not running`. Closes
  `AUDIT.md` C3.
- **The KV-cache figure is per model and per `KV_QUANT`.** Every guard —
  `MIN_FREE_GB`, the GPU-ceiling refusal, `models.sh list`'s `ok`/`TIGHT`/`NO`,
  `download-model.sh`'s "not worth downloading" — charged every model the 27B's
  64 KiB per token at 4 bits, whatever the checkpoint and whatever `KV_QUANT`
  said: the 9B was over-charged twice over, a dense model would have been
  under-charged by a factor of several while reading as authoritative, and
  `KV_QUANT=off` (which `docs/06` and `docs/07` tell people to try, promising a
  refusal if the Mac cannot spare it) was invisible to the guard, so a 131072-
  token window at 16 bits passed the ceiling check with a phantom 2 GB where
  the true term is 8. Now `model_kv_kib` (`bin/env.sh`) reads growing layers ×
  2 × kv-heads × head_dim × 2 bytes from the selected checkpoint's own
  `config.json` (every layer counts unless it is `linear_attention`; no
  `layer_types` means dense), `bin/catalog.sh` carries a `kv KiB/token` column
  VERIFIED against all nine repositories' `config.json` on huggingface.co (64
  for every 27B, 32 for the 9B) for builds not on disk, and `hw_rebudget`
  scales by `KV_QUANT`'s bit-width (`off` 16, `8`, `4`/`turbo4`, `turbo2`; an
  unknown name reads as 16). Refusals, doctor's `gpu ceiling` row and
  `verify-model.sh`'s new `kv` line quote the figure and where it came from
  (`config.json`, `catalog`, or `assumed from <build>`). Not counted, and said
  so: the per-group scale a quantized cache carries — mlx-serve does not
  publish its group size. The reference configuration is unchanged
  (22 / 21GB / 1536MB on 36 GB). `tests/kv-figure.sh`. Closes `AUDIT.md` F5.
- **The prefix cache's memory tier is stated in tokens, and its other cap is
  named.** `PREFIX_CACHE_MEM` is set in bytes and thought about in tokens;
  `hw_kv_tokens` (`bin/detect-hardware.sh`) joins the two at the selected
  model's per-token KV cost — 1536 MB is at most 98,304 prompt tokens for the
  27B at `turbo4`, about four and a half of Claude Code's 20,909-token block,
  twice that for the 9B. `serve.sh` prints it on a new `prefix` banner line,
  doctor's `prefix cache` row carries it, `docs/07` §5 works it, always as an
  upper bound: SSM checkpoints share the budget, and the server's own
  32-entry cap (printed at load as `capacity=32`) may bind first — a
  possibility now stated rather than absent. `hw_size_gb` keeps four decimal
  places so 1000 MB no longer reads as 1 GB. Closes the tokens half of
  `AUDIT.md` E2; whether the entry cap binds is a measurement and stays open.
- **The server flags that act on this workload are named, with their
  defaults, and labelled unmeasured.** `docs/07` §12 lists `--mtp-depth`,
  `--mtp-history-window` (which applies to every Claude Code turn — all are
  above its 16,384-token threshold), `--pld-draft-len`, `--pld-key-len`,
  `--ssm-checkpoint-stride`, `--ssm-checkpoint-max` and
  `--prefix-cache-entries`, each with the default `mlx-serve --help` states at
  26.8.8, and says NOT MEASURED where it is. They reach the server through
  `EXTRA_ARGS` and were deliberately not made settings: no effect is measured,
  and an unmeasured speed knob does not earn a name (the rule that made
  thinking-off opt-in). `config.env.example` and `docs/07` §14 point at the
  table. Closes the label half of `AUDIT.md` E3.
- `bin/verify-model.sh`, `bin/stop.sh`.
- Nine documents, `docs/01` to `docs/09`, written for readers who have never
  opened a terminal, plus a glossary of every technical term used.
- `ROADMAP.md` — where this goes next: any harness, any runtime, one abstraction.
- `AGENT.md` — the contributor contract, plus the environment facts already
  established against the installed binaries and the approaches already tried
  and falsified. It exists so no contributor, human or agent, spends their time
  re-deriving what is already settled.
- `AUDIT.md` — the open gap register from the 2026-08-17 audit against
  [`antirez/ds4`](https://github.com/antirez/ds4): 31 items, each with its
  evidence, its user impact and the shape of the fix. Referenced by id from
  `ROADMAP.md`.
- `llms.txt`, `AI-CITATION.md` and `CITATION.cff` so AI assistants and crawlers
  read stated facts with provenance rather than inferring them.

### Known limitations

- **The 27B has never been served in this repository.** The end-to-end path
  (`serve → doctor → claude-local -p`) was validated with the catalog's 9B and
  with Qwen3.5-0.8B, both the same `qwen3_5` architecture family. See "What has
  and has not been run here" in the README.
- **`mtp_loaded: true` is unconfirmed on the 27B checkpoint.** `mlx-serve`
  documents its MTP head as auto-loading from `mtp/weights.safetensors`; this
  checkpoint has no such file, and instead carries 29 MTP tensors embedded in the
  main shards as `language_model.mtp.*`. The publisher reports it working under
  mlx-serve 26.8.7. Not reproduced here. `bin/doctor.sh` reports it.
- **No tokens-per-second figure for the 27B has been measured**, on any machine.
  The one measured speed is the 9B's. `bin/bench.sh` produces yours.
- Only the 36 GB row of the hardware table is measured. The other rows are
  arithmetic from that one.
- Of the nine catalog builds, only `27b-5bit` (files verified) and `9b-4bit`
  (served end to end) have been run here. The rest are listed because they exist
  and their sizes and weight indexes were read from Hugging Face.
