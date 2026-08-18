# Roadmap

Where `airgap` is going, and in what order. This is a plan, not a promise;
items move when evidence says they should. Anything here that is not shipped is
labelled as such, in the same spirit as the MEASURED / NOT MEASURED convention
in the docs.

Work items reference ids from [`AUDIT.md`](AUDIT.md), which holds the evidence
for each — file, line, impact and the shape of the fix. Facts already
established against the installed binaries, and approaches already tried and
falsified, are in [`AGENT.md`](AGENT.md). **Read both before implementing
anything here.** They exist so that no session spends its budget re-discovering
what the last one already proved.

## The problem this exists to remove

People who already live in a coding harness — Claude Code, Codex, Pi and
Hermes today, Aider's or anyone else's tomorrow — want to point it at a model on their own
machine and get on with their work. What stands in the way is not the model. It
is everything around it: which runtime, which build, which download tool, which
memory setting will not stall the Mac, which environment variable the harness
reads, and which of the resulting failures are silent. Learning MLX or Ollama
just to answer those questions, for one harness, is the friction. `airgap`
exists to remove it fully.

Today it does that for **four harnesses on one model family on one runtime**:
Claude Code, the Codex CLI, Pi and Hermes Agent (each verified end to end on
2026-08-18), Qwen3.8
in MLX format, `mlx-serve` on Apple Silicon. The rest of this page is the path
from there to *any harness, any runtime, one abstraction*,
without giving up the three things that make the current version worth using:

1. **Guards, not warnings.** The scripts refuse rather than let a Mac swap or a
   model listen on the network.
2. **Measured, or labelled.** Every figure says whether it was measured here,
   reported by a publisher, or is arithmetic.
3. **One source of truth per fact.** Model sizes live in one file; the free
   memory a build needs is computed by the same function the guard enforces.

## What is already true, and what the abstraction can lean on

- `mlx-serve` speaks the Anthropic Messages API, the OpenAI chat API and the
  Ollama API on one port. Any harness that speaks one of those three can be
  wired without a translation proxy. That covers the vast majority of harnesses.
- **`mlx-serve` is three engines, not one.** `mlx-serve --version` reports
  `llama.cpp b10034 · gguf 3 · ds4 unknown` beside `mlx 0.32.0`, and
  `--engine {auto|ds4|llama}` routes `.gguf` inputs by their
  `general.architecture` metadata. The binary `bin/setup.sh` already installs
  can serve GGUF today. This changes Phase 3 substantially — see `AUDIT.md` F1.
- The catalog (`bin/catalog.sh`) is already data, not code: key, repository,
  sizes, provenance. Adding a build is one line.
- The memory model (`bin/detect-hardware.sh`) is already model-agnostic: it takes
  a weight size and a context window and produces the budget. Only the KV-cache
  constant is architecture-specific, and it is documented as such.
- A *harness adapter* maps "the server at this address, this model id, this
  context size" onto the settings one harness reads. That mapping is the whole
  per-harness surface, and since 2026-08-18 it is one file per harness in
  `harness/`, with `bin/run.sh` doing the parts every harness needs.

## Phase 0 — close the credibility gaps in 0.1.0 (before publishing)

Shipped code, unshipped evidence. Nothing here is a feature.

- [ ] Load and serve the 27B on the test machine; record `mtp_loaded` from
      `doctor.sh` and a `bench.sh` run. Every "NOT YET" in the docs about the
      27B becomes a number or stays labelled. **Half of this turned out to be
      done already, and the docs were the last to hear (corrected
      2026-08-18):** the 27B was loaded under `serve.sh`'s flags on
      2026-08-17 and served one `/v1/messages` turn, and the server's log
      settles the MTP question on its own — `[mtp] loading in-checkpoint head
      from the trunk shards`, `MTP head ready (depth=6)`, and `mtp=enabled
      (streaming, depth=6)` on the request itself. What that run produced was
      not one figure: the turn hit `max_tokens` after a single token, the next
      was cancelled at shutdown, and neither `doctor.sh` nor `bench.sh` was
      ever pointed at it. So what is left here is the measurement, not the
      load — and `C1` was the same lesson about the cache line. The server
      writes the evidence down; nothing in this repository was reading it.
- [ ] Run `start.sh` on a fresh user account (no Homebrew, no Claude Code) and
      correct anything the docs promise that the fresh run does not show.
- [ ] Run the small-Mac path for real (`HW_FORCE_RAM_GB=16` is arithmetic; a
      16 GB Mac is evidence).
