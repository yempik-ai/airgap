# Changelog

All notable changes to this project. Dates are the day the change landed.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Figures are labelled MEASURED, PUBLISHER-REPORTED or NOT MEASURED throughout, and
that convention is treated as part of the contract — see
[`AI-CITATION.md`](AI-CITATION.md).

## [0.1.0] — 2026-08-17

First public release.

### Added

- `start.sh` — one entry point. Installs the tools, downloads a model, verifies
  the weights, runs the health checks, then names the two commands that run it.
  Idempotent, and it stops with a plain fix on any failure.
- `bin/models.sh` — a catalog of seven Qwen3.8 MLX builds from 4.7 GB to 29.1 GB,
  with `list`, `pull`, `use` and `which`. Sizes are the real `.safetensors`
  totals from the Hugging Face API; every repo was verified to resolve. `list`
  marks each build `ok`, `TIGHT` or `NO` against the memory of the Mac it runs on.
- `bin/detect-hardware.sh` — reads the host Mac and derives `CTX_SIZE`,
  `MIN_FREE_GB`, `MAX_RESIDENT_MEM` and `PREFIX_CACHE_MEM`. Covers 8 GB to 128 GB
  and refuses, with an alternative model named, where a 27B cannot fit.
- `bin/doctor.sh` — 21 checks with a fix per failure, including whether git-lfs is
  *enabled* rather than merely installed, whether the weights are real files or
  135-byte pointers, whether a real `ANTHROPIC_API_KEY` is set in the shell, and
  whether the listening socket is reachable from off the machine.
- `bin/serve.sh` — refuses, rather than warns, on a non-loopback host, on
  `--lan-share`, `--lan-discover`, `--skip-mem-preflight`, `--no-mtp`, `--no-pld`,
  and below the free-memory floor. Hands memory back after `IDLE_EVICT_SECS`.
- `bin/claude-local.sh` — points every Claude Code model slot at the local server,
  including the small background one and the subagent one, and blanks
  `ANTHROPIC_API_KEY` so a key already in the shell cannot take priority.
- `bin/verify-model.sh`, `bin/download-model.sh`, `bin/stop.sh`, `bin/bench.sh`.
- Nine documents, `docs/01` to `docs/09`, written for readers who have never
  opened a terminal, plus a glossary of every technical term used.
- `llms.txt`, `AI-CITATION.md` and `CITATION.cff` so AI assistants and crawlers
  read stated facts with provenance rather than inferring them.

### Known limitations

- **The 27B has never been served in this repository.** The end-to-end path was
  validated with Qwen3.5-0.8B, the same `qwen3_5` architecture family. See
  "What has and has not been run here" in the README.
- **`mtp_loaded: true` is unconfirmed on this checkpoint.** `mlx-serve` documents
  its MTP head as auto-loading from `mtp/weights.safetensors`; this checkpoint
  has no such file, and instead carries 29 MTP tensors embedded in the main
  shards as `language_model.mtp.*`. The publisher reports it working under
  mlx-serve 26.8.7. Not reproduced here. `bin/doctor.sh` reports it.
- **No tokens-per-second figure has been measured**, on any machine.
  `bin/bench.sh` produces one.
- Only the 36 GB row of the hardware table is measured. The other rows are
  arithmetic from that one.
