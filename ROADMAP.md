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

People who already live in a coding harness — Claude Code today, Pi, Hermes,
DeepSeek's or anyone else's tomorrow — want to point it at a model on their own
machine and get on with their work. What stands in the way is not the model. It
is everything around it: which runtime, which build, which download tool, which
memory setting will not stall the Mac, which environment variable the harness
reads, and which of the resulting failures are silent. Learning MLX or Ollama
just to answer those questions, for one harness, is the friction. `airgap`
exists to remove it fully.

Today it does that for **one harness on one model family on one runtime**:
Claude Code, Qwen3.8 in MLX format, `mlx-serve` on Apple Silicon. The rest of
this page is the path from there to *any harness, any runtime, one abstraction*,
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
- `bin/claude-local.sh` is already a *harness adapter*: it maps "the server at
  this address, this model id, this context size" onto the settings one harness
  reads. That mapping is the whole per-harness surface.

## Phase 0 — close the credibility gaps in 0.1.0 (before publishing)

Shipped code, unshipped evidence. Nothing here is a feature.

- [ ] Load and serve the 27B on the test machine; record `mtp_loaded` from
      `doctor.sh` and a `bench.sh` run. Every "NOT YET" in the docs about the
      27B becomes a number or stays labelled.
- [ ] Run `start.sh` on a fresh user account (no Homebrew, no Claude Code) and
      correct anything the docs promise that the fresh run does not show.
- [ ] Run the small-Mac path for real (`HW_FORCE_RAM_GB=16` is arithmetic; a
      16 GB Mac is evidence).
- [ ] Label the GPU wired ceiling, or replace it with the number MLX reports
      (`AUDIT.md` A7). It is the figure behind the hardest refusal in the stack
      and the only one carrying no label at all.
- [ ] Settle the two stall-timeout unknowns in one experiment (`A5`). It also
      produces the first real 27B prefill timing, which closes the first item
      above from a different direction.

## Phase 0.5 — the audit backlog

From the 2026-08-17 audit against `antirez/ds4`. These are small, they are
independent of every abstraction below, and four of the six make the repository
able to prove things it currently only asserts. Ordered as in `AUDIT.md`.

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
- [ ] `D3` — doctor probes a *streamed* tool call. Today every check can pass
      on a build that cannot emit one, which is the capability Claude Code is
      entirely built on.
- [ ] `E1` — stop overriding the engine's own prefill sizing. This one is
      subtraction: `mlx-serve` already sizes the chunk from memory, and airgap's
      hardcoded 4096 is a second, worse-informed source of truth.

Deliberately **not** in this list, and recorded in `AGENT.md` so it is not
proposed again: a server-side reasoning budget. The flag exists, and it was
measured doing nothing. The real lever is client-side, is an on/off switch
rather than a budget, and is `AUDIT.md` E4.

## Phase 1 — any harness: `bin/run.sh <harness>`

One command per harness, all reading the same `env.sh`, none of them starting
the server (that stays `serve.sh`, one window, one job).

- A harness adapter is a small file, `harness/<name>.sh`, that declares three
  things and nothing else: which API dialect it speaks (`anthropic`, `openai` or
  `ollama`), how to hand it the base URL, model id and context size (environment
  variables, a flag, or a config file it owns), and how to prove the wiring
  worked (`-p 'reply AIRGAP OK'` or its equivalent).
- `bin/claude-local.sh` becomes `harness/claude-code.sh` with a compatibility
  shim, so nothing documented breaks.
- Candidates, in the order people asked: Pi, Hermes Agent, a DeepSeek harness,
  Codex CLI, OpenCode, Aider — each verified end to end before it is listed, the
  way Claude Code was. **Not shipped**: none of these adapters exists yet, and
  which config surface each harness exposes has to be checked against its
  current release, not remembered.
- `doctor.sh` gains one row per adapter present: does the harness binary exist,
  and would it be pointed at loopback.
- The docs gain one page, `docs/10-other-harnesses.md`, and the README's "Pick
  your path" gains one line. Nothing else in the docs should need to change,
  because nothing else is harness-specific — that is the test of whether the
  abstraction is right.

## Phase 2 — the catalog as a first-class thing

- Move the catalog from a shell heredoc to a data file (`catalog.tsv` or JSON)
  with the same six columns plus two: **format** (`mlx`, `gguf`) and **family**
  (`qwen3.8`, `gemma`, `deepseek`, …). Scripts read it; humans and PRs edit it.
- Add families that the runtime already serves and people already ask for,
  each entry with a verified repository, a verified size, and a verified weight
  index — never a guessed one.
- `models.sh list` grows a `--family` filter and keeps printing the free memory
  each build needs *on this Mac*, which is the number that matters.
- A per-model KV-cache constant in the catalog, replacing the single Qwen3.8
  figure that is currently documented as exact-for-this-architecture and
  conservative-for-the-9B. (`AUDIT.md` F5 — this is the precondition for the
  wider catalog, not a nicety: every guard under-estimates KV cost the moment a
  non-hybrid family is added, while still reading as authoritative.)
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
an M3 Max 36 GB (paste the whole output into an issue); a harness adapter for a
harness you actually use, with its `AIRGAP OK` transcript; a catalog line for a
build you have actually loaded, with `verify-model.sh` output. Claims without the
transcript are not merged — not out of distrust, but because the whole point of
this repository is that its numbers are real.

Prose in an issue is the wrong container for the first of those, and it is the
contribution the project needs most. Once `B1` lands, `bench.sh` should emit one
CSV per machine, committed to the repository the way ds4 accumulates
`m4_max.csv` and `m5_max.csv` — so contributed runs can be diffed, plotted and
used as a regression baseline instead of read once and lost. (`AUDIT.md` B4.)

There is also no checked-in release gate: nothing states what must be re-run
before a tag, on what hardware, or what counts as a blocker. The MEASURED
convention is currently enforced by the maintainer's memory, which is the exact
failure mode the convention exists to prevent. (B5.)
