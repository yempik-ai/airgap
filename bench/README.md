# bench/ — one file per Mac, one row per run

`./bin/bench.sh` ends every run by printing the run as one tab-separated row,
and `ROW_FILE=bench/<file>.tsv ./bin/bench.sh` appends it here. These files
are the repository's benchmark evidence: they can be diffed, plotted and used
as a baseline, which prose in an issue cannot (`AUDIT.md` B4).

**File name:** `<chip>-<ram>gb.tsv`, lower-case, e.g. `m3-max-36gb.tsv`,
`m4-pro-48gb.tsv`, `m2-ultra-192gb.tsv`. One file per machine; every run on
that machine is a row in it, oldest first. Never edit a row by hand — re-run.

**Header** (written by `bench.sh` when the file is new; column order is fixed):

```
date	commit	chip	gpu_cores	ram_gb	macos	mlx_serve	model	ctx_size	kv_quant	prefill_chunk	prompt	prompt_tokens	gen_tokens	decode_on_tps	decode_off_tps	prefill_on_tps	peak_on_gb	peak_off_gb	identical
```

| column | meaning |
|:--|:--|
| `date`, `commit` | when, and which `airgap` commit ran it |
| `chip`, `gpu_cores`, `ram_gb`, `macos`, `mlx_serve` | the machine and runtime, read at run time |
| `model` | the model directory name |
| `ctx_size`, `kv_quant`, `prefill_chunk` | the load shape; `auto` = not pinned, so the one-shot load read at the 8192-token ceiling and `peak_*` is an upper bound on the server's ([07 §10](../docs/07-tuning.md#bench)) |
| `prompt` | `default`, or the file name given as `PROMPT_FILE=` — rows are comparable only on the same prompt |
| `prompt_tokens`, `gen_tokens` | as counted by `mlx-serve` |
| `decode_on_tps`, `decode_off_tps` | tokens/s generating, speed features on (MTP head if the build ships one + prompt lookup) and off — `mlx-serve`'s own figures, decode only, load excluded |
| `prefill_on_tps` | tokens/s reading the prompt, speed features on; meaningless under a few thousand prompt tokens |
| `peak_on_gb`, `peak_off_gb` | `mlx-serve`'s peak for its Metal buffers, each run |
| `identical` | `yes` if the two answers were byte-identical on this run |

Every figure is MEASURED by definition — the file only ever holds what
`bench.sh` printed. To contribute: run it, commit the file, open a PR with the
run's full output in the description. Rows for the 27B are the ones this
repository is missing most.
