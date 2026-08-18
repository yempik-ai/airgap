# Audit — 2026-08-17

An audit of `airgap` against [`antirez/ds4`](https://github.com/antirez/ds4)
(DwarfStar), a DeepSeek-V4 inference engine for Metal, CUDA and ROCm. The
question was narrow: *what should airgap take from ds4 to be better and faster
for everybody?*

Nothing here is a proposal to port C. ds4 is 240,000 lines of engine; `airgap`
is shell over a server someone else compiled. What transfers is technique,
policy and discipline — and, as it turned out, a set of capabilities airgap
already installs and never uses.

**Every item below was checked against the files and binaries on disk, then
attacked by a second reviewer whose default position was to reject it.** Seven
candidates went in; one was falsified outright and is recorded in
[`AGENT.md`](AGENT.md) under *Falsified — do not retry*, along with the
environment facts established along the way. Read that file first — it exists so
these findings are not researched twice.

Items are referenced by id from [`ROADMAP.md`](ROADMAP.md). All are **OPEN**
except `A1`, `A2`, `A4`, `A5`, `A6`, `A7`, `B1`, `B3`, `B4`, `B5`, `C1`, `C3`,
`D1`, `D2`, `D3`, `D4` and `E1`, `E4`, marked **DONE** below; §F is roadmap
sequencing and was absorbed into `ROADMAP.md` Phases 2–3 on 2026-08-17.

Evidence is cited as `file:line` at the time of the audit. Line numbers drift;
the greps are given where the reader will need to re-locate something.

---

## Order of work

Ranked by user-visible benefit against effort and confidence. `A1` and `A5`
first because they are small and self-contained; `C1` and `B1` next because
`B1`'s measurement is what finally puts a number on claims the README currently
marks *never measured*.

| | item | effort | confidence |
|:--|:--|:--|:--|
| ✅ | `A1` instance lock in `serve.sh` — **DONE** | small | high |
| ✅ | `A5` name the stall timeout — **DONE** | small | medium |
| ✅ | `C1` read the cache evidence already being written — **DONE** | medium | high |
| ✅ | `B1` make `bench.sh` keep prefill and peak memory — **DONE** | medium | high |
| ✅ | `D3` doctor probes a streamed tool call — **DONE** | medium | high |
| ✅ | `E1` stop overriding the engine's prefill sizing — **DONE** | small | medium |
| ✅ | `E4` thinking off, opt-in — **DONE** | small | high |
| ✅ | `A7` label the wired ceiling; doctor quotes the measured one — **DONE** | small | high |
| ✅ | `B3` say what `IDENTICAL` proves: this run, not the algorithm — **DONE** | small | high |
| ✅ | `B5` a checked-in release gate, `RELEASE.md` — **DONE** | small | high |
| ✅ | `B4` `bench.sh` ends as one row; `bench/` holds one file per Mac — **DONE** | small | high |
| ✅ | `D1`+`D2` a truncated or half-arrived shard is caught, once, for everyone — **DONE** | small | high |
| ✅ | `A4` `CTX_SIZE` refused above the model's own maximum, in `serve.sh` — **DONE** | small | high |
| ✅ | `D4` `stop.sh` stops what holds the weights; names a foreign port holder — **DONE** | small | high |
| ✅ | `A6` a minimum `mlx-serve` version, refused in `serve.sh` — **DONE** | small | high |
| ✅ | `A2` a disk refusal for the prefix cache, from one function — **DONE** | small | high |
| ✅ | `C3` say the log rotates; show its tail when a server is gone — **DONE** | small | medium |

No numbered item is left that neither a loaded model nor a second machine is
needed for — with one exception, recorded here so it is not lost: `F5` is
arithmetic over each checkpoint's own `config.json` and needs nothing loaded
at all. It is filed under §F as Phase 2 sequencing, which is why it reads as
deferred rather than as the small offline fix it also is. `E4` carried the largest measured speed-up in this audit and shipped
opt-in, as required: a behavioural change with an unmeasured quality cost is
not a default. Everything in §F is roadmap sequencing, not code — absorbed
into `ROADMAP.md` Phases 2–3 (revised 2026-08-17), nothing left to do until
Phase 2 starts. Still open, and why: `B2` (a context sweep) and `B6` (a
quality suite — also the only way `E4`'s quality cost becomes a number) need
the model loaded at length; `C4`, `E2`, `E3` need a measurement to say
anything honest. Of the measurements, only `A3`'s missing number needs the
27B; `B2`, `B6` and `E5`'s two questions are answerable on the 9B — `E5`'s
own note says "needs the 27B loaded", and that is over-stated: what it has
to compare is two `[hot-cache]` lines and how Claude Code's `-p` mode renders
its system block, neither of which is a property of the weights.

---

## A. Guards that do not guard

### A1 — `serve.sh` has no instance lock — **DONE**

> **Shipped 2026-08-17.** `LOCK_DIR` (default `~/.airgap/model.lock`), an
> mkdir-based lock holding the owner's pid. Taken by `serve.sh` (a new guard,
> ahead of the memory guard) and `bench.sh`, reported by `doctor.sh`, cleared by
> `stop.sh` only when the holder is gone. A stale lock is reclaimed rather than
> obeyed. `bench.sh` kept its port probe, as the analysis required.
>
> One thing the analysis did not predict, found by running it: `: "${LOCK_DIR:=…}"`
> substitutes on *empty* as well as unset, so `LOCK_DIR=` silently got the
> default back and the documented off-switch did not work. It is the one setting
> in `env.sh` written with `=` rather than `:=`, and the reason is commented
> there.
>
> Verified on the reference machine: refusal fires against a live holder
> (`serve.sh` and `bench.sh` both exit 1, naming the pid); a lock with a dead pid
> is reclaimed and the load proceeds; `doctor.sh` reports PASS / WARN / SKIP
> correctly in all three states; `stop.sh` clears a stale lock and refuses to
> touch a live one.
>
> *Follow-up, 2026-08-17:* `stop.sh` waited on `/health`, but `mlx-serve`
> closes its port before its process exits, so the lock check could find the
> holder still alive, print "still held … not the server on port N", and leave
> a lock that went stale a second later. It now records the pids before the
> signal and waits on `kill -0`, not the port. Verified three start/stop
> cycles: lock cleared each time, correct message; a lock held by a live
> non-server pid is still left alone.

`bin/bench.sh:81-86` refuses to run when the port is busy. `bin/serve.sh` has no
equivalent: it is a bare `exec mlx-serve` at `:313`. Grepped `bin/` and
`start.sh` for `flock|lockfile|pidfile|pgrep` — zero matches; `lsof` appears only
in `bench.sh:82` and `doctor.sh:252`. So the repository enforces this rule on
one script and not on the one that actually loads the model.

**Narrower than it first appears, and the write-up must say so.** `mlx-serve`
binds its port before loading (see `AGENT.md`), so a same-port double-start dies
at bind. It also runs its own free-RAM preflight, which catches a *staggered*
second load even off-port. The genuinely unguarded window is: two `bench.sh`
runs (bench passes no `--port`, so `bench.sh:82` cannot see a sibling bench), a
`PORT=` override, which defeats every port-based check in the repo, or two
starts within the same few seconds on different ports.

`bin/stop.sh:53` compounds it: its `pkill -f "mlx-serve.*--port ${PORT}"` cannot
match a bench run or an off-port server, and then reports *"nothing running on
port 11234"* — see `D4`.

**ds4** takes an exclusive `flock` before weights are read (`ds4.c:49172-49214`,
`LOCK_EX|LOCK_NB` at `:49183`, pid written at `:49211`, `atexit` release at
`:49213`, single call site at `ds4.c:57209`) and raises it to a stated safety
rule in `AGENT.md:29`: *"Do not run multiple huge model processes concurrently.
The instance lock is intentional."*

**Shape.** `acquire_model_lock` / release helper in `bin/env.sh`; a new guard in
`bin/serve.sh` ahead of the memory guard at `:198-217`; `bench.sh` takes the same
lock but **keeps** its port probe, whose message is the more specific one;
`stop.sh` clears it; `doctor.sh` reports a stale one. Liveness via `kill -0` and
a named override are mandatory so a SIGKILL cannot brick the start path.

**Do not** use `/tmp/ds4.lock` — the installed `mlx-serve` binary embeds ds4's
lock code and that literal path. `flock(1)` is absent on macOS; `/usr/bin/shlock`
exists if a platform primitive is preferred over `mkdir` + `kill -0`.

**Also update** `bin/serve.sh:35`, which says "Checks seven things" and
enumerates 1–7 at `:36-41`.

### A2 — no disk guard for the prefix cache — **DONE**


> **Shipped 2026-08-18.** `hw_disk_need_gb` (`bin/detect-hardware.sh`) is the
> one place the arithmetic lives, with `hw_size_gb` to read `10GB`/`512MB`/`0`
> and `HW_DISK_SPARE_GB=5` stated once as the policy number it is:
>
> - `download` — the larger of the peak (two copies of the download, until
>   `git lfs dedup` reclaims one) and the steady state after it (weights +
>   cache tier), plus the spare. `MIN_DISK_GB` now defaults to this instead of
>   a hardcoded 45: **45** for the 5-bit 27B (unchanged, and now derived) and
>   **20** for the 9B, where 45 was simply wrong. The DOWNLOAD size is the
>   input, not the loaded size the memory guards use — the vision tower lands
>   on disk (`catalog_download_gb_for_dir`).
> - `serve` — the cache tier plus the spare, which is `serve.sh`'s new Guard 3
>   and `doctor.sh`'s `disk` row once the model is here (it asked for a flat
>   5 GB before). Measured on the volume holding `~/.mlx-serve`, not the
>   checkout's, because that is where `kv-cache` goes.
>
> The refusal names the fix that is usually right — a smaller cache, not more
> disk: `PREFIX_CACHE_DISK=2GB`, or `0` to keep only the memory tier (the
> server documents `0/off disables`).
>
> Refusal transcript: `PREFIX_CACHE_DISK=100000GB ./bin/serve.sh` →
> `REFUSING TO START — not enough free disk for the prefix cache. available:
> 465.2 GB … required: 100005 GB`. Offline proof: `tests/serve-guards.sh`.


