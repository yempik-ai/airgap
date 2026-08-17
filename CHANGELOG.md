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
- `bin/doctor.sh` — 21 checks with a fix per failure (24 with the server up),
  including whether git-lfs is *enabled* rather than merely installed, whether
  the weights are real files or 135-byte pointers, whether the selected model
  fits under the GPU wired ceiling, whether `CTX_SIZE` is within the model's own
  maximum, whether a real `ANTHROPIC_API_KEY` is set in the shell, and whether
  the listening socket is reachable from off the machine.
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
- `bin/bench.sh` — loads the selected model twice, speed features on and off,
  compares the two answers byte for byte, and reports mlx-serve's own decode
  tokens-per-second for each. MEASURED on the test machine with the 9B: identical
  output, 57 tokens/s.
- `bin/verify-model.sh`, `bin/stop.sh`.
- Nine documents, `docs/01` to `docs/09`, written for readers who have never
  opened a terminal, plus a glossary of every technical term used.
- `ROADMAP.md` — where this goes next: any harness, any runtime, one abstraction.
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