- [x] Label the GPU wired ceiling, or replace it with the number MLX reports
      (`AUDIT.md` A7). It is the figure behind the hardest refusal in the stack
      and the only one carrying no label at all. **Done 2026-08-18** — labelled
      ARITHMETIC everywhere; the server prints Metal's real number at load
      (`[wired] … limit=28753 MB`, 28.1 GB MEASURED against 27.0 estimated on
      the test machine) and `doctor.sh` now quotes it beside the estimate and
      judges the build against both. The guards keep the estimate, which
      exists before any load.
- [ ] Settle the two stall-timeout unknowns in one experiment (`A5`). It also
      produces the first real 27B prefill timing, which closes the first item
      above from a different direction.

## Phase 0.5 — the audit backlog

From the 2026-08-17 audit against `antirez/ds4`. These are small, they are
independent of every abstraction below, and most of them make the repository
able to prove things it previously only asserted. Ordered as in `AUDIT.md`.
Complete as of 2026-08-18: every audit item that needs neither the 27B loaded
nor a measurement is shipped. What is left in `AUDIT.md` is named at the end
of its "Order of work".

- [x] `A1` — an instance lock in `serve.sh`. The repository enforced "no two
      model loads" in `bench.sh` and not in the script that loads the model.
      **Shipped 2026-08-17.**
- [x] `A5` — name the stall timeout. Server and client both expired at 300 s,
      under two different unnamed defaults. **Shipped 2026-08-17** — the knob,
      not the measurement: the two mechanism unknowns in `AUDIT.md` A5 remain,
      and so does the 27B prefill timing the experiment would produce.
- [x] `C1` — read the cache evidence the server already writes. The single
      measured cache figure is hand-typed into five documents while the same
      line is produced on every request into a log nothing opens.
      **Shipped 2026-08-17** — `doctor.sh` reads the current run's log and
      `/metrics.json`; `docs/05` §7d names the log path.
- [x] `B1` — `bench.sh` keeps the prefill rate and peak memory it currently
      parses away. Peak memory is the only empirical check that exists on the
      memory arithmetic; prefill is the number behind "the first response is
      slow", which the README still marks never measured.
      **Shipped 2026-08-17** — with `PROMPT_FILE=` and the load flags shared
      with `serve.sh`. First numbers, 9B only: prefill 374 tok/s at 16,377
      tokens, and a 2.6 GB working set the arithmetic does not model (`A3`).
- [x] `D3` — doctor probes a *streamed* tool call. Today every check can pass
      on a build that cannot emit one, which is the capability Claude Code is
      entirely built on.
      **Shipped 2026-08-17** — two rows, `tool call` and `streamed call`, one
      body with only `stream` toggled, every failure named. Its reader's
      failure branches are held by `tests/tool-call-verdict.sh` (2026-08-18).
- [x] `E1` — stop overriding the engine's own prefill sizing. This one is
      subtraction: `mlx-serve` already sizes the chunk from memory, and airgap's
      hardcoded 4096 is a second, worse-informed source of truth.
      **Shipped 2026-08-18** — the pin is gone; the server picks 512–1024 for
      the 9B on the test machine (from what is free at load) and the working
      set while reading 16k tokens fell 2.6 → 0.7–1.1 GB (MEASURED, 9B).
      `bench.sh`'s one-shot load does not get that sizing and now says so.
- [x] `B3`, `B4`, `B5` — the exactness claim now says what one `IDENTICAL`
      proves (this run, MEASURED; not the algorithm in a closed binary);
      `bench.sh` ends every run as one tab-separated row and `bench/` holds
      one file per Mac (`ROW_FILE=`), the reference machine's two rows first;
      `RELEASE.md` is the checked-in gate: what is re-run before a tag, on
      what, and what blocks it. **Shipped 2026-08-18.**
- [x] `E4` — thinking off, opt-in. The largest speed-up the audit measured
      (9B, one prompt: 3× fewer output tokens, 3× faster) behind a client-side
      switch, `MAX_THINKING_TOKENS=0`, with the quality cost stated as
      unmeasured. **Shipped 2026-08-18** — passed through by
      `claude-local.sh`, guarded, on the banner; the server log confirms the
      request changes (`thinking=false`) through Claude Code 2.1.234.
- [x] `D1`, `D2` — the download is verified for real. A shard cut short by a
      full disk kept its header, so every count agreed and `verify PASS` was
      printed over weights that load as garbage; and three of the four "is the
      model here?" checks read one shard, so an interrupted multi-shard pull
      reported "already here" and skipped its own resume.
      **Shipped 2026-08-18** — `verify-model.sh` measures each shard against
      its own header and against the index; `model_state` in `env.sh` is the
      one answer every script reads. `tests/verify-truncation.sh`,
      `tests/model-state.sh`.