`bin/env.sh:233` sets `PREFIX_CACHE_DISK=10GB` and `bin/serve.sh:253` passes it.
`bin/doctor.sh:160-164` requires only 5 GB free once `config.json` exists, and
`serve.sh` performs no disk check at all (`MIN_DISK_GB` appears in
`download-model.sh`, `doctor.sh` and `env.sh` only). A Mac with 6 GB free passes
every check and then starts a server configured to write up to 10 GB of cache.

Disk is the one resource in the stack with no refusal covering it. Principle (3)
also applies: `MIN_DISK_GB` should be weights + cache tier, from one function.

### A3 — the memory guard is a single startup snapshot

`bin/serve.sh:202-217` samples `available_gb()` once and then `exec`s. Nothing
re-checks. `hw_rebudget` (`bin/detect-hardware.sh:210-223`) budgets weights + KV
+ prefix cache + 1 GB spare + an 8 GB macOS reserve, with **no line item for the
harness itself** — and the documented workflow starts Claude Code in window 2,
i.e. *after* the guard has already passed (`start.sh:146-158`).

Related and measured: a 4051-token prompt raised mlx-serve's reported peak by
1.67 GB over a 15-token one, while the KV term predicts 0.06 GB for that depth.
The remainder is prefill activation working set, which the arithmetic does not
model at all and which the 1 GB spare may not cover at `PREFILL_CHUNK=4096`.
`docs/04-memory-safety.md:196-200` narrates a "~1 GB working space" into the
peak, but `hw_rebudget` never adds it. `B1` is what turns this into a number.

*Number, 2026-08-17 (`B1`, 9B, MEASURED, single sample):* the working set above
weights + KV was **+2.56 GB** at 16,377 prompt tokens with `PREFILL_CHUNK=4096`
and **+1.11 GB** at `PREFILL_CHUNK=1024`. On the 9B that sits inside a
`MIN_FREE_GB` of 11 with room to spare; on the 27B, where `MIN_FREE_GB=22`
rounds up from 21.6, a comparable working set is not covered. Not measured on
the 27B — still the missing measurement.

*Number, 2026-08-18 (`E1`, 9B, MEASURED, single samples):* with the pin gone
the server sizes the chunk to **512 or 1024** on this machine, by what is
free when it loads (14.9 GB → 512, 19.5 GB → 1024), and the working set is
**+0.72 GB** at 512 and **+1.11 GB** at 1024 — about the "~1 GB" row
`docs/04` narrates. So on the 9B the prose row is about right, and it is
right because the server sizes the chunk to the memory it actually has, not
because the formula models it. The formula still has no prefill term, and the
27B's number is still missing; both remain this item.

### A4 — `CTX_SIZE` is validated only in `doctor.sh` — **DONE**


> **Shipped 2026-08-18.** `model_max_ctx` (`bin/env.sh`) is now the one reader
> of `max_position_embeddings`, and `serve.sh` Guard 0b refuses above it:
>
> ```
> REFUSING TO START — CTX_SIZE is larger than this model's own maximum.
>   CTX_SIZE      : 999999 tokens
>   model maximum : 262144 tokens (Qwen3.8-9B-mlx-4Bit/config.json)
> ```
>
> It runs BEFORE the GPU-ceiling guard on purpose, so an oversized window is
> refused for its own reason instead of as "the weights do not fit under the
> ceiling" — a wrong reason is worse than no reason. `doctor.sh`'s `context`
> row reads the same helper, so the advisory copy and the guard cannot
> disagree. Quiet when the model is not downloaded (Guard 1 refuses that) or
> python3 is missing. `serve.sh`'s help text went from eight checks to eleven
> with this, `A6` and `A2`.
>
> Offline proof: `tests/serve-guards.sh`.


Grepped for `max_position_embeddings` across `bin/` and `start.sh`: one hit,
`bin/doctor.sh:370`. `serve.sh:250` passes `--ctx-size` unvalidated. So
`CTX_SIZE=262144 ./bin/serve.sh` on a model whose ceiling is lower inflates
`MIN_FREE_GB`, may trip the wired-ceiling guard for the wrong reason, or starts
and fails per-request. This is a guard living in the advisory script — the
inverse of principle (1).

### A5 — the stall timeout has no name, and both ends expire together — **DONE**

> **Shipped 2026-08-17.** `SERVE_TIMEOUT` (default 300, the server's own
> default, now named). `serve.sh` passes `--timeout` and prints it;
> `claude-local.sh` derives the client limit as `SERVE_TIMEOUT + 60`, floored at
> 300 s because Claude Code cannot go below it, and prints both numbers. Not
> added to the `serve.sh` denylist, per the analysis. `docs/06` §12 gained the
> failure case only — the slow-but-working text was already there and was not
> duplicated. `docs/07`'s two settings tables gained both new settings.
>
> `CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS` is deliberately **not** set, and the
> reason is commented in `claude-local.sh`: whether the server's SSE keepalive
> frames feed that watchdog is one of the two open unknowns below.
>
> Verified on the reference machine: `SERVE_TIMEOUT=300` → client 360 s;
> `600` → 660 s; `30` → client floored at 300 s while the server keeps 30;
> `0` → no `--timeout` passed and both banners say so.
>
> **Still open:** the two mechanism unknowns at the end of this item, and the
> 27B prefill timing the experiment would produce. Naming the limit does not
> measure it.

`mlx-serve --timeout` defaults to **300 s**. Claude Code's
`CLAUDE_STREAM_IDLE_TIMEOUT_MS` floors at **300000 ms**. The two coincide
exactly, so a cold turn that crosses 300 s without a token fails on both ends
simultaneously, under two different unnamed defaults. Neither appears anywhere
in `bin/` or `config.env.example`.

The exposed class is the **36 GB machine and larger** running `27b-5bit` — not
small Macs, which `detect-hardware.sh:262-265` steers to the 4.7 GB 9B. Say so;
the obvious phrasing ("on a slower Mac") is backwards.

**`mlx-serve` already sends SSE keepalive frames** — this is about *naming a
limit airgap inherits*, not adding a mechanism.

**Shape.** `SERVE_TIMEOUT` through all three lists in `bin/env.sh` (see
`AGENT.md` § Layout), passed by `serve.sh`; explicit values for the two Claude
Code variables in `claude-local.sh:109-128`. Docs: `docs/06-troubleshooting.md`
§12 already covers the slow-but-working case at `:981-1046` — do **not** add a
second copy. The missing sentence is the *failure* case: what the abort looks
like and which of the two limits produced it.

Leave `--timeout` out of the `serve.sh` denylist, or justify it differently: the
denylist's stated rationale at `:152-154` is that the help promises the script
never passes those flags, which stops being true once it passes `--timeout`.

**Unknowns.** Whether mlx-serve's stall clock starts at request receipt (thus
counting an idle-evict reload) or at generation entry; and whether its keepalive
comment frames reset Claude Code's stream watchdog or only its byte watchdog.
One experiment settles both — `SERVE_TIMEOUT=30 IDLE_EVICT_SECS=5`, one cold
~20k-token turn, record which side aborts — and it produces the first real 27B
prefill timing as a side effect.

