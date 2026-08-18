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
setting takes seconds. The benchmark in Section 10 takes a couple of minutes and
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
`~/dev/local-llms/airgap`; use your own path if it differs.

```
cd ~/dev/local-llms/airgap
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

You should see a report ending in five recommended settings — the build it
picks for you, and the four memory numbers. Every line is specific to your Mac. The output is described in
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
architecture at `turbo4`**. The 9B in the catalog has the same layer pattern with
half as many layers, so it costs half; an ordinary dense model, where every layer
holds a growing cache, costs several times more; and Section 3's `KV_QUANT=8` and
`KV_QUANT=off` cost two and four times this. The scripts do not carry the formula
— they read the growing-layer count, the kv-heads and the head size from the
selected checkpoint's own `config.json` and scale by `KV_QUANT`, so the memory
guard's `MIN_FREE_GB` and the GPU-ceiling refusal follow the model you actually
selected and the setting you actually chose. `./bin/verify-model.sh` prints the
figure it read on its `kv` line.

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

**There is a ceiling on this setting, and it is the model's, not ours.** Every
checkpoint states its own maximum in `config.json` as `max_position_embeddings`
— 262,144 for the Qwen3.8 builds, and less for many other models you could point
`MODEL_DIR` at. `./bin/serve.sh` reads it and **refuses** above it:

```
REFUSING TO START — CTX_SIZE is larger than this model's own maximum.
  CTX_SIZE      : 999999 tokens
  model maximum : 262144 tokens (Qwen3.8-9B-mlx-4Bit/config.json)