- [x] `A4`, `A6`, `A2` — three refusals `serve.sh` did not have: a `CTX_SIZE`
      above the model's own maximum, an `mlx-serve` older than the build every
      flag was verified against, and a disk that cannot hold the prefix cache
      the server is about to be told to write. **Shipped 2026-08-18** — the
      guard list in its help went from eight to eleven, and `MIN_DISK_GB` is
      now computed by the same function as the new disk refusal.
      `tests/serve-guards.sh`.
- [x] `D4`, `C3` — the stop button stops what holds the weights (the model
      lock's holder and its children, not a `--port` pattern a `bench.sh` run
      never matches), names a foreign holder instead of calling it "nothing
      running", and shows the last lines of the log when a server is gone and
      did not say goodbye. **Shipped 2026-08-18** — `tests/stop-targets.sh`.

Deliberately **not** in this list, and recorded in `AGENT.md` so it is not
proposed again: a server-side reasoning budget. The flag exists, and it was
measured doing nothing. The real lever is client-side, is an on/off switch
rather than a budget, and is `E4` above.

## Phase 1 — any harness: `bin/run.sh <harness>`

One command per harness, all reading the same `env.sh`, none of them starting
the server (that stays `serve.sh`, one window, one job).

- [x] **The contract and the dispatcher.** A harness adapter is a small file,
      `harness/<name>.sh`, that declares which API dialect it speaks
      (`anthropic`, `openai` or `ollama`), which command starts it, how to make
      it answer one question and exit, and how to point it at the base URL,
      model id and context size. **Shipped 2026-08-18** — four names
      (`HARNESS_DIALECT`, `HARNESS_BIN`, `HARNESS_ONESHOT`, `harness_wire`),
      plus three optional ones: `harness_usage`, `HARNESS_ENDPOINT` for an
      adapter whose real endpoint disagrees with its dialect's usual one, and —
      since the Pi adapter needed it (2026-08-18) — `harness_prepare`, for a
      harness that can only be told about a provider through a file it reads.
      Checking the server, the banner, the timeout arithmetic and the probe
      live once in `bin/run.sh` and `bin/env.sh`, never in an adapter.
      `bin/run.sh [--probe] <name>` dispatches; `tests/harness-contract.sh` and
      `tests/run-dispatch.sh` hold both halves offline.
- [x] `bin/claude-local.sh` becomes `harness/claude-code.sh` with a
      compatibility shim, so nothing documented breaks. **Shipped 2026-08-18**
      — the shim is one `exec` line and the ~58 references to the old name in
      the docs stay true. Its banner is now eight lines, not six: line 1 names
      the adapter and its dialect, and the answer cap moved to an `output` line
      of its own.
- [x] **Claude Code, verified end to end.** **Shipped 2026-08-18** —
      `./bin/run.sh --probe claude-code` → `AIRGAP OK`, 55.4 s on a first turn
      and 4.8 s warm, 20,718 prompt tokens per turn at `LEAN_MCP=1` (MEASURED;
      Claude Code 2.1.234, mlx-serve 26.8.8, `Qwen3.8-9B-mlx-4Bit`, M3 Max
      36 GB).
- [x] **Codex CLI, verified end to end.** **Shipped 2026-08-18** —
      `./bin/run.sh --probe codex` → `AIRGAP OK`, 29.8 s cold and 3.4 s warm,
      9,336 prompt tokens per turn at `LEAN_MCP=1` against 10,271 at
      `LEAN_MCP=0`, i.e. 935 for its plugins (MEASURED; Codex CLI 0.147.0, same
      server, model and machine). One design assumption was falsified on
      contact: the plan said `wire_api = "chat"`, and 0.147.0 refuses to start
      on it ("no longer supported"), so the adapter speaks Responses
      (`/v1/responses`), which mlx-serve 26.8.8 serves and the probe verified.
- [x] `doctor.sh` gains one row per adapter present: does the harness binary
      exist, and would it be pointed at loopback. **Shipped 2026-08-18** — the
      section is now `harness wiring`, the rows are derived from `harness/*.sh`,
      and a missing binary is a `WARN` pointing at `docs/10-other-harnesses.md`.
