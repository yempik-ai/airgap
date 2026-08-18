# 04 — Memory safety: will this break your Mac?

**Who this is for.** Anyone about to run the model for the first time. You do not
need to know anything about memory, macOS internals, or how the model works. Every
term is explained here before it is used.

**What you will have at the end.** A clear answer to three questions: does this
model fit on *your* Mac, what is the worst thing that can happen, and how to keep
the worst thing from happening. You will also know which single setting on macOS
is genuinely risky, and why this repo tells you to leave it alone.

**How long it takes.** About 10 minutes of your attention. Nothing to download and
nothing to wait for. The commands on this page each finish in under a second.

**What it costs.** No disk space. No memory. No money. Nothing on this page sends
anything over the network. One optional command asks for your password, and it is
clearly marked.

**What you need first.**

- A Mac with an Apple chip. See [01 — requirements](01-requirements.md).
- This repository cloned to your Mac. See [02 — install](02-install.md).
- You do **not** need the model downloaded yet. Read this page before you run the
  server for the first time.

**If you only read one thing:** the model needs a large, unbroken block of your
Mac's memory. This repo refuses to start the server when that block is not
available, so the normal failure is a clear error message, not a broken Mac.

---

## 1. The short answer

With the guards in this repository, **no — this will not break your Mac.**

The failure you will actually meet is a script that stops and prints
`REFUSING TO START — not enough free memory.` That is the guard doing its job. It
is annoying. It is not damage. Nothing is lost and nothing needs repairing.

There is one setting on macOS that *can* make a Mac stall hard enough that you
have to hold the power button. It is called `iogpu.wired_limit_mb`, and Section 8
covers it. This repo never changes it, and recommends you do not change it either.

Three states, and this page keeps them apart everywhere:

- **EXPECTED** — a message that looks alarming and is harmless.
- **FIX THIS** — a real problem with a named fix.
- **STOP** — do not continue until you have changed something.

---

## 2. What "memory" means on an Apple Silicon Mac