```

Without that refusal the number still had effects: it raised `MIN_FREE_GB` for a
window nothing would ever hold, could trip the GPU-ceiling guard for a reason
that was not the real one, and otherwise failed one request at a time once the
server was up. `./bin/doctor.sh` reports the same comparison in its `context`
row before you get there.

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

At the default 65,536-token window this raises the cache from 1.0 GB to 2.0 GB,
and `MIN_FREE_GB` — the free memory `serve.sh` insists on — rises with it, so a
Mac that cannot spare the extra is refused rather than stalled. If yours is,
lower `CTX_SIZE` in the same command:

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
| `IDLE_EVICT_SECS` | 900 | Seconds of silence before the memory goes back to macOS | Section 8. |
| `SERVE_TIMEOUT` | 300 | Seconds a question may produce **nothing** before it is given up on | A cold first turn is being cut off. Not a length limit. |
| `LOCK_DIR` | `~/.airgap/model.lock` | Where the lock that stops two model loads lives | Almost never. Empty switches the lock off. |
| `PREFILL_CHUNK` | empty — the server sizes it | How much text is read at a time on the first pass. Empty lets the server pick from the memory free when it loads (512 or 1024 on the test machine with the 9B, printed in its log). | Almost never. Pin it to reproduce a shape in `bench.sh`. Section 13. |
| `NO_VISION` | 1 | Skips loading the image-reading part | Only to feed the model pictures. |
| `LEAN_MCP` | 1 | Starts Claude Code with optional tool servers off | Section 6. |
| `MAX_THINKING_TOKENS` | unset — thinking on | `0` turns the model's thinking off; 3x faster on the one prompt measured, quality cost not measured | You want speed and will judge the answers yourself. Section 7. |
| `MODEL_QUANT` | worked out from your memory | Which OrcaRouter build: `4bit`, `5bit`, `6bit`, `8bit` | Section 9. |
| `MODEL_REPO` | worked out from your memory | Which model, by its huggingface.co address — any build, catalog or not | Section 9, or `./bin/models.sh use`. |
| `METRICS` | 1 | Publishes speed and cache counters | Leave it on. Section 11. |
| `EXTRA_ARGS` | empty | Passed to the server exactly as typed, last | A setting this repository has not named. Section 12. |

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
instructions were not re-read. To see the same evidence from your own server,
run `./bin/doctor.sh` while it is up — its `prefix cache` and `/metrics.json`
lines are that log line and the server's counters, read for you
([05 — Run it, §7d](05-run-it.md#7d-the-repeated-instructions-are-remembered-not-re-read)).

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

## 7. <a id="thinking"></a>Turning thinking off — the biggest speed lever after the cache

Every build in the catalog thinks before it answers — the 27B at its highest
effort — and Claude Code asks for that on every request. Thinking makes the
answer better on hard problems and slower on all of them. `MAX_THINKING_TOKENS`
is Claude Code's own name for the setting; `claude-local.sh` passes it through,
checks it is a whole number, and says on its banner which way it is set.

```
MAX_THINKING_TOKENS=0 ./bin/claude-local.sh
```

You should see the banner's `thinking` line read `OFF (MAX_THINKING_TOKENS=0)`.

MEASURED on the test machine, the 9B, one prompt (*"What is 17\*23? Think step
by step."*, temperature 0, `max_tokens` 3000, `mlx-serve` 26.8.8), single
samples:

| | Output tokens | Wall | Answer |
|---|--:|--:|---|
| Thinking on (unset — the default) | 1156 | 20.9 s | correct |
| `MAX_THINKING_TOKENS=0` | 376 | 7.2 s | correct, complete |

Through Claude Code itself (`2.1.234`, `-p`, the same question), the server's
log shows `thinking=false` with `0` and `thinking=true` otherwise, and 3 output
tokens against 47 — the request really changes; this is not a client-side trim.

**Three things to know before you set it.**

- **The quality cost is not measured** — not on the 9B, not on the 27B. Turning
  off the way the model reasons is a large change in how it behaves, not a
  tuning nudge. Try it on your own work before trusting it; the default stays
  on for that reason.
- **A positive number does not make anything faster.** Claude Code sends it as
  a *budget*, and the model reasons to the answer regardless: MEASURED, 128,
  1024 and unset all produced 1156 tokens in ~21 s. What a positive value does
  is cap the thinking text Claude Code stores and replays into later turns,
  which slows the growth of the context — a second-order saving.
- **The server has a `--reasoning-budget` flag. It does nothing here**, and
  `serve.sh` will not grow a setting for it: Claude Code's request-level budget
  overrides it on every real turn, and even when it applies it trims the
  returned text after the fact. MEASURED, and recorded in `AGENT.md` so it is
  not tried again.

To make it permanent, `MAX_THINKING_TOKENS=0` in `config.env`.

---

## 8. Getting your Mac back between questions

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

## 9. Moving to a different build of the model

The publisher offers the same checkpoint at 4, 5, 6 and 8 bits, and the catalog
in `bin/catalog.sh` adds a 9B, a 2-bit and an AEON 27B, and the stock
`mlx-community` 27B. Fewer bits means a smaller file and slightly lower
quality; this is **quantization** ([Glossary](09-glossary.md#quantization)).

| Build | Weights in memory, text only | Suits |
|---|---|---|
| `27b-4bit` | about 16.3 GB | 32 GB Macs |
| `27b-5bit` | about 19.1 GB (MEASURED) | 36 and 48 GB Macs — the tested build |
| `27b-6bit` | about 23 GB (download size; not known separately) | 48 GB Macs with memory to spare |
| `27b-8bit` | about 27.7 GB | 64 GB Macs and larger |
| `9b-4bit` | about 4.7 GB (MEASURED) | anything under 32 GB, and everyday work next to a browser |

Only the 5-bit and 9B figures were measured on the test machine. The 4-bit and
8-bit figures were computed from the file sizes the publisher lists on
huggingface.co, and are PUBLISHER-REPORTED. `./bin/models.sh list` prints every
build with the free memory it needs on your Mac.

If you have 64 GB or more and downloaded 5-bit first, 8-bit is a real quality
improvement and worth the second download. The short way is three commands:

```
./bin/stop.sh
./bin/models.sh pull 27b-8bit
./bin/models.sh use  27b-8bit
```

`use` writes a `MODEL_REPO` line into `config.env` and removes any `MODEL_DIR`
or `MODEL_QUANT` line that would override it. The long way is to put
`MODEL_QUANT=8bit` in `config.env` yourself (remove the `#` in front of it) and
run `./bin/download-model.sh`; you should see a `repo` line ending in `-8bit`
and a `target` line naming a new folder ending in `-8bit`.

Each build lives in its own folder, named after itself, so the name the server
answers to always describes what is really inside. Several builds can sit on
disk at once if you have the space; the settings decide which one runs.