- [x] The docs gain one page, `docs/10-other-harnesses.md`, and the README's
      "Pick your path" gains one line. **Shipped 2026-08-18.** The rest of that
      item was a test of whether the abstraction is right — *nothing else in the
      docs should need to change, because nothing else is harness-specific* —
      and it mostly held. Three other pages changed. Two of them in quoted
      output only: `docs/02` and `docs/06` paste the Claude Code banner and
      doctor's section, and both changed shape. The third changed in prose:
      `docs/07`'s settings reference had to stop calling `LEAN_MCP` a Claude
      Code setting — it is every harness's, and each states its own measured
      cost — and gained a Codex CLI section with `CODEX_BIN`. That is the
      honest result: no explanation of how anything *works* was rewritten
      anywhere, and `docs/05` took its one new sentence, but a page that lists
      settings has to say which harness each one belongs to once there is more
      than one harness. Captured output and settings tables are the parts of a
      document that a refactor touches; that is worth knowing before Phases 2
      and 3 make the same bet.
- [x] **Pi, verified end to end.** **Shipped 2026-08-18** —
      `./bin/run.sh --probe pi` → `AIRGAP OK`, 5.2 s on the first turn against
      a freshly started server and 1.5 s warm, 2,024 prompt tokens per turn
      (MEASURED; Pi 0.84.2, mlx-serve 26.8.8, `Qwen3.8-9B-mlx-4Bit`, M3 Max
      36 GB; identical tokens at `LEAN_MCP=0` — no Pi extensions installed
      here, so their cost is not measured). Pi forced the contract's first
      growth: it reads providers only from `~/.pi/agent/models.json`, so the
      adapter surface gained an optional `harness_prepare` — runs after every
      refusal, writes the one file, held by `tests/pi-models-json.sh` — rather
      than letting a file write hide inside `harness_wire`.
- [x] **Hermes Agent, verified end to end.** **Shipped 2026-08-18** —
      `./bin/run.sh --probe hermes` → `AIRGAP OK`, 36.7 s on its first turn
      (its own 15,060-token prefix) and 7.5 s warm, 15,060 prompt tokens per
      probe turn (MEASURED; Hermes Agent 0.20.4, same server, model and
      machine; identical at `LEAN_MCP=0` — no MCP servers configured for it
      here, so their cost is not measured). Wiring is environment-only
      (`CUSTOM_BASE_URL` + `--provider custom`), and one discovery was worth a
      guard: Hermes loads `~/.hermes/.env` *over* the process environment, so
      a `CUSTOM_BASE_URL` line there would silently win — the adapter refuses
      that case, and `tests/hermes-env-guard.sh` holds it. One honest limit:
      `hermes` checks for updates with a `git fetch` of its own checkout, and
      0.20.4 has no switch for it.
- [ ] Candidates, in the order asked (2026-08-18): Aider, OpenCode,
      mini-swe-agent, little-coder — each verified end to end before it is
      listed, the way the four shipped ones were. **Not shipped**: none of
      these adapters exists, none of those harnesses is installed on the
      machine this repository is developed on, and which config surface each
      one exposes has to be checked against its current release, not
      remembered.

## Phase 2 — the catalog as a first-class thing

- Move the catalog from a shell heredoc to a data file (`catalog.tsv` or JSON)
  with the same seven columns plus two: **format** (`mlx`, `gguf`) and **family**
  (`qwen3.8`, `gemma`, `deepseek`, …). Scripts read it; humans and PRs edit it.
- Add families that the runtime already serves and people already ask for,
  each entry with a verified repository, a verified size, and a verified weight
  index — never a guessed one.
- `models.sh list` grows a `--family` filter and keeps printing the free memory
  each build needs *on this Mac*, which is the number that matters.
- ~~A per-model KV-cache constant in the catalog~~ — **done 2026-08-18**
  (`AUDIT.md` F5): the per-token figure is read from each checkpoint's own
  `config.json`, the catalog carries a verified copy per entry, and `KV_QUANT`
  scales it. It was the precondition for the wider catalog: a new family's
  entry needs its figure computed from its `config.json`, and its guards are
  then right without anyone touching `detect-hardware.sh`.
- The `format` column is also what unblocks GGUF, which Phase 3 no longer has to
  wait for a second server to deliver. See F1.

## Phase 3 — any runtime

**Revised 2026-08-17.** This phase was written on the assumption that a second
runtime means a second server to install, start, stop and health-check. That is
not the situation. `mlx-serve` already embeds llama.cpp and antirez's ds4 engine
and routes `.gguf` inputs between them by file metadata. The blocking work is
therefore a *memory model* and a *catalog column*, not an integration.

`mlx-serve` is still the right choice today because it keeps the OrcaRouter MTP
head and speaks the Anthropic dialect natively. Neither is universal: most
catalog builds ship no MTP head.