Your Mac has one pool of fast memory. The main processor and the graphics
processor both draw from that same pool. This design is called **unified memory**
(see [Glossary](09-glossary.md#unified-memory)).

> **Think of it like** one shared water tank that both the kitchen and the garden
> hose draw from. On a Windows gaming PC there are two separate tanks: system
> memory, and a smaller dedicated tank on the graphics card called VRAM.
> **Where the comparison stops:** water is interchangeable, and memory pages are
> not. Some pages are locked in place and cannot be moved, which is the whole
> subject of Section 8.

Two consequences follow, and they explain everything else on this page.

**Good news.** A large model does not have to be copied from system memory to a
graphics card. There is nowhere to copy it to. A Mac with 36 GB can therefore run
a model that would need a very expensive graphics card on a PC.

**Bad news.** The model and macOS are competing for the same tank. Every gigabyte
the model takes is a gigabyte your browser, your editor, and macOS itself cannot
have.

Memory is measured in gigabytes (GB). This repository's model needs about
**19.1 GB** — roughly four high-definition movies, except all of it must sit in
memory at the same time, not stream from disk. (MEASURED on the test machine.)

---

## 3. Why the weights have to fit in memory all at once

A **model** is a very large table of numbers. Those numbers are called the
**weights** (see [Glossary](09-glossary.md#weights)). To produce a single word of
an answer, the model reads *every* weight. Not some of them. All of them.

That is why the whole file has to be in memory. If the weights lived on the disk
and were read as needed, the Mac would read 19.1 GB from disk for every few
characters of output. It would work, in the sense that a bicycle works for
crossing a continent.

### The three things that take memory

**1. The weights — about 19.1 GB, and this number does not move.** (MEASURED on
the test machine.) It is fixed by the model file you downloaded.

The file is stored using **quantization** (see
[Glossary](09-glossary.md#quantization)): each number is squeezed into fewer bits
so the whole table takes less room. This model uses **5-bit** weights.

> **Think of it like** saving a photo as a JPEG instead of the raw camera file.
> The picture is still there and still recognizable, but it takes a quarter of the
> space and some fine detail is gone. **Where the comparison stops:** JPEG loses
> detail you can see. Quantization loses precision in numbers you never see
> directly; it shows up as slightly worse answers, not as visible blur.

Fewer bits means less memory and slightly worse answers. A 4-bit build of the same
model takes about 16 GB. An 8-bit build takes about 27 GB. (Both figures are NOT
YET MEASURED in this repository — only the 5-bit build is present here. Check the
publisher's file listing before you plan around them.)

**2. The conversation memory — this one grows as you talk.**

Text is fed to a model in pieces called **tokens** (see
[Glossary](09-glossary.md#token)). A token is roughly three quarters of an English
word, so 1,000 tokens is about 750 words.

> **Think of it like** the model reading in syllables rather than in letters or
> whole words. **Where the comparison stops:** the pieces are chosen by frequency,
> not by pronunciation, so a common word is one token and a rare name may be four.

The **context window** (see [Glossary](09-glossary.md#context-window)) is the
maximum number of tokens the model can hold at once — the conversation, your
files, and its own replies, all together. This repo sets it to **65,536 tokens**,
which is roughly 49,000 English words.

> **Think of it like** the size of the desk the model works at. Papers that do not
> fit on the desk get pushed off the edge and are gone. **Where the comparison
> stops:** a real desk holds whatever you put on it. This desk has to be paid for
> in memory up front, before the first page arrives.

As the conversation grows, the model keeps working notes about everything it has
already read. Those notes are the **KV cache** (see
[Glossary](09-glossary.md#kv-cache)).

> **Think of it like** a notebook the model writes as it reads, so it never has to
> re-read the whole conversation from the start. **Where the comparison stops:**
> you can skim your own notes. The model's notes are only useful in the exact
> order they were written.

On this particular model the notebook is unusually small, and that is the main
reason a 27-billion-parameter model fits on a laptop at all. At the repo's default
settings the notebook costs **1.0 GB** at a full 65,536 tokens.

<details>
<summary><strong>For the curious: the arithmetic behind that 1.0 GB</strong></summary>

This model has 64 layers, but only 16 of them keep a growing notebook. The other
48 keep a single fixed-size summary that is rewritten in place and never grows.
You can read the split yourself in the checkpoint's own `config.json`, in the
`layer_types` list, or see it printed by `./bin/verify-model.sh`.

The per-token cost of the growing part:

```
16 layers x 2 (keys and values) x 4 kv-heads x 256 head-dim x 2 bytes = 65536 bytes
```

That is exactly 64 KiB per token at 16-bit precision. This repo also compresses
the notebook itself (`KV_QUANT=turbo4`, 4-bit), which divides it by four to
16 KiB per token. So:

```
KV cache in GB = context window in tokens / 65536
```

65,536 tokens is therefore exactly 1.0 GB. 131,072 tokens is 2.0 GB.

**This formula is exact for this model and wrong for most others.** A conventional
model where all 64 layers keep a growing notebook would cost four times as much.
The 9B in the catalog has the same pattern with half as many layers, so for it
the formula over-estimates by two — the safe direction for a guard, which is why
the scripts use the one formula for both. Do not reuse it for a conventional
model, where every layer keeps a growing notebook.
</details>

**3. Everything else — about 2 to 3 GB.** Working space while the model reads your
prompt, plus a **prefix cache** that stores the notebook for the long, unchanging
instructions Claude Code sends at the start of every turn.

> **Think of it like** keeping the answer to a question you get asked every single
> day on a sticky note, instead of working it out again each morning. **Where the
> comparison stops:** the sticky note is only valid while the question is
> word-for-word identical from the beginning. Change the first sentence and the
> whole note is discarded.

### The total, on the test machine

The conclusion to draw from this table: the weights dominate, and everything else
put together is smaller than the rounding error on a browser.

| What | Size | How it was established |
|---|---|---|
| Weights, text only | 19.1 GB | MEASURED on the test machine |
| Conversation notebook at 65,536 tokens | 1.0 GB | Calculated exactly, see the deep dive above |
| Fixed summaries for the other 48 layers | ~0.2 GB | Does not grow with the conversation |
| Prefix cache ceiling | 1.5 GB | Set by `PREFIX_CACHE_MEM=1536MB` in `bin/env.sh` |
| Working space while reading a prompt | ~1 GB | The server sizes its read chunk from what is free when it loads; MEASURED 0.7–1.1 GB on the 9B at the 512–1024 it chose |
| **Peak total** | **~22.8 GB** | Added up from the rows above |

This is where `MIN_FREE_GB=22` comes from, and it is arithmetic rather than a
guess. `bin/detect-hardware.sh` computes it as:

```
MIN_FREE_GB = weights + conversation notebook + prefix cache, rounded up
            = 19.1 + 1.0 + 1.5, rounded up
            = 22
```

The two remaining rows above — the fixed summaries and the working space while
reading a prompt — are transient and are covered by the rounding. The server
refuses to start below this number.

**The "~1 GB" working-space row has measurements against it, and which one
applies depends on who sizes the read chunk.** `./bin/bench.sh` puts
mlx-serve's own peak next to this arithmetic ([07 §10](07-tuning.md#bench)).
MEASURED on the test machine with the **9B**, single samples, a 16,377–16,408
token prompt: **2.6 GB** above weights + conversation at a pinned
`PREFILL_CHUNK=4096` (what this repository passed until 2026-08-18), **1.1 GB**
at 1024, **0.7 GB** at 512 — and 512 or 1024 is what the server picks for
itself on this machine when nothing pins it, sizing the chunk from the memory
free when it loads, the context size and the resident cap (14.9 GB free →
512, 19.5 GB free → 1024, both under `MAX_RESIDENT_MEM=6GB`) and printing
`Prefill chunk: N tokens (memory-sized down from 8192; --prefill-chunk
overrides)` in its log. Prefill speed did not track the chunk in those samples
(single samples; the table in 07 §10). So with the pin gone the row is about
right on the 9B, and it is right *because* the server sizes the chunk to the
memory it actually has. Not measured on the 27B, whose working set is likely
larger. That is `AUDIT.md` A3, and it is open.

**That figure is different on every Mac**, because the context window and the
prefix cache are sized from your Mac's memory. To print yours, run from the repo
root:

```
bash -c 'source bin/env.sh && echo "$MIN_FREE_GB GB"'
```

You should see a single number followed by ` GB`. It is 22 on the 36 GB test
machine, 19 on a 32 GB Mac, and 26 on a 48 GB Mac.

---

<a id="free-memory"></a>
## 4. Find out what your Mac actually has

Work in the folder you cloned in [02 — install](02-install.md). Open Terminal and
move into it first. Terminal windows get closed, so this page never assumes you
are already somewhere.

This moves you into the repository folder. Replace
`<PATH_TO_THE_REPO_FOLDER>` with the full path where you cloned it — for
example, `~/dev/local-llms/airgap`.

```bash
cd <PATH_TO_THE_REPO_FOLDER>
```

You should see something like this:

```
(no output)
```

This command prints nothing. That is success. If you see
`cd: no such file or directory`, the path is wrong. Find the folder in Finder,
drag it onto the Terminal window, and the correct path is typed for you.

### 4a. How much memory does your Mac have in total?

This asks macOS for the total size of the memory pool, in bytes.

```bash
sysctl -n hw.memsize
```

You should see something like this:

```
38654705664
```

That number is bytes. Divide by 1,073,741,824 to get gigabytes. On the test
machine 38654705664 becomes 36 GB. Your number will be different; the common
values are 8, 16, 18, 24, 32, 36, 48, 64, 96, and 128 GB.

If the command prints nothing or an error, use the Apple menu in the top-left
corner, choose **About This Mac**, and read the **Memory** line instead.

### 4b. How much memory is free *right now*?

This is the number that decides whether the server will start. It is almost always
much smaller than the total.

This asks the repo's own helper for the memory macOS could hand to a new program
this second.

```bash
bash -c 'source bin/env.sh && echo "$(available_gb) GB available"'
```

You should see something like this:

```
14.8 GB available
```

The number changes every time you run it, and it changes on every machine. That
particular reading was taken on the test machine (Apple M3 Max, 36 GB unified
memory) with a normal set of apps open — a browser, an editor, and a container
tool. **A 36 GB Mac had 14.8 GB free.** That is the honest reality, and it is
below the 22 GB this model needs.

If you see `bash: bin/env.sh: No such file or directory`, you are not in the
repository folder. Repeat the `cd` command at the top of Section 4.

---

## 5. Reading `vm_stat`, and the one number people misread

`vm_stat` is the macOS tool that reports where every page of memory went. You do
not need it to run the model. You need it when you want to know *why* your Mac
feels slow.

This prints the raw memory accounting for the whole machine.

```bash
vm_stat
```

You should see something like this:

```
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                   266633.
Pages active:                                 638121.
Pages inactive:                               540869.
Pages speculative:                             95619.
Pages throttled:                                   0.
Pages wired down:                             231527.
Pages purgeable:                               68977.
Pages occupied by compressor:                 532490.
```

Output trimmed after that line — the real command prints about a dozen more
counters that measure lifetime totals rather than current state.

Every count is in **pages**, not bytes. The page size is printed on the first
line: 16,384 bytes on Apple Silicon, 4,096 bytes on older Intel Macs. Multiply
pages by that size to get bytes.

The conclusion to draw from the next table: only four of these lines are memory
you can actually get back.

| Line | Plain meaning | Can the model use it? |
|---|---|---|
| Pages free | Nothing is in it | Yes |
| Pages inactive | Was used recently, macOS can take it back | Yes |
| Pages speculative | Guessed-ahead file data | Yes |
| Pages purgeable | Apps said "throw this away if you need to" | Yes |
| Pages active | In use by a running app right now | No |
| Pages wired down | Locked by macOS and drivers, cannot be moved | No, and see Section 8 |
| Pages occupied by compressor | **See below** | **No** |

`available_gb()` in `bin/env.sh` adds the first four and nothing else. You can
read that function yourself; it is about ten lines at the bottom of the file.

### The compressor is not spare memory

When macOS runs short, it does not go straight to the disk. First it squeezes
memory that belongs to *live, running apps* into a smaller space. That squeezed
region is the **compressor**.

Pages in the compressor still belong to programs that are running. They are not
available. They are the opposite of available: a large compressor number means
macOS was already short of memory before you arrived.

On the test machine during setup, the compressor held **11.35 GB** (MEASURED).
That single number is why this repository is careful. It is not "a 36 GB Mac with
an empty tank". It is "a 36 GB Mac that was already squeezing".

Rough reading guide, and the label to apply:

- Compressor under about 2 GB: normal. **EXPECTED.**
- Compressor between 2 and 8 GB: the Mac is working for its living. Close
  something before starting the server. **FIX THIS.**
- Compressor above 8 GB, or `Swapouts` climbing while you watch: the Mac is
  already moving memory to disk. Do not start a 19.1 GB model on top of that.
  **STOP.**

### A friendlier version of the same information

This prints a plain-language summary of the same accounting, including how much
has been moved to disk.

```bash
memory_pressure
```

You should see something like this:

```
The system has 38654705664 (2359296 pages with a page size of 16384).

Stats: 
Pages free: 305223 
Pages purgeable: 25760 
Pages purged: 509790381 

Swap I/O:
Swapins: 22548971 
Swapouts: 27973049 

Page Q counts:
Pages active: 583553 
Pages inactive: 510525 
Pages speculative: 94144 
Pages throttled: 0 
Pages wired down: 276407 

Compressor Stats:
Pages used by compressor: 532490 
```

Output trimmed after that line. Reading this command **does not** change anything;
it only reports. The `Swapins` and `Swapouts` counts are lifetime totals since the
Mac last booted, so a large number is not by itself a problem. Watch whether they
*grow* while the model runs.

If `memory_pressure` is not found, use `vm_stat` above. It reports the same facts
in a denser format.

---

## 6. Will it fit on your Mac?

The conclusion to draw from this table: below 32 GB, this 27-billion-parameter
model is the wrong choice, and a smaller model is a real recommendation rather
than a consolation prize.

The **Verdict** column answers exactly one question: *how does the 27B model at
5-bit fare on this Mac?* The **Recommended build** column then says what you
should actually run there, which is sometimes a different build or a different
model.

| Total memory | Verdict for 27B at 5-bit | The build the scripts pick | Context window | Free memory needed |
|---|---|---|---|---|
| 8 GB | Impossible | `9b-4bit` (~4.7 GB) — 6 GB free is more than an 8 GB Mac usually has | 32,768 | 6 GB |
| 16 GB | Impossible | `9b-4bit` (~4.7 GB) | 32,768 | 6 GB |
| 18 GB | Impossible | `9b-4bit` (~4.7 GB) | 32,768 | 6 GB |
| 24 GB | Not recommended | `9b-4bit` (~4.7 GB); `27b-4bit-aeon` (14.1 GB) fits under the ceiling with everything closed | 32,768 | 8 GB |
| 32 GB | Tight | `27b-4bit` (~16.3 GB) | 32,768 | 19 GB |
| **36 GB** | **Workable — the reference** | **`27b-5bit` (~19.1 GB)** | **65,536** | **22 GB** |
| 48 GB | Comfortable | `27b-5bit` (~19.1 GB) | 131,072 | 26 GB |
| 64 GB | Comfortable | `27b-8bit` (~27.7 GB) | 131,072 | 36 GB |
| 96 GB | Comfortable | `27b-8bit` (~27.7 GB) | 262,144 | 40 GB |
| 128 GB | Comfortable | `27b-8bit` (~27.7 GB) | 262,144 | 40 GB |

The **Context window** and **Free memory needed** columns describe the build in
the third column on that row, not the 27B at 5-bit. Every figure comes out of
`bin/detect-hardware.sh`, and you can reproduce any row with
`HW_FORCE_RAM_GB=48 ./bin/detect-hardware.sh`. The build names are keys in
`./bin/models.sh list`, which prints the free-memory figure for every build on
your own Mac.

**Only the 36 GB row is MEASURED.** It is the test machine: Apple M3 Max, 30 GPU
cores, 36 GB unified memory, macOS 26.5.2. Every other row is arithmetic derived
from that one, and is **NOT YET MEASURED**. The 4-bit (~16.3 GB) and 8-bit
(~27.7 GB) weight sizes were computed from the publisher's own file listings on
huggingface.co and have not been checked against files on disk in this
repository.

**This table predicts whether the model FITS. It says nothing about how fast it
will feel.** Speed is driven mainly by the number of graphics cores in your chip,
not by how much memory you have. An entry-level chip with 32 GB and a high-end
chip with 36 GB get similar answers from this table and behave very differently.
No speed figure for the 27B has been measured on any machine.

Reading the rows in words:

- **8 to 18 GB — the scripts will not download 20 GB of weights here.** The
  smallest 27B build needs 16 GB of memory on its own, which is your entire
  machine. This is the range where people waste an hour on a download that could
  never have worked, so `./bin/download-model.sh` refuses a build that cannot fit
  under the ceiling and the default is the 9B instead. It is genuinely useful,
  and it leaves the Mac usable.
- **24 GB — technically borderline, practically no.** The 5-bit build cannot fit
  under the memory ceiling explained in Section 8. Even the 4-bit OrcaRouter
  build lands exactly *at* that ceiling. Making it run means raising the one
  setting that can hard-stall a Mac, on the machine with the least room for
  error. The scripts pick the 9B; `27b-4bit-aeon` at 14.1 GB is the one 27B that
  fits under the ceiling, with everything else closed.
- **32 GB — the first machine where a 27B genuinely runs.** The scripts download
  the 4-bit build here and use a 32,768-token window, and you keep a usable Mac.
  The 5-bit build fits on paper with about 1.7 GB to spare, and any browser or
  container tool destroys that margin. If you already have the 5-bit build on
  disk, the scripts use it and size the memory budget for it rather than for the
  build they would have recommended.
- **36 GB — the reference, and honestly at the edge.** It works. It works after
  you close things. Section 10 says this plainly, because it is not a failure on
  your part.
- **48 GB and above — you stop negotiating with your own Mac.** At 64 GB the
  quality-versus-memory trade disappears and the 8-bit build becomes the sensible
  choice.

---

## 7. Set your Mac's numbers, if it is not a 36 GB machine

Every value in `bin/env.sh` can be overridden. Nothing is hard-coded into the
scripts. There are two ways to do it, and the second is better for most people.

**Precedence, from strongest to weakest:** a variable set in your Terminal beats a
line in `config.env`, which beats what `bin/detect-hardware.sh` measured about
your Mac, which beats the built-in default in `bin/env.sh`.

**You do not normally need to set the memory numbers at all.** `CTX_SIZE`,
`MIN_FREE_GB`, `MAX_RESIDENT_MEM` and `PREFIX_CACHE_MEM` are worked out from your
Mac's own memory size and from the model you actually have selected. Changing
`CTX_SIZE` alone re-works the other three to match it, so you cannot
accidentally leave the guard sized for a window you are no longer using; and
selecting a smaller model with `./bin/models.sh use` shrinks the guard to that
model rather than demanding room for a 27B that is not being loaded.

**Option A — one run only.** Put the setting in front of the command. It applies
to that run and nothing else.

This starts the server once with a smaller conversation window, without changing
any file.

```bash
CTX_SIZE=32768 ./bin/serve.sh
```

You should see something like this:

```
memory   24.3 GB available (need 22 GB) — ok
```

Both numbers are yours. The second is recomputed for the window you asked for.

Output trimmed — the full startup banner is shown in
[05 — run it](05-run-it.md). If you see `REFUSING TO START` instead, that is
Section 9, and it is the guard working correctly.

**Option B — make it permanent.** Copy the example settings file once, then edit
the copy. This is the better route if you are not comfortable with Terminal, since
you edit one commented text file instead of remembering variable names.

This creates your own settings file from the example. Run it from the repository
folder.

```bash
cp config.env.example config.env
```

You should see something like this:

```
(no output)
```

This prints nothing. That is success. Open the new `config.env` in any text editor,
remove the `#` in front of the lines you want, and change the values. `config.env`
is ignored by git, so your settings are never uploaded anywhere.

If you see `cp: config.env.example: No such file or directory`, you are not in
the repository folder. Repeat the `cd` in Section 4.

---

<a id="wired-limit"></a>
## 8. Wired memory — the one genuinely dangerous thing

Everything up to here has been about being slow or being refused. This section is
about the only setting that can force you to hold down the power button.

Some memory is **wired** (see [Glossary](09-glossary.md#wired-memory)). Wired
memory is locked in place. macOS cannot compress it, cannot move it to disk, and
cannot take it back under pressure. It is either there or the machine is stuck.

> **Think of it like** furniture bolted to the floor of a small room. Everything
> else can be shuffled around or carried out when you need space. The bolted-down
> pieces cannot. Bolt down too much and there is no floor left to stand on.
> **Where the comparison stops:** you can unbolt furniture. Wired memory is only
> released when the program that wired it exits.

Memory the graphics processor uses for a model is wired. macOS therefore enforces
a ceiling on how much of the pool can be wired for graphics work. That ceiling is
a system setting named `iogpu.wired_limit_mb` (see
[Glossary](09-glossary.md#iogpu-wired-limit-mb)).

By default the setting reads `0`, which means "let macOS choose". macOS chooses
roughly two thirds of your memory at 32 GB and below, and roughly three quarters
above that. On the test machine that automatic value is about 27 GB out of 36 GB,
leaving about 9 GB that can never be taken by the graphics processor.

This checks the current value. It changes nothing.

```bash
sysctl -n iogpu.wired_limit_mb
```

You should see something like this:

```
0
```

`0` is the correct value and the one this repository recommends. If you see a
number such as `30720`, someone raised it — possibly an older version of these
instructions. Read the warning block below, then set it back to `0`.

If the command prints `sysctl: unknown oid`, your Mac does not expose this
setting. Nothing is wrong. Skip this section.

### Why raising it is usually the wrong advice

Guides all over the internet tell you to raise `iogpu.wired_limit_mb` so a bigger
model fits. That advice is popular because it appears to work, and it is wrong for
this stack for three reasons.

1. **This configuration does not need it.** The peak the arithmetic in Section 3
   gives for the test machine is about 23 GB, and the automatic ceiling there is
   about 27 GB. There is already headroom. Raising the ceiling does not make the
   model smaller.
2. **What you take, you take from macOS.** Raising the ceiling to 30 GB on a 36 GB
   Mac leaves macOS about 6 GB of memory it can never reclaim. macOS is not a
   background process. The window server, the file system, and every driver live
   in that remainder.
3. **It is the actual hard-failure path.** A model that will not fit under the
   ceiling gets refused, which is recoverable. A macOS that cannot get memory it
   cannot reclaim has no fallback available.

The temptation is strongest on exactly the machines with the least room: 24 GB and
32 GB. That is the worst place to take the risk.

> ### WARNING — this command changes a macOS system setting
>
> Only run the command below if `sysctl -n iogpu.wired_limit_mb` printed something
> other than `0` and you want to restore the default.
>
> - **What it changes on your Mac.** The ceiling on how much memory the graphics
>   processor may lock. Setting it to `0` returns control to macOS.
> - **Is it reversible?** Yes, completely. Running it with a different number
>   changes it back. It affects no files and no data.
> - **A restart also reverts it.** This setting is never saved to disk. Every
>   reboot returns it to `0` on its own. If you are unsure, restart instead of
>   running the command.
> - **It asks for your password.** `sudo` means "run this as the administrator".
>   Terminal will not show the characters as you type. That is normal.
> - **What happens if a wired limit is set too high.** The Mac does not show an
>   error. It stalls. The pointer stops moving, the fans spin up, and the screen
>   stops redrawing. You may have to hold the power button to restart. Nothing on
>   your disk is damaged, but unsaved work in open apps is lost.
> - **Why you might skip this entirely.** If the value is already `0`, there is
>   nothing to do. Leave it at `0` unless you have measured a specific reason not
>   to. This repository has no such reason.

This returns the graphics memory ceiling to the macOS default.

```bash
sudo sysctl iogpu.wired_limit_mb=0
```

You should see something like this:

```
iogpu.wired_limit_mb: 30720 -> 0
```

The first number is whatever it was before, so yours will differ. If you see
`sysctl: oid 'iogpu.wired_limit_mb' is read only`, your macOS version does not
allow the change. Restart the Mac; the reboot resets it.

`bin/serve.sh` checks this value at startup and prints a warning whenever it is
not `0` — a sharper one when it is above 80% of your Mac's memory. That warning
does not stop the server. It is there so a setting you made months ago cannot
quietly cause trouble today.

---

## 9. What actually breaks a Mac, and what only annoys it

The conclusion to draw from this table: of the four ways this can go wrong, three
are inconvenient and one is dangerous, and the dangerous one is the only one you
control by hand.

| What happens | How bad | Why it happens | What prevents it |
|---|---|---|---|
| The Mac stalls and needs a forced restart | **Dangerous** | Wired graphics memory starves macOS of memory it cannot reclaim | Leaving `iogpu.wired_limit_mb` at `0`, plus `MAX_RESIDENT_MEM=21GB` |
| The Mac becomes very slow | Recoverable | Total demand exceeds memory, so macOS moves pages to disk | The free-memory check in `bin/serve.sh` |
| The server refuses to start | Harmless | The free-memory check found less than `MIN_FREE_GB` | **This is the good outcome.** Nothing broke. |
| macOS shuts the server down on its own | Harmless | macOS ends the largest program when memory runs out — that is the server, not your editor | `MAX_RESIDENT_MEM=21GB` keeps the server from becoming that large |

Only the first row can cost you unsaved work. It is the only row that requires a
manual change to a system setting. Do not make that change.

---

## 10. The guards this repository installs

You do not have to remember Sections 2 through 9. The scripts enforce them. Here
is what each guard is and where to read it.

**1. The server refuses to start when memory is short.** `bin/serve.sh` reads
available memory the way Section 5 describes, compares it to `MIN_FREE_GB`
(default `22`), and stops before loading anything. It also lists the largest
programs currently running, so you know what to close.

**STOP — this is the message, and it means do not continue:**

```
REFUSING TO START — not enough free memory.
  available : 10.5 GB
  required  : 22 GB (weights ~19.1 GB + conversation + prefix cache)

Free some memory, then retry. Biggest wins, in order:
    2.7 GB  com.apple.Virtualization.VirtualMachine
    1.0 GB  Arc Helper

Docker Desktop is a common one — 'docker desktop stop' frees its whole VM.
Override with MIN_FREE_GB=0 if you know what you are doing.
```

The program names and sizes will be different on your Mac. The fix is in
Section 11. Full entry:
[06 — troubleshooting](06-troubleshooting.md#not-enough-memory).

**2. The model is handed back when you stop using it.** `IDLE_EVICT_SECS=900`
means: after 15 minutes with no requests, the server releases the model and
returns about 19.1 GB to macOS. The next request reloads it, which takes about a
minute. This is the single most useful setting for running the model on a Mac you
are also working on. Set `IDLE_EVICT_SECS=0` to keep the model in memory instead.

**3. A hard ceiling on the model itself.** `MAX_RESIDENT_MEM=21GB` is set
explicitly rather than derived from the graphics memory ceiling. The budget stays
where you put it even if that system setting changes.

**4. Only one copy, ever.** This takes two separate mechanisms, because they
stop two different things.

`MAX_RESIDENT_MODELS=1` stops one server from holding two models at once. It is
a limit *inside* a single server, so it says nothing at all about a second
server — that is a different program with its own separate limit.

The second server is the one that actually happens: a `./bin/serve.sh` in a
Terminal window you forgot was open. Nothing else in this stack catches it. The
free-memory check in guard 1 is a single reading taken before anything is
loaded, and guard 2 makes that reading *worse*: after 15 minutes of silence the
first server has already handed its memory back, so the memory really is free —
right up until the second server loads and it is not.

So there is a **model lock**. Only one process on this Mac may hold the weights,
and the second one refuses instead of loading:

```
REFUSING TO START — something else on this Mac is already holding the weights.
  holder : pid 41207 — serve.sh, port 11234
  lock   : /Users/<YOUR_USER_NAME>/.airgap/model.lock
```

The `holder` line names the process, so you can find the window it is running
in. `./bin/stop.sh` ends it. `./bin/doctor.sh` reports whether the lock is free,
held, or left behind by something that crashed — and a lock whose process is
gone is taken over rather than obeyed, so a crash can never leave this Mac
unable to start a server. Full entry:
[06 — troubleshooting](06-troubleshooting.md#model-lock).

**5. Smaller spikes while reading a long prompt — sized by the server, not by
this repository.** The server reads a long prompt in pieces and picks the piece
size when it starts, from the memory free at that moment, the context size and
the resident cap, printing what it chose in its log. This repository used to
pin that to 4096; on the test machine the server picks 512 or 1024 for itself,
and the temporary spike while reading a 16,000-token prompt was 0.7–1.1 GB
there against 2.6 GB pinned (MEASURED, 9B, [07 §10](07-tuning.md#bench)). `PREFILL_CHUNK=` still pins it, and the server still
caps a pinned value lower when it would not fit.

**6. A stop button.** `./bin/stop.sh` ends the server and reports how much memory
came back. It is safe to run when nothing is running.

**7. The server's own safety check, left switched on.** The server has an internal
memory check of its own. **Never pass `--skip-mem-preflight`.** That check is what
turns a hard crash into the clean refusal in guard 1.

---

## 11. Running it safely, step by step

### Step 1 — free memory before you start

Container tools are usually the largest single win, because they run a whole
virtual machine. Skip this step if you do not use Docker.

This stops Docker Desktop's virtual machine and returns its memory. Your
containers and images are not deleted.

```bash
docker desktop stop
```

You should see something like this:

```
Docker Desktop is stopping...
```

If you see `command not found: docker`, Docker is not installed, and there is
nothing to stop. Move to the next step.

Then quit your browser. Browsers spread their memory across many helper processes,
so quitting the whole app frees far more than closing tabs.

### Step 2 — CHECKPOINT: confirm you have enough memory

**Stop here. Do not start the server until this check passes.**

This reports how much memory macOS could hand to the server right now. Run it from
the repository folder.

```bash
bash -c 'source bin/env.sh && echo "$(available_gb) GB available"'
```

You should see something like this:

```
24.3 GB available
```

You need at least the **Free memory needed** value for your machine from the table
in Section 6. On a 36 GB Mac that is **22 GB**.

If the number is lower, go back to Step 1. Close more. Re-run this command. Do not
lower `MIN_FREE_GB` to get past this check — that setting exists to protect the
machine you are typing on.

### Step 3 — start the server

Read the whole checklist above before running this. This command loads about
19.1 GB into memory and keeps it there. Your Mac will feel loaded while it runs.
The server runs in the foreground; press Control-C to stop it.

```bash
./bin/serve.sh
```

You should see something like this:

```
memory   24.3 GB available (need 22 GB) — ok
model    /Users/<YOUR_USER_NAME>/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
endpoint http://127.0.0.1:11234   (Anthropic: http://127.0.0.1:11234/v1/messages)
context  65536 tokens, kv-quant turbo4
budget   weights<=21GB, prefix 1536MB, idle-evict 900s
timeout  300s without a token before a question is given up on
log      ~/.mlx-serve/logs/mlx-serve-11234.log
```

The file path on the `model` line is yours and will differ.

If you see `REFUSING TO START` instead, go back to Step 1. If you see
an error naming a file and the words `is still a git-lfs pointer`, the download
did not finish — see
[06 — troubleshooting](06-troubleshooting.md#lfs-pointers).

### Step 4 — treat the Mac as loaded while it runs

This is a 27-billion-parameter model taking more than half of a 36 GB machine. It
is not a background process. Expect to keep containers and heavy browsers closed
for the whole session.

---

## 12. If your Mac becomes sluggish anyway

First, stop the server. This is always the first move, and it is always safe.

```bash
./bin/stop.sh
```

You should see something like this:

```
stopped.
memory: 12.4 GB -> 31.8 GB available
```

Both numbers will differ on your Mac. If it prints
`nothing running on port 11234.`, the server was already down and the problem is
something else.

Then confirm the memory came back.

```bash
memory_pressure
```

You should see something like this:

```
The system has 38654705664 (2359296 pages with a page size of 16384).

Stats: 
Pages free: 1305223 
Pages purgeable: 25760 
Pages purged: 509790381 
```

Output trimmed. `Pages free` should be much larger than before you ran
`./bin/stop.sh`.

**If Terminal itself responds slowly, the Mac is moving memory to disk, not
frozen.** Wait 30 seconds. It recovers on its own. This is uncomfortable and it is
not damage.

**If the pointer stops moving entirely and nothing responds for minutes**, that is
the wired-memory case from Section 8. Hold the power button to restart. The
restart resets `iogpu.wired_limit_mb` to `0` by itself, so the same failure will
not repeat unless something sets it again.

Full entry: [06 — troubleshooting](06-troubleshooting.md#mac-sluggish).

---

## 13. If your Mac stays too tight

A 27-billion-parameter model at 5-bit on a 36 GB Mac is at the edge of what the
machine supports. If it does not fit comfortably, that is the hardware, not you.

Options, best first.

1. **Use the 4-bit build instead of the 5-bit build.** About 16 GB instead of
   19.1 GB, so you get nearly 4 GB back. That is the difference between "close
   everything" and "works next to a browser". The answers are slightly worse, and
   the difference is smaller than most people expect. (Weight size NOT YET
   MEASURED in this repository.) `./bin/models.sh pull 27b-4bit` then
   `./bin/models.sh use 27b-4bit`.
2. **Lower the context window.** Set `CTX_SIZE=32768`. It saves about 0.5 GB and
   costs nothing else. Small, but free.
3. **Use a smaller model for everyday work.** This is where most people land.
   The 9B in the catalog (`9b-4bit`, 4.7 GB) coexists with a normal set of open
   apps and needs about 11 GB free on a 36 GB Mac. It will feel far better in an
   interactive loop than a 27B model that forces you to close your browser. Keep
   the 27B for the tasks that need it; both stay on disk and
   `./bin/models.sh use` switches between them.
4. **More memory.** Not useful advice today, but for planning: the 27B at 5-bit
   wants 48 GB to be comfortable and 64 GB to be unremarkable.

---

## How to know it worked

- `sysctl -n iogpu.wired_limit_mb` prints `0`.
- The available-memory one-liner prints at least the **Free memory needed** value
  for your row in Section 6.
- The first line `./bin/serve.sh` prints starts with `memory` and ends with
  `— ok`, rather than reading `REFUSING TO START`.
- `./bin/doctor.sh` prints `PASS` on the `memory` and `wired limit` lines.

## How to stop

This ends the server and returns the memory. Run it from the repository folder.

```bash
./bin/stop.sh
```

You should see something like this:

```
stopped.
memory: 12.4 GB -> 31.8 GB available
```

The second number should be close to what you had before you started. If it is
not, something else on your Mac took the memory in the meantime.

## How to undo everything

- **Return the graphics memory ceiling to default:** `sudo sysctl
  iogpu.wired_limit_mb=0`, or restart the Mac, which does the same thing.
- **Return your settings to the repo defaults:** delete `config.env` from the
  repository folder. `bin/env.sh` then uses its built-in values again.
- **Reclaim the disk space:** delete the model folder inside the repository. It is
  about 20 GB after the download finishes cleaning up, and it is the only large
  thing this project puts on your disk. See
  [03 — get the model](03-get-the-model.md).
- Nothing in this document writes to any file outside the repository folder, and
  nothing survives a restart except the model folder itself.

## What this will not do

- It will not make a 27B model fit on a 16 GB Mac. No setting on this page
  changes that; the 9B in the catalog is what fits there.
- It will not stop macOS from slowing down when you run a model that takes more
  than half your memory. It only stops the slowdown from becoming a stall.
- It will not protect you if you raise `iogpu.wired_limit_mb` by hand and then
  load a model that does not fit under the new ceiling. That path is outside every
  guard in this repository, which is why Section 8 recommends against it.
- It will not tell you how fast the model will run on your Mac. Speed depends on
  your chip's graphics cores, and no speed figure for the 27B has been measured
  on any machine.

---

**Next:** [05 — run it](05-run-it.md). That is where the server starts and Claude
Code connects to it.
