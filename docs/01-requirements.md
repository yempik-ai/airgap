# 01 — Will this work on my Mac, and what will it feel like?

**Who this is for.** Anyone deciding whether to spend an evening on this. You do
not need to know how to program, what a model is, or what any technical word on
this page means. Every one of them is explained here before it is used, and
again in the [Glossary](09-glossary.md).

**What you will have at the end.** A clear yes or no about your own Mac, an
honest picture of what the result can and cannot do, and the numbers to expect
for disk, memory, and time. You will not have installed anything.

**How long it takes.** About 10 minutes of your attention. Nothing to download
and nothing to wait for. Every command on this page finishes in under a second.

**What it costs.** Nothing at all on this page. No disk space, no memory, no
money, and nothing leaves your Mac. The costs of the *whole* setup are listed in
[Section 5](#5-what-the-whole-thing-costs) below.

**What you need first.**

- A Mac, turned on.
- This repository folder on your Mac, if you want to run the two commands in
  [Section 4](#4-let-your-mac-answer-for-itself). See
  [02 — install](02-install.md) for how to get it. You can read this whole page
  without it.

**If you only read one thing:** read the table in
[Section 3](#ram-tiers). It answers the only question that matters before you
download 20 GB — does the model fit in your Mac's memory?

---

## 1. The two hard requirements

There are exactly two things your Mac must have. Everything else on this page is
advice; these two are not.

### <a id="apple-silicon"></a>1a. An Apple chip

Your Mac must have an Apple-designed chip. Apple calls this family **Apple
Silicon** ([Glossary](09-glossary.md#apple-silicon)). The chip names all start
with the letter M: M1, M2, M3, M4, and so on, sometimes followed by Pro, Max, or
Ultra.

Older Macs have an Intel chip instead. Those cannot run this. Neither can a
Windows PC or a Linux machine.

The reason is not stubbornness. The software that does the arithmetic here is
called **MLX** ([Glossary](09-glossary.md#mlx)), and Apple wrote it specifically
for the way Apple chips share memory between the main processor and the graphics
part. There is no version of MLX for any other chip, and there is no way to make
one work.

**How to check, without any commands.** Open the Apple menu at the top left of
your screen, then choose "About This Mac". Read the line labeled **Chip**.

- If it begins with "Apple M", you have an Apple chip. Continue.
- If it names an Intel processor, stop here. This will not work on your Mac.

Do not use the year your Mac was made to decide this. Apple sold Intel Macs
alongside Apple Silicon ones for years: the Intel 13-inch MacBook Pro was on sale
until 2022, and the Intel Mac mini and Mac Pro until 2023. The **Chip** line is
the only reliable answer.

**If you have an Intel Mac.** Nothing here will help you, and this repository has
no workaround to offer. Two honest alternatives exist, and neither is covered by
these documents: run a much smaller model on the processor with a program called
llama.cpp, or use a model hosted by somebody else over the internet.

### <a id="ram-tiers"></a>1b. Enough memory

The second requirement is memory, and it is the one that decides everything else.
Section 3 is entirely about it.

---

## 2. Why memory is the whole story

To answer a question, the model's numbers must all be in your Mac's memory at
once. Not most of them. All of them, for every single word it produces.

Those numbers are called the **weights**
([Glossary](09-glossary.md#weights)). For the version of the model this
repository uses by default, the weights are about **19.1 GB** — MEASURED on the
test machine by `./bin/verify-model.sh`, which adds up the sizes recorded inside
the files themselves.

19.1 GB is a hard number to feel. A rough comparison: it is about four
high-definition films, and all four have to be open on the desk at the same time,
not stored in a drawer.

> **Think of it like** a chef who needs every ingredient laid out on the counter
> before starting, because there is no time to walk to the pantry between steps.
> **Where the comparison stops:** the chef could work slowly with a small
> counter. The model cannot. If the weights do not fit, it does not run slowly —
> it does not run.

Memory on an Apple Silicon Mac is called **unified memory**
([Glossary](09-glossary.md#unified-memory)). The main processor and the graphics
part share one pool instead of each having its own.

> **Think of it like** one large desk that two people share, instead of two small
> separate desks. **Where the comparison stops:** these two "people" can hand
> work to each other with no copying at all, which two desks could never do.

This is why a 20 GB model runs on a laptop here and would need an expensive
separate graphics card on a Windows PC. It is also why the model competes
directly with your browser, your editor, and everything else you have open. There
is only the one desk.

---

## 3. <a id="the-table"></a>The table: what your Mac can do

Find your memory number first. Open the Apple menu, choose "About This Mac", and
read the line labeled **Memory**.

The conclusion to draw from this table: **36 GB is the machine this was tested
on, 48 GB and above is comfortable, 32 GB works with a smaller build of the
model, and below 32 GB you should run a different and smaller model instead.**

Two words in the table are worth knowing before you read it.

- A **context window** ([Glossary](09-glossary.md#context-window)) is how much
  text the model can hold in mind at once. It is counted in **tokens**
  ([Glossary](09-glossary.md#token)) — a token is a chunk of text, roughly three
  quarters of an English word. A 65,536-token window is therefore roughly 49,000
  English words. *Think of it like the size of the desk the model can spread its
  papers on.* Where the comparison stops: this desk costs memory, so a bigger one
  leaves less room for everything else.
- **4-bit**, **5-bit** and **8-bit** describe how heavily the model's numbers were
  compressed to save memory. The process is called **quantization**
  ([Glossary](09-glossary.md#quantization)) and Section 6 explains it. Fewer bits
  means a smaller file and slightly lower quality.

| Your memory | Verdict for a 27B model | Which build | Context window | Free memory the server asks for |
|---|---|---|---|---|
| 8 GB | Does not fit | none — run Qwen3-4B instead (about 2.3 GB) | — | — |
| 16 GB | Does not fit | none — run Qwen3-8B instead (about 4.5 GB) | — | — |
| 18 GB | Does not fit | none — run Qwen3-14B instead (about 8 GB) | — | — |
| 24 GB | Not recommended | 4-bit, about 16.3 GB | 16,384 | 18 GB |
| 32 GB | Tight | 4-bit, about 16.3 GB | 32,768 | 19 GB |
| 36 GB | Workable — the tested machine | 5-bit, about 19.1 GB | 65,536 | 22 GB |
| 48 GB | Comfortable | 5-bit, about 19.1 GB | 131,072 | 26 GB |
| 64 GB | Comfortable | 8-bit, about 27.7 GB | 131,072 | 36 GB |
| 96 GB or more | Comfortable | 8-bit, about 27.7 GB | 262,144 | 40 GB |
| Intel Mac, Windows, Linux | Not supported | — | — | — |

Every number in that table comes out of `bin/detect-hardware.sh`, which you can
run yourself. The last column is the setting named `MIN_FREE_GB`: the amount of
memory that must be free before `./bin/serve.sh` will agree to start.

### What each verdict actually means

**Does not fit.** The weights alone are larger than everything your Mac has.
There is no setting that changes this and no flag to force it. This repository
refuses to download the model on these machines, before the 20 GB rather than
after it. The smaller models named in the table are genuinely useful — a
Qwen3-8B on a 16 GB Mac will handle single-file edits well — they are just not
what these documents cover.

**Not recommended (24 GB).** Even the smallest build of this model, at about
16.3 GB, does not fit under the memory ceiling Apple reserves for the graphics
part on a 24 GB Mac, which is about 16 GB. `./bin/serve.sh` refuses to start
here, and the refusal is deliberate: the only way past it is to raise a macOS
setting that can make a Mac stop responding entirely. Section 8 of
[04 — memory safety](04-memory-safety.md#wired-limit) explains why. Run
Qwen3-14B instead.

**Tight (32 GB).** The 4-bit build runs. You will close your browser and Docker
Desktop first, most times. The setting that hands memory back to macOS between
questions matters more here than anywhere else, and it is on by default.

**Workable (36 GB).** This is the machine everything in this repository was
measured on: an Apple M3 Max, 30 graphics cores, 36 GB of unified memory, macOS
26.5.2. It works. You will still close memory-hungry apps first. See Section 4.

**Comfortable (48 GB and up).** You stop negotiating with your own Mac. At 64 GB
the 8-bit build fits, which is a real quality improvement over 5-bit and worth
the larger download.

### The two honest warnings about that table

**First: it predicts whether the model fits. It says nothing about speed.**
Speed depends far more on how many graphics cores your chip has than on how much
memory it has. An entry-level M4 with 32 GB and an M3 Max with 36 GB get similar
verdicts from that table and behave very differently. Only the 36 GB row
describes a machine anything was measured on. Every other row is arithmetic, and
is NOT YET MEASURED.

**Second: no speed figure exists at all.** This repository has not measured
tokens per second for this model on any machine, so it does not print one.
Anyone who quotes you a speed figure should tell you which Mac produced it.

---

## 4. <a id="4-let-your-mac-answer-for-itself"></a>Let your Mac answer for itself

Two commands. Both only read; neither changes anything, downloads anything, or
starts anything.

Both run from the folder you cloned this repository into. Throughout these
documents that folder is written as `~/dev/local-llms/airgap`. If you put it
somewhere else, use your own path.

### 4a. Move into the repository folder

This puts your Terminal window inside the folder that holds the scripts.
**Terminal** ([Glossary](09-glossary.md#terminal)) is the text window on your Mac
where you type commands instead of clicking buttons; open it from Applications,
then Utilities.

```
cd ~/dev/local-llms/airgap
```

This prints nothing. That is success.

**If you do not see that.** A message ending in `No such file or directory` means
the folder is somewhere else, or you have not copied the repository yet. Go to
[02 — install](02-install.md), Step 4.

### 4b. Ask the scripts what they make of your Mac

This reads your Mac's memory size, how much of it is free right now, and Apple's
graphics memory ceiling, then prints a recommendation.

```
./bin/detect-hardware.sh
```

You should see something like this:

```
chip           Apple M3 Max (30 GPU cores)
memory         36 GB total, 24.3 GB available now
compressor     8.3 GB  (pressure signal, NOT free memory)
wired ceiling  27.0 GB  (auto — GPU-wired memory cannot be swapped)

verdict        workable  --  The reference configuration. Fits, but you must close memory-hungry apps first.

recommended settings for this Mac:
  quant             5-bit  (~19.1 GB of weights, text-only)
  CTX_SIZE          65536   (KV cache 1.00 GB at turbo4)
  MIN_FREE_GB       22
  MAX_RESIDENT_MEM  21GB
  PREFIX_CACHE_MEM  1536MB

These are predictions about whether the model FITS. They say nothing
about how fast it will feel. Speed follows GPU cores, not memory, and
no speed figure has been measured on any machine but the test machine.
```

Every line will differ on your Mac except the last three, which are the same
everywhere. The `verdict` line is the one to read: it is the row from the table
in Section 3 that applies to you.

Two extra blocks may appear, and both are worth reading if they do:

- A block beginning `WARNING  weights + KV cache` means the model does not fit
  under Apple's graphics memory ceiling on your Mac. `./bin/serve.sh` will refuse
  to start. This is the 24 GB row.
- A block beginning `NOTE     only N GB is available right now` means the model
  fits in principle but not at this moment, because other apps are using the
  memory. It lists what to close. This is normal and Section 4c is about it.

**If you do not see that.** `command not found` or `Permission denied` means you
are not in the repository folder, or the file lost its permission to run. Run
`cd ~/dev/local-llms/airgap` again first. If that does not help, see
[06 — troubleshooting](06-troubleshooting.md).

### 4c. "36 GB total" is not "36 GB free"

This is the single most surprising fact on this page, so it gets its own section.

On the test machine — Apple M3 Max, 36 GB of unified memory, macOS 26.5.2 — a
normal working day left only about **10.5 GB actually available**, MEASURED. The
model needs 22 GB. It did not load until Docker Desktop and a web browser were
closed.

This is not a fault. macOS deliberately keeps memory busy: a browser holds
several gigabytes across its tabs, Docker Desktop runs a whole virtual machine
that was using 2.7 GB on the test machine, and macOS itself compresses pages it
has not needed recently rather than freeing them.

So the honest reading of the table in Section 3 is: **your Mac needs that much
memory free, not that much memory installed.** Closing apps before you start is a
normal part of using this, not a sign that something is wrong.

[04 — memory safety](04-memory-safety.md#free-memory) explains how to see the
number and what to close. It also explains the guard: `./bin/serve.sh` measures
free memory before it loads anything and refuses with a readable message rather
than stalling your Mac.

---

## 5. <a id="5-what-the-whole-thing-costs"></a>What the whole thing costs

Nothing is charged, but four real resources are spent.

| Resource | Amount | Notes |
|---|---|---|
| Money | Zero | No account, no key, no card, no usage fee, ever. |
| Disk, while downloading | About 45 GB free | The download tool keeps a second copy of every file while it works. |
| Disk, afterwards | About 20 GB | One step at the end reclaims the duplicate. Instant, and nothing is lost. |
| Memory, while running | The last column of the table in Section 3 | 22 GB on a 36 GB Mac. The server refuses to start below it. |
| Your attention | 20 to 40 minutes | Spread over pages 02 to 05. |
| Waiting, once | However long 20 GB takes on your connection | On a 100 Mbit connection, roughly half an hour. Nobody has to watch it. |
| Waiting, each time | About a minute for the first answer after a quiet period | The server hands memory back to macOS after 15 minutes of silence, then reloads. |
| Network | The download, and nothing else | Afterwards you can turn Wi-Fi off and it still works. |

**Everything here is reversible.** Deleting the model folder reclaims the disk.
Stopping the server returns the memory immediately. None of these scripts changes
a macOS setting. The full undo list is at the end of this page.

---

## 6. What you get, and what you do not

This is the section people skip and then feel misled by, so it is stated
plainly.

**A 27-billion-parameter model at 5-bit is not Claude Sonnet, and it is not
Claude Opus.**

Two separate things make it weaker.

**It is a smaller model.** Fewer numbers means less knowledge and less ability to
follow a complicated chain of reasoning.

**Its numbers have been compressed.** This is **quantization**
([Glossary](09-glossary.md#quantization)). **5-bit** means each of the model's
numbers is stored using 5 binary digits instead of the 16 it was trained with.

> **Think of it like** saving a photograph as a smaller JPEG file. It still looks
> like the photograph, and the fine detail is gone. **Where the comparison
> stops:** the lost detail here is spread evenly across everything the model
> knows, rather than concentrated in one corner of a picture.

**What it does well:**

- Short, clearly described tasks. "Rename this function everywhere in this file."
  "Explain what this script does." "Write a test for this function."
- Reading and summarizing code that is already in front of it.
- Working with no internet connection at all.
- Anything where you would rather the code did not leave your machine.

**What it does badly:**

- Long chains of steps without supervision. It loses the thread.
- Following complicated instructions exactly. It drifts.
- Producing correctly formatted requests to its own tools. When it gets one
  wrong, Claude Code recovers poorly and you see a confusing failure.
- Very long conversations. Quality drops as the conversation grows.

**How to use it well:** give it one job at a time, read the result before
accepting it, and start a fresh conversation often. Treat it as a capable
assistant that needs supervision, not as a replacement for a person or for a
larger model.

---

## 7. Two things to know before you commit

**This particular model has had its refusal behavior removed.** The publisher did
that deliberately. The technical name is an **abliterated** model
([Glossary](09-glossary.md#abliterated-model)). In plain words: most models
decline certain requests, and this one declines very little.

That is workable for research on your own machine, alone, which is what this
setup is for. It is not something to put where other people can reach it. For
that reason the server in this repository listens only on the address
`127.0.0.1`, which means "this Mac and nothing else". The server's own default is
to listen on every network, and this repository overrides that. The override is
not optional: `./bin/serve.sh` refuses to start with any other address, and
`./bin/doctor.sh` checks the address the server is really using.

**The model has its own license.** The checkpoint this repository downloads ships
under the Apache License 2.0. The license text is the file named `LICENSE` inside
the model folder after you download it, and the file named `LINEAGE.json` next to
it records what the model was built from. Read both. This repository redistributes
neither the weights nor their license, and the MIT license covering these scripts
gives you no rights over them. See
[03 — get the model](03-get-the-model.md#license) for the detail.

---

## 8. How to know this page worked

You have finished this page correctly when you can answer three questions about
your own Mac without guessing:

1. Does it have an Apple chip? (Apple menu, About This Mac, the **Chip** line.)
2. How much memory does it have, and which row of the Section 3 table is that?
3. How much memory is free *right now*? (`./bin/detect-hardware.sh`.)

## How to stop

There is nothing running. This page started nothing and installed nothing.

## How to undo everything

There is nothing to undo. If you also ran the two commands in Section 4, they
only read your Mac's settings.

## What this page will not do

It cannot tell you how fast the model will feel on your Mac. That depends on
graphics cores, and no speed figure has been measured on any machine other than
the test machine. It also cannot promise the model is good enough for your work.
Section 6 is the honest description; the only real test is to try it.

---

## The decision

**If your Mac has an Apple chip and 32 GB of memory or more:** continue to
[02 — install](02-install.md).

**If your Mac has an Apple chip and less than 32 GB:** stop here. Do not download
20 GB. Pick the smaller model named for your row in the Section 3 table. These
documents do not cover those models, and the scripts here will refuse to download
this one on your machine, by design.

**If your Mac has an Intel chip:** stop here. There is no version of this that
runs on your Mac.

**Read next:** [02 — install](02-install.md).
