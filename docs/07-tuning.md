# 07 — Tuning

**Who this is for.** Anyone whose setup already works and who now wants a longer
memory, better quality in long conversations, the optional tool servers back, or
a speed measurement. You do not need to know how any of it works; each setting is
explained in plain words before it is used.

**What you will have at the end.** A settings file of your own, an understanding
of which settings are worth changing and which are not, and the ability to
measure the speed feature on your own Mac rather than trusting a published
number.

**How long it takes.** About 15 minutes of your attention to read. Changing a
setting takes seconds. The benchmark in Section 9 takes a couple of minutes and
loads the model twice.

**What it costs.** Nothing to read. Some settings cost memory, and every one that
does says so. Nothing here sends anything over the network.

**What you need first.**

- [05 — run it](05-run-it.md) finished: the model answered a question.
- [04 — memory safety](04-memory-safety.md) read, because most of this page
  spends memory.

**If you only read one thing:** every memory setting is already worked out for
your Mac by `bin/detect-hardware.sh`. Run `./bin/detect-hardware.sh` and change
nothing unless a specific problem sends you here.

---

## 1. Where a setting comes from

Four sources, and the first one that has a value wins.

| Priority | Source | Example |
|---|---|---|
| 1 (highest) | What you type in front of the command | `CTX_SIZE=32768 ./bin/serve.sh` |
| 2 | Your `config.env` file | a line reading `CTX_SIZE=32768` |
| 3 | What your Mac was measured as | `bin/detect-hardware.sh` works it out |
| 4 (lowest) | The built-in default | `bin/env.sh` |

The conclusion to draw: a value you type on the command line always wins, and a
Mac larger or smaller than the test machine gets numbers that fit it without you
doing anything.

### To make a setting permanent

All commands on this page run from the repository folder. This puts your Terminal
window there. Throughout these documents that folder is written as
`~/dev/local-llms/qwen3.8free`; use your own path if it differs.

```
cd ~/dev/local-llms/qwen3.8free
```

This prints nothing. That is success.