### A6 — no minimum-version check on `mlx-serve` — **DONE**


> **Shipped 2026-08-18.** `MLX_SERVE_MIN=26.8.8` in `bin/env.sh` — a fact
> about the flags `serve.sh` passes, not a setting — with `mlx_serve_version`
> and `version_lt` beside it. `serve.sh` Guard 0a refuses below it and names
> `brew update && brew upgrade mlx-serve`; `doctor.sh`'s `mlx-serve` row FAILs
> on the same comparison and prints the minimum beside the version; `setup.sh`
> says it at install time, which is the earliest the answer exists. A version
> that cannot be parsed is a WARN, never "too old": it is a shape this repo
> does not know.
>
> Parsing was checked against the real binary and against what this file used
> to say. `mlx-serve --version` prints **eight lines** on stdout, one per
> component, plus a `[mem]` line on stderr — not the one `·`-separated line
> `AGENT.md` recorded. The version is the first line's second field; the three
> places that parsed it by hand now call the one helper.
>
> Offline proof: `tests/serve-guards.sh` stubs `mlx-serve --version` at 26.8.7,
> 26.8.8 and 26.9.0.


`serve.sh:245-276` passes `--kv-quant turbo4`, `--prefix-cache-disk`,
`--idle-evict-secs`, `--metrics` and `--prefill-chunk` with no capability probe.
Grepped `bin/*.sh` for `version`: display only (`doctor.sh:196`,
`setup.sh:153,166`), never compared. A user on an older brew build gets an
argparse error after passing every guard — the exact failure doctor exists to
pre-empt. `doctor.sh:320` already anticipates version drift for `mtp_loaded`;
nothing generalises it.

### A7 — the wired ceiling is arithmetic presented as fact — **DONE**