- A runtime adapter is the mirror of a harness adapter: how to install it, how
  to start it on a model directory bound to loopback with a context size and a
  memory ceiling, how to stop it, and **how to know it is ready**.
  `serve.sh` and `stop.sh` become thin over it.
- **Correction to the contract above.** It previously said "what `/health` and
  `/v1/models` look like", and `env.sh`'s `server_up()` and `doctor.sh` both
  call `/health` directly. ds4-server implements `/v1/models` and
  `/v1/messages` and has **no health route at all**. So readiness must be a
  *hook the adapter supplies*, not a fixed path, and `doctor.sh` needs one row
  per adapter rather than one hardcoded curl. Cheap to fix now, expensive once
  two adapters exist. (`AUDIT.md` F4.)
- **GGUF is nearer than this page assumed.** `--engine {auto|ds4|llama}` is
  already accepted by the installed binary. What is genuinely missing is a GGUF
  memory model and the catalog `format` column already scheduled in Phase 2.
  **Not shipped**: Apple Silicon stays the only supported platform until that
  memory model exists, and a second `llama-server` process is no longer the
  route to it. (F1.)
- **ds4 as a runtime: an optional 96 GB+ path, not a tier.** Recorded so it is
  not re-investigated. ds4 compiles in exactly three model shapes — DeepSeek V4
  Flash, DeepSeek V4 PRO, GLM 5.2 — all 100B+ MoE, and is explicitly not a
  generic GGUF runner. Its smallest target is 81 GB on disk against a 36 GB
  tested machine and a 45 GB disk budget. No airgap user below 64 GB can run any
  ds4 model, and no amount of Bash creates one: the shapes are compiled
  constants. Listing it as an ordinary option would be the first catalog entry
  most readers cannot use. (F2.)
- **`--ssd-streaming` is the one capability that reaches below the current
  floor** — it runs a model larger than RAM. It also inverts the guard:
  `hw_rebudget` assumes resident weights, streaming assumes they exceed RAM with
  a bounded expert cache instead. That is a second budget function for the same
  guard, which principle (3) forbids unless the two are unified deliberately.
  Naming this cost is a precondition for offering the path at all. (F3.)
- The `--no-mtp`/`--no-pld` refusals become runtime-specific facts, not global
  ones.

## Phase 4 — one entry point, one abstraction

When the three adapters exist (harness, catalog, runtime), the surface collapses
to one command with five verbs, and `start.sh` becomes its first-run mode:

```
airgap doctor                    # what this machine can run, and what is wrong
airgap models [list|pull|use]    # the catalog, fitted to this machine
airgap serve | stop              # the runtime, on loopback, under the guards
airgap run <harness>             # your harness, pointed at your machine
airgap bench                     # measure this machine, this model, honestly
```

Everything above it — `.env` precedence, the guards, the labelling — is
unchanged. The bar for that release is the same as for this one: every command
run for real, every figure measured or labelled, and a first-time reader able
to get from a clean Mac to a working harness without learning MLX.

## Deliberate non-goals

- Voice, phone, browser or desktop-launcher front ends. Other projects do those
  well; this one wires harnesses people already use.
- Serving other people. Loopback only, by refusal, for as long as the catalog
  carries abliterated builds.
- Speed claims not measured here. `bench.sh` is the only source of a
  tokens-per-second figure in this repository, and it prints the machine, the
  model, the prompt and the token count next to every one.

## How to help

The most valuable contributions, in order: a `bench.sh` run on a Mac that is not
an M3 Max 36 GB (`ROW_FILE=bench/<chip>-<ram>gb.tsv ./bin/bench.sh`, commit the
file, put the full output in the PR — `bench/README.md`); a harness adapter for a
harness you actually use, with its `AIRGAP OK` transcript; a catalog line for a
build you have actually loaded, with `verify-model.sh` output. Claims without the
transcript are not merged — not out of distrust, but because the whole point of
this repository is that its numbers are real.

Prose in an issue was the wrong container for the first of those, and it is the
contribution the project needs most — so since 2026-08-18 `bench.sh` ends every
run as one tab-separated row and `bench/` holds one file per Mac, the way ds4
accumulates `m4_max.csv` and `m5_max.csv`: contributed runs can be diffed,
plotted and used as a baseline instead of read once and lost (`AUDIT.md` B4).
The release gate is `RELEASE.md` (`B5`): what is re-run before a tag, on what,
and what blocks it — so the MEASURED convention is enforced by a checklist, not
by the maintainer's memory.