**What this does.** It makes your own copy of the settings file. The copy is
listed in `.gitignore` ([Glossary](09-glossary.md#gitignore)) so it never goes
into version control, which matters because it can hold a password.

```
cp config.env.example config.env
```

This prints nothing. That is success. Now open `config.env` in any text editor.
Every setting is there, commented out, with its default and an explanation.
Remove the `#` from the front of a line to make it take effect.

**HONEST WARNING about that file.** `bin/env.sh` *runs* `config.env` as a shell
script rather than merely reading names and values out of it. Put nothing in it
except `KEY=value` lines and comments, and never paste a command you found on the
internet into it.

**If you do not see that.** `No such file or directory` means you are not in the
repository folder. Run the `cd` command above first.

### To see what your Mac was measured as

```
./bin/detect-hardware.sh
```

You should see a report ending in five recommended settings. Every line is
specific to your Mac. The output is described in
[01 — requirements](01-requirements.md#4-let-your-mac-answer-for-itself).

---

## 2. The one setting most people come here for: context size

`CTX_SIZE` is how much text the model can hold in mind at once, counted in
**tokens** ([Glossary](09-glossary.md#token)) — chunks of text, roughly three
quarters of an English word each. The whole amount is called the **context
window** ([Glossary](09-glossary.md#context-window)).

> **Think of it like** the size of a desk the model can spread papers on. A
> bigger desk means more of the conversation stays in view. **Where the
> comparison stops:** this desk is made of the same memory as everything else on
> your Mac, so a bigger one leaves less room for your browser.

The model's own maximum is 262,144 tokens. That is not the question. The question
is what fits alongside 19.1 GB of weights on your machine.

### <a id="kv-arithmetic"></a>What a bigger window actually costs

As you talk, the model keeps notes on everything said so far. Those notes are the
**KV cache** ([Glossary](09-glossary.md#kv-cache)), and they are what grows.

In this model they grow unusually slowly, and here is the plain version of why.
The model has 64 layers. **Only 16 of them keep growing notes.** The other 48
keep one fixed-size summary that is rewritten each time. So the cache costs a
quarter of what it would in an ordinary 64-layer model of the same size.

<details>
<summary><strong>For the curious: the exact arithmetic</strong></summary>

Read straight out of the checkpoint's own `config.json`:

- `num_hidden_layers`: 64
- `layer_types`: 48 entries reading `linear_attention`, 16 reading
  `full_attention`
- `full_attention_interval`: 4
- `num_key_value_heads`: 4
- `head_dim`: 256

Only full-attention layers hold a growing key/value cache. At 16 bits per number
that is:

```
16 layers x 2 (keys and values) x 4 heads x 256 numbers x 2 bytes
  = 65,536 bytes = exactly 64 KiB per token
```

This repository stores the cache at 4 bits instead of 16 — the setting
`KV_QUANT=turbo4`, Section 4 — so the real cost is **16 KiB per token**, and:

```
memory for the cache, in GiB = context size in tokens / 65,536
```

65,536 tokens therefore costs exactly 1.00 GiB. This formula is **exact for this
architecture and wrong for any other model**. Every smaller model named as a
fallback in [01 — requirements](01-requirements.md#ram-tiers) is an ordinary
dense model where all forty-odd layers hold a growing cache, so its per-token
cost is several times higher. Do not carry this formula across.

</details>

The conclusion to draw from this table: doubling the window costs about one more
gigabyte of cache, and the free memory the server demands goes up to match — but
less than one-for-one, because the scripts take some of it back out of the prefix
cache in Section 5.

| Context size | Cache memory | `MIN_FREE_GB` on the test machine | `PREFIX_CACHE_MEM` |
|---|---|---|---|
| 32,768 | 0.5 GB | 22 | 1792MB |
| 65,536 (the default here) | 1.0 GB | 22 | 1536MB |
| 131,072 | 2.0 GB | 23 | 1280MB |
| 262,144 | 4.0 GB | 24 | 768MB |

Those figures are what `bin/env.sh` works out on the 36 GB test machine, and you
can reproduce any row with
`CTX_SIZE=131072 bash -c 'source bin/env.sh && echo $MIN_FREE_GB'`. On your Mac
they differ, and you do not have to compute them: **changing `CTX_SIZE`
automatically re-works both the free-memory requirement and the prefix cache.**
Raising the window without raising the guard would leave the guard protecting a
configuration you are no longer running.

### To try a larger window once

```
CTX_SIZE=131072 ./bin/serve.sh
```

You should see the server's usual banner, with `context  131072 tokens` on the
`context` line and a larger number on the `memory` line's `need` figure.

**If you do not see that.** `REFUSING TO START — not enough free memory.` means
exactly what it says: the larger window needs more free memory and you do not
have it right now. Close more apps, or go back to the smaller window. That is the
guard working.
[06 — troubleshooting](06-troubleshooting.md#not-enough-memory).

### How much window do you actually get?

Less than the number suggests, because Claude Code spends some of it before you
type anything. MEASURED on the test machine with Claude Code 2.1.233:

| What | Tokens |
|---|---|
| Claude Code's own instructions, tool servers off | 20,909 |
| Claude Code's own instructions, tool servers loaded | 38,054 |

At the default 65,536-token window with tool servers off, that leaves roughly
44,000 tokens — about 33,000 English words — for your actual conversation and the
files it reads. With tool servers loaded it leaves about 27,000. Section 6 is
about that difference.

---

## 3. <a id="quality"></a>If answers get worse in long conversations

Try this before anything else on the page.

The running conversation is stored compressed, at four bits per number, using a
scheme called `turbo4`. That saves three quarters of the memory the notes would
otherwise take. It also loses a little accuracy, and the loss compounds as the
conversation grows.

To store it at eight bits instead — twice the memory, less loss:

```
KV_QUANT=8 ./bin/serve.sh
```

You should see the server's usual banner with `kv-quant 8` on the `context` line.

At the default 65,536-token window this raises the cache from 1.0 GB to 2.0 GB.
If your Mac cannot spare that, lower `CTX_SIZE` in the same command:

```
CTX_SIZE=32768 KV_QUANT=8 ./bin/serve.sh
```

**Change this before you change anything else.** It is the cheapest quality
setting in the whole stack. Full entry:
[06 — troubleshooting](06-troubleshooting.md#quality-degrades).

**If you do not see that.** If the server rejects the value, your version accepts
a different set of names; run `mlx-serve --help` and look for the `--kv-quant`
line.

---

## 4. The settings that matter, and what each one is for

Every one of these can go in `config.env` or in front of a command.

| Setting | Default on the test machine | What it does | Change it when |
|---|---|---|---|
| `CTX_SIZE` | 65536 | How much text the model holds at once | You keep running out of room. Section 2. |
| `KV_QUANT` | turbo4 | How the running conversation is stored | Answers get worse over a long conversation. Section 3. |
| `MIN_FREE_GB` | 22 | Free memory the server insists on before starting | Almost never. It is worked out from your Mac. |
| `MAX_RESIDENT_MEM` | 21GB | Hard ceiling on what the loaded weights may occupy | Almost never. |
| `PREFIX_CACHE_MEM` | 1536MB | Memory kept for remembering repeated instructions | You have memory to spare. Section 5. |
| `PREFIX_CACHE_DISK` | 10GB | The same thing on your SSD, so it survives a restart | Disk is short. Costs disk, not memory. |
| `IDLE_EVICT_SECS` | 900 | Seconds of silence before the memory goes back to macOS | Section 7. |
| `PREFILL_CHUNK` | 4096 | How much text is read at a time on the first pass | Your Mac spikes while reading a long file. |
| `NO_VISION` | 1 | Skips loading the image-reading part | Only to feed the model pictures. |
| `LEAN_MCP` | 1 | Starts Claude Code with optional tool servers off | Section 6. |
| `MODEL_QUANT` | worked out from your memory | Which build: `4bit`, `5bit`, `8bit` | Section 8. |
| `METRICS` | 1 | Publishes speed and cache counters | Leave it on. Section 10. |
| `EXTRA_ARGS` | empty | Passed to the server exactly as typed, last | A setting this repository has not named. Section 11. |

The four memory settings — `CTX_SIZE`, `MIN_FREE_GB`, `MAX_RESIDENT_MEM` and
`PREFIX_CACHE_MEM` — are worked out from your Mac's own size. On a 36 GB Mac they
come out as the values above. On a 48 GB Mac they come out larger. You only need
to set them by hand if you disagree with the result.

---

## 5. The prefix cache: the biggest speed win there is

Claude Code sends almost the same block of instructions — over 20,000 tokens of
them — at the start of every single turn. Reading a block of text into the model
is called **prefill** ([Glossary](09-glossary.md#prefill)) and it is the slow part
of a short reply.

The server keeps the processed form of that block, so an unchanged beginning is
not read again. That store is the **prefix cache**
([Glossary](09-glossary.md#prefix-cache)).

> **Think of it like** a bookmark in a long document you keep reopening at the
> same page. **Where the comparison stops:** the bookmark here stores the
> *result* of having read those pages, not just the position, so reopening them
> costs almost nothing.

**The evidence.** MEASURED on the test machine: on the second turn of a
conversation the server's own log printed
`[hot-cache] reused 16384/20906 tokens`. About four fifths of Claude Code's
instructions were not re-read.

There are two tiers. `PREFIX_CACHE_MEM` is the fast one and costs memory;
`PREFIX_CACHE_DISK` is the slower one on your SSD and costs only disk, but it
survives a restart of the server rather than being recomputed. The default here
is 1536MB of memory and 10GB of disk: memory is the scarce resource on a 36 GB
Mac, and the disk tier recovers most of the benefit for free.

If your Mac has memory to spare, raising the memory tier is the single most
useful thing you can do with it.

```
PREFIX_CACHE_MEM=3GB ./bin/serve.sh
```

You should see `prefix 3GB` on the banner's `budget` line.

**If you do not see that.** If the server refuses to start after this, you have
taken memory the free-memory guard was counting on. Lower the value.

---

## 6. <a id="mcp"></a>Turning the optional tool servers back on

**MCP** stands for Model Context Protocol
([Glossary](09-glossary.md#model-context-protocol-mcp)). MCP servers are optional
add-ons that give Claude Code extra tools — a database connection, a search tool,
and so on.

Each one describes its tools to the model, and those descriptions travel as part
of the instructions on **every single turn**, whether or not any tool is used.

MEASURED on the test machine with Claude Code 2.1.233:

| Setting | Claude Code's instructions, per turn |
|---|---|
| Tool servers loaded | 38,054 tokens |
| Tool servers off (`--strict-mcp-config`) | 20,909 tokens |

The conclusion: about **17,000 tokens of every turn** go to descriptions before
you have typed anything. On a 65,536-token window that is more than a quarter of
the model's whole capacity.

That is the only reason `LEAN_MCP=1` is the default. To turn them back on:

```
LEAN_MCP=0 ./bin/claude-local.sh
```

You should see the banner's `mcp` line read `your normal config (LEAN_MCP=0)`.

**If you do not see that.** If the line still says `strict`, you have
`LEAN_MCP=1` in `config.env`, which does not beat what you typed — check you
typed it in front of the command and not after it.

**Worth knowing before you do it.** A 27B model handles many tool descriptions
badly. It picks the wrong tool, or produces a malformed request. Turning these on
tends to cost quality as well as room.

---

## 7. Getting your Mac back between questions

`IDLE_EVICT_SECS` is the setting that makes this usable on a Mac you are also
working on. After that many seconds with no questions, the server hands the
model's memory back to macOS. The next question pays about a minute to read the
20 GB off disk again.

The default is 900 seconds — 15 minutes.

- **Set it to `0`** to keep the model in memory permanently. Every answer starts
  quickly, and 19.1 GB of your Mac is unavailable for anything else, all day.
- **Set it lower**, say 300, on a tight Mac where you switch between the model
  and other work often.

```
IDLE_EVICT_SECS=0 ./bin/serve.sh
```

You should see `idle-evict 0s` on the banner's `budget` line.

---

## 8. Moving to a different build of the model

The publisher offers three sizes of the same checkpoint. Fewer bits means a
smaller file and slightly lower quality; this is **quantization**
([Glossary](09-glossary.md#quantization)).

| Build | Weights in memory, text only | Suits |
|---|---|---|
| 4-bit | about 16.3 GB | 24 and 32 GB Macs |
| 5-bit | about 19.1 GB (MEASURED) | 36 and 48 GB Macs — the tested build |
| 8-bit | about 27.7 GB | 64 GB Macs and larger |

Only the 5-bit figure was measured on the test machine. The other two were
computed from the file sizes the publisher lists on huggingface.co, and are
PUBLISHER-REPORTED.

If you have 64 GB or more and downloaded 5-bit first, 8-bit is a real quality
improvement and worth the second download. To get it, put a line reading
`MODEL_QUANT=8bit` in your `config.env` (remove the `#` in front of it), then:

```
./bin/download-model.sh
```

You should see a `repo` line ending in `-8bit` and a `target` line naming a new
folder ending in `-8bit`.

Each build lives in its own folder, named after itself, so the name the server
answers to always describes what is really inside. Both builds can sit on disk at
once if you have the space; the settings decide which one runs.

**If you do not see that.** If `repo` still ends in `-5bit`, the `#` is still in
front of your `MODEL_QUANT` line, or you have a `MODEL_REPO` line further up the
file overriding it.

---

## 9. <a id="bench"></a>Measure the speed feature yourself

The model carries a small extra piece that guesses several of the next chunks of
text ahead of time, which the full model then checks in one pass. This is
**multi-token prediction (MTP)**
([Glossary](09-glossary.md#multi-token-prediction-mtp)), a form of **speculative
decoding** ([Glossary](09-glossary.md#speculative-decoding)).

The claim worth checking is not that it is faster. It is that the answer is
**identical** — that this is a pure speed gain and not a quality trade.
`./bin/bench.sh` runs the model twice with the randomness switched off, once with
the feature on and once with it off, and compares a fingerprint of each answer.

**WHAT THIS CHANGES ON YOUR MAC.** It loads about 19.1 GB into memory, twice, one
after the other. It uses the same free-memory rule `./bin/serve.sh` does and
refuses to start below it.

**IS IT REVERSIBLE.** There is nothing to reverse. It reads the model and prints
numbers. Press Control-C to stop it at any point.

**WHAT HAPPENS IF IT GOES WRONG.** Nothing beyond the machine being busy for a
couple of minutes. The memory returns when it finishes.

**WHY YOU MIGHT SKIP IT.** It is a curiosity, not part of the setup. Everything
works without it.

**CONFIRM FIRST** that the server is stopped — two copies of the model do not
fit, and the script refuses while the server holds the port.

```
./bin/stop.sh
```

You should see `stopped.` or `nothing running on port 11234.`, then a line
showing the memory before and after. Then:

```
./bin/bench.sh
```

You should see something like this:

```
memory   24.3 GB available (need 22 GB) — ok
prompt: Explain why speculative decoding produces output identical to standard...
tokens: 200, temp 0.0 (greedy — required for an exact-match comparison)
This loads about 20 GB twice. Expect a couple of minutes with no output.

── spec-on ─────────────────────────────────
  wall clock : 6.81s (includes ~20GB model load)
  output sha : 65966537xxxxxxxx
── spec-off ────────────────────────────────
  wall clock : 10.15s (includes ~20GB model load)
  output sha : 65966537xxxxxxxx

── result ──────────────────────────────────
  outputs IDENTICAL  <- speculative decoding is exact, as expected
  speedup ~ 1.49x (load time dilutes this; the decode-only gain is larger)
```

**The two times in that example are the model publisher's published figures, not
this repository's.** They are PUBLISHER-REPORTED and have NOT YET been reproduced
on the test machine. They are shown here only so you know the shape of the output.
Your own two times will differ, and the interesting line is the last-but-one:
`outputs IDENTICAL`.

Both times include reading 20 GB off disk, which makes the difference look
smaller than it is. The gain during the actual writing is larger, and this
repository has not measured it.

**If you do not see that.**

- `error: serve.sh is running on port 11234 — stop it first` — FIX THIS by
  running `./bin/stop.sh`.
- `REFUSING TO START — not enough free memory.` — **STOP.** Close what it lists,
  then run it again.
- `outputs DIFFER` — that is unexpected with the randomness off. Do not trust the
  timings. See [06 — troubleshooting](06-troubleshooting.md#mtp-missing).

To measure a longer answer, put the token count in front:

```
TOKENS=400 ./bin/bench.sh
```

---

## 10. Reading the server's own counters

With `METRICS=1`, which is the default, the server publishes counters while it
runs. This is worth doing when you want to know *why* something feels slow rather
than guessing.

**What this does.** It asks the running server for its current counters. The
server must be running.

```
curl http://127.0.0.1:11234/metrics
```

You should see many lines of `name value` pairs. The three worth finding:

- a **decode** rate — how fast text is being produced.
- a **draft acceptance** rate — what fraction of the guessed chunks survived the
  check. Higher means the guessing is paying off.
- a **prefix cache hit** rate — what fraction of the repeated instructions did not
  have to be re-read. Section 5 is about this one.

The exact names depend on the server version, which is why they are described
rather than quoted here.

**If you do not see that.** `Connection refused` means the server is not running.
A 404 means `METRICS=0` — put `METRICS=1` back in `config.env`.

---

## 11. <a id="extra-args"></a>The escape hatch, and its limits

`EXTRA_ARGS` is passed to the server exactly as you type it, after every other
setting. It exists for settings this repository has not given a name to.

```
EXTRA_ARGS='--some-flag value' ./bin/serve.sh
```

**Six flags are refused outright**, and `./bin/serve.sh` will not start if it
finds one there:

| Flag | Why it is refused |
|---|---|
| `--host` | Would move the server off `127.0.0.1`. See below. |
| `--lan-share` | Offers the model to your network. |
| `--lan-discover` | Advertises the model to your network. |
| `--skip-mem-preflight` | That check is what turns a stalled Mac into a message you can read. |
| `--no-mtp` | Switches off the guessing feature this setup exists for. |
| `--no-pld` | Switches off the repeat-detection feature. |

The first three are refused because **this model has had its refusal behavior
removed** ([Glossary](09-glossary.md#abliterated-model)) and the server has no
password unless you set one. It stays on this Mac. There is no setting that turns
this refusal off, and that is deliberate.

`./bin/bench.sh` passes `--no-mtp` and `--no-pld` once, on purpose, so there is
something to compare against. That is the only place in this repository where
they appear.

---

## 12. <a id="never"></a>Settings deliberately left alone

Reading this table is the fastest way to understand the design. The conclusion:
the two most-recommended settings on the internet are both wrong here.

| Setting | Why this repository does not use it |
|---|---|
| `--mtp` | This is a *different* feature with a similar name: it draws an extra guessing head for models built from many expert sub-models. This model has its own built-in guessing head, which is on by default and needs no flag. |
| `--drafter` | Runs a second, smaller model to do the guessing. Pointless when the model already carries a guessing head, and it costs a second model's worth of memory. |
| `sudo sysctl iogpu.wired_limit_mb=<large number>` | The single genuinely dangerous change in this area. Memory reserved this way **cannot be swapped out**, so raising the ceiling lets the model squeeze macOS itself, and a Mac that runs out of that memory stalls until you hold the power button. Apple's automatic value is the right one. [04 — memory safety](04-memory-safety.md#wired-limit) has the full argument. |
| `--skip-mem-preflight` | Turns a clear refusal into a stalled Mac. |
| Raising `MAX_RESIDENT_MODELS` | Loading two copies of a 19 GB model is how you fill a Mac in one step. |

---

## 13. Full list of settings

Every setting this stack understands, with its default. All of them can go in
`config.env` or in front of a command. The commented file `config.env.example`
carries the same list with a longer explanation each.

**Which model**

| Name | Default |
|---|---|
| `MODEL_QUANT` | worked out from your memory: `4bit`, `5bit` or `8bit` |
| `MODEL_REPO` | `chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-<MODEL_QUANT>` |
| `MODEL_DIR` | the repository folder, plus the name of `MODEL_REPO` |
| `MODEL_ID` | the last part of `MODEL_DIR` — the name the server answers to |

**The server**

| Name | Default |
|---|---|
| `HOST` | `127.0.0.1` — enforced, not merely suggested |
| `PORT` | `11234` |
| `API_KEY` | empty. Not a secret: a value here is visible to other accounts on this Mac. |
| `METRICS` | `1` |
| `LOG_LEVEL` | `info` |
| `LOG_FILE` | `~/.mlx-serve/logs/mlx-serve-<PORT>.log` |
| `EXTRA_ARGS` | empty |

**Memory and size** — all four worked out from your Mac

| Name | On the 36 GB test machine |
|---|---|
| `CTX_SIZE` | `65536` |
| `MIN_FREE_GB` | `22` |
| `MAX_RESIDENT_MEM` | `21GB` |
| `PREFIX_CACHE_MEM` | `1536MB` |
| `PREFIX_CACHE_DISK` | `10GB` |
| `IDLE_EVICT_SECS` | `900` |
| `PREFILL_CHUNK` | `4096` |
| `KV_QUANT` | `turbo4` |
| `NO_VISION` | `1` |
| `MAX_RESIDENT_MODELS` | `1` |

**Downloading**

| Name | Default |
|---|---|
| `MIN_DISK_GB` | `45` |
| `DEDUP` | `1` |

**Claude Code**

| Name | Default |
|---|---|
| `LEAN_MCP` | `1` |
| `CLAUDE_BIN` | `claude` |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `8192` |

**Tools and scripts**

| Name | Default | Used by |
|---|---|---|
| `PYTHON_BIN` | `python3` | `verify-model.sh`, `setup.sh` |
| `WITH_VENV` | `0` | `setup.sh` |
| `SKIP_BREW` | `0` | `setup.sh` |
| `PROBE` | `1` | `doctor.sh` |
| `TOKENS` | `200` | `bench.sh` |
| `PROMPT` | a fixed question | `bench.sh` |

---

## How to know it worked

After changing a setting, the proof is in the server's own banner:

```
./bin/doctor.sh
```

You should see `doctor: OK` on the last line, and the `context declared` line
showing the context size you chose. `./bin/serve.sh`'s banner shows `context`,
`budget` and `log` for the settings actually in use.

**If you do not see that.** A setting that appears not to have taken effect is
almost always priority: something further up the table in Section 1 is winning.
Check whether you typed it in front of the command, and whether `config.env` also
sets it.

## How to stop

`./bin/stop.sh` from the repository folder, or Control-C in the server's window.
The memory comes straight back and the command prints how much.

## How to undo everything

Delete `config.env`. Every setting returns to what your Mac was measured as.

```
rm ~/dev/local-llms/qwen3.8free/config.env
```

This prints nothing. That is success. Nothing else on your Mac is affected —
these scripts never change a macOS setting.

## What this will not do

No setting on this page makes a 27B model into a larger one. Raising `CTX_SIZE`
gives it more room, not more ability; raising `KV_QUANT` reduces one specific
kind of degradation, not all of them. The honest description of the ceiling is in
[01 — requirements](01-requirements.md#6-what-you-get-and-what-you-do-not).

No tokens-per-second figure has been measured for this model on any machine, so
this page does not print one. `./bin/bench.sh` measures a comparison on your own
Mac, which is the only speed number worth having.

---

**Read next:** [08 — how it works](08-how-it-works.md) for the engineering
behind every setting on this page, or
[09 — glossary](09-glossary.md) for any word that stayed unclear.
