# Roadmap

Where `airgap` is going, and in what order. This is a plan, not a promise;
items move when evidence says they should. Anything here that is not shipped is
labelled as such, in the same spirit as the MEASURED / NOT MEASURED convention
in the docs.

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
  conservative-for-the-9B.

## Phase 3 — any runtime

`mlx-serve` is the right choice today because it keeps the OrcaRouter MTP head
and speaks the Anthropic dialect natively. Neither is universal: most catalog
builds ship no MTP head, and llama.cpp's server now speaks `/v1/messages` too.

- A runtime adapter is the mirror of a harness adapter: how to install it, how
  to start it on a model directory bound to loopback with a context size and a
  memory ceiling, how to stop it, and what `/health` and `/v1/models` look like.
  `serve.sh` and `stop.sh` become thin over it.
- First second runtime: llama.cpp `llama-server` for GGUF builds. It brings
  Intel Macs and Linux into reach for the *guard and wiring* layer, with the
  memory model rewritten for discrete GPUs where that applies — a large piece of
  work that must not be hand-waved. **Not shipped, not scheduled**: Apple
  Silicon stays the only supported platform until that memory model exists.
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