**If you do not see that.** If `repo` still ends in `-5bit`, the `#` is still in
front of your `MODEL_QUANT` line, or you have a `MODEL_REPO` line further up the
file overriding it — `MODEL_REPO` always wins over `MODEL_QUANT`.

---

## 10. <a id="bench"></a>Measure the speed feature yourself

The model carries a small extra piece that guesses several of the next chunks of
text ahead of time, which the full model then checks in one pass. This is
**multi-token prediction (MTP)**
([Glossary](09-glossary.md#multi-token-prediction-mtp)), a form of **speculative
decoding** ([Glossary](09-glossary.md#speculative-decoding)).

The claim worth checking is not that it is faster. It is that the answer is
**identical** — that this is a pure speed gain and not a quality trade. In exact
arithmetic the algorithm guarantees that: it keeps only guesses the full model
would have written itself. A real implementation verifies in batches and can
drift in floating point, and `mlx-serve` is a closed binary, so this repository
does not assert identity — it **observes** it, one run at a time.
`./bin/bench.sh` runs the model twice with the randomness switched off, once with
the feature on and once with it off, and compares a fingerprint of each answer.
While it is at it, it keeps the two other figures mlx-serve prints — how fast
the prompt was read (prefill) and the peak memory — and puts the peak next to
the arithmetic the memory guard in
[04](04-memory-safety.md#the-total-on-the-test-machine) is built on. It loads the model with the same context size, KV format and
vision setting `./bin/serve.sh` uses, so that comparison is fair — with one
flag it cannot share unless you pin it: the server sizes its own prefill chunk
when it starts, and a one-shot load like this reads at the ceiling instead, so
the peak is an upper bound on the server's. The output says so and names the
`PREFILL_CHUNK=` that reproduces the server's shape.

**WHAT THIS CHANGES ON YOUR MAC.** It loads the selected model's weights into
memory — about 19.1 GB for the 5-bit 27B — twice, one after the other. It uses
the same free-memory rule `./bin/serve.sh` does and refuses to start below it.

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

You should see `stopped.` or `nothing is holding the weights`, then a line
showing the memory before and after. Then:

```
./bin/bench.sh
```

You should see something like this — this is a real run, MEASURED on the test
machine, of the 9B rather than the 27B:

```
memory   21.0 GB available (need 11 GB) — ok
model:  Qwen3.8-9B-mlx-4Bit (~4.7 GB)
prompt: Explain why speculative decoding produces output identical to standard...
tokens: 200, temp 0.0 (greedy — required for an exact-match comparison)
load:   --ctx-size 65536 --kv-quant turbo4 --no-vision   (the same as serve.sh)
chunk:  not pinned. A one-shot load reads at the server's 8192-token ceiling;
        the server itself sizes the chunk down to what is free, so the peak
        below is an upper bound on its. Its last run chose 1024 (from its log);
        PREFILL_CHUNK=1024 ./bin/bench.sh measures that shape.
This loads the model twice. Expect a wait with no output while it reads the disk.
The figures per run are the ones mlx-serve prints itself; the load is not in them.

── spec-on ─────────────────────────────────
  prompt      : 41 tokens, read at 201.224 tokens/s   (prefill)
  generated   : 200 tokens, at 36.746 tokens/s        (decode — the speed figure)
  peak memory : 4.779 GB
  output sha  : 5df6c56513eeea39
── spec-off ─────────────────────────────────
  prompt      : 41 tokens, read at 197.445 tokens/s   (prefill)
  generated   : 200 tokens, at 36.055 tokens/s        (decode — the speed figure)
  peak memory : 4.779 GB
  output sha  : 5df6c56513eeea39

── result ──────────────────────────────────
  outputs IDENTICAL  <- byte identity, observed on this run
  speed-up ~ 1.02x  (36.746 tokens/s with the speed features on, 36.055 off)
  prefill    201.224 tokens/s at 41 prompt tokens (speed features on)
             ^ at a prompt this short that is mostly per-call overhead, several
               times under the real rate. PROMPT_FILE=<file> measures a real one.
  peak       4.78 GB, the higher of the two runs — mlx-serve's own figure for its
             Metal buffers, a lower bound on the process (about 0.5 GB under it, measured)
  guard      counts weights ~4.7 GB + a full 65536-token conversation 1.00 GB = 5.70 GB
             for a load like this (arithmetic; MIN_FREE_GB=11 adds the prefix cache,
             which a one-shot run never fills). This run used 241 of those tokens: 0.00 GB.
  gap        +0.08 GB — peak minus weights minus the conversation actually used: the
             working set the arithmetic does not line-item. It grows with the prompt;
             a longer PROMPT_FILE= is how to see by how much.
```

Read that run honestly: the 9B ships no MTP head, and this prompt gives prompt
lookup nothing to copy, so the two speeds are the same within noise — which is
exactly what the two identical fingerprints and a ratio of 1.0 say. It is a
37-tokens-per-second figure for the 9B on an M3 Max, one short run, and nothing
more (an earlier 60-token run of the same script printed 57 — one short run is
not a stable figure, so always quote it with its prompt and token count). On an OrcaRouter 27B,
where the head exists, the publisher's own figures are 6.81 seconds against
10.15 seconds for the same answer — PUBLISHER-REPORTED, NOT YET reproduced on
the test machine. The interesting line is always the first of the result block:
`outputs IDENTICAL` — and what it says is that *this* run was byte-identical
(MEASURED, the 9B, every run so far). It is not a guarantee for the next run,
another build or another `mlx-serve`; that is exactly why the script checks
every time instead of the docs asserting it once.

The three figures per run are the ones mlx-serve prints after each run. Reading
the model off the disk is in none of them.

**The prefill figure is only worth quoting with a long prompt.** At the
built-in question it is mostly fixed per-call overhead, several times under the
real rate. `PROMPT_FILE=` makes the whole of a file the prompt — any document
from `docs/` is a fair stand-in for the ~21,000 tokens Claude Code sends on
every turn:

```
PROMPT_FILE=docs/08-how-it-works.md ./bin/bench.sh
```

MEASURED on the test machine with the 9B, `mlx-serve 26.8.8`, single samples,
same settings as above. The prefill chunk is the one flag a one-shot load does
not share with the server (the `chunk:` line above), so it is named on every
long-prompt row:

| prompt | prefill chunk | prefill | decode after it | peak memory | working set above weights + KV |
|---:|---:|---:|---:|---:|---:|
| 41 tokens | 4096 | 201 tokens/s | 36.7 tokens/s | 4.78 GB | +0.08 GB |
| 16,377 tokens (`docs/08`, 2026-08-17) | 4096, the old default | 374 tokens/s | 15.6 tokens/s | 7.52 GB | +2.56 GB |
| 16,377 tokens (2026-08-17) | 1024 | 285 tokens/s | 15.6 tokens/s | 6.06 GB | +1.11 GB |
| 16,408 tokens (`docs/08`, 2026-08-18) | 4096, pinned again | 309 tokens/s | 7.7 tokens/s | 7.535 GB | +2.58 GB |
| 16,408 tokens (2026-08-18) | not pinned: 8192, the one-shot ceiling | 594 tokens/s | 24.6 tokens/s | 9.52 GB | +4.57 GB |
| 16,408 tokens (2026-08-18) | 512, what the server chose that run | 430 tokens/s | 20.1 tokens/s | 5.63 GB | +0.72 GB |
| 16,416 tokens, **the server itself**, unpinned (2026-08-18) | 512, its own choice with 14.9 GB free at load | 483 tokens/s (`[prefill:` in its log) | — | not printed in serve mode | — |

Four things that table says, each on the 9B only. The prefill rate at a real
prompt is roughly double the short-prompt figure, and depth costs decode: the
same model wrote at 36.7 tokens/s after a 41-token prompt and 15.6 after a
16,377-token one. The peak grows far more than the conversation does, and it
is the chunk that sets it: the working set while reading a long prompt was
4.6 GB at the 8192 ceiling, 2.6 GB at 4096, 1.1 GB at 1024 and 0.7 GB at 512
— and 512 or 1024 is what the server sizes itself down to on this machine,
by what is free when it loads (14.9 GB free → 512, 19.5 GB → 1024, same
settings) — the peak reproduces to
the second decimal across days, the speed figures do not (374 then 309 at
4096, single samples on a shared machine, and `docs/08` grew 31 tokens in
between), and speed did not track the chunk (594 at 8192, 309 at 4096, 430 at
512), so the 24% cost once quoted for 1024 against 4096 was one pair of single
samples and these do not repeat it. What the numbers do support is that the
peak is chunk-bound and reproducible, and the rate is noisy. That is why
`PREFILL_CHUNK` is left empty and the server sizes it
([§13](#never)). And mlx-serve's `Peak memory` is its own accounting of its
Metal buffers: `footprint(1)` on the same process showed about 0.5 GB more, so
treat the printed peak as a lower bound. None of this has been measured on the
27B, whose working set is likely larger — see `AUDIT.md` A3.

**Every run ends as one row.** The last block `bench.sh` prints is the whole
run, tab-separated in a fixed column order — machine, runtime, model, load
shape, prompt, and every figure above. `ROW_FILE=bench/<chip>-<ram>gb.tsv
./bin/bench.sh` appends it to a file under [`bench/`](../bench/README.md), one
file per Mac, which is how a run from a Mac that is not the test machine
becomes evidence this repository can diff and plot instead of prose in an
issue. The reference machine's own rows are in `bench/m3-max-36gb.tsv`.

**If you do not see that.**

- `error: serve.sh is running on port 11234 — stop it first` — FIX THIS by
  running `./bin/stop.sh`.
- `REFUSING TO START — not enough free memory.` — **STOP.** Close what it lists,
  then run it again.
- `outputs DIFFER` — that is unexpected with the randomness off. Do not trust the
  speeds; the two answers are kept in a temporary folder the script names. See
  [06 — troubleshooting](06-troubleshooting.md#mtp-missing).

To measure a longer answer, put the token count in front:

```
TOKENS=400 ./bin/bench.sh
```

---

## 11. Reading the server's own counters

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
rather than quoted here. For the third one you do not need to read the page at
all: `./bin/doctor.sh` fetches the same counters (from `/metrics.json`, the
same data as one JSON document) and prints the prefix-cache figures on its
`/metrics.json` line, next to the biggest hit from the server's own log.
[05 — Run it, §7d](05-run-it.md#7d-the-repeated-instructions-are-remembered-not-re-read)
shows the two lines.

**If you do not see that.** `Connection refused` means the server is not running.
An HTTP 503 means `METRICS=0` — put `METRICS=1` back in `config.env`.

---

## 12. <a id="extra-args"></a>The escape hatch, and its limits

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

## 13. <a id="never"></a>Settings deliberately left alone

Reading this table is the fastest way to understand the design. The conclusion:
the two most-recommended settings on the internet are both wrong here.

| Setting | Why this repository does not use it |
|---|---|
| `--mtp` | This is a *different* feature with a similar name: it draws an extra guessing head for models built from many expert sub-models. This model has its own built-in guessing head, which is on by default and needs no flag. |
| `--drafter` | Runs a second, smaller model to do the guessing. Pointless when the model already carries a guessing head, and it costs a second model's worth of memory. |
| `sudo sysctl iogpu.wired_limit_mb=<large number>` | The single genuinely dangerous change in this area. Memory reserved this way **cannot be swapped out**, so raising the ceiling lets the model squeeze macOS itself, and a Mac that runs out of that memory stalls until you hold the power button. Apple's automatic value is the right one. [04 — memory safety](04-memory-safety.md#wired-limit) has the full argument. |
| `--skip-mem-preflight` | Turns a clear refusal into a stalled Mac. |
| Raising `MAX_RESIDENT_MODELS` | Loading two copies of a 19 GB model is how you fill a Mac in one step. |
| `--prefill-chunk` (`PREFILL_CHUNK`) | The server already sizes this when it starts — from the memory free at that moment, the context size and the resident cap — and prints what it chose: `Prefill chunk: N tokens (memory-sized down from 8192; --prefill-chunk overrides)` in its log. Until 2026-08-18 this repository pinned 4096, four to eight times the 512–1024 the server picks for itself on the test machine, and that cost 2.6 GB of working set against 0.7–1.1 GB for no speed the samples could show (MEASURED, 9B, [§9](#bench)). A pinned value is a ceiling the server still caps lower; an empty one is the server's own number, and the only reason to set it is to give `bench.sh` the server's shape. |

---

## 14. Full list of settings

Every setting this stack understands, with its default. All of them can go in
`config.env` or in front of a command. The commented file `config.env.example`
carries the same list with a longer explanation each.

**Which model**

| Name | Default |
|---|---|
| `MODEL_QUANT` | the OrcaRouter build: `4bit`, `5bit`, `6bit` or `8bit`; empty for any other model |
| `MODEL_REPO` | the catalog build `bin/detect-hardware.sh` picks for your memory — `chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-<MODEL_QUANT>` from 32 GB up, `keXjos/Qwen3.8-9B-mlx-4Bit` below |
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
| `LOG_FILE` | `~/.mlx-serve/logs/mlx-serve-<PORT>.log` (mlx-serve rotates it at 32 MB) |
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
| `SERVE_TIMEOUT` | `300` |
| `LOCK_DIR` | `~/.airgap/model.lock` |
| `PREFILL_CHUNK` | empty (the server chose `512` and `1024` for the 9B, by what was free at load) |
| `KV_QUANT` | `turbo4` |
| `NO_VISION` | `1` |
| `MAX_RESIDENT_MODELS` | `1` |

**Downloading**

| Name | Default |
|---|---|
| `MIN_DISK_GB` | worked out for the selected build: `45` for the 5-bit 27B, `20` for the 9B |
| `DEDUP` | `1` |

`MIN_DISK_GB` is the free disk `./bin/download-model.sh` insists on, and it is
computed rather than typed: the larger of the download's peak (two copies of
the download, until `git lfs dedup` reclaims one) and the steady state after it
(the weights plus `PREFIX_CACHE_DISK`), plus 5 GB of spare for macOS. The
download size is the input, not the loaded size the memory guards use — the
vision tower and the tokenizer files land on disk even though the server never
loads them. The same
function sizes the refusal `./bin/serve.sh` makes when the disk cannot hold the
prefix cache it is about to be told to write — `PREFIX_CACHE_DISK` + that same
5 GB, measured on the volume holding `~/.mlx-serve`. Lower the cache rather
than the guard: `PREFIX_CACHE_DISK=2GB`, or `0` to switch the disk tier off and
keep only the memory one.

**Claude Code**

| Name | Default |
|---|---|
| `LEAN_MCP` | `1` |
| `CLAUDE_BIN` | `claude` |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `8192` |
| `MAX_THINKING_TOKENS` | unset — thinking on, as the model ships; `0` turns it off (Section 7) |

**Tools and scripts**

| Name | Default | Used by |
|---|---|---|
| `PYTHON_BIN` | `python3` | `verify-model.sh`, `setup.sh` |
| `WITH_VENV` | `0` | `setup.sh` |
| `SKIP_BREW` | `0` | `setup.sh` |
| `PROBE` | `1` | `doctor.sh` |
| `TOKENS` | `200` | `bench.sh` |
| `PROMPT` | a fixed question | `bench.sh` |
| `PROMPT_FILE` | unset — a file whose whole contents are the prompt; overrides `PROMPT` | `bench.sh` |
| `ROW_FILE` | unset — a `.tsv` to append the run's row to (`bench/`) | `bench.sh` |

---

## How to know it worked

After changing a setting, the proof is in the server's own banner:

```
./bin/doctor.sh
```

You should see `doctor: OK` on the last line, and the `context` line showing the
context size you chose. `./bin/serve.sh`'s banner shows `context`, `budget` and
`log` for the settings actually in use.

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
rm ~/dev/local-llms/airgap/config.env
```

This prints nothing. That is success. Nothing else on your Mac is affected —
these scripts never change a macOS setting.

## What this will not do

No setting on this page makes a 27B model into a larger one. Raising `CTX_SIZE`
gives it more room, not more ability; raising `KV_QUANT` reduces one specific
kind of degradation, not all of them. The honest description of the ceiling is in
[01 — requirements](01-requirements.md#6-what-you-get-and-what-you-do-not).

No tokens-per-second figure has been measured for the 27B on any machine, so
this page does not print one for it. `./bin/bench.sh` measures a comparison on
your own Mac, which is the only speed number worth having; the 9B run above is
what that looks like.

---

**Read next:** [08 — how it works](08-how-it-works.md) for the engineering
behind every setting on this page, or
[09 — glossary](09-glossary.md) for any word that stayed unclear.
