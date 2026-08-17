# Run a 27B model on your Mac, and let Claude Code use it

This repository gives you the scripts and the instructions to run a large
AI model entirely on your own Mac, and to point Claude Code at it, so your
code and your questions never leave the machine and cost nothing to answer.

---

## Start here

**Never done anything like this before?** Read
[docs/01-requirements.md](docs/01-requirements.md) first — about two minutes, and
it tells you honestly whether your Mac can do this before you spend an hour
finding out the hard way. Then follow
[docs/02-install.md](docs/02-install.md) from step 1. It assumes nothing.

**Comfortable with Terminal already?** It is five commands, run from the repo
folder, in this order:

| # | Command | What it does |
|---|---|---|
| 1 | `./bin/setup.sh` | installs the four tools needed |
| 2 | `./bin/download-model.sh` | downloads the 20 GB of weights |
| 3 | `./bin/doctor.sh` | checks everything, changes nothing |
| 4 | `./bin/serve.sh` | starts the server — leave the window open |
| 5 | `./bin/claude-local.sh` | starts Claude Code in a second window |

Two things to know before you start: you must **free memory before command 4**
(the server refuses to start otherwise, and says what to close), and the model
is **uncensored** — see [the safety note](#a-safety-note-you-should-not-skip).

The rest of this page explains what those five commands are actually doing.
Nothing below downloads or starts anything.

---

## Before you start

**Who this is for.** Three kinds of reader:

1. A curious person who owns a Mac and wants to watch an AI model run on it,
   with nobody's server involved. You do not need to write code. You do not
   need to know what any of the technical words mean. Every one of them is
   explained where it first appears, and again in the
   [Glossary](docs/09-glossary.md).
2. An engineer who wants to judge whether a local model is good enough for
   real coding work.
3. Someone who wants to point the Claude Code command-line tool at a model they
   run themselves, offline, with nothing sent to anyone.

**What you do not need to know.** How to program. What a model is. What a
server is. What Terminal is. All of that is covered on the way.

**What you will have at the end.** A coding assistant running in a window on
your Mac. You type a question, your Mac answers it. Your Mac is not connected
to any AI company while it does this.

**How long it takes.** About 20 to 40 minutes of your attention, spread over
the pages below. Plus waiting: the download is about 20 GB, and how long that
takes depends entirely on your internet connection. On a 100 Mbit connection,
expect roughly half an hour of waiting. Nobody has to sit and watch it.

**What it costs.** No money. No account. No credit card. It costs disk space
(about 45 GB free while downloading, about 20 GB once finished) and memory (a
block of it has to be free while the model runs: 22 GB on the 36 GB machine this
was tested on, and `./bin/doctor.sh` prints the figure for yours). After the
download, nothing leaves your machine.

**One thing to know before you download 20 GB.** The model this repository uses
is named `Qwen3.8-27B-Uncensored`, and the word in that name is accurate: its
publisher removed its refusal behavior, so it declines very little. That is
workable for research on your own machine and is the reason the server here
listens only on your own Mac and refuses to listen anywhere else. The full note
is [further down this page](#a-safety-note-you-should-not-skip).

**What you need first.**

- [ ] A Mac with an Apple chip, called **Apple Silicon**
      ([Glossary](docs/09-glossary.md)). To check: Apple menu, then "About This
      Mac". If the **Chip** line starts with "Apple M", you have one. If it names
      an Intel processor, this will not run — Apple sold Intel Macs until 2023,
      so the year your Mac was made does not answer this. Windows and Linux
      cannot run it either.
- [ ] At least 32 GB of memory for a 27B model at all, and 36 GB for the build
      this was tested with. Find your row in
      [Will this run on your Mac](#will-this-run-on-your-mac) below.
- [ ] About 45 GB of free disk space.
- [ ] Claude Code. You do not need it yet —
      [docs/02-install.md](docs/02-install.md) installs it at step 9 if you do
      not have it.

**If you only read one thing:** read
[docs/01-requirements.md](docs/01-requirements.md). It tells you honestly
whether your Mac can do this before you spend an hour finding out the hard
way.

---

## What you are actually building

Three separate pieces have to work together. People often mix them up, so
here is what each one is.

**1. The model.** This is the AI itself. It is not a program you run. It is a
very large file of numbers, about 20 GB, produced by training. Those numbers
are called the **weights** ([Glossary](docs/09-glossary.md)). The specific
model here is named Qwen3.8-27B. On its own, a file of numbers does nothing.

**2. The server.** A program called **mlx-serve**
([Glossary](docs/09-glossary.md)) that loads the weights into your Mac's
memory and does the arithmetic to turn your question into an answer. A
program that does this job is called an **inference server**
([Glossary](docs/09-glossary.md)). It runs quietly in one Terminal window and
waits to be asked something.

**3. The app.** **Claude Code** ([Glossary](docs/09-glossary.md)) is the
program you actually type into. It reads your files, runs commands, and
writes code. Normally it sends your questions to Anthropic's servers over the
internet. This repository redirects it to the server on your own Mac instead.

Here is how a question travels:

```
        you type a question in Terminal
                     |
                     v
        +--------------------------+
        |       Claude Code        |
        +--------------------------+
                     |
                     |  one request, sent to your own Mac
                     |  address 127.0.0.1, port 11234
                     v
        +--------------------------+
        |        mlx-serve         |
        +--------------------------+
                     |
                     v
        +--------------------------+
        |       MLX / Metal        |
        +--------------------------+
                     |
                     v
        +--------------------------+
        |   your Apple Silicon     |
        |   chip and its memory    |
        +--------------------------+
                     |
                     v
        the answer comes back up the same path
```

**Legend, one line per part:**

- **Terminal** ([Glossary](docs/09-glossary.md)) is the text window on your
  Mac where you type commands instead of clicking buttons.
- **Claude Code** is the app that reads your files and decides what to ask
  the model.
- **The first arrow** carries one request. The address `127.0.0.1` means
  "this same computer". This address is called **loopback**
  ([Glossary](docs/09-glossary.md)). A request sent there physically cannot
  leave your Mac. `11234` is the **port**
  ([Glossary](docs/09-glossary.md)) number, which is how one program on your
  Mac tells several others apart, like an apartment number on a building.
- **mlx-serve** is the server holding the 20 GB of weights.
- **The second arrow** hands the arithmetic to Apple's software.
- **MLX** ([Glossary](docs/09-glossary.md)) is Apple's math library for AI
  models. **Metal** is Apple's graphics and computation layer underneath it.
- **The third arrow** runs the actual arithmetic on the chip.
- **Apple Silicon** is the chip. It shares one pool of memory between the
  processor and the graphics part, which is why a 20 GB model can run on a
  laptop at all.

**One thing worth noticing about that diagram: there is nothing between
Claude Code and mlx-serve.** Claude Code speaks a specific request format
called the **Anthropic Messages API** ([Glossary](docs/09-glossary.md)) — the
agreed shape of a message that an app sends to a model. mlx-serve understands
that exact format already. Most local setups need an extra translation
program sitting in the middle to convert between formats. This one does not.
That is one fewer program to install, one fewer thing to break, and no
information lost in translation.

---

## Will this run on your Mac

Read this table before you download anything. The short version: 36 GB of
memory works and is what was tested, 48 GB or more is comfortable, and below
32 GB you should run a smaller model instead of this one.

Memory on an Apple Silicon Mac is called **unified memory**
([Glossary](docs/09-glossary.md)). The processor and the graphics part share
one pool instead of having separate pools. *Think of it like one large desk
that two people share, rather than two small desks.* The analogy stops being
true because the two "people" here can hand work to each other with no copying
at all, which two desks could never do.

To find your number: Apple menu, then "About This Mac". The line that says
"Memory" is the one that matters.

Two words appear in the table and are worth knowing before you read it.

- A **context window** ([Glossary](docs/09-glossary.md)) is how much text the
  model can hold in mind at once, counted in tokens. A token is roughly three
  quarters of an English word, so a 65,536-token window is roughly 49,000
  English words. *Think of it like the size of the desk the model can spread papers
  on.* The analogy stops being true because the desk costs memory: a bigger
  window means less memory left for everything else.
- **4-bit**, **5-bit** and **8-bit** describe how heavily the model's numbers
  were compressed to save memory. The process is called **quantization**
  ([Glossary](docs/09-glossary.md)) and it is explained in
  [Honest expectations](#honest-expectations) below. Fewer bits means a
  smaller file and slightly lower quality.

The verdict column answers one question only: **how does the model in this
repository, Qwen3.8-27B at 5-bit, fare on that machine?** It says nothing
about speed. See the note under the table.

| Your memory | Verdict for this model | What to do |
|---|---|---|
| 8 GB | Does not fit | Run Qwen3-4B instead (about 2.3 GB). Useful for single-file edits, not for long tasks. |
| 16 GB | Does not fit | Run Qwen3-8B instead (about 4.5 GB). It leaves your Mac usable. |
| 18 GB | Does not fit | Run Qwen3-14B instead (about 8 GB). Common on M3 and M4 Pro laptops. |
| 24 GB | Not recommended | Even the 4-bit build does not fit under Apple's graphics memory ceiling here. `./bin/serve.sh` refuses to start. Run Qwen3-14B instead. |
| 32 GB | Tight | The scripts download the 4-bit build and use a 32,768-token window. The 5-bit build fits only with your browser and Docker closed. |
| 36 GB | Workable — this is the tested machine | The scripts download the 5-bit build and use a 65,536-token window. You must close memory-hungry apps first. |
| 48 GB | Comfortable | 5-bit build, 131,072-token window. No app-closing needed. |
| 64 GB | Comfortable | The scripts download the 8-bit build (about 27.7 GB). Better quality, still fits. |
| 96 GB or more | Comfortable | 8-bit build at the model's full 262,144-token window. |
| Intel Mac, Windows, or Linux | Not supported | MLX is built only for Apple Silicon. There is no version for other chips. |

**Two honest warnings about that table.**

First, the table predicts whether the model **fits**. It says nothing about
whether it will feel **fast**. Speed depends far more on how many graphics
cores your chip has than on how much memory it has. Only the 36 GB row was
measured. Every other row is arithmetic, labeled NOT YET MEASURED.

Second, "36 GB total" is not "36 GB free". On the test machine (Apple M3 Max,
30 graphics cores, 36 GB unified memory, macOS 26.5.2), a normal working day
left only about 10.5 GB actually available — MEASURED. Docker Desktop and a
browser had to be closed before the model would load. This is normal and it
is explained in [docs/04-memory-safety.md](docs/04-memory-safety.md).

You do not have to work any of this out yourself. `./bin/doctor.sh` measures
your machine and tells you.

---

## What it costs

Nothing is charged, but three real resources are spent.

| Resource | Amount | Notes |
|---|---|---|
| Money | Zero | No account, no key, no subscription, no usage fee. |
| Disk, during download | About 45 GB free | The download tool keeps a second copy while it works. |
| Disk, after download | About 20 GB | One step reclaims the duplicate copy instantly, and prints what it reclaimed on your Mac. The before-and-after pair is NOT YET MEASURED on the test machine. |
| Memory, while running | Whatever `./bin/doctor.sh` reports for your Mac — 22 GB on the 36 GB test machine | The server refuses to start below this. That refusal is a safety feature. |
| Your attention | 20 to 40 minutes | Spread across the numbered pages. |
| Waiting | Download time, plus about one minute the first time the model loads | Load time MEASURED on the test machine, approximate. |
| Network | The download only | After that, nothing leaves your Mac. You can turn off Wi-Fi and it still works. |

---

## Why this is interesting

You can skip this section and the setup still works. It is here because two
things about this particular model are genuinely unusual, and they are the
reason a 27-billion-parameter model fits on a laptop at all.

### 1. Most of this model does not remember your conversation word for word

A model reads text in pieces called **tokens**
([Glossary](docs/09-glossary.md)). A token is roughly three quarters of an
English word. *Think of tokens like the individual beads on a string that the
model reads one at a time.* The analogy stops being true because tokens are
not always whole words — long or unusual words get split into several.

As you talk to a model, it keeps notes on everything said so far, so it does
not have to re-read the whole conversation for each new word. Those notes are
called the **KV cache** ([Glossary](docs/09-glossary.md)). *A rough
comparison: it is like a running set of margin notes in a book you are
reading.* The analogy stops being true because the notes are numbers, not
text, and you could never read them yourself.

The problem with those notes is that they grow. In a normal model, every
layer keeps its own set, and the longer you talk, the more memory they eat.

This model is built differently. It has 64 **layers** — the stacked stages a
model passes text through ([Glossary](docs/09-glossary.md)). **Only 16 of
them keep growing notes. The other 48 keep a single fixed-size summary that
gets rewritten instead.**

*Think of the 16 as a notebook that gets longer as you talk, and the 48 as one
sticky note that gets erased and rewritten each time.* The analogy stops being
true because the sticky note is not losing information randomly — it holds a
deliberate compressed summary.

The result: the growing notes cost four times less memory than they would in
an ordinary model of the same size. That is a large part of why this fits in
36 GB.

**You can check this yourself.** Open the file `config.json` inside the model
folder and look at `layer_types`. It lists 64 entries. 48 say
`linear_attention` and 16 say `full_attention`. The full explanation is in
[docs/08-how-it-works.md](docs/08-how-it-works.md).

### 2. The model guesses its own next words, and the guesses are exact

Normally a model produces one token, then uses it to produce the next, one at
a time. That is slow, and it is slow for a boring reason: the chip spends most
of its time moving 20 GB of weights around rather than doing arithmetic.

This model ships with a small extra piece, built in, whose only job is to
guess several of the next tokens ahead of time. The full model then checks
all the guesses in one pass. Guesses that were right are kept. Guesses that
were wrong are thrown away. This technique is called **speculative decoding**,
and this model's built-in version is called **multi-token prediction (MTP)**
([Glossary](docs/09-glossary.md)).

*Think of it like a fast typist who guesses the end of your sentence while an
editor checks each guess before it is printed.* The analogy stops being true
because the "editor" here is mathematically strict: any wrong guess is
discarded completely, so the final text is exactly what the slow method would
have produced.

That last point is the interesting one. This is not an approximation. It is
not a quality trade. The output is identical, byte for byte.

**The evidence.** The model's publisher measured 6.81 seconds with the
feature on versus 10.15 seconds with it off, and the two outputs had the same
SHA-256 fingerprint — an identical digital signature for identical text. That
figure is PUBLISHER-REPORTED. It has NOT YET BEEN reproduced on the test
machine. You can run the comparison yourself with `./bin/bench.sh`, described
in [docs/07-tuning.md](docs/07-tuning.md).

**And a catch that explains this whole repository.** The most common tool for
running MLX models deletes that guessing piece when it loads the file. One
line of its source code filters those weights out. The fix has been proposed
but not accepted. That single fact is why this setup uses mlx-serve and not
the more common tool. The details are in
[docs/08-how-it-works.md](docs/08-how-it-works.md).

---

## The fastest correct path

Five commands, in this order. **Do not run them yet.** Each one has its own
page below that tells you what to expect and what to do when something goes
wrong. This list is a map, not the instructions.

**First, get this repository onto your Mac.** Replace `<REPO_URL>` with the
address from this project's page on GitHub: click the green **Code** button and
copy the HTTPS address, which ends in `.git`. Worked example: if the page shows
`https://github.com/example-owner/qwen3.8free.git`, that is what goes in place of
`<REPO_URL>`.

```
mkdir -p ~/dev/local-llms && cd ~/dev/local-llms && git clone <REPO_URL> qwen3.8free
```

That is one action: make a folder, move into it, and copy the repository. It ends
with a line saying `done.` Then move into the new folder:

```
cd ~/dev/local-llms/qwen3.8free
```

This prints nothing. That is success. If `git clone` reports
`could not read Username`, the address is wrong — copy it again from the green
**Code** button. Step 4 of [docs/02-install.md](docs/02-install.md) walks through
this more slowly.

Every command below runs from that folder. Throughout the documentation it is
written as `~/dev/local-llms/qwen3.8free`. Yours may be somewhere else. Use your
own path.

Before command 4, you must free memory on your Mac. The server needs a block of
it free and refuses to start below that. The figure is worked out from your Mac's
memory size — 22 GB on the 36 GB test machine — and command 3 prints yours.
[docs/04-memory-safety.md](docs/04-memory-safety.md) explains exactly what to
close and why. Read it before command 4, not after.

The conclusion to draw from this table: nothing here downloads or starts
anything until you tell it to, and the third command checks your work before
the slow parts begin.

| # | Command | What it does | Last line when it finishes | Full instructions |
|---|---|---|---|---|
| 1 | `./bin/setup.sh` | Installs the four tools this needs. Does not download the model. | `setup complete — next: ./bin/doctor.sh` | [docs/02-install.md](docs/02-install.md) |
| 2 | `./bin/download-model.sh` | Downloads the 20 GB of weights, correctly. This is the long one. | `download complete — next: ./bin/verify-model.sh` | [docs/03-get-the-model.md](docs/03-get-the-model.md) |
| 3 | `./bin/doctor.sh` | Checks your whole setup and prints PASS, WARN, FAIL or SKIP for each item. Changes nothing. | `doctor: OK — next: ./bin/serve.sh` | [docs/02-install.md](docs/02-install.md) |
| 4 | `./bin/serve.sh` | Starts the server. Leave this Terminal window open. Press Control-C to stop it. | a line saying it is listening on `http://127.0.0.1:11234` | [docs/05-run-it.md](docs/05-run-it.md) |
| 5 | `./bin/claude-local.sh` | Starts Claude Code in a second Terminal window, pointed at your own Mac. | the normal Claude Code prompt | [docs/05-run-it.md](docs/05-run-it.md) |

When a command fails, the error message names the fix, and
[docs/06-troubleshooting.md](docs/06-troubleshooting.md) has a section for
every error this stack can produce.

---

## The documents

Read them in this order the first time. Each one ends by naming the next.

| Document | Read this if |
|---|---|
| [docs/01-requirements.md](docs/01-requirements.md) | You want the honest answer to "will this work on my Mac, and what will it feel like" before installing anything. |
| [docs/02-install.md](docs/02-install.md) | You are ready to install the four tools. |
| [docs/03-get-the-model.md](docs/03-get-the-model.md) | You are ready to download the 20 GB of weights, and want to avoid the single most common beginner failure. |
| [docs/04-memory-safety.md](docs/04-memory-safety.md) | You are about to start the server for the first time. Read this **before**, not after. |
| [docs/05-run-it.md](docs/05-run-it.md) | You want the payoff: server in one window, Claude Code in another, and proof that nothing left your Mac. |
| [docs/06-troubleshooting.md](docs/06-troubleshooting.md) | Something printed an error, or `./bin/doctor.sh` pointed you here. Find your symptom, not your cause. |
| [docs/07-tuning.md](docs/07-tuning.md) | It works and now you want a longer memory, better quality, or a speed measurement. |
| [docs/08-how-it-works.md](docs/08-how-it-works.md) | You want the engineering: why this design, why not the alternatives, and what it genuinely cannot do. |
| [docs/09-glossary.md](docs/09-glossary.md) | Any word confused you. Every technical term in this repository has an entry, in plain language, tied to a real number from this setup. |

**Two shortcuts, so nobody feels obliged to read all of it.**

- **In a hurry, and comfortable in Terminal?** Clone the repository with the
  command above, then run commands 1 to 5 from the table. Read nothing else
  unless `./bin/doctor.sh` complains. Read
  [docs/04-memory-safety.md](docs/04-memory-safety.md) before command 4 anyway;
  it is the one that protects your Mac.
- **New to all of this?** Read this page, then
  [docs/01-requirements.md](docs/01-requirements.md), then keep
  [docs/09-glossary.md](docs/09-glossary.md) open in another tab. Then follow
  02 through 05 one command at a time. Treat
  [docs/06-troubleshooting.md](docs/06-troubleshooting.md) as the help desk.

---

## Honest expectations

This matters more than anything else on this page, so it is stated plainly.

**A 27B model at 5-bit is not Claude Sonnet, and it is not Claude Opus.**

Two things make it weaker. It is a smaller model. And its numbers have been
compressed to save memory, a process called **quantization**
([Glossary](docs/09-glossary.md)). **5-bit** means each of the model's numbers
is stored in 5 binary digits instead of 16. *Think of it like saving a photo
as a smaller JPEG: it still looks like the photo, and fine detail is gone.*
The analogy stops being true because the lost detail here is spread evenly
across everything the model knows, rather than concentrated in one region of
an image.

**What it does well:**

- Short, clearly described tasks. "Rename this function everywhere in this
  file." "Explain what this script does." "Write a test for this function."
- Reading and summarizing code that is already in front of it.
- Working with no internet connection at all.
- Anything where you would rather not send the code to a company.

**What it does badly:**

- Long chains of steps without supervision. It loses the thread.
- Following complicated instructions exactly. It drifts.
- Producing correctly formatted requests to its own tools. When it gets one
  wrong, Claude Code recovers poorly, and you see a confusing failure.
- Very long conversations. Quality drops as the conversation grows.

**How to use it well:** give it one job at a time, check the result, and start
a fresh conversation often. Treat it as a capable assistant that needs
supervision, not as a replacement for a person or for a larger model.

**On speed:** no tokens-per-second figure has been measured for this model on
any machine, so this repository does not print one. Anyone quoting a speed
figure to you should say which Mac produced it.

---

## How to know it worked

Three checks, in order, each described fully in
[docs/05-run-it.md](docs/05-run-it.md):

1. `./bin/doctor.sh` prints `doctor: OK`.
2. The server window prints a line saying it is listening on
   `http://127.0.0.1:11234`.
3. Claude Code answers a question you type, while your Wi-Fi is turned off.

One message you **will** see and should ignore: Claude Code prints a one-line
warning about an `unrecognized_model` at startup. That is EXPECTED. It is
cosmetic. It happens because Claude Code does not have this model's name in
its list. Nothing is broken. This is explained again where you will first hit
it, in [docs/05-run-it.md](docs/05-run-it.md).

## How to stop

Press Control-C in the server window. Or, from the repository folder, run
`./bin/stop.sh`. That command is safe to run when nothing is running, and it
prints how much memory came back. Full details in
[docs/05-run-it.md](docs/05-run-it.md).

## How to undo everything

Everything here is reversible, and none of it changes a macOS setting unless
you choose to.

- **Free the memory:** run `./bin/stop.sh`. The memory returns immediately.
- **Reclaim the 20 GB of disk:** delete the model folder inside the
  repository. Nothing else depends on it. You can download it again later.
- **Remove the tools:** the two tools this installed, `git-lfs` and
  `mlx-serve`, are removed with Homebrew. The exact commands are at the end of
  [docs/02-install.md](docs/02-install.md).
- **Remove everything:** delete the repository folder.
- **Nothing to revert in macOS:** these scripts do not change any system
  setting by default. [docs/04-memory-safety.md](docs/04-memory-safety.md)
  describes one setting some guides tell you to change, explains why this
  repository recommends leaving it alone, and gives the undo command in case
  you already changed it.

---

## A safety note you should not skip

**This particular model has had its refusal behavior removed.** The publisher
did this deliberately. The technical name for it is an **abliterated** model
([Glossary](docs/09-glossary.md)). In plain words: most models decline certain
requests, and this one will not decline much of anything.

That is workable for research on your own machine, alone, which is what this
setup is for. It is not something to put where other people can reach it.

For that reason, **the server in this repository listens only on
`127.0.0.1`** — your own Mac, and nothing else. This is a deliberate override.
mlx-serve's own default is `0.0.0.0`, which would accept requests from every
other device on your network. This repository changes that default, and the
change is not optional. `./bin/doctor.sh` checks it and tells you.

Do not make this server reachable from your network or from the internet.

The model also comes with its own license from its publisher. That license is
separate from this repository's license and you are responsible for reading
it. [docs/03-get-the-model.md](docs/03-get-the-model.md) has the details.

---

## This repository contains no model weights

There are no model files in this repository, and there never will be. The
20 GB of weights is downloaded from HuggingFace by
`./bin/download-model.sh`, into a folder that this repository's `.gitignore`
excludes from version control. A `.gitignore` file
([Glossary](docs/09-glossary.md)) is a list of files that the version control
system is told to ignore completely.

Two consequences worth knowing:

- Cloning this repository is a few hundred kilobytes, not 20 GB.
- After you download the model, running `git status --short` inside the
  repository folder does not list the model folder. If it ever does, stop and
  read [docs/03-get-the-model.md](docs/03-get-the-model.md).

## License

The scripts in `bin/` and the documents in `docs/` are covered by the MIT
license. See [LICENSE](LICENSE).

**The model is not covered by that license.** The checkpoint this repository
downloads ships under the **Apache License 2.0**. After the download, the license
text is the file named `LICENSE` inside the model folder, and the file named
`LINEAGE.json` beside it records what the model was built from. Read both. This
repository redistributes neither, and the MIT license here grants you no rights
over them. Details in
[docs/03-get-the-model.md](docs/03-get-the-model.md#license).