*Shipped 2026-08-18. Labelled ARITHMETIC at every statement — the function
comment in `detect-hardware.sh`, its report line, both refusals (`serve.sh`,
`download-model.sh`), doctor's two rows, `docs/04` §8, `docs/01`, the
glossary. And the real number turned out to be reachable from Bash after all:
`mlx-serve` prints Metal's ceiling at every load, `[wired] mode=max
limit=28753 MB` on the test machine — 28.1 GB MEASURED against the 27.0 GB
the rule gives (MLX's `max_recommended_working_set_size` reads the same
28.08 GiB), so the arithmetic erred on the refusing side by 1.1 GB, n=1, and
the rule is not corrected from one sample. `doctor.sh`'s `gpu ceiling` row
now quotes the measured value beside the estimate whenever the log has one and
FAILs a build that fits the estimate but not the measurement — the direction
that stalls a Mac. The guards keep the estimate on purpose: it exists before
any load and cannot go stale the way a log can. `tests/wired-log.sh` holds the
reader.*


`bin/detect-hardware.sh:119-127` computes the GPU ceiling as
`g <= 32 ? g*2/3 : g*3/4`, and `docs/04-memory-safety.md:577-580` states it
without a label. This is the number behind the repository's hardest refusal, and
it is the one figure that carries no MEASURED / REPORTED / ARITHMETIC tag —
principle (2) broken at the highest-stakes point in the stack.

ds4 does not guess: it asks Metal for `recommendedMaxWorkingSetSize`
(`ds4_metal.m:4239-4243`) and **refuses rather than falling back to a heuristic**
when it is unavailable (`ds4.c:55110-55117`). MLX exposes the same property from
Python, and `mlx-serve` already derives `--max-resident-mem auto` from it
("80% of MLX wired limit at startup"). Grepped airgap for
`recommendedMaxWorkingSet|metal.device_info|max_recommended`: zero hits.

Both failure directions are silent: refusing a build that would have fitted, or
admitting one that will not.

---

## B. Measurement

### B1 — `bench.sh` throws away two numbers it already receives — **DONE**

> **Shipped 2026-08-17.** `bench.sh` keeps all three lines: each run prints
> `prompt : N tokens, read at R tokens/s`, the decode line, and `peak memory`;
> the result block quotes prefill *with its prompt length*, and puts the peak
> next to the guard's arithmetic as *peak − weights − KV actually used* — the
> working set `hw_rebudget` does not line-item (`A3`). `PROMPT_FILE=` makes a
> whole file the prompt. Correction 2 is done by construction, not by copying:
> the four load-shape flags (`--ctx-size`, `--kv-quant`, `--prefill-chunk`,
> `--no-vision`) now live in one list, `LOAD_SHAPE_ARGS` in `env.sh`, which
> `serve.sh` and `bench.sh` both pass; `serve.sh`'s argv was captured with `ps`
> before and after and the flag/value pairs are identical (order aside).
>
> Verified on the reference machine, 9B, `mlx-serve 26.8.8`, single samples:
> the built-in 41-token prompt gives prefill 201 tok/s, decode 36.7, peak
> 4.78 GB (+0.08 GB working set); `PROMPT_FILE=docs/08-how-it-works.md`
> (16,377 tokens) gives prefill 374 tok/s, decode 15.6, peak 7.52 GB —
> **+2.56 GB working set** at `PREFILL_CHUNK=4096`; the same file at
> `PREFILL_CHUNK=1024` gives 285 tok/s and +1.11 GB. So the working set is
> chunk-bound, `PREFILL_CHUNK` is the lever, and `docs/04`'s "~1 GB" row is
> right on the 9B only at the smaller chunk — noted there. `PROMPT_FILE`
> missing or empty refuses before anything loads; the lock is released on
> both refuse paths — and, found 2026-08-18 while running `E1`, *not* on a
> completed run: `bench.sh`'s own `trap 'rm -rf "$TMP"' EXIT` replaced the
> release trap `acquire_model_lock` had installed, so every finished bench
> left a stale lock (reclaimed by the next start, reported as "left behind
> by something that crashed" by `doctor.sh` in between). Fixed the same day
> by repeating the release in that trap; proven by a full run leaving no
> lock. The flags do not distort the speed figure: same prompt with and
> without them, decode 35–36 vs 37 tok/s.
>
> The **Unknown** below is resolved: `footprint(1)` on the one-shot process
> reported `phys_footprint 5328 MB`, of which the `IOAccelerator (graphics)`
> row was 4946 MB, against a printed `Peak memory: 4.822 GB`. The printed
> figure is MLX's Metal-buffer accounting; the whole process is ~0.5 GB above
> it. It is labelled a lower bound in the script and the docs.
>
> Not measured on the 27B. Its working set at a 20,909-token first turn is
> the number `A3` still needs, and it is likely larger than the 9B's 2.6 GB.


`mlx-serve` prints three lines; `bin/bench.sh:145` greps one. The comment at
`:120-127` *quotes the other two* and then discards them:

```
Prompt: 18 tokens, 130.792 tokens-per-sec     ← discarded
Generation: …                                  ← the only one parsed
Peak memory: 4.821 GB                          ← discarded
```

Peak memory measured against `MIN_FREE_GB` is the only empirical check that
exists on `hw_rebudget`'s arithmetic (see `A3`). Prefill is the number behind
"the first response is slow" (`README.md:244`), which `README.md:189` and
`AI-CITATION.md:74` both currently declare never measured.

**Two corrections that would otherwise blow up mid-implementation.**

1. **Parsing the prefill line alone publishes noise.** At `bench.sh`'s default
   ~30-token prompt (`:115`) the figure is dominated by fixed per-call overhead.
   Measured, same model and machine: 15 tokens → **115 tok/s**; 4051 tokens →
   **448 tok/s**. A ~4× understatement. The change must add a long-prompt input
   (`PROMPT_FILE=`) and report the prompt length beside the rate.
2. **Peak memory must be measured with the flags `serve.sh` uses.**
   `bench.sh:132-137` passes neither `--ctx-size` nor `--kv-quant` nor
   `--prefill-chunk`, while `serve.sh:250-256` passes all three. A peak measured
   at model-max context under mlx-serve's own defaults is not comparable to the
   guard it is supposed to check.

The plumbing already exists: `run()` forwards extra flags (`:129`, `:137`) and
the caller at `:164` uses that path for `--no-mtp --no-pld`. What is missing is
a CLI, not a rewrite.

**Unknown.** Whether "Peak memory" is MLX buffer accounting or whole-process
RSS. It includes the weights (4.789 GB reported against a 4804.8 MB checkpoint)
and tracks the working set, but it may exclude process overhead — label it
*mlx-serve's own figure* and treat it as a lower bound.

### B2 — the only speed measurement is taken outside the workload

`bench.sh` measures at ~30 tokens of context. Every real Claude Code turn starts
at 20,909. There is no `PROMPT_FILE`, no context sweep, and no document stating
that decode speed decays with depth — `docs/08-how-it-works.md:350-372` presents
a context-independent bandwidth ceiling.

*Partly answered by `B1`, 2026-08-17:* `PROMPT_FILE=` exists, and the decay is
now a measured figure on the 9B — decode 36.7 tok/s after a 41-token prompt,
15.6 after 16,377 (single samples). The sweep and the `docs/08` correction are
still open.

ds4's committed CSVs show the decay is large on this hardware class: M5 Max
Flash q2 falls **39.35 → 27.64 t/s decode** and **790 → 398 t/s prefill**
between ctx 2048 and 65536. Its bench produces a curve, not a number:
`ctx_tokens,prefill_tokens,prefill_tps,gen_tokens,gen_tps,gen_first_ms,gen_steady_tps,kvcache_bytes`,
with first-token time separated from steady state and each row flushed
immediately so an aborted sweep keeps its rows.

**Shape.** `CTX_SWEEP=1 ./bin/bench.sh` behind the existing memory refusal,
capped at what the detected Mac can hold — the sweep must never be the thing
that swaps the machine.

Note for any sweep touching `PREFILL_CHUNK`: at ~30 tokens that flag is a literal
no-op (mlx-serve's help calls it "the ceiling, not a floor"). A sweep on the
stock prompt will report "no difference" and be wrong.

### B3 — the exactness claim rests on one 9B run, and is stated six times — **DONE**

*Shipped 2026-08-18, wording only: `bench.sh` prints `outputs IDENTICAL <-
byte identity, observed on this run`; `docs/07`, `docs/08` and the glossary
say identity is the algorithm's promise in exact arithmetic, that a batched
floating-point implementation in a closed binary can drift, and that the
script therefore checks every run instead of the docs asserting it once — it
has held on every 9B run so far. Not "divergence is expected". The
median-of-N and spread wait on `B2`.*


`README.md:186`, `docs/07-tuning.md:421-424`, `:473`, `:484`, `:495-497` and
`docs/09-glossary.md:990-991` all assert that speculative decoding is exact and
that `bench.sh` proves it. The evidence is a single `IDENTICAL` on the 9B.

ds4 treats byte identity as something an implementation must *guarantee* — it
commits the batched verifier state, and its rule is that no faster path may keep
unexplained attention, KV or logits drift. **Whether `mlx-serve` does the same
is unknowable**: it is a closed binary. So the honest wording is *"byte identity
is not guaranteed by the algorithm and has not been established for mlx-serve;
IDENTICAL was observed on the 9B on the test machine"* — not "divergence is
expected", which would replace one unearned confident claim with another.

The single recorded run is also 57.114 vs 56.302 tok/s — a 1.01× ratio that
`docs/07-tuning.md:477-479` has to explain away as noise. A repository that must
talk its reader out of its only measured ratio is the argument for a
median-of-N and a spread.

### B4 — contributed benchmarks arrive in a form nothing can use — **DONE**

*Shipped 2026-08-18: `bench.sh` ends every run by printing it as one
tab-separated row — date, commit, chip, GPU cores, RAM, macOS, `mlx-serve`,
model, `ctx_size`, `kv_quant`, `prefill_chunk` (`auto` when unpinned), prompt
(`default` or the `PROMPT_FILE` name), prompt and generated tokens, decode
on/off, prefill, peak on/off, identical — and `ROW_FILE=bench/<chip>-<ram>gb.tsv`
appends it, header first when the file is new. `bench/README.md` fixes the
name, the header and the meaning of every column. `bench/m3-max-36gb.tsv`
holds the reference machine's first two rows (9B, default prompt and
`docs/08` — 27.4/26.4 tok/s at 41 tokens; 11.9/9.6 tok/s and 269 tok/s
prefill at 16,458, 1.25× with prompt lookup given text to copy, peak 9.55 GB
unpinned; MEASURED). No plotter: stdlib-only SVG is Python, out of scope, and
a TSV opens in anything.*


`ROADMAP.md` asks contributors to *"paste the whole output into an issue"*.
Prose in issues cannot be diffed, plotted, aggregated or used as a baseline —
and evidence from Macs that are not the 36 GB M3 Max is the thing the roadmap
says it needs most.

ds4 asks for one CSV per machine committed to the repo (`m2_ultra.csv`,
`m4_max.csv`, `m5_max.csv`, `gb10.csv`) plus a stdlib-only plotter that renders
an SVG beside it.

### B5 — there is no checked-in release gate — **DONE**

*Shipped 2026-08-18: `RELEASE.md` — eight numbered runs with pass and block
conditions (CI, doctor with the server up, `bench.sh` on a real prompt with a
>10 % repeatable decode slowdown as a blocker unless written down, the
end-to-end `AIRGAP OK`, re-proving any touched guard, the argv diff, the
label check on every changed figure, CHANGELOG + CITATION), the one-line
record each manual run leaves in the release notes, and what 0.1.0 still owes
so a tag cannot skip it silently.*


Phase 0 lists three evidence tasks in prose. Nothing states what must be re-run
before a tag, on what hardware, with what configuration recorded, or what counts
as a blocker. Grepped for `QA|release checklist|sign-off|.github/workflows`: no
such file.

ds4 ships a numbered release matrix recording commit, hardware, model file,
context size and non-default flags for every manual run, and makes a repeatable
>10% slowdown a release blocker unless the trade-off is documented.

The MEASURED convention is currently enforced by the author's memory, which is
the failure mode the convention exists to prevent.

### B6 — the quality claims are the most consequential and the least measured

*"Materially weaker at long tool-calling chains"* (`README.md:242,301`) and
*"a 27B handles many tool descriptions badly — it picks the wrong tool, or
produces a malformed request"* (`docs/07-tuning.md:340-342`) are stated three
times, unlabelled, with no evidence. `LEAN_MCP=1` — a default that costs the
user their MCP servers — rests partly on the second.

ds4 ships a small embedded capability suite framed exactly as this repository
would want: explicitly not a leaderboard, deliberately including questions the
model should fail, published as a regression gate with a deterministic
four-question sub-gate whose expected answers and token counts are in the
README, plus `--regrade-trace` to re-score a saved transcript without reloading
the model.

Without something equivalent, a user cannot tell whether malformed tool calls
are inherent to the model, caused by their `KV_QUANT`, or a regression in a new
`mlx-serve` — and neither can the repository. `D3` is the cheap first step.

---

## C. Observability

### C1 — the stack writes its own evidence and nothing reads it — **DONE**

> **Shipped 2026-08-17.** Two rows in `doctor.sh`'s server section, placed
> *before* the `/v1/messages` probe so doctor's own 8-token question cannot
> become the evidence. `prefix cache` reads `LOG_FILE`, scoped to everything
> after the last `^Logging to ` banner, and quotes the `[hot-cache] reused N/M`
> line with the **largest** N in that run — largest, not latest, because on the
> second doctor run the probe itself is a 12/13-token hit and would otherwise
> displace the 20,000-token line the row exists to show. `/metrics.json` reports
> `hits/queries` and `prefix_cache_tokens_total/prompt_tokens_total`; a 503 is a
> SKIP (`METRICS=0`), a `000` or empty answer a WARN. When the server is down, a
> SKIP row names the log path. All server probes now go through one `srv_curl`
> helper that adds `x-api-key` when `API_KEY` is set (`C2`'s hoist), written as
> two branches because bash 3.2 cannot expand an empty array under `set -u`.
> `docs/05` §7d now names the log path and shows the two rows; `docs/06` §12,
> `docs/07` §5 and §10 point at them; `docs/07` §10's "404 means METRICS=0" was
> wrong and now says 503.
>
> Verified on the reference machine against the 9B, `mlx-serve 26.8.8`: counter
> semantics established by traffic (three identical 1212-token prompts →
> `queries=3, hits=2, prefix_cache_tokens=2362, prompt_tokens=3636,
> prefill_tokens=1274`; wall 3241 → 337 → 236 ms — MEASURED, single sample);
> run scoping proven on a log holding four runs, whose older run's bigger
> `23494/23567` hit is correctly excluded; `METRICS=0` → SKIP; server down →
> SKIP with path; `LOG_FILE` pointing nowhere → SKIP; `PROBE=0` unaffected.
> The `docs/05` example is pasted from that run.

`METRICS` defaults to 1 and `serve.sh:263-265` passes `--metrics`; `serve.sh:258`
passes `--log-file`. Neither is ever read. Grepped `/metrics` across `bin/`,
`start.sh`, `docs/` and `README.md`: `env.sh:269` (a comment), `serve.sh:263-265`
(the flag), `docs/07-tuning.md:517` (a curl the *user* is told to type).
`LOG_FILE` is set, `mkdir`'d and echoed — `doctor.sh` never opens it.

Meanwhile the single measured cache figure — `reused 16384/20906 tokens` — is
hand-typed into **five** documents (`docs/05-run-it.md:478`,
`06-troubleshooting.md:1017`, `07-tuning.md:284`, `08-how-it-works.md:1026`,
`09-glossary.md:834-835`). That exact line is already on disk in
`~/.mlx-serve/logs/`, written by the server on every request.

So the repository's central performance claim — the prefix cache is "the single
biggest speed win" — is unverifiable on the user's own Mac, while the evidence
for it is being generated and discarded continuously.

**ds4** logs every cache hit with tokens, quant, key kind and load milliseconds
(`ds4_kvstore.c:1320-1327`) and a per-request `cached..prompt:suffix` span
(`ds4_server.c:10204-10209`), and treats the startup cache report as *the line
the user is told to read*.

**Shape.** A `doctor.sh` row that scopes the log to the current server run and
reports the last `[hot-cache]` line, plus the `/metrics.json` counters when the
server is up. Key names and the stale-log hazard are recorded in `AGENT.md` —
do not re-derive them. A 503 from `/metrics.json` is a SKIP row, not a FAIL.

Also fix `docs/08-how-it-works.md:1100`, which says of the `[hot-cache]` line
"Where to look for it is covered in 05 — Run it", while `docs/05` §7d
(`:464-479`) quotes the measurement and never names the log path.

### C2 — doctor's auth header is applied to one probe out of three — **DONE, and narrower than written**

> **Shipped with `C1`, 2026-08-17.** Every doctor probe now goes through
> `srv_curl`, which adds the header once. But running it showed the premise was
> too strong: `--api-key` **exempts loopback**. The server's own banner reads
> `API key auth: ENABLED for non-loopback requests (localhost is trusted;
> /health stays open)`, and against a server started with `API_KEY=s3cret`,
> `/v1/models`, `/metrics.json` and `/v1/messages` all answered 200 from
> `127.0.0.1` with no key and with a wrong key. Since `serve.sh` refuses any
> non-loopback `HOST` and doctor's `BASE_URL` follows `HOST`, the false WARN
> below could not actually occur under airgap's own guards. The consolidation
> stands on its merits — one place, not three — and `AGENT.md`'s `--api-key`
> fact now carries the loopback qualifier.

`bin/doctor.sh:325-326` builds the `x-api-key` header for the `/v1/messages`
probe. The `/v1/models` fetch at `:293` has none, and `--api-key` gates
`/v1/models` and `/metrics` (not `/health`). With `API_KEY` set, the failing
curl yields an empty `models_json` and falls through to `:300` — a **false WARN**,
not a false FAIL, and doctor still exits 0. Hoist the header array above `:293`
and reuse it for the metrics fetch in `C1`.

### C3 — the log is unbounded, unread, and never surfaced on failure — **DONE**


> **Shipped 2026-08-18.** The log is not unbounded — `mlx-serve` rotates it at
> 32 MB — and the repository now says so where a reader meets the setting:
> `docs/07` §11's `LOG_FILE` row, `config.env.example`, and `docs/06`'s "How to
> stop everything". That is the whole of the first half; nothing in `bin/`
> rotates anything, which is correct.
>
> The second half is `log_tail` (`bin/env.sh`), and where it is called:
> `stop.sh` prints the last 8 lines when there was nothing of ours to stop
> **and** the last run did not end with the server's own goodbye line — the
> case where "nothing is running" is a surprise and the reason is in the file.
> `doctor.sh` prints them under a `/v1/messages` that failed, and under
> `server not running`. Not a row of its own: it is evidence for the row above
> it, not a verdict.


Grepped `bin/` for `rotate|logrotate`: zero. At `LOG_LEVEL=debug` a long-lived
server writes into `~/.mlx-serve/logs/` forever, on a Mac whose disk requirement
drops to 5 GB once the model exists (`doctor.sh:161-163`). And when the server
dies, the one artifact that explains why is shown to the user by no script.
(mlx-serve rotates its own log at 32 MB; airgap neither knows nor states this.)

### C4 — the banner reports requested values, never effective ones

`bin/serve.sh:302-311` echoes `$MODEL_DIR`, `$CTX_SIZE`, `$KV_QUANT`,
`$MAX_RESIDENT_MEM`, `$PREFIX_CACHE_MEM`, `$IDLE_EVICT_SECS` — the values airgap
*asked for*. It says nothing about what mlx-serve chose for everything it was
not given (`prefix-cache-entries=32`, `ssm-checkpoint-stride=256`, adaptive MTP
depth), nor about a requested budget that was silently clamped after context and
KV accounting.

ds4's operating advice is the opposite: the startup cache report is the line the
user is told to read, *because* the requested budget may be capped.

Principle (3) is violated invisibly here — a clamped value looks identical to an
honoured one, and `doctor.sh` cannot tell them apart either.

---

## D. Verification that does not verify

### D1 — `verify-model.sh` cannot detect a truncated shard — **DONE**


> **Shipped 2026-08-18.** Each shard is now measured against its own header:
> `8 + hlen + max(data_offsets[1])` is where the last tensor has to end, and a
> file shorter than that is truncated, by exactly the number of bytes it names.
> The header is written first, so it survives every cut — which is why every
> count in the report agreed and `verify PASS` was printed over weights that
> load as garbage. A second check shipped with it for the shape that leaves
> nothing behind to inspect: a shard `model.safetensors.index.json` names and
> that never arrived at all. Still no content hashing, and still deliberately:
> the publishers ship no checksums, and the byte comparison catches the failure
> this item is about.
>
> Offline proof: `tests/verify-truncation.sh`, over folders built at test time
> by `tests/fixtures/make-model.py` — whole at 1 and 5 shards, truncated,
> missing, pointer. Built rather than committed because a shard has to be over
> 1 MB to get past the pointer test, and a 1 MB blob does not belong in git.


`bin/verify-model.sh:128-160` reads the safetensors header and uses
`os.path.getsize` only for the <1 MB pointer test at `:130`. The loop sums
`offs[1]-offs[0]` into `payload` at `:157-160` and never compares
`8 + hlen + max(offs[1])` against the actual size. No content hashing anywhere
(grepped `bin/` for `shasum|sha256|md5|checksum`: one hit, `bench.sh:150`, an
output fingerprint).

A shard truncated by a full disk or a killed pull — but over 1 MB and with an
intact header — passes `verify PASS` and the manifest tensor-count check, because
the counts come from the header rather than the bytes. The user meets it as a
load failure or garbage output. The comparison is two lines.

### D2 — three of four "is the model here?" checks look at one shard — **DONE**


> **Shipped 2026-08-18.** One helper set in `bin/env.sh` — `model_shards`,
> `model_pointer_shard`, `model_missing_shards`, `model_state` — giving one
> answer over every shard: `absent`, `partial`, `complete`. Every caller reads
> it. `start.sh` says "Half here … About to resume it" and offers the resume
> instead of "already here"; `models.sh` marks `~` in `list`, refuses `use`
> with the `pull` that finishes it, and reports `PART downloaded` in `which`;
> `serve.sh` Guard 2 names the pointer shard and the missing ones;
> `doctor.sh`'s `weights` row and `download-model.sh`'s own final check ask the
> same two questions.
>
> `env.sh`'s model discovery deliberately still counts a `partial` folder as
> "the model here". Its question is *which folder*, not *is it whole* — and
> skipping a half-downloaded folder would point everything at a build that is
> not there and offer to download a different one, when the right answer is to
> resume this one.
>
> Offline proof: `tests/model-state.sh` — shard 1 of 5 with the rest pointers,
> shard 1 of 5 with the rest never written, a first-shard pointer, a folder
> with a `config.json` and no weights, whole at 1 and 5 shards — plus a grep
> rule that only `env.sh` and `verify-model.sh` may enumerate `*.safetensors`,
> which is how the four answers drifted apart in the first place.


`bin/models.sh:95-100` returns inside the first loop iteration; `start.sh:82-87`
and `bin/env.sh:128-135` `break` after the first shard. Only `serve.sh:189-196`
and `doctor.sh:221-229` iterate all of them.

A multi-shard download interrupted after shard 1 therefore reports "already
here" in `start.sh`, is accepted by `models.sh use`, and the download step is
skipped — so the user is caught two steps later by `verify-model.sh` instead of
simply having the download resumed.

### D3 — doctor never exercises a tool call, and never the streamed path — **DONE**

> **Shipped 2026-08-17.** Two rows in `doctor.sh`'s server section, after
> the `/v1/messages` round trip so a cold server has already reloaded:
> `tool call` (`stream:false`) and `streamed call` (`stream:true`). One body,
> built once, only that flag differs — one tool (`get_weather`, required
> `city`), "What is the weather in Paris?", **thinking on** because Claude
> Code always sends it (so the `tool_use` block arrives after a thinking
> block, as in a session), `temperature: 0`, `max_tokens: 1024`. The streamed
> answer is reassembled from its `input_json_delta` pieces by a python3 reader
> that also checks for `message_stop`, so "the pieces do not add up to JSON"
> and "the stream never ended" are outcomes of their own. Every outcome names
> a different fault: `declined` (words, not a call), `unparsed` (a raw
> `<tool_call>` passed through as text), `wrong_tool`, `bad_input` (required
> arg missing), `unassembled`, `unterminated`, `error` (the server refused),
> `truncated` (a WARN: still reasoning at the cap — a slow build, not a
> broken one), `empty`. FAILs point at a new `docs/06` §24. `PROBE=0` SKIPs
> both. `claude-local.sh` exports `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1`
> (name verified in 2.1.233 with `strings -a`).
>
> Two things the shape below did not predict, found by running it. **(1)**
> `tool_choice` is **ignored** by `mlx-serve 26.8.8` — `any`, a named tool and
> nothing at all render the same prompt (a `283/284` cache hit across the
> three) and an off-topic question comes back as text under all three. So it
> cannot do the job the shape gave it, and it is not sent: the question has
> to need the tool, and the row reads *how* the answer failed instead. **(2)**
> The 8-token "hi" probe was kept as the liveness row and the two new rows
> come after it; the reasoning cost is 44 tokens on the 9B (69 with thinking
> against 25 without), well inside the estimate.
>
> Verified on the reference machine against the 9B, `mlx-serve 26.8.8`: both
> rows PASS (`get_weather({"city":"Paris"})`, 69 tokens each; whole doctor
> 4.3 s — MEASURED); all thirteen reader outcomes exercised against captured
> answers (live: decline, truncation at `max_tokens: 5`, an API error;
> crafted from live captures: an unparsed `<tool_call>`, a stream with a torn
> `partial_json`, a stream missing `message_stop`, a wrong tool name, an empty
> `input`, an empty body, non-JSON); `PROBE=0` → three SKIP rows; a
> `claude-local.sh -p` turn with the fallback disabled answered, streamed.
> Doctor is 29 checks against a live server (was 27), 22 with it down.
> Those reader checks were ad hoc in a scratch directory that day; since
> 2026-08-18 they are `tests/tool-call-verdict.sh` with the captures under
> `tests/fixtures/tool-call/`, run by CI, so a change to `tool_call_verdict`
> or `tool_call_row` is caught without a server.

`bin/doctor.sh:323-331` sends `max_tokens: 8`, content `"hi"`, and checks only
that curl exited 0. Every check can pass on a build — the 2-bit at
`catalog.sh:44`, or any off-catalog model `models.sh:56-60` accepts — that
cannot emit a parseable tool call. That is the one capability Claude Code
requires. The user discovers it as mysterious agent failures against an
all-green report.

**Streaming is the path that matters.** In ds4, tool-call recovery is a ladder,
and tier 2 is explicitly disabled for streaming requests (`ds4_server.c:11941`
and again at `:12037`, guarded on `!j->req.stream`). Three separate SSE state
machines exist — OpenAI (`:6469`), Responses (`:7188`), Anthropic (`:8098`).
Streamed and non-streamed assembly genuinely differ, so both must be tested.

**Shape.** Two rows behind the existing `PROBE` variable (`doctor.sh:69`): one
`stream:false`, one `stream:true`, each with a trivial tool schema and
`tool_choice: {"type":"any"}` — without forcing the choice, a FAIL conflates
*"the model declined to call a tool"* with *"the server could not parse the
call"*, which destroys the row's diagnostic value. Measured cost on an already-
loaded server: ~1–5 s for both.

Four implementation notes that will otherwise cost an afternoon:

- `curl -sN … | grep -q` is SIGPIPE-fragile under doctor's `set -euo pipefail`
  (`:14`): `grep -q` exits on first match, curl dies 141, pipefail propagates it
  and the enclosing `if` silently takes the FAIL branch. Capture to a variable
  and grep that. Use `-sN`, not `-fsSN`.
- The header array already exists at `:325-326`; this does not depend on `C1`.
- Qwen3.8 emits reasoning before tool calls — use `max_tokens >= 256` and assert
  on `stop_reason`, so a truncated-mid-reasoning response reports as truncation
  rather than as a tool-call failure.
- A FAIL is a property of the *model*, not the install. Point the row at
  `./bin/models.sh list`.

Related: export `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1` in
`claude-local.sh` (verified present in Claude Code 2.1.233) so the harness
cannot paper over a broken stream by silently retrying non-streamed.

**Do not** add `--no-tool-autocorrect` to the `serve.sh` denylist. It is a debug
knob a user diagnosing tool failures has every reason to set, and it is narrower
than it sounds: per its own help it coerces *argument types* on an
already-parsed call (Python `False` → JSON `false`). It is **not** syntax
repair, and it is not the analogue of ds4's `try_repair_dsml`. Do not write
"mlx-serve already repairs tool calls" anywhere.

*(For accuracy about ds4: `try_repair_dsml` at `ds4_server.c:5221` only appends
missing **closing** tags, refuses when closes exceed opens (`:5273-5277`), and
its own comment at `:5219-5220` says it "deliberately does not rewrite malformed
but balanced DSML into assistant text; semantic recovery belongs to the model".
It is truncation repair, not general repair.)*

### D4 — `stop.sh` cannot stop everything it implies — **DONE**


> **Shipped 2026-08-18.** Three sources, unioned, instead of one `pkill`
> pattern: the model lock (the only thing that knows about a holder with no
> port — a `bench.sh` run) **and its children** (bench stays a shell and runs
> `mlx-serve` as a child, so killing the lock's pid alone would leave the child
> holding the weights); `lsof` on the port, which is also what tells our server
> from somebody else's program; and the old `pgrep`, kept for the moments
> around startup and shutdown when a server is not answering `lsof`. A foreign
> holder is reported and left alone — `nothing of ours is running, but port
> 11234 is held by node (pid 4821)` — where it used to read `nothing running on
> port 11234.`, the opposite of the truth.
>
> Offline proof: `tests/stop-targets.sh` — a lock holder with a child (both
> stopped, lock given back), a foreign listener on the port (reported, still
> alive afterwards), and nothing at all.


`bin/stop.sh:53` matches `mlx-serve.*--port ${PORT}`. `bench.sh:132-137` invokes
mlx-serve with no `--port`, so a bench run holding ~19 GB cannot be stopped by
the documented stop button. And when a foreign process holds the port,
`stop.sh:65-67` reports *"nothing running on port 11234"* purely because `pkill`
found no match — it never consults `lsof`, which `doctor.sh:252` does. The
stop/start loop the docs recommend gives a contradictory answer to the one
question the user is asking.

---

## E. Tuning surface the stack owns and does not use

### E1 — `PREFILL_CHUNK` overrides the engine's own memory sizing — **DONE**

> **Shipped 2026-08-18.** Subtraction, as prescribed: `PREFILL_CHUNK` defaults
> to empty and `--prefill-chunk` is added to `LOAD_SHAPE_ARGS` in `env.sh` only
> when it is set, so `serve.sh` and `bench.sh` both stop passing it. No
> `HW_PREFILL_CHUNK`. `config.env.example`, `docs/04`, `docs/07` (§4 table,
> §9 sample and measurements, §12 left-alone table, §13 defaults) and
> `docs/09` updated; the `docs/04` "MIN_FREE_GB=22 comes from" gap is `A3` and
> was left there.
>
> **The first action did not collapse it.** The banner had printed before on
> this machine, but only for the 0.8B in ad hoc launches; for the 9B it never
> had. Unpinned, `serve.sh` at `LOG_LEVEL=info` printed
> `Prefill chunk: 512 tokens (memory-sized down from 8192; --prefill-chunk
> overrides)` — eight times smaller than the 4096 airgap was pinning; a later
> start under the same settings with more memory free chose 1024. Probing the
> sizing (serve mode, 9B, `ps`-verified argv, free figure from the server's
> own `[preflight]` line): `--max-resident-mem 6GB` → 512 at 14.9 GB free and
> 1024 at 19.5 GB free; `12GB` → 1024 at 19.1; `24GB` → 2048 at 20.1; no flag
> (engine default 22.5 GB) → 2048 at 18.9 — all at `--ctx-size 65536`; `6GB`
> at `--ctx-size 8192` → 2048 at 19.9. So the engine sizes the chunk from the
> memory free at load, the resident budget **and** the context size — the last
> two being settings airgap already derives from the Mac, the first being what
> only the engine can see at that moment — which is exactly the
> "better-informed source of truth" the item claimed. The rule itself is not
> known and is not written down anywhere in this repository. When the flag is
> pinned the server prints **no** chunk line at all, which is why the figure
> in use was invisible until now.
>
> **One thing the analysis did not predict, found by running it: one-shot mode
> does not memory-size.** `mlx-serve --prompt` (what `bench.sh` uses) prints no
> banner, ignores `--max-resident-mem` (no `[registry]` line; the same 9.52 GB
> peak with and without it) and reads at the 8192 ceiling. So after `E1`,
> `bench.sh`'s peak is an *upper bound* on the server's shape, not "the same as
> serve.sh". `bench.sh` now says so when `PREFILL_CHUNK` is empty — a `chunk:`
> line quoting the figure the server chose in its last run (from its log,
> scoped past the last `Logging to` banner like `C1`'s reader) and the exact
> pin that reproduces it — and marks the `gap` line as the ceiling's.
>
> Numbers, 9B, `docs/08` as prompt (16,408 tokens), `bench.sh` single samples:
>
> | prefill chunk | prefill | peak | working set |
> |:--|--:|--:|--:|
> | 8192 (unpinned one-shot) | 594 tok/s | 9.52 GB | +4.57 GB |
> | 4096 (the old pin, re-run) | 309 tok/s | 7.535 GB | +2.58 GB |
> | 512 (the server's choice, pinned) | 430 tok/s | 5.63 GB | +0.72 GB |
>
> and the server itself, unpinned at 512, prefilled 16,416 tokens at 483 tok/s
> (`[prefill:` in its log; serve mode prints no peak). Peak reproduces the
> 2026-08-17 figure to the second decimal (7.52 → 7.535); prefill speed does
> not (374 → 309), and speed did not track the chunk (594 at 8192, 309 at
> 4096, 430 at 512, one sample each on a shared machine), so the "small speed
> cost" claim was retired from `env.sh`, `config.env.example` and `docs/04`
> rather than restated — the peak is the reproducible number, the rate is
> not. On the 27B nothing is measured, and since free memory at load is an
> input, nothing about its chunk is predicted here either.
>
> argv, `ps -o args=` on the running server, before → after: identical except
> `--prefill-chunk 4096` removed. `PREFILL_CHUNK=1024 ./bin/serve.sh` puts the
> pair back, and `PREFILL_CHUNK= ./bin/serve.sh` (empty) leaves it out.

`bin/env.sh:251` hardcodes 4096 and `serve.sh:256` passes it always. But
`mlx-serve` already sizes this from memory, printing
`Prefill chunk: N tokens (memory-sized down from M; --prefill-chunk overrides)`.
airgap's constant is a **second and worse-informed source of truth**: Bash cannot
know the model's per-layer attention-score budget that the flag's own help says
the engine caps against.

**The fix is subtraction, not addition.** Make `--prefill-chunk` conditional
(the `_YOURS_*` idiom at `env.sh:74,203-205` is the existing pattern), drop the
default at `env.sh:251`, and let the engine size it. Do **not** add a
`HW_PREFILL_CHUNK` to `detect-hardware.sh`; ds4 is not precedent for that (see
`AGENT.md` § Falsified).

**Six edit sites, not two.** `bin/env.sh:249-250`; `config.env.example:129-131`;
`docs/07-tuning.md:251` (table row) and `:620` (defaults table);
`docs/04-memory-safety.md:727-729` ("halves the temporary memory spike … at a
small cost in speed" — unlabelled arithmetic assuming linear scaling);
`docs/09-glossary.md:233-236`. The phrase "a small speed cost" appears only in
`env.sh:250` and `config.env.example:130`, not in `docs/07`.

**This exposes an existing guard gap rather than creating one.**
`docs/04-memory-safety.md:196-200` narrates a ~1 GB prefill working space into
its "peak total ~22.8 GB" and says *"this is where MIN_FREE_GB=22 comes from"* —
but `hw_rebudget` computes 19.1 + 1.0 + 1.5 = 21.6 → 22 with no prefill term.
The prose has a line item the formula does not. See `A3`.

**First action:** launch once with the flag removed at `LOG_LEVEL=info` and grep
`~/.mlx-serve/logs/` for `Prefill chunk:`. That banner line has probably never
printed in this repository's history, because airgap always passes the flag. If
the engine picks ~4096 on 36 GB anyway, this collapses to a docs-and-measurement
change with no behaviour delta on the test machine.

### E2 — the prefix cache is tuned by bytes only

`serve.sh:252-253` passes `--prefix-cache-mem` and `--prefix-cache-disk`.
`mlx-serve` also caps the cache **by entry count** (`--prefix-cache-entries`,
default 32) and caps SSM checkpoints per entry (`--ssm-checkpoint-max`, default
32). Grepped airgap for both: zero hits.

So a user with two or three Claude Code projects open silently evicts their own
cached system prompt and pays full prefill on every switch — with no counter, no
doc and no setting that names the cause. And `docs/07` §5's advice to raise
`PREFIX_CACHE_MEM` may buy nothing if the 32-entry cap binds first.

No document converts `PREFIX_CACHE_MEM` into the unit the user thinks in, even
though the repository owns the constant one section earlier: 1536 MB at
16 KiB/token (`docs/07-tuning.md:137`) is roughly 98,000 tokens — about four
Claude Code system prompts.

### E3 — the hot-path speculative-decoding knobs are undocumented

`docs/07` §13 claims to list *"every setting this stack understands"*. Grepped
`docs/`, `bin/` and `config.env.example` for
`mtp-depth|mtp-history|pld-draft-len|pld-key-len`: zero hits. Yet:

- `--mtp-history-window` changes MTP behaviour only above 16,384 tokens —
  airgap's floor is 20,909, so **every airgap turn crosses that threshold**.
- `--pld-draft-len` (default 5) and `--pld-key-len` (default 3) govern the
  prompt-lookup win that `docs/08` §7 celebrates for file editing, which is
  airgap's core workload.
- `--ssm-checkpoint-stride` is explained in prose at `docs/08:1080-1083` and
  `docs/09`, but appears in no settings table and no `config.env.example` line —
  a documented mechanism with no exposed control.

A user who wants more speed is told to use `EXTRA_ARGS` blind rather than being
pointed at the four flags that move their workload.

### E4 — no control over thinking, and the only real lever is client-side — **DONE**

*Shipped 2026-08-18, exactly the shape below: `MAX_THINKING_TOKENS` on
`ENV_KEYS` (so `config.env` can hold it and the command line can beat it), no
default, exported by `claude-local.sh` only when set, refused if not a whole
number, reported on a `thinking` banner line; `tests/thinking-knob.sh` holds
the guard. Nothing server-side moved. Proven through the harness on Claude
Code 2.1.234 (`-p`, the 9B): the server log reads `thinking=false` under `0`
and `thinking=true` under `1024` and unset — 3 output tokens against 33 and
47 for a one-number answer, all three correct (MEASURED, single samples). The
quality cost stays unmeasured, on both builds, and the setting stays opt-in
until `B1`'s suite puts a number on it.*


The server-side flag is inert; that is settled and recorded in `AGENT.md`
under *Falsified*. **Do not implement `--reasoning-budget` in `serve.sh`.**

What is real:

| | output tokens | wall |
|:--|--:|--:|
| thinking on (default) | 1156 | 20.9 s |
| `thinking: disabled` | 376 | 7.2 s, complete answer |

*MEASURED, n=1, Qwen3.8-9B-mlx-4Bit, M3 Max 36 GB, mlx-serve 26.8.8, temp 0,
ctx 8192, max_tokens 3000, prompt "What is 17*23? Think step by step."
Not measured on the 27B. Quality cost not measured on either.*

**Shape.** Entirely client-side: an opt-in knob in `bin/claude-local.sh` mapping
to `MAX_THINKING_TOKENS`, defaulting to today's behaviour (unset) so nothing
changes silently. `0` yields `thinking:{type:"disabled"}`; a positive value
yields `{type:"enabled",budgetTokens:n}` clamped to `max_tokens-1`. Nothing
server-side moves — no `serve.sh`, no `env.sh`, no `config.env.example`.

State plainly that a *positive* value buys nothing on latency or generated
tokens (measured: 128 vs 1024 vs unlimited all produced 1156 tokens in ~20.8 s).
Its only real effect is shrinking the thinking text Claude Code stores and
replays, which slows input-context growth across a session — a second-order
saving, not the headline.

The 27B's template defaults to `reasoning_effort: xhigh`, so turning thinking
off is a large behavioural change. It ships opt-in, labelled, with the quality
cost stated as unmeasured. `n=1` on one prompt is not a benchmark — this is
precisely what `B1`'s suite should turn into a real number.

**Do not** claim the knob derives from `CLAUDE_CODE_MAX_OUTPUT_TOKENS` "so the
two numbers come from one place": `env.sh:35` lists the name in `ENV_KEYS` but
sets no default; the default lives in `claude-local.sh:121`. `serve.sh` and
`claude-local.sh` are separate processes.

### E5 — nothing seeds the cache on purpose

`README.md:244` apologises that the first response is slow: ~21,000 tokens of
system prompt must be prefilled, and the prefix cache absorbs it only from turn
two. So every *new* session pays it again.

ds4 does not wait for turn two. On a cold request it computes an anchor —
`ds4_kvstore_chat_anchor_pos` (`ds4_kvstore.c:711-728`) finds the end of the
stable system/tool scaffolding, before the user's actual task — **splits the
prefill**, writes that partial state to disk as `reason="cold"`, and only then
prefills the rest (`ds4_server.c:11411-11470`). Its comment states the intent:
*"Cold checkpoints maximize reuse across independent agent sessions."*

airgap cannot split a prefill. What it can do is make the first request happen
before the user's first question, using the genuine article rather than a
reconstruction: `claude-local.sh:35` already documents `-p` one-shot mode.

**Shape.** `bin/warm.sh` that waits for `server_up` (`env.sh:321`), runs one
real one-shot with a short output cap, and **prints the `[hot-cache] reused N/M`
line it produced as evidence** — it must never assert a speed-up it did not
measure.

**The integration point is `bin/claude-local.sh`, not `start.sh`.** `start.sh`
deliberately never starts the server (`:10-13`) and ends by telling the user to
open two windows (`:146-161`) — a warm call there always fails `server_up`.
`serve.sh` ends in `exec` (`:313`), so nothing can run after it. The only seam
is `claude-local.sh` between `server_up` (`:70`) and `exec` (`:147`). Two guards
are mandatory: `warm.sh` must invoke `$CLAUDE_BIN` directly with the same
exports, or `claude-local.sh` recurses infinitely; and `WARM_ON_START` must
default to **0** — an opt-in that spends a full ~21k-token prefill, never a
silent cost on every session start.

**Blocked on evidence.** Whether Claude Code's `-p` mode renders the same
leading system block as an interactive session, and by how much a warm run
raises the next turn's `reused` count, cannot be settled from the repository —
it needs the 27B loaded and two `[hot-cache]` lines compared. Land `C1` first;
ship `warm.sh` only as a print-the-number tool until that measurement exists.
Note that Claude Code's system prompt embeds the working directory, so `warm.sh`
must run from the folder the user will work in.

---

## F. Runtime and roadmap architecture

### F1 — the installed binary already contains the second and third runtimes

`mlx-serve 26.8.8` reports `llama.cpp b10034 · gguf 3 · ds4 unknown` and exposes
`--engine {auto|ds4|llama}` for `.gguf` inputs, routing by the file's
`general.architecture` metadata: deepseek4 and ds4-MLA quants to the embedded
ds4 engine, everything else to llama.cpp. `--ssd-streaming` and `--no-ds4-mtp`
are ds4-specific flags on the same binary. The model directory's own
`RUNTIME-REQUIREMENTS.json` already records `llama_cpp_build: b10034` beside
`mlx_version: 0.32.0`.

`ROADMAP.md` Phase 3 proposes llama.cpp `llama-server` as "the first second
runtime" and calls it a large piece of work, not scheduled. That is more
pessimistic than the evidence supports. The genuinely blocking work is a **GGUF
memory model** and a catalog **`format` column** — and the column is already
scheduled in Phase 2. It is not a second process to install, start, stop and
health-check.

Mis-sequencing here delays GGUF support, which is the thing users ask for most.

### F2 — ds4 is not a runtime airgap's median user can reach

Verdict, stated plainly so it is not re-investigated: **not viable below 64 GB,
and viable at all only as an optional high-end path.**

ds4 compiles in exactly three model shapes — DeepSeek V4 Flash, DeepSeek V4 PRO,
GLM 5.2 (`ds4.c:486-489`, `:541,579,617`) — all 100B+ MoE, dispatching on two
architecture strings (`deepseek4`, `glm-dsa`, `ds4.c:5811-5814`), and its
`AGENT.md:3-4` states it is not a generic GGUF runner. Smallest target: **81 GB
on disk**, recommended for 96/128 GB machines; the SSD-streaming floor is a
64 GB MacBook, and streaming is documented as slower and more fragile. airgap's
tested machine is 36 GB and its entire disk budget is 45 GB.

No amount of Bash changes this — the shapes are compiled constants. Listing ds4
as a runtime option would be the first entry in the repository that most readers
cannot use, which fails the hardware-reach test the README's own table is built
on.

The honest framing: an optional path for 96 GB+ users, reached through the
existing `--engine ds4` route, documented as such.

### F3 — SSD streaming would require a second memory model

`--ssd-streaming` is the one capability here that reaches *below* airgap's
current floor: it runs a model larger than RAM. But it inverts the guard.

`hw_rebudget` assumes resident weights (`MIN_FREE_GB` = weights + KV + prefix
cache). Streaming deliberately runs weights that exceed RAM, with a bounded
routed-expert cache sized from 80% of the recommended working set minus
non-routed weights, then capped again after context and KV accounting
(`ds4.c:39185`, `:55110-55125`). That is a *different budget function for the
same guard*, which principle (3) forbids unless the two are unified
deliberately.

Adopting streaming without naming this produces either a guard that refuses
every streaming configuration (weights alone exceed RAM by design) or one
switched off for streaming and therefore protecting nothing.

**As a technique it is NOT_TRANSFERABLE** to the MLX path: it is engine-level,
it requires an MoE, and the default checkpoint has no experts. Do not attempt an
analogue. *(For the record, the mechanism: on decode the shared expert's matmuls
are submitted first; while that command buffer executes, a service thread waits
on a Metal event for the router's selected-id readback and pulls exactly those
experts' slices from disk. On prefill, the next layer loads during the current
layer's compute.)*

### F4 — the adapter contract hard-codes an endpoint the second runtime lacks

Phase 3 defines a runtime adapter partly as *"what `/health` and `/v1/models`
look like"*, and both `env.sh:322` (`server_up`) and `doctor.sh:291,303` call
`/health` directly. **ds4-server has no health route at all** — it implements
`/v1/models` (`ds4_server.c:12811`) and `/v1/messages` (`:12831`); grepped
`ds4_server.c` for `health`: zero hits.

So the abstraction as written needs editing on contact with its second
implementation. The adapter needs a readiness **hook** — a command the adapter
supplies — rather than a fixed path, and `doctor.sh` needs one row per adapter
rather than one hardcoded curl. Cheap now, expensive after two adapters exist.

### F5 — the KV formula is one Qwen3.8 constant with no per-model value

`bin/detect-hardware.sh:176-185` derives `kv_gb = ctx/65536` from 16
full-attention layers, and its own comments state it over-estimates the 9B and
is *"WRONG for a dense model"*. `bin/catalog.sh:13-40` has no KV field.

Already named at `ROADMAP.md` Phase 2, and repeated here because it is the
precondition for the wider catalog: the moment a non-Qwen3.8-hybrid family is
added, every guard — `MIN_FREE_GB`, the wired-ceiling refusal, the ok/TIGHT/NO
column in `models.sh list` — under-estimates KV cost while still reading as
authoritative.

---

## Also considered, and rejected

- **Porting anything from ds4's C, Metal or CUDA.** Never on the table. airgap
  ships no compiled code by design.
- **mmap / wired-memory policy as a knob.** MLX and mlx-serve expose none —
  verified against `mlx_lm/utils.py:282-323` and the complete `mlx-serve --help`.
  Its value transfers as *one paragraph* in `docs/08` explaining why MLX
  materialises and wires weights, why wired memory is not swappable, and hence
  why the wired-ceiling check is a refusal and `iogpu.wired_limit_mb` must not
  be raised. Do not claim airgap turns anything on.
- **`dir-steering` (activation steering for verbosity).** Real in ds4, but it
  operates on the residual stream and has no MLX-side control surface. A
  distraction relative to `E4`, which reaches the same goal with a request field.
- **ds4's download-script patterns.** Compared against
  `bin/download-model.sh` and `bin/models.sh`: resumability, pointer
  verification, de-duplication and the active-model switch are already present
  and, in places, stronger. The one idea not already held is refusing when a
  partial download from a *different* downloader is detected (ds4 checks for an
  aria2 sidecar beside a curl `.part` and stops rather than corrupting it).
  Small, and worth doing if the downloader is touched for another reason.
