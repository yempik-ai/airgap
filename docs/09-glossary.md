# 09 — Glossary

**Who this is for.** Anyone who hits a word in this repository and wants a plain
answer. You do not need any background in computers, machine learning, or the
command line. Every entry stands on its own.

**What you will have at the end.** A definition for every technical word used
anywhere in this repository, tied to a real number or a real file from this
setup rather than an abstract example.

**How long it takes.** Nothing to wait for. Look up one word in under a minute.
Reading the whole file takes about 25 minutes of your attention.

**What it costs.** No disk space, no memory, no money. Nothing on this page
runs anything or sends anything anywhere.

**What you need first.** Nothing. This is the one document in the repository
with no prerequisites. The other documents are listed in the
[main README](../README.md).

**If you only read one thing:** read [token](#token). Almost every other word on
this page is measured in tokens.

---

## How to use this page

Entries are in alphabetical order. Numbers and symbols come first.

Every entry has two parts, and some have a third:

- **The definition.** One or two sentences in plain words.
- **Why you care here.** What the word means for this specific setup, with a
  number you can check.
- **Think of it like.** An everyday comparison, where one helps. Every
  comparison states where it stops being true, because a comparison that is
  taken too far becomes wrong.

Numbers on this page are labeled **MEASURED** (recorded on the test machine, an
Apple M3 Max with 30 GPU cores and 36 GB of memory, running macOS 26.5.2),
**PUBLISHER-REPORTED** (published by whoever made the model, not reproduced
here), or **NOT YET MEASURED**. See
[MEASURED vs NOT YET MEASURED](#measured-vs-not-yet-measured).

---

## Numbers and symbols

### 0.0.0.0 (and why it is dangerous here)

An address that means "accept connections from every network this machine is
on", including the office wifi and the coffee shop wifi.

**Why you care here.** The server program used in this repository binds to
0.0.0.0 by default, and it asks for no password unless you give it one. The
model in this repository is [abliterated](#abliterated-model), which means its
built-in refusals were removed. So this repository overrides the default and
binds to [127.0.0.1](#localhost--127001--loopback), which accepts connections
only from your own Mac. That override is not optional and must not be reversed.

### 5-bit

The size of the number used to store each weight in this copy of the model. Five
binary digits per weight, instead of the 16 the model was trained with.

**Why you care here.** Five bits is why the model needs about 19.1 GB of memory
instead of about 54 GB (MEASURED file size: 19.1 GB of text-only weights). It is
one form of [quantization](#quantization).

### `--strict-mcp-config`

A setting you pass to [Claude Code](#claude-code) that tells it to ignore the
extra tool servers configured on your machine.

**Why you care here.** With those servers loaded, Claude Code's opening
instructions to the model are 38,054 [tokens](#token) long. With this setting,
they are 20,909 tokens (both MEASURED). That difference is paid on every single
turn of the conversation. See [Model Context Protocol (MCP)](#model-context-protocol-mcp).

---

## A

### abliterated model

A model that has had its refusal behavior removed on purpose, by editing the
weights rather than by changing the instructions given to it.

**Why you care here.** The model in this repository is one of these. It will
answer requests that the original model declines. That is workable for private
research on your own Mac, and it is the reason the server binds to
[127.0.0.1](#localhost--127001--loopback) only. Never expose it beyond your own
machine. See also [guardrails / refusal behavior](#guardrails--refusal-behavior).

### affine quantization

A method for shrinking numbers that stores each small group of weights as whole
numbers plus two extra values: a scale and a starting point.

**Why you care here.** This is the method used in this copy of the model, at
[5-bit](#5-bit) with a [group size](#group-size) of 64. The two extra values per
group are what let the original numbers be reconstructed closely enough to keep
the answers good. See [quantization](#quantization).

### agent

A program that gives a model tools, lets it choose which tool to use, runs the
tool, and feeds the result back, in a loop, until the task is done.

**Why you care here.** [Claude Code](#claude-code) is an agent. It reads files,
edits files, and runs commands on your behalf. That loop is why the amount of
text sent to the model grows so quickly, and why the
[context window](#context-window) matters so much here.

### Anthropic Messages API (`/v1/messages`)

One specific agreed format for sending a conversation to a model and getting a
reply back. It is the format Claude Code speaks.

**Why you care here.** The server in this repository speaks this format
natively. That is the single fact that removes an entire extra program from this
setup. Without it you would need a
[translation proxy](#litellm--translation-proxy) sitting in the middle. See
[API](#api) and [endpoint](#endpoint).

### API

A fixed set of rules for how one program asks another program to do something.

**Why you care here.** Claude Code was built to talk to Anthropic's servers over
one particular set of rules. The local server follows the same rules, so Claude
Code cannot tell the difference and needs no modification.

### Apple Silicon

Apple's own line of Mac processors, sold under names that start with M: M1, M2,
M3, M4 and their Pro, Max, and Ultra versions.

**Why you care here.** This setup runs only on these Macs. The software it
depends on ([MLX](#mlx)) is written for the way these chips share memory between
the main processor and the graphics processor. An Intel Mac cannot run it, and
neither can Windows or Linux. See [unified memory](#unified-memory).

### attention

The part of a model that decides which earlier words matter for the word being
written now.

**Why you care here.** Attention is where the memory cost of a long conversation
comes from. This model uses two different kinds of it, which is the reason it
fits on a 36 GB Mac at all. See [full attention](#full-attention) and
[linear attention](#linear-attention).

### auto-compact

A feature in Claude Code that summarizes the older part of a long conversation
and throws away the original, to make room for more.

**Why you care here.** It fires when the conversation approaches the
[context window](#context-window) limit. With a smaller window, it fires sooner.
Summarizing loses detail, so long sessions with a local model drift more than
long sessions with a hosted one.

---

## B

### batching

Answering several separate requests at the same time, in one pass over the
model's weights, so the cost of reading those weights is shared.

**Why you care here.** Batching is how servers in data centers get high total
output. It does nothing for you here, because you are one person sending one
request at a time. This is a large part of why server software built for data
centers is the wrong choice on a Mac. See [vLLM](#vllm).

### benchmark

A measurement taken by running something and timing it, rather than estimating
it.

**Why you care here.** This repository contains one benchmark script,
`bin/bench.sh` (path relative to the repository root). It runs the model twice
and reports both times. Numbers that came from an actual run are labeled
MEASURED. Everything else is labeled honestly. See
[MEASURED vs NOT YET MEASURED](#measured-vs-not-yet-measured).

### brew tap

A command that adds a new source of installable software to
[Homebrew](#homebrew-brew).

**Why you care here.** The server program used here is not in Homebrew's main
list. You add its source with one `brew tap` command before you can install it.

### brew trust

A command that tells Homebrew you accept software from a source outside its main
list.

**Why you care here.** Homebrew requires this step for outside sources. Skipping
it makes the install fail with a message that looks like the source is broken,
which sends people hunting for the wrong problem. `bin/setup.sh` runs the step
for you.

---

## C

### `cd`

The command that changes which folder your [Terminal](#terminal) window is
pointed at. It stands for "change directory".

**Why you care here.** Almost every command in this repository must run from the
repository folder. Every section of every document starts with a `cd` command
for that reason. See [working directory](#working-directory).

### checkpoint

One saved copy of a model's [weights](#weights) at one point in time, as a set
of files on disk.

**Why you care here.** The folder this repository downloads is a checkpoint. It
contains 2207 [tensors](#tensor) spread across 5
[shards](#shard) (MEASURED). `bin/verify-model.sh` counts them for you.

### chunked prefill

Reading a long incoming message in slices rather than all at once, so the
temporary memory spike stays small.

**Why you care here.** The server sizes the slice from the memory free when it
loads and prints the figure in its log (`Prefill chunk: N tokens (memory-sized
down from 8192; …)`); this repository leaves that alone. `PREFILL_CHUNK=` pins
it. Reading a 20,000-token opening message in one piece would produce a memory
spike large enough to matter on a 36 GB Mac (MEASURED on the 9B: 2.6 GB at a
4096-token slice, 1.1 GB at 1024). See [prefill](#prefill).

### Claude Code

Anthropic's coding assistant, which runs in your [Terminal](#terminal) and can
read and edit files in a project folder.

**Why you care here.** It is the program you actually use. This repository does
not modify it. It points it at a server on your own Mac instead of Anthropic's
servers, using settings Claude Code already supports. See
[harness](#harness) and [agent](#agent).

### context window

The largest amount of text a model can consider at one time, counted in
[tokens](#token). Everything past the limit must be dropped or summarized.

**Why you care here.** This repository sets the window to 65,536 tokens. Claude
Code's opening instructions alone use 20,909 of those (MEASURED, with
[`--strict-mcp-config`](#--strict-mcp-config)), which leaves roughly 44,000 for
your actual work.

**Think of it like** a desk. Only so many pages fit on it at once. To add a new
page, one has to come off. The comparison stops working because the model does
not choose which page to remove; the program around it does, and the model
cannot tell that anything was taken.

### CUDA

The software layer that lets programs use graphics cards made by NVIDIA.

**Why you care here.** Most instructions you find online for running models
locally assume CUDA. None of that applies to a Mac. Your Mac uses
[Metal](#metal) and [MLX](#mlx) instead.

### `curl`

A command that fetches a web address from the [Terminal](#terminal) and prints
what comes back, instead of showing it in a browser.

**Why you care here.** It is how the documents in this repository ask the local
server whether it is awake, and how you can confirm with your own eyes that the
answer is coming from your Mac.

---

## D

### decode (generation)

The stage where the model produces its reply, one [token](#token) at a time.
Each token depends on every token before it.

**Why you care here.** Decode is the part you sit and watch. It is slow for a
reason that has nothing to do with how clever the model is: producing one token
requires reading all 19.1 GB of [weights](#weights) from memory. See
[memory-bandwidth bound](#memory-bandwidth-bound) and
[speculative decoding](#speculative-decoding).

### dense model vs mixture of experts (MoE)

A dense model uses all of its [weights](#weights) for every [token](#token). A
mixture of experts model contains many separate sub-models and uses only a few
of them per token.

**Why you care here.** The model in this repository is dense. That matters
because several speed settings in the server software help only mixture of
experts models, so this repository deliberately leaves them off.

### draft acceptance rate

The share of guessed [tokens](#token) that turn out to be correct and are kept.

**Why you care here.** It is the number that decides whether
[speculative decoding](#speculative-decoding) is helping. The server reports it
if you turn on its measurements page. On this model it is NOT YET MEASURED in
this repository.

### drafter / draft model

The cheap, fast guesser in [speculative decoding](#speculative-decoding). It
proposes the next few [tokens](#token), and the real model checks them.

**Why you care here.** Most setups need a second, smaller model as the drafter,
which costs more memory. This model carries its own guesser inside it, so no
second model is needed. See [multi-token prediction (MTP)](#multi-token-prediction-mtp).

---

## E

### endpoint

One specific web address on a server that performs one specific job.

**Why you care here.** The local server offers several. `/health` says whether
it is awake. `/v1/models` lists what it can run.
[`/v1/messages`](#anthropic-messages-api-v1messages) is the one Claude Code
uses. All of them live on your own Mac.

### environment variable

A named setting that you hand to a program at the moment you start it, instead
of writing it into a file.

**Why you care here.** This is how Claude Code is pointed at your Mac rather
than at Anthropic. The script `bin/claude-local.sh` sets about a dozen of them
and then starts Claude Code. They apply to that one run and vanish when it ends.

---

## F

### full attention

The kind of [attention](#attention) that lets the model look back at every
earlier [token](#token) individually, with perfect recall.

**Why you care here.** Full attention is accurate and expensive: it is what
builds the growing [KV cache](#kv-cache). In this model only 16 of the 64
[layers](#layer) use it (MEASURED, from the model's own configuration file). The
other 48 use the cheaper kind.

---

## G

### Gated DeltaNet (GDN)

The specific design used for the cheap [layers](#layer) in this model. It keeps
one fixed-size summary of the conversation and updates it as each new
[token](#token) arrives.

**Why you care here.** These 48 layers cost the same memory whether your
conversation is 100 tokens or 60,000. That is the property that makes a long
conversation affordable here. See
[linear attention](#linear-attention) and [recurrent state](#recurrent-state).

### `git`

A program that tracks changes to a folder of files, and the standard way source
code is shared online.

**Why you care here.** You use it once, to copy the model files down from the
website that hosts them. Your Mac already has it.

### `git clone`

The command that copies a [repository](#repository) from the internet onto your
Mac.

**Why you care here.** Cloning the model folder is the download step. It is
about 20 GB and takes a long time. It also has one trap, described under
[LFS pointer file](#lfs-pointer-file-the-135-byte-file-problem).

### git-lfs

An add-on to `git` for handling very large files. Without it, `git` stores a
short text note in place of each large file.

**Why you care here.** This is the most common way people fail at this setup. If
git-lfs is missing, the download appears to succeed and you get 135-byte notes
where 4 GB of weights should be. Installing git-lfs first makes the failure
impossible. `bin/setup.sh` installs it.

### gitignore

A file that lists things `git` must never copy or upload.

**Why you care here.** The file `.gitignore` in the repository root is what
stops the 20 GB model folder from being uploaded if you ever publish your own
copy. It is the single most consequential file in this repository.

### GPU cores

The number of parallel processing units in the graphics part of your chip.

**Why you care here.** GPU cores drive speed, not capacity. Two Macs with the
same amount of memory can run the same model at very different speeds. The test
machine has 30 (MEASURED). Speed of the 27B is NOT YET MEASURED on any chip,
including that one.

### group size

How many [weights](#weights) share one set of [quantization](#quantization)
bookkeeping values.

**Why you care here.** This model uses 64 (MEASURED). Smaller groups keep more
accuracy and use more space. Sixty-four is the usual compromise.

### guardrails / refusal behavior

A model's trained tendency to decline certain requests.

**Why you care here.** This model's refusal behavior was deliberately removed.
See [abliterated model](#abliterated-model). Treat the output as unfiltered and
keep the server on your own Mac.

---

## H

### Hadamard rotation

A mathematical shuffle applied to numbers before shrinking them, which spreads a
few extreme values out across many positions.

**Why you care here.** Extreme values are what make
[quantization](#quantization) lose accuracy. Spreading them first means the
shrunk numbers stay closer to the originals, at the same storage cost. It is
what the [turbo4](#turbo4) setting in this repository does. See
[outlier channels](#outlier-channels).

### harness

The program that wraps a model: it holds the conversation, adds instructions,
offers tools, and decides what to send next.

**Why you care here.** [Claude Code](#claude-code) is the harness in this setup.
The harness sends far more text than you type. Measuring that is why the
20,909-token figure (MEASURED) appears throughout these documents.

### Homebrew (`brew`)

The standard tool for installing command-line software on a Mac.

**Why you care here.** It installs [git-lfs](#git-lfs) and the model server.
This repository never installs Homebrew for you; if it is missing, the setup
script stops and gives you the official install address.

### HTTP

The set of rules web browsers and programs use to fetch things over a network.

**Why you care here.** Claude Code talks to the local server over HTTP, the same
way it would talk to a server on the internet. The difference is the address:
the message travels inside your Mac and never reaches a network card.

### hybrid architecture

A model that mixes two different [layer](#layer) designs instead of repeating
one.

**Why you care here.** This model is one: 48 cheap [layers](#layer) and 16
expensive ones (MEASURED). A model of the same size built entirely from the
expensive kind would need four times as much memory for the same conversation.

---

## I

### inference

Running a finished model to get an answer. It is the opposite of training, which
is the process that produced the model.

**Why you care here.** Everything in this repository is inference. Nothing here
trains or changes the model. The files on disk are read and never written.

### inference server

A program that keeps a model loaded in memory and answers requests for it.

**Why you care here.** Loading a 19.1 GB model takes about a minute. A server
pays that cost once and then answers quickly. The one used here is
[mlx-serve](#mlx-serve).

<a id="iogpu-wired-limit-mb"></a>
### `iogpu.wired_limit_mb`

A macOS setting that caps how much memory the graphics processor is allowed to
lock down.

**Why you care here.** This is the one setting in this whole stack that can make
your Mac stall badly enough to need a force restart. Locked memory cannot be
moved aside, so raising this too high leaves macOS itself with nowhere to go.
The recommendation in this repository is to leave it at 0, which means Apple
chooses. It resets on reboot. See [wired memory](#wired-memory) and
[sysctl](#sysctl).

---

## J

### JSON

A plain-text way of writing structured information, readable by both people and
programs.

**Why you care here.** The messages between Claude Code and the local server are
JSON, and the model's configuration file is JSON. You can open the configuration
file in any text editor and read it yourself.

---

## K

### kernel panic

A total failure of the operating system, where macOS stops and the Mac restarts
itself.

**Why you care here.** Nothing in the default settings of this repository can
cause one. The one path that can is raising
[`iogpu.wired_limit_mb`](#iogpuwired_limit_mb) too far. This repository never
changes that setting and recommends against changing it by hand.

### KV cache

The model's running notes on the conversation so far, kept so it does not have to
re-read everything to write each new word. KV stands for "keys and values".

**Why you care here.** It grows as you talk, and it lives in the same memory as
the model. In this model it costs 64 KiB per [token](#token) at full precision,
which works out to 4 GB for a 65,536-token conversation — 1 GB once this
repository compresses it to four bits (derived from the model's configuration
file; see [KV cache quantization](#kv-cache-quantization)).

**Think of it like** notes you take during a long meeting so you do not have to
replay the recording before every sentence you say. The comparison stops working
because these notes are not a summary: they are exact, and they grow at a fixed
rate per word with no editing.

### KV cache quantization

Storing the [KV cache](#kv-cache) in smaller numbers than the model natively
uses.

**Why you care here.** This repository stores it at four bits instead of
sixteen, which cuts that 4 GB to 1 GB at a 65,536-token window. The cost is a
small loss of precision in the model's recall of the older parts of a long
conversation. See [turbo4](#turbo4).

---

## L

### large language model (LLM)

A program trained on enormous amounts of text that predicts what text should
come next, one piece at a time.

**Why you care here.** Predicting the next piece, over and over, is all the
model does. Everything that looks like reasoning or planning comes out of that
one repeated operation.

### layer

One processing stage inside a model. Text passes through every layer in order.

**Why you care here.** This model has 64 (MEASURED). What matters here is that
they are not all the same: 48 are cheap and 16 are expensive. See
[hybrid architecture](#hybrid-architecture).

<a id="lfs-pointer-file"></a>
### LFS pointer file (the 135-byte file problem)

A short text note that `git` leaves in place of a large file when
[git-lfs](#git-lfs) is missing or has not fetched the real content yet.

**Why you care here.** This is the number one failure in this setup. The
download reports success. The folder looks complete. But the weight files are
135 bytes each instead of several GB, and nothing tells you until the server
fails in a confusing way. Two scripts here check for it:
`bin/verify-model.sh` and `bin/serve.sh` both refuse to continue if any weight
file is under 1 MB.

### linear attention

A cheaper kind of [attention](#attention) that keeps one fixed-size summary of
everything so far, instead of a growing record of every [token](#token).

**Why you care here.** Forty-eight of this model's 64 [layers](#layer) work this
way (MEASURED). Their memory use does not grow as the conversation grows. The
tradeoff is recall: they cannot reliably pull back one exact detail from far
earlier. The 16 [full attention](#full-attention) layers exist to cover that.

### LiteLLM / translation proxy

An extra program that sits between two pieces of software and converts messages
from one format to the other.

**Why you care here.** Most guides for running a local model with Claude Code
need one of these, because the local server speaks a different format. This
setup does not, because the server speaks
[the format Claude Code already uses](#anthropic-messages-api-v1messages). One
fewer program is one fewer thing to configure and one fewer place for a request
to fail.

### llama.cpp

A widely used program for running models locally, written to work on many
different kinds of hardware.

**Why you care here.** It is the best-known alternative. The server used here
includes parts of it, but runs this particular model through [MLX](#mlx)
instead, because MLX is built for the way Apple chips share memory.

### localhost / 127.0.0.1 / loopback

Three names for the same thing: the address your Mac uses to talk to itself.
Traffic sent there never reaches a network.

**Why you care here.** This is the security boundary in this setup. The server
listens only on this address, so nothing outside your Mac can reach it, even on
a shared wifi network. Compare [0.0.0.0](#0000-and-why-it-is-dangerous-here).

---

## M

### MEASURED vs NOT YET MEASURED

A labeling rule used throughout this repository. MEASURED means the number was
recorded by running something on the test machine. NOT YET MEASURED means it was
not, and no one should treat it as fact.

**Why you care here.** The test machine is an Apple M3 Max with 30 GPU cores,
36 GB of memory, and macOS 26.5.2. No speed figure for the 27B has been
measured on it or anywhere else; the one measured speed is 57 tokens per second
for the 9B, one short run of `bin/bench.sh`. A third label, PUBLISHER-REPORTED,
marks numbers published by the people who made the model and not reproduced
here.

### model lock

A marker one program leaves behind to say "I am using this, wait your turn". The
next program checks for it, finds it, and stops instead of going ahead.

**Why you care here.** Only one program on your Mac may hold the model, because
two copies of about 19.1 GB do not fit in 36 GB. A second `./bin/serve.sh`
refuses and names the one already running, rather than loading and stalling your
Mac. The marker is a folder at `~/.airgap/model.lock` holding the [process
id — the number macOS gives every running program — of the program that owns it.
That number is how a marker left behind by a crash is told apart from one held
by a program still running, and taken over rather than obeyed.
`./bin/doctor.sh` reports which of the three it is.

### memory-bandwidth bound

A situation where the limit on speed is how fast data moves out of memory, not
how fast the processor can compute.

**Why you care here.** Producing one [token](#token) requires reading all
19.1 GB of [weights](#weights). The processor spends most of that time waiting.
This is why [speculative decoding](#speculative-decoding) is such a large win:
checking several guessed tokens costs one trip through the weights, nearly the
same as producing one token.

### memory pressure

macOS's own measure of how short of memory it is.

**Why you care here.** You can see it in the Activity Monitor app, under the
Memory tab. If the graph is yellow or red before you start the server, the
model will not fit. Close applications first.

### Metal

Apple's software layer for using the graphics processor in a Mac.

**Why you care here.** It is what actually runs the model's arithmetic. You
never call it directly; [MLX](#mlx) does. It is the Apple equivalent of
[CUDA](#cuda).

### MLX

Apple's software library for running machine learning models on
[Apple Silicon](#apple-silicon) Macs.

**Why you care here.** It is the reason this works on a laptop at all. MLX is
built around [unified memory](#unified-memory), so the model is loaded once and
both processors read the same copy. Nothing is copied back and forth.

### mlx-lm

The standard command-line tool for running language models with [MLX](#mlx).

**Why you care here.** This repository does not use it for serving, for one
specific reason: as of version 0.31.3, mlx-lm deletes this model's built-in
guesser when it loads the file. The change that would keep it has been proposed
but not accepted. That single fact is why this repository uses
[mlx-serve](#mlx-serve). See
[multi-token prediction (MTP)](#multi-token-prediction-mtp).

### mlx-serve

The [inference server](#inference-server) this repository uses. It keeps the
model loaded and answers requests.

**Why you care here.** Two reasons it was chosen over the alternatives: it keeps
this model's built-in guesser instead of deleting it, and it speaks
[Claude Code's own message format](#anthropic-messages-api-v1messages) directly,
so no [translation proxy](#litellm--translation-proxy) is needed.

### model

The trained file or set of files that produces text, plus the design that
describes how those files are used.

**Why you care here.** In this repository, "the model" always means the one
folder you download. See [weights](#weights) and [checkpoint](#checkpoint).

### model id

The name a program must send when it asks the server for a particular model.

**Why you care here.** For this server, the name is exactly the model folder's
name. Rename the folder and the name changes, and Claude Code stops being able
to ask for it. The default name here is
`Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit`.

### Model Context Protocol (MCP)

An agreed way for [Claude Code](#claude-code) to connect to extra tool servers
that give it new abilities, such as reading a database or browsing the web.

**Why you care here.** Every connected tool server adds a description of its
tools to the instructions sent to the model, on every turn. Measured here: 38,054
[tokens](#token) with them loaded against 20,909 without. On a model with a
65,536-token [context window](#context-window), that is a quarter of your space
spent before you type anything. See
[`--strict-mcp-config`](#--strict-mcp-config).

### `model_type` (and why it says `qwen3_5`)

A field in the model's configuration file that names the design family the model
belongs to. Programs read it to decide how to load the model.

**Why you care here.** This model is called Qwen3.8-27B, but its `model_type`
reads `qwen3_5`. That is correct and not an error. The name of a model and the
name of its design family are different things: every Llama 3.1, 3.2 and 3.3
model reports `model_type` as `llama` in the same way. You can open
`config.json` inside the model folder and read the line yourself.

### multi-token prediction (MTP)

An extra piece built into this model whose job is to guess the next few
[tokens](#token) quickly, so the full model can check several at once.

**Why you care here.** It removes the need for a second guesser model, which
would cost more memory. This copy of the model contains 29 pieces belonging to
it (MEASURED, read from the weight files themselves by
`bin/verify-model.sh`). The publisher reports 6.81 seconds with it against 10.15
seconds without, on identical output (PUBLISHER-REPORTED; NOT YET MEASURED
here). See [speculative decoding](#speculative-decoding).

---

## O

### OpenAI chat completions API

A different agreed message format, used by many model providers and by most
local model tools.

**Why you care here.** The local server speaks this format too, on the same
port, which is useful for other programs. Claude Code does not use it. See
[Anthropic Messages API](#anthropic-messages-api-v1messages).

### out of memory (OOM)

The state where a program asks for memory that is not available. On macOS, the
usual result is that the program is shut down.

**Why you care here.** This is a recoverable outcome, not a dangerous one. The
server stops, your other applications keep running, and the memory comes back.
The memory check in `bin/serve.sh` exists to turn this into a clean refusal
before anything is loaded.

### outlier channels

A small number of positions inside a model's weights that hold values far larger
than the rest.

**Why you care here.** They are the main source of accuracy loss when
[quantization](#quantization) shrinks the numbers, because the size of the
largest value sets the scale for everything sharing its group. Spreading them
out first is what [Hadamard rotation](#hadamard-rotation) does.

---

## P

### port

A numbered door on a machine, so that several programs can each listen for
network traffic without colliding.

**Why you care here.** The local server uses port 11234 by default. If something
else on your Mac already uses that number, the server will not start, and you
change the number rather than fight over it.

### prefill

The stage where the model reads everything sent to it before it writes a single
word of reply.

**Why you care here.** With Claude Code, prefill is at least 20,909
[tokens](#token) of instructions on every turn (MEASURED). It is why the
[prefix cache](#prefix-cache) matters so much here.

**Think of it like** reading a long email before starting to type an answer. The
comparison stops working because the model re-reads the entire thread from the
first message on every reply, not only the new part.

### prefix cache

Stored [KV cache](#kv-cache) from earlier requests, kept so that an identical
opening stretch of text does not have to be read again.

**Why you care here.** Claude Code sends nearly the same 20,909-token opening
every turn. On the second turn, the server reported reusing 16,384 of 20,906
tokens (MEASURED). That is work skipped entirely.

**Think of it like** a bookmark that lets you resume a book instead of starting
from page one. The comparison stops working because the bookmark is only valid
if every single word up to that point is unchanged; one edited word earlier in
the text invalidates everything after it.

### prompt

The text you send to the model.

**Why you care here.** What you type is a small part of what is actually sent.
Claude Code adds instructions, tool descriptions, file contents, and the
conversation so far. See [system prompt](#system-prompt).

### prompt lookup decoding (PLD)

A guessing method that looks for the text the model is about to produce inside
the text it was given, and proposes it directly.

**Why you care here.** When Claude Code edits a file, the model repeats large
stretches of that file back nearly unchanged. Those stretches are already in the
[prompt](#prompt), so they can be guessed at almost no cost. This helps most on
edits and helps least on original writing. That difference is expected behavior,
not a fault. See [speculative decoding](#speculative-decoding).

### Prometheus metrics endpoint

A web address on the server that reports its own performance numbers in a
standard format.

**Why you care here.** It is how you read speed, guess acceptance rate, and
cache hit rate without guessing. This repository turns it on by default.

### Python virtual environment (venv)

A private folder holding one project's Python add-ons, so they cannot conflict
with any other project's.

**Why you care here.** This repository can build one, but it is optional and off
by default. Nothing in the main path needs it. It is excluded from `git` because
it contains file paths specific to your Mac and breaks on anyone else's.

---

## Q

### quantization

Storing a model's numbers with fewer digits than it was trained with, so it
takes less space and less time to read.

**Why you care here.** Without it this model needs about 54 GB and fits on no
laptop. At [5-bit](#5-bit) it needs 19.1 GB and fits in 36 GB of memory with
room to work. The cost is a small, real loss of quality.

**Think of it like** rounding prices to the nearest dollar instead of tracking
cents. Totals stay close, and the file gets much smaller. The comparison stops
working because the rounding here is done per small group of numbers, each with
its own scale, so accuracy is preserved much better than plain rounding.

---

## R

### recurrent state

A single fixed-size running summary that a [layer](#layer) updates as each new
[token](#token) arrives.

**Why you care here.** It is what the 48 cheap [layers](#layer) keep instead of
a growing record. Fixed size means their memory cost does not change as the
conversation gets longer. It also means you cannot rewind to an earlier point
inside it, which is why the [prefix cache](#prefix-cache) needs a special
mechanism here. See [SSM checkpoint](#ssm-checkpoint).

### repository

A folder tracked by [`git`](#git), usually shared online. Often shortened to
"repo".

**Why you care here.** Two are involved. This one holds the scripts and
documents, and is a few hundred KB. The model's own repository holds the
[weights](#weights), and is about 20 GB. This one contains no model files at
all.

### runtime

The software that actually executes a model.

**Why you care here.** In this setup it is [MLX](#mlx), driven by
[mlx-serve](#mlx-serve). Choosing the right runtime is the decision this whole
repository rests on, because the obvious choice
([mlx-lm](#mlx-lm)) removes this model's built-in guesser.

---

## S

### safetensors

A file format for storing model [weights](#weights) that is quick to read and
cannot execute code when opened.

**Why you care here.** The weights arrive as 5 files with this extension. Each
begins with a short readable description of its contents, which is how
`bin/verify-model.sh` inspects the download by reading a few hundred KB rather
than loading 19.1 GB.

### script

A file of commands that runs them in order, so you type one thing instead of
twenty.

**Why you care here.** Everything in the `bin` folder (relative to the
repository root) is a script. They are plain text. You can open any of them in a
text editor and read exactly what they will do before you run them.

### SHA-256 / checksum

A short fingerprint calculated from a file or a piece of text. Identical input
always gives an identical fingerprint; any change gives a completely different
one.

**Why you care here.** The benchmark script prints the fingerprint of the
model's output with the guessing feature on and off. Matching fingerprints prove
the two outputs are identical, character for character, so the speed gain costs
no accuracy.

### shard

One file out of a set that together make up a model too large for a single file.

**Why you care here.** This model's [weights](#weights) arrive as 5 shards
(MEASURED). All 5 must be complete. One shard left as a
[pointer file](#lfs-pointer-file-the-135-byte-file-problem) breaks the whole
model.

### shell

The program inside [Terminal](#terminal) that reads what you type and runs it.

**Why you care here.** The scripts here are written for `bash`, which every Mac
has. Recent versions of macOS open Terminal with a different one, `zsh`. That
difference does not matter, because each script names the one it needs on its
first line.

### speculative decoding

A technique where a cheap guesser proposes several [tokens](#token) ahead and
the full model checks them all in one pass, keeping the correct ones.

**Why you care here.** It is faster with no change to the output. Checking
several guesses costs one trip through the 19.1 GB of [weights](#weights), which
is nearly the cost of producing one token. Rejected guesses cost nothing but the
guess. The result is exact, which the benchmark script proves with matching
[fingerprints](#sha-256--checksum).

**Think of it like** a colleague finishing your sentences while you nod or shake
your head. You still approve every word, so the meaning never changes; you save
only the time spent forming each word. The comparison stops working because a
wrong guess costs you nothing here, whereas a person would have to be
interrupted.

### stall timeout

A limit on how long something may produce **nothing** before it is given up on.
Not a limit on how long it may take in total: work that keeps producing output
is never cut off, however long it runs.

**Why you care here.** `SERVE_TIMEOUT` (default 300 seconds) is how long the
server waits on a question that has not yet produced a single word. The turn
most likely to reach it is the first one after an idle period, which reloads the
model and then reads about 21,000 tokens of instructions before it can start
answering — see [prefill](#prefill). Claude Code has a limit of its own, also
300 seconds, so `bin/claude-local.sh` gives it a minute longer than the server:
that way the server gives up first, and the side that can say why is the side
that reports it.

### SSM checkpoint

A saved copy of the fixed-size running summary held by the cheap
[layers](#layer), taken at intervals during reading.

**Why you care here.** The [prefix cache](#prefix-cache) works by resuming from
a point partway through the text. The [full attention](#full-attention) layers
allow that naturally. The cheap layers do not, because their
[recurrent state](#recurrent-state) has no earlier version inside it. Saving
copies at intervals is what makes resuming possible for them.

### `--strict-mcp-config`

See [`--strict-mcp-config`](#--strict-mcp-config) in the symbols section at the
top of this page.

### subagent

A second, separate conversation that [Claude Code](#claude-code) starts on its
own to handle a side task, using its own [context window](#context-window).

**Why you care here.** Claude Code picks a model for these separately from your
main one. The launch script here points that setting at the local model too, so
background work cannot quietly reach Anthropic's servers.

### `sudo`

A command prefix that runs the next command with administrator rights. It asks
for your Mac's password.

**Why you care here.** Nothing in the normal path of this repository needs it.
Any document that shows a `sudo` command states what it changes, whether a
reboot undoes it, and why you might skip it. See
[`iogpu.wired_limit_mb`](#iogpuwired_limit_mb).

### swapping / thrashing

Swapping is macOS moving memory it is not using out to disk to make room.
Thrashing is what happens when it has to do this constantly.

**Why you care here.** Thrashing is what a Mac that is out of memory feels like:
the cursor stutters, applications stop responding, and the fans spin up. It is
recoverable, and the memory check in `bin/serve.sh` exists to prevent it.

### `sysctl`

The command for reading and changing low-level macOS settings.

**Why you care here.** Exactly one setting in this stack is worth reading with
it, and this repository recommends reading it and not changing it. See
[`iogpu.wired_limit_mb`](#iogpuwired_limit_mb).

### system prompt

The block of instructions a program puts in front of your message, telling the
model how to behave and what tools it has.

**Why you care here.** Claude Code's is 20,909 [tokens](#token) with tool
servers turned off, and 38,054 with them on (both MEASURED). You never see it,
and it is sent again on every single turn.

---

## T

### temperature

A setting that controls how much randomness the model uses when picking each
next word. Zero means always pick the most likely one.

**Why you care here.** The benchmark script uses zero. That is what makes the
comparison meaningful: with no randomness, two runs must produce identical text,
so any difference would mean a real change in behavior.

### tensor

One block of numbers inside a model, stored as a named grid.

**Why you care here.** This [checkpoint](#checkpoint) contains 2207 of them
(MEASURED): 504 shrunk weight grids, 333 belonging to the unused image
component, and 29 belonging to the built-in guesser.

### Terminal

The Mac application where you type commands instead of clicking.

**Why you care here.** It is where everything in this repository happens. It is
already installed. Open it from the Applications folder, inside Utilities, or by
pressing Command and Space and typing its name.

### throughput vs latency

Throughput is how much total work a server finishes over time. Latency is how
long your one request takes.

**Why you care here.** Only latency matters to you. Server software built for
data centers optimizes throughput, using techniques such as
[batching](#batching) that do nothing for a single user. That is a large part of
why such software is the wrong choice here.

### token

A chunk of text the model works in. Roughly three quarters of an English word on
average, so 100 tokens is about 75 words.

**Why you care here.** Every limit, cost, and speed number in this repository is
counted in tokens. The 65,536-token [context window](#context-window) is
somewhere near 49,000 words of conversation, instructions and file contents
combined.

**Think of it like** syllables rather than letters or words: some short words
are one token, longer or unusual words split into several. The comparison stops
working because the split follows what the text looked like in the model's
training data, not how the word is pronounced.

### tokens per second (tok/s)

How many [tokens](#token) the model produces each second. The direct measure of
how fast text appears on your screen.

**Why you care here.** This figure for the 27-billion-parameter model is NOT
YET MEASURED in this repository. The one figure on record is 57 tok/s for the
9B in the catalog, one short greedy run of `bin/bench.sh` on the test machine
(MEASURED). It depends heavily on [GPU cores](#gpu-cores), so a figure from
one Mac tells you little about another, and a figure for one model tells you
nothing about a bigger one.

### tool call (`tool_use` / `tool_result`)

A message where the model asks the program to do something concrete, such as
read a file, and a second message carrying back the result.

**Why you care here.** This is how [Claude Code](#claude-code) works at all.
Long chains of tool calls are the hardest thing for a smaller local model. Short,
well-scoped tasks are where this setup performs best.

### transformer

The design nearly all current language models are built on. It stacks many
identical processing [layers](#layer), each using
[attention](#attention).

**Why you care here.** This model is a transformer with a change: its layers are
not all identical. See [hybrid architecture](#hybrid-architecture).

### turbo4

The setting this repository uses for storing the [KV cache](#kv-cache): four
bits per number, with a [Hadamard rotation](#hadamard-rotation) applied first.

**Why you care here.** It uses the same space as plain four-bit storage but
loses less accuracy, because the rotation spreads the extreme values before they
are shrunk. If quality drops on long conversations, this is the first setting to
change.

---

## U

### unified memory

One pool of memory shared by the main processor and the graphics processor on
[Apple Silicon](#apple-silicon) Macs.

**Why you care here.** It is the whole reason a 36 GB laptop can run a model
that would need an expensive graphics card elsewhere. The model is loaded once
and both processors read the same copy.

**Think of it like** two people working from one shared desk instead of each
having a private desk and passing papers between them. The comparison stops
working because the desk is also where macOS and all your applications keep
their papers, so the model is competing with everything else you have open.

### unrecognized_model warning

A one-line message [Claude Code](#claude-code) prints at startup when it does
not know the model name you gave it.

**Why you care here.** This one is EXPECTED. Claude Code has never heard of a
local model name, so it says so and continues normally. It is not an error and
nothing is broken. It appears on every launch.

---

## V

### vision tower / vision-language model (VLM)

The part of a model that processes images. A model with one is a
vision-language model.

**Why you care here.** This model has one: 333 [tensors](#tensor) of it
(MEASURED). Claude Code sends text, so this repository skips loading it, which
saves memory. That is the difference between the 19.1 GB actually loaded and the
larger figure on disk.

### vLLM

A widely used [inference server](#inference-server) built for data centers with
NVIDIA graphics cards.

**Why you care here.** It is often recommended and it is the wrong tool here.
It needs [CUDA](#cuda), which no Mac has, and it optimizes for
[throughput](#throughput-vs-latency) across many users rather than latency for
one.

### VRAM (and why Macs do not have it)

Memory attached directly to a graphics card, separate from the computer's main
memory.

**Why you care here.** Guides written for graphics cards talk about fitting a
model "in VRAM" and about copying data back and forth. Your Mac has no separate
pool, so none of that applies. See [unified memory](#unified-memory).

---

## W

### weights

The numbers a model learned during training. They are the model's knowledge, and
they are what the download consists of.

**Why you care here.** These weights take 19.1 GB in memory (MEASURED,
text-only). All of them must be in memory at once, and all of them are read for
every [token](#token) produced.

### wired memory

Memory that macOS has locked in place and cannot move to disk under any
circumstances.

**Why you care here.** Model weights on the graphics processor are wired. Normal
memory shortage makes a Mac slow, because macOS can move things aside. Wired
memory removes that option, which is why the setting that governs it is the one
genuinely risky knob here. See
[`iogpu.wired_limit_mb`](#iogpuwired_limit_mb).

**Think of it like** a parking space marked reserved with a bollard. Nobody else
can use it, even while it sits empty. The comparison stops working because you
cannot tow a wired page: if macOS runs short elsewhere, it has no way to reclaim
this space at all.

### working directory

The folder your [Terminal](#terminal) window is currently pointed at. Commands
that use a relative path act inside it.

**Why you care here.** Running a script from the wrong folder is a common and
confusing failure. Every set of commands in these documents begins with a
[`cd`](#cd) to a full path, so it does not matter what came before.

---

## Where to go next

- New here: start at the [main README](../README.md).
- Something is broken: go to [06 — Troubleshooting](06-troubleshooting.md).
- You want the engineering behind these words:
  [08 — How it works](08-how-it-works.md).
