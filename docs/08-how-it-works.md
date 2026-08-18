# 08 — How it works

**Who this is for.** Anyone who has the stack running, or who is curious before
installing it, and wants to know *why* a 27-billion-parameter model fits on a
laptop and answers in seconds. You do not need to know any mathematics beyond
multiplication and division. You do not need to have written code. You do need
to be willing to read carefully.

**What you will have at the end.** A working mental model of every moving part:
what a word-piece is, why writing text is limited by memory speed rather than by
arithmetic, what quantization costs you, why this model's memory grows so slowly,
and how it writes several words for the price of one. You will also be able to
check every factual claim on this page yourself, with commands that read a few
hundred kilobytes and change nothing.

**How long it takes.** About 40 minutes of your attention if you read the whole
page. About 15 minutes if you skip every block marked "For the curious". There is
no waiting for downloads: this page assumes you already have the model folder,
and it never starts the server.

**What it costs.** No disk space. No memory beyond what your text editor uses. No
money. Nothing on this page sends anything to the internet, and nothing on this
page loads the 20 GiB model into memory.

**What you need first.**

- The model folder on disk. Get it with [03 — Get the model](03-get-the-model.md).
- A Terminal window. Terminal is the macOS app where you type commands instead of
  clicking. [02 — Install](02-install.md) opens it for the first time.
- Nothing else. The server does not need to be running.

**If you only read one thing:** read section 3, "Why writing text is limited by
memory speed". Almost every design decision in this repository follows from it.

---

## What this page is not

This page does not install anything and does not fix anything.

- To install, read [02 — Install](02-install.md).
- To run the stack, read [05 — Run it](05-run-it.md).
- When something is broken, read [06 — Troubleshooting](06-troubleshooting.md).
- When a word here means nothing to you, read [09 — Glossary](09-glossary.md).
  Every technical word on this page is explained where it first appears, and the
  glossary repeats the explanation in one place.

---

## How to read the commands on this page

Every command on this page only reads files. None of them writes, deletes,
downloads, or starts anything.

All of them run from the repository folder. That is the folder you cloned in
[02 — Install](02-install.md). Throughout these documents it is written as
`~/dev/local-llms/airgap`. Yours is wherever you cloned it.

**Go to the repository folder.** Replace `<YOUR_REPO_FOLDER>` with the full path
to your copy. A worked example: if you cloned into a `dev` folder inside your
home folder, the path is `~/dev/local-llms/airgap`.

```bash
cd <YOUR_REPO_FOLDER>
```

This prints nothing. That is success. Terminal returns to a fresh line and waits
for your next command.

**If you do not see that**, and instead see `cd: no such file or directory`, the
path is wrong. Find the folder in Finder, drag it onto the Terminal window, and
Terminal will type the correct path for you.

Every section below that contains commands repeats this step. Terminal windows
get closed, and you should never have to remember where a previous section left
you.

---

## 1. What a language model actually does

### The claim, in plain words

The model does one thing, over and over: it looks at all the text so far and
guesses the next small piece of text. Then it adds that piece to the text and
guesses again. Everything else in this document is machinery to make that one
step fast enough to be useful.

A **large language model** (LLM) is a very large table of numbers, together with
the arithmetic that turns text into a guess about what comes next. The numbers
are called the **weights**. In this setup the weights are about 19 GiB of files
on your disk. (See the **large language model** and **weights** entries in the
[Glossary](09-glossary.md).)

The small pieces of text are called **tokens**. A token is usually a whole common
word, sometimes a fragment of a longer word, sometimes a space or a punctuation
mark. (See the **token** entry in the [Glossary](09-glossary.md).)

### An analogy, and where it stops being true

Think of it like the autocomplete on your phone, with two differences. First, it
has read far more text than your phone's autocomplete. Second, it does not
suggest one word for you to tap — it accepts its own suggestion and immediately
suggests the next one, thousands of times in a row.

The analogy stops being true in one important place. Your phone's autocomplete
looks at the last word or two. This model looks at everything in front of it,
which can be tens of thousands of tokens. That difference is the whole reason
this document needs a section about memory.

### The evidence you can check

The list of pieces this model knows is a file in the model folder called
`vocab.json`. You can look inside it.

**Go to the repository folder.** Replace `<YOUR_REPO_FOLDER>` with the full path
to your copy.

```bash
cd <YOUR_REPO_FOLDER>
```

This prints nothing. That is success.

**Count the pieces the model knows, and test a few words against the list.** This
is one command. Copy the whole block, including the last line that reads `PY`.

```bash
python3 - <<'PY'
import json
v = json.load(open("Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit/vocab.json"))
print("pieces in this model's vocabulary:", len(v))
for word in ["Ġthe", "Ġmodel", "ĠMac", "Ġunbelievable", "Ġquantization", "Ġquant", "ization"]:
    print("%-16s %s" % (word.replace("Ġ", "_"), "one piece" if word in v else "split into pieces"))
PY
```

You should see something like this:

```
pieces in this model's vocabulary: 248044
_the             one piece
_model           one piece
_Mac             one piece
_unbelievable    one piece
_quantization    split into pieces
_quant           one piece
ization          one piece
```

MEASURED on the test machine, reading the checkpoint files in this repository.
The leading underscore stands for a leading space, which is how this model marks
the start of a word. Nothing in this output changes from machine to machine: it
is a property of the model files, not of your Mac.

Read the last three lines together. The word "quantization" is not in the list,
so the model spells it as two pieces, `_quant` and `ization`. The word
"unbelievable" is longer and it *is* one piece. The rule is not length. The rule
is how often the word appeared in the text the model learned from.

**If you do not see that**, and instead see
`No such file or directory: 'Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit/vocab.json'`,
you are either in the wrong folder or the model is not downloaded yet. Run the
`cd` command from "How to read the commands on this page" above, then read
[03 — Get the model](03-get-the-model.md).

### For the curious: why 248044 and not 248320

`config.json` in the model folder reports `vocab_size: 248320`, while
`vocab.json` holds 248044 entries. The difference is reserved slots for special
markers that are not ordinary text — the marker that says "a conversation turn
starts here", the markers that wrap an image, and so on. Two of them are visible
in `config.json` as `image_token_id: 248056` and `video_token_id: 248057`, both
above the 248044 boundary.

---

## 2. Context window: the model's desk, not its memory

### The claim, in plain words

The model has no memory between requests. Every single time it writes a token, it
is handed the entire conversation from the beginning and reads all of it again.
The largest amount of text it can be handed at once is called the **context
window**, and it is measured in tokens. (See the **context window** entry in the
[Glossary](09-glossary.md).)

In this repository the context window is set to 65536 tokens. That is roughly
49,000 English words, or a short novel. The model architecture allows up to 262144
tokens, and section 5 explains why that number is unusually large and why this
repository does not use it.

### An analogy, and where it stops being true

Think of it like a desk, not like a brain. Everything the model can refer to has
to be laid out on the desk in front of it. When the desk is full, something has
to come off the desk, and the model has no recollection of it at all.

The analogy stops being true in one way: a person clears a desk by choosing what
to remove. The model does not choose. The program driving it — here, Claude Code
— decides what to keep, which is why long conversations with a coding assistant
eventually get summarized and shortened.

### The evidence you can check

The maximum the architecture allows is written in the model's own configuration
file.

**Go to the repository folder.** Replace `<YOUR_REPO_FOLDER>` with the full path
to your copy.

```bash
cd <YOUR_REPO_FOLDER>
```

**Read the three numbers that set the memory arithmetic for the rest of this
page.** The path in this command is relative to the repository folder.

```bash
python3 -c "import json;t=json.load(open('Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit/config.json'))['text_config'];print('kv heads',t['num_key_value_heads'],'| head dim',t['head_dim'],'| max positions',t['max_position_embeddings'])"
```

You should see something like this:

```
kv heads 4 | head dim 256 | max positions 262144
```

MEASURED on the test machine, reading `config.json` in the model folder. None of
these three numbers changes from machine to machine. Section 4 uses the first two
to work out exactly how much memory each token of conversation costs.

**If you do not see that**, and instead see a `No such file or directory` error,
run the `cd` command above first. If it says `KeyError`, you are pointing at a
different model, whose configuration file is laid out differently.

The context window this repository actually uses is a separate setting, in
`bin/env.sh` at the repository root. It is `CTX_SIZE`, and its default is 65536.
[07 — Tuning](07-tuning.md) explains how to change it and what it costs.

---

## 3. Why writing text is limited by memory speed, not by mathematics

This is the most important section on the page. Read it even if you skip
everything else.

### The claim, in plain words

To produce **one** token, your Mac has to read **all** of the model's weights out
of memory. Every one of the 19 GiB. It does that again for the next token, and
again for the one after that.

The arithmetic involved is small. The reading is enormous. So the speed you feel
is set almost entirely by how fast your Mac can move bytes out of memory, not by
how clever or fast its processors are. The technical name for this is
**memory-bandwidth bound**. (See the **memory-bandwidth bound** entry in the
[Glossary](09-glossary.md).)

Every trick in the rest of this document is a way of getting more useful output
out of one pass through those bytes.

### An analogy, and where it stops being true

Think of it like this. You have a library of 19000 books. To write a single word,
the rule says you must walk past every shelf. Walking takes an hour. Writing the
word takes a second.

Now here is the interesting part. If someone hands you a guess at the next five
words before you set off, you can check all five guesses during the same walk.
The walk costs the same. That is speculative decoding, and it is section 6.

The analogy stops being true in one place: you would not really need to read
every book to write one word, and neither does a person. The model does, because
the arithmetic it performs genuinely touches every weight.

### The evidence you can check

**Go to the repository folder.** Replace `<YOUR_REPO_FOLDER>` with the full path
to your copy.

```bash
cd <YOUR_REPO_FOLDER>
```

**Measure how many bytes have to be read for each token, by adding up the weight
files.** This is one command. Copy the whole block, including the last line that
reads `PY`.

```bash
python3 - <<'PY'
import glob, json, struct
group = {"vision tower": 0, "MTP head": 0, "word table": 0, "everything else": 0}
for shard in sorted(glob.glob("Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit/*.safetensors")):
    with open(shard, "rb") as f:
        size = struct.unpack("<Q", f.read(8))[0]
        header = json.loads(f.read(size))
    for name, info in header.items():
        if name == "__metadata__":
            continue
        start, end = info["data_offsets"]
        if name.startswith("vision_tower."):
            group["vision tower"] += end - start
        elif ".mtp." in name:
            group["MTP head"] += end - start
        elif "embed_tokens" in name:
            group["word table"] += end - start
        else:
            group["everything else"] += end - start
total = sum(group.values())
for name in group:
    print("%-18s %6.2f GiB" % (name, group[name] / 1073741824))
print("%-18s %6.2f GiB" % ("TOTAL on disk", total / 1073741824))
print("%-18s %6.2f GiB" % ("loaded at run time", (total - group["vision tower"]) / 1073741824))
PY
```

You should see something like this:

```
vision tower         0.86 GiB
MTP head             0.34 GiB
word table           2.37 GiB
everything else     16.41 GiB
TOTAL on disk       19.97 GiB
loaded at run time  19.12 GiB
```

MEASURED on the test machine, by reading only the index at the front of each
weight file. This command reads a few hundred kilobytes, not 20 GiB. None of
these numbers changes from machine to machine.

This command is worth understanding, because it quietly proves four separate
claims used later on this page:

| Line | What it proves |
|---|---|
| `vision tower 0.86 GiB` | The picture-reading part is real and separable. The server skips it, which is where `--no-vision` gets you 0.86 GiB back. |
| `MTP head 0.34 GiB` | The built-in guesser of section 6 is physically in the files, and it is small. |
| `word table 2.37 GiB` | The table that maps word-pieces to numbers is left at full precision on purpose. Section 4 explains why. |
| `loaded at run time 19.12 GiB` | This is the number that must fit in your Mac's memory, and the number that must be read for every token. |

**If you do not see that**, and instead every line reads `0.00 GiB`, the model
folder is empty or is somewhere else. If the command fails with
`UnicodeDecodeError` or `MemoryError`, one of the weight files is not a real
weight file — most likely it is a 135-byte placeholder. That specific failure is
the most common one in this whole setup, and it is the first entry in
[06 — Troubleshooting](06-troubleshooting.md).

### For the curious: turning bytes into an upper limit on speed

Apple publishes a memory bandwidth figure for every chip. The M3 Max family is in
the range of 300 to 400 GB per second depending on the exact variant
(PUBLISHER-REPORTED by Apple; not measured in this repository). Look up the
figure for your own chip rather than borrowing this one.

Take 300 GB per second as a worked example, and the 19.12 GiB measured above,
which is 20.5 GB in the decimal units chip vendors use:

```
20.5 GB per token  /  300 GB per second  =  0.068 seconds per token
1 / 0.068                                =  about 15 tokens per second
```

"Tokens per second" is how generation speed is usually quoted. Fifteen tokens per
second is roughly the pace of a fast typist, which is comfortable to read as it
appears. (See the **tokens per second** entry in the [Glossary](09-glossary.md).)

That is a **ceiling**, not a prediction. It assumes perfect memory efficiency and
zero time spent anywhere else. The real figure is lower. This arithmetic is
labeled NOT YET MEASURED: no tokens-per-second number has been recorded for this
27B model on the test machine, and this repository does not print one.

Two consequences follow, and both shape the rest of the design:

1. **Smaller weights are directly faster.** Halving the bytes roughly halves the
   walk. That is section 4.
2. **Getting more than one token out of a single pass is nearly free.** That is
   sections 6 and 7.

<details>
<summary>For the curious: the arithmetic-intensity version of the same statement</summary>

Generating one token with a batch size of one performs on the order of two
floating-point operations per weight. A chip that can sustain, say, tens of
trillions of operations per second, paired with memory that delivers hundreds of
gigabytes per second, is offered roughly two operations for every two bytes
fetched. That ratio is far below the ratio the arithmetic units could consume, so
the arithmetic units idle while memory catches up.

Serving many users at once fixes this by reusing each fetched weight across many
requests in the same pass — that is what **batching** buys, and it is why server
software is built around it. You are one user. Batching has nothing to reuse, so
it buys you nothing here. This is the core of the argument in section 10 about
why vLLM is the wrong tool for this particular job.
</details>

---

## 4. Quantization: making the weights smaller on purpose

### The claim, in plain words

The model was trained with very precise numbers. Storing every number that
precisely would need roughly 54 GB, which does not fit on the test machine.
**Quantization** rounds each number off so it takes fewer bits to store. The model
gets smaller and faster, and it gets slightly worse at its job. (See the
**quantization** entry in the [Glossary](09-glossary.md).)

This checkpoint uses **5 bits** per weight. Section 4's job is to show you why 5
and not 4 or 8.

### An analogy, and where it stops being true

Think of it like saving a photograph as a JPEG. You pick a quality setting. Lower
quality means a smaller file and a picture that is still recognizable but has lost
some detail. You cannot get the detail back.

The analogy stops being true in one place. A JPEG's damage is concentrated in
places you can see, like sharp edges. Quantization damage is spread thinly across
everything the model knows, so it does not show up as one visible flaw. It shows
up as slightly worse judgment, most visibly on long, multi-step tasks.

### The evidence you can check

**Go to the repository folder.** Replace `<YOUR_REPO_FOLDER>` with the full path
to your copy.

```bash
cd <YOUR_REPO_FOLDER>
```

**Read the rounding scheme out of the model's configuration file.** The path is
relative to the repository folder.

```bash
python3 -c "import json;print(json.load(open('Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit/config.json'))['quantization'])"
```

You should see something like this:

```
{'bits': 5, 'group_size': 64, 'mode': 'affine'}
```

MEASURED on the test machine, reading `config.json` in the model folder. This
does not change from machine to machine.

Read it as three facts. `bits: 5` means each weight is stored in 5 bits instead of
16. `group_size: 64` means the weights are rounded in batches of 64, and each
batch of 64 gets its own scale, so a batch of small numbers is not forced to share
a scale with a batch of large ones. `mode: affine` names the specific rounding
formula.

**If you do not see that**, and instead see `KeyError: 'quantization'`, you are
pointing at a model that was not quantized, or at a different model entirely.

### Why 5 bits, with the size arithmetic

The conclusion to draw from this table is that 5 bits is the only setting that
both fits the test machine and leaves room to work.

| Bits per weight | Approximate weight size | What that leaves on a 36 GB Mac |
|---|---|---|
| 4 | about 16.3 GB | Fits with room to spare, and loses the most quality |
| **5** | **about 19.1 GB** | **Fits, with enough left for the conversation and macOS — the setting this repository uses** |
| 8 | about 27.7 GB | Does not leave enough for both macOS and a usable conversation |

The 5-bit row is MEASURED: it is the `loaded at run time 19.12 GiB` line from
section 3, which is 20.5 GB in decimal units. The 4-bit and 8-bit rows were
computed from the publisher's own file listings on huggingface.co, so they are
PUBLISHER-REPORTED rather than measured here. Treat them
as a guide to the shape of the trade, not as precise numbers.

Because this advice depends on how much memory your Mac has, here is the same
question answered per machine. The conclusion to draw is that under 32 GB you
should be running a smaller model, not a smaller version of this one.

| Your Mac's memory | Can it run this 27B model? | What to do |
|---|---|---|
| 16 GB | No | Run a much smaller model. See [01 — Requirements](01-requirements.md). |
| 24 GB | Not recommended | Even the 4-bit build sits at the limit your Mac reserves for the graphics processor. See [04 — Memory safety](04-memory-safety.md). |
| 32 GB | Tight | The 4-bit build works. The 5-bit build needs everything else closed. |
| 36 GB | Workable | This is the test machine. The 5-bit build works with Docker and your browser closed. |
| 48 GB and above | Comfortable | The 5-bit build works without closing anything, and you can raise the context window. |

Full detail per machine, including what to close and why, is in
[01 — Requirements](01-requirements.md) and
[04 — Memory safety](04-memory-safety.md).

### For the curious: what was deliberately left un-rounded

Two things in this checkpoint were kept at full precision on purpose, and section
3's byte breakdown shows one of them directly.

The `word table 2.37 GiB` line is the table that turns each of the 248044 word
pieces into a list of numbers. Rounding that table hurts more than it saves,
because errors introduced there flow into everything downstream. It was left
alone.

The other is inside the MTP head of section 6: its `fc` matrix is stored at full
precision while the rest of the head is rounded.

You can see which parts were rounded and which were not. Rounded parts have a
companion entry ending in `.scales`.

**Count what was rounded and what was not.** The path is relative to the
repository folder.

```bash
python3 -c "import json;w=json.load(open('Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit/model.safetensors.index.json'))['weight_map'];print('total',len(w),'| quantized',sum(1 for k in w if k.endswith('.scales')),'| vision',sum(1 for k in w if k.startswith('vision_tower.')))"
```

You should see something like this:

```
total 2207 | quantized 504 | vision 333
```

MEASURED on the test machine. These three counts are also what
`./bin/verify-model.sh` checks, and they match the publisher's own file list
shipped in the model folder as `ARTIFACT-MANIFEST.json`.

**If you do not see that**, and the counts are lower, the download is incomplete.
Run `./bin/verify-model.sh` from the repository folder, which will name the
missing part.

<details>
<summary>For the curious: quantizing a quantization compounds the damage</summary>

The model folder contains a file named `LINEAGE.json` that records where these
weights came from. Its `precision_parent` field reads:

```
direct floating F16 GGUF plus source-matched floating mmproj; no FP8 intermediate
```

That sentence matters. A common shortcut is to build a 5-bit version from a
version that was already rounded down to 8 bits. Each rounding step adds its own
error, and the errors do not cancel — they stack. This checkpoint was built from a
16-bit parent in one step, so it paid the rounding cost once.

The publisher's own comparison table, in the model folder's `README.md` under
"Bounded matched fidelity", shows the 16-bit-derived builds scoring slightly
better than the 8-bit-derived ones on a standard quality measure. Those figures
are PUBLISHER-REPORTED and were not reproduced here.
</details>

---

## 5. The KV cache, and the hybrid design that keeps it small

### The claim, in plain words

Section 2 said the model re-reads the whole conversation for every token. Doing
that literally would be unbearably slow, so the model keeps notes about everything
it has already read. Those notes are the **KV cache**. (See the **KV cache** entry
in the [Glossary](09-glossary.md).)

The notes grow. Every token you add to the conversation adds a fixed amount of
notes, forever, until the conversation ends. The notes live in the same memory as
the weights, so they compete with them.

Here is what makes this particular model unusual. It has 64 **layers** — 64
stacked processing stages, each refining what the one below produced. In an
ordinary model, all 64 layers keep growing notes. In this model, only 16 do. The
other 48 keep a fixed-size summary that never grows, no matter how long the
conversation gets.

That single design choice is why the KV cache here is four times smaller than
you would expect, and it is why the model can be offered 262144 tokens of context
at all.

### An analogy, and where it stops being true

Think of it like two kinds of note-taking in a long meeting.

Sixteen of the note-takers keep a **verbatim transcript**. They can quote any
sentence from three hours ago exactly. Their notebooks get thicker every minute.

The other forty-eight keep **one index card**, which they rewrite after every
sentence. The card always holds their best current summary. It never gets bigger.
They can tell you the gist of the meeting instantly, but they cannot quote you a
specific sentence from three hours ago.

The analogy stops being true in one important way. The index card is not a lossy
human summary that forgets randomly. It is a fixed-size mathematical state,
updated by a precise rule, and it is very good at carrying forward the kind of
information that turns out to matter. But it genuinely cannot reproduce an
arbitrary token from far back, and that is exactly why the sixteen transcripts
exist.

The technical names: the transcript-keepers are **full attention** layers. The
index-card holders are **linear attention** layers, and the specific design used
here is called **Gated DeltaNet** (GDN). A model that mixes both is a **hybrid
architecture**. (See the **full attention**, **linear attention**, **Gated
DeltaNet** and **hybrid architecture** entries in the
[Glossary](09-glossary.md).)

### The layer stack, drawn

```
   layer   0  linear   (index card, fixed size)
   layer   1  linear   (index card, fixed size)
   layer   2  linear   (index card, fixed size)
   layer   3  FULL     (transcript, grows with every token)
   layer   4  linear
   layer   5  linear
   layer   6  linear
   layer   7  FULL     (transcript, grows with every token)
   (layers 8 through 59 repeat the same three-then-one pattern)
   layer  60  linear
   layer  61  linear
   layer  62  linear
   layer  63  FULL     (transcript, grows with every token)

   totals:  48 linear  +  16 FULL  =  64 layers
```

Legend, one line per element:

- **layer** — one processing stage. Text enters at layer 0 and leaves at layer 63,
  refined a little by each stage.
- **linear** — a Gated DeltaNet stage. Holds a fixed-size summary. Its memory cost
  is the same whether your conversation is 10 tokens or 100000 tokens long.
- **FULL** — a full-attention stage. Holds a transcript that grows by a fixed
  amount per token. These 16 stages are the only ones that consume growing memory.
- **the repeating pattern** — every 4th layer is a FULL layer. That spacing is a
  setting in the model's configuration file called `full_attention_interval`.
- **the bracketed line in the middle** — this is a drawing, not command output.
  Layers 8 through 59 follow the same three-then-one pattern shown above and below
  it. The command in the next section prints the real, complete list.

### The evidence you can check

**Go to the repository folder.** Replace `<YOUR_REPO_FOLDER>` with the full path
to your copy.

```bash
cd <YOUR_REPO_FOLDER>
```

**Count the two kinds of layer, and read the spacing between the full ones.** The
path is relative to the repository folder.

```bash
python3 -c "import json,collections;t=json.load(open('Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit/config.json'))['text_config'];print(collections.Counter(t['layer_types']));print('every Nth layer is full:',t['full_attention_interval'])"
```

You should see something like this:

```
Counter({'linear_attention': 48, 'full_attention': 16})
every Nth layer is full: 4
```

MEASURED on the test machine, reading `config.json` in the model folder. This
does not change from machine to machine.

**If you do not see that**, and instead see `KeyError: 'layer_types'`, you are
pointing at a model that is not a hybrid. Ordinary models do not have this field,
because all their layers are the same kind.

### What that means for memory, with the arithmetic

Each token of conversation costs a fixed number of bytes of transcript. The
formula for this model, using the numbers you printed in section 2:

```
   16 full layers
 x  2                (one transcript for keys, one for values)
 x  4 kv heads       (num_key_value_heads from config.json)
 x  256 dimensions   (head_dim from config.json)
 x  2 bytes          (16-bit storage)
 = 65536 bytes       = exactly 64 KiB per token
```

A conventional model of the same shape, where all 64 layers keep transcripts,
would cost 256 KiB per token — four times as much. That factor of four is the
whole point of the hybrid design.

This repository stores those transcripts rounded down to 4 bits rather than 16,
using a setting called `KV_QUANT` whose default value is `turbo4`. That divides
the cost by four again, to 16 KiB per token. So:

```
conversation memory  =  context window in tokens  /  65536   GiB
```

65536 tokens costs exactly 1.0 GiB. The conclusion to draw from the table below is
that the context window is a direct purchase of memory, and the hybrid design is
what makes the price affordable.

| Context window | This model, 4-bit notes | This model, 16-bit notes | A conventional 64-layer model, 16-bit notes |
|---|---|---|---|
| 65536 tokens (this repo's default) | 1.0 GiB | 4.0 GiB | 16.0 GiB |
| 131072 tokens | 2.0 GiB | 8.0 GiB | 32.0 GiB |
| 262144 tokens (the architectural maximum) | 4.0 GiB | 16.0 GiB | 64.0 GiB |

Every figure in that table is arithmetic from the formula above, which is exact
for this architecture. It is not a benchmark and does not depend on your Mac.
The scripts do not carry the formula: they read the growing-layer count and the
head sizes from the selected checkpoint's own `config.json` and scale by
`KV_QUANT`, so the same arithmetic comes out right for the 9B in the catalog
(half the layers, half the cost) and for a conventional model (every layer, four
times the cost) without anyone editing a constant.

Look at the bottom-right cell. A conventional model at full context would need 64
GiB of notes on top of 19 GiB of weights. That is why 262144 is printed in this
model's configuration file and not in a conventional model's.

Two honest warnings. First, 262144 is the architectural maximum, not a practical
one on 36 GB — the 4.0 GiB of notes is affordable, but the time spent reading a
quarter of a million tokens is not. Second, rounding the notes down to 4 bits
costs quality on top of the quality already given up in section 4. If long
conversations start producing worse answers, raising `KV_QUANT` from `turbo4` to
`8` is the first thing to try, and [07 — Tuning](07-tuning.md) explains how.

### For the curious: the cost table behind the design

| | Arithmetic cost as text gets longer | Memory cost as text gets longer |
|---|---|---|
| Full attention | grows with the square of the length | grows in a straight line, forever |
| Linear attention (Gated DeltaNet) | grows in a straight line | flat — fixed size |

Full attention is expensive and has perfect recall: every token can look directly
at every earlier token. Linear attention compresses history into a fixed-size
state that is updated one token at a time, in the manner of an older recurrent
network. It is cheap and constant in memory, and it cannot reliably retrieve an
arbitrary token from far back.

The 2025-to-2026 insight is that you do not have to choose. Let the cheap layers
carry most of the sequence modeling, and insert a full-attention layer every 4th
layer to restore exact recall. The result scales close to linearly and keeps most
of the quality. This is the same family of design as Qwen3-Next, MiniMax-01, and
the Gemma hybrids.

<details>
<summary>For the curious: the same split, visible in the runtime's source code</summary>

If you built the optional Python environment during setup, the runtime library's
own loader makes the split concrete. Its file
`.venv/lib/python3.12/site-packages/mlx_lm/models/qwen3_5.py`, at line 305,
creates one memory object per layer, choosing the type by layer:

```python
return [ArraysCache(size=2) if l.is_linear else KVCache() for l in self.layers]
```

`KVCache()` grows with the conversation. `ArraysCache(size=2)` holds exactly two
arrays and does not grow. Forty-eight of the objects created by that line are the
non-growing kind.

This file only exists if you set `WITH_VENV=1` during setup. It is not needed to
run the stack, which uses a different program. It is quoted here because it is the
clearest available statement of the design, in code rather than prose.
</details>

---

## 6. Speculative decoding: writing several tokens for the price of one

### The claim, in plain words

Section 3 established the key fact: one walk past all 19 GiB of weights produces
one token, and the walk is almost all of the cost.

Speculative decoding breaks that link. A cheap guesser proposes the next few
tokens. The full model then checks all of them in a **single** walk, because
checking five tokens costs one walk, the same as producing one. Every guess that
turns out to be right is a token you got for free.

The property that makes this trustworthy: the output is **identical** to what the
model would have written on its own. Not similar. Identical. Wrong guesses are
discarded, and the model's own next token is used instead. That is the algorithm
in exact arithmetic; a real implementation verifies in batches and can drift in
floating point, which is why `bench.sh` checks identity on every run rather than
this page asserting it once (it has held on every 9B run so far — MEASURED). (See the **speculative
decoding** entry in the [Glossary](09-glossary.md).)

### An analogy, and where it stops being true

Think of it like a slow, careful editor and a fast, sloppy assistant. The
assistant scribbles a guess at the next sentence. The editor reads the guess and
marks the exact point where they would have written something different. Every
word before that point is kept, because the editor confirms they would have
written those words anyway. Everything from that point on is thrown away, and the
editor writes the next word themselves.

The analogy stops being true in one place, and it is the place that matters most.
A human editor might be tempted to accept a phrasing that is merely acceptable.
The verification rule here is mechanical: a guessed token is kept only if it
matches what the model itself would have produced. There is no "close enough".

### Drawn

```
   WITHOUT speculation                 WITH speculation
   ------------------                  ----------------
   walk 19 GiB  ->  token 1            guesser proposes:  t1 t2 t3 t4 t5
   walk 19 GiB  ->  token 2            walk 19 GiB  ->  check all five at once
   walk 19 GiB  ->  token 3            keep t1 t2 t3  (they matched)
   walk 19 GiB  ->  token 4            drop t4 t5     (t4 did not match)
   walk 19 GiB  ->  token 5            model writes the real t4 itself

   5 walks for 5 tokens                1 walk for 4 tokens
```

Legend, one line per element:

- **walk 19 GiB** — one full read of all the model's weights out of memory. This
  is the expensive step from section 3.
- **guesser proposes** — the cheap step. In this checkpoint the guesser is built
  into the weights, and it is the `MTP head 0.34 GiB` line you printed in
  section 3.
- **check all five at once** — the full model processes all five guessed tokens in
  the same pass. This is possible because checking is a different operation from
  writing, and it parallelizes.
- **keep / drop** — the verification rule. Guesses are kept only up to the first
  one that does not match what the model itself would have written.
- **1 walk for 4 tokens** — the saving. The exact ratio depends on how often the
  guesser is right, which depends on the text.

### Why a built-in guesser beats a separate small model

The classical way to do this is to run a second, smaller model as the guesser.
That works, and it has three problems that matter here.

The conclusion to draw from this table is that a guesser trained as part of the
model, and shipped inside it, avoids all three problems at once.

| | Separate small model as guesser | This checkpoint's built-in guesser |
|---|---|---|
| Extra memory | A whole second model, competing for the same 36 GB | 0.34 GiB, MEASURED in section 3 |
| Agreement with the big model | Two models trained separately drift apart, so guesses are rejected more often | Trained together with the big model, and reuses its internal state |
| Word-piece list | Both models must use the identical list, which limits your choices | The same list by construction |

The built-in guesser is called a **multi-token prediction** (MTP) head. It is one
extra small layer bolted onto the model, which reads the model's own internal
state and predicts what comes next. (See the **multi-token prediction** entry in
the [Glossary](09-glossary.md).)

For this checkpoint, the usual question "which draft model should I use?" has an
unusual answer: **the draft model is already inside the weights.**

### The evidence you can check

**Go to the repository folder.** Replace `<YOUR_REPO_FOLDER>` with the full path
to your copy.

```bash
cd <YOUR_REPO_FOLDER>
```

**Count the pieces of the built-in guesser inside the weight files.** The path is
relative to the repository folder.

```bash
python3 -c "import json;w=json.load(open('Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit/model.safetensors.index.json'))['weight_map'];print('mtp tensors:',sum(1 for k in w if '.mtp.' in k))"
```

You should see something like this:

```
mtp tensors: 29
```

MEASURED on the test machine. The word "tensor" in that output means one named
block of numbers inside the model — the unit the weight files are organized into.
(See the **tensor** entry in the [Glossary](09-glossary.md).) So: twenty-nine
named pieces of the guesser are listed in the weight index, which is the file
that says which piece lives in which of the five weight files. Section 3's byte breakdown showed those same 29 pieces occupy
0.34 GiB of real bytes, so they are not merely named — they are present.

**If you do not see that**, and instead see `mtp tensors: 0`, this checkpoint has
no built-in guesser. The stack will still run, and generation will be slower.
For this specific model `./bin/verify-model.sh` reports that as a failure,
because the publisher's manifest says the head should be there and its absence
means the download is not what it should be. For a checkpoint that ships no
head — the 9B in the catalog, the 2-bit, AEON and stock 27B builds — it prints
`MTP head absent` and passes.

### What the publisher measured, and what this repository did not

The publisher of this checkpoint ran the model twice on their own machine, once
with the guesser switched on and once with it off, and published both results.

| | Guesser off | Guesser on |
|---|---|---|
| Time | 10.150830 seconds | 6.809538 seconds |
| Tokens guessed | 0 | 66 |
| Tokens accepted | 0 | 66 |
| Output fingerprint | `65966537023045093dda6a4bf49057afef35319d2f5170c68435d3330c8cec10` | `65966537023045093dda6a4bf49057afef35319d2f5170c68435d3330c8cec10` |

PUBLISHER-REPORTED. Measured by the publisher on a Mac M4 Pro with 48 GiB of
memory running macOS 26.6.1 — a different machine from the test machine used for
this repository. You can read these numbers yourself in the model folder's own
`README.md`, in the section headed "M4 Pro runtime".

Two things deserve emphasis, one encouraging and one restraining.

The encouraging one: the two output fingerprints are the same. A fingerprint is a
short code computed from a piece of text, such that different text almost
certainly produces a different code. The same code means the same text, character
for character. This is the exactness claim from the start of this section, shown
for this run rather than asserted in general.

The restraining one: the publisher labels those durations, in their own words,
"bounded smoke-test evidence, not performance benchmarks". They come from a single
short run. This repository has NOT YET MEASURED any speed comparison on the test
machine. `./bin/bench.sh` exists to let you run the comparison on your own Mac,
and [07 — Tuning](07-tuning.md) explains how.

<details>
<summary>For the curious: how often are the guesses right</summary>

The fraction of guesses accepted is called the **draft acceptance rate**, and it
sets how much speed you actually gain. It varies with the text: predictable text
gets high acceptance, surprising text gets low acceptance.

The discussion on the upstream pull request that adds this feature to the stock
Python library reports acceptance rates in the region of 88 percent at
temperature 0 — a setting that makes the model always pick its single most likely
next token, rather than sampling among the likely ones. (See the **temperature**
entry in the [Glossary](09-glossary.md).) That is a THIRD-PARTY REPORT about other checkpoints, not a
measurement of this one, and not a measurement on the test machine.

The publisher's smoke test above accepted 66 out of 66 guesses. That is a real
observation, but it is one short run on one prompt, and it should not be read as a
general rate.

When the server is running, it publishes its own live acceptance rate. Reading it
is covered in [07 — Tuning](07-tuning.md).
</details>

---

## 7. Prompt lookup: why editing files is fast

### The claim, in plain words

There is a second guesser, and it is not a model at all. It is a text search.

When the model is about to write something that already appears word for word in
the text it was given, this guesser copies it and offers it as the guess. The
verification step from section 6 is unchanged, so the output is still exactly what
the model would have written. This is called **prompt lookup decoding** (PLD).
(See the **prompt lookup decoding** entry in the [Glossary](09-glossary.md).)

This sounds like it would rarely help. For a coding assistant it helps enormously.
When Claude Code asks the model to change three lines in a file, most of the
model's output *is* the file, echoed back with three lines different. Every
echoed region is guessed correctly at almost no cost.

### An analogy, and where it stops being true

Think of it like copying a paragraph that is already on the page in front of you,
rather than composing it from scratch. Copying is fast. Composing is slow.

The analogy stops being true in one way: the model is not really copying. It is
being *offered* a copy and checking, token by token, whether that is what it would
have written. When the model wants to deviate — those three changed lines — the
check fails at exactly that point and the model writes its own token.

### What you will feel

This has a consequence you should expect, so it does not read as a bug: **editing
an existing file is noticeably faster than writing new prose of the same length.**
Both are correct. One has more material to copy from.

The two guessers cover different situations, and the server picks per request.

| Situation | Which guesser helps | Why |
|---|---|---|
| Rewriting a file with small changes | Prompt lookup | Most of the output is already in the input |
| Writing new prose or new code | The built-in MTP head | There is nothing to copy, so a learned guess is the only option |
| Both available | The server prefers the MTP head, then a separate draft model, then prompt lookup | The MTP head is the better guesser when it applies |

### The evidence you can check

Both guessers are switched on by default by the server, and this repository never
turns them off. You can confirm that by reading `bin/serve.sh` at the repository
root: the flags `--no-mtp` and `--no-pld` appear nowhere in it, and
[07 — Tuning](07-tuning.md) lists them among the flags this stack deliberately
never passes.

When the server is running, it also reports guessing activity live. Reading that
is covered in [05 — Run it](05-run-it.md) and [07 — Tuning](07-tuning.md). This
page does not start the server.

---

## 8. Prefix caching, and the problem the hybrid design creates

### The claim, in plain words

Claude Code sends the model a large block of instructions before your actual
question — how to use its tools, what it is allowed to do, and the conversation so
far. It sends nearly the same block every single turn.

Reading that block is called **prefill**, and it is the slow part of every turn.
(See the **prefill** entry in the [Glossary](09-glossary.md).)

A **prefix cache** stores the notes from section 5 for a block of text that has
already been read, so that the next turn resumes instead of re-reading. (See the
**prefix cache** entry in the [Glossary](09-glossary.md).)

Part of that block describes optional extra helpers you can connect to Claude
Code — a web browser, a database, a note-taking app. Each one has to describe
every command it offers, in full, so the model knows how to call it. The system
for connecting them is called the **Model Context Protocol** (MCP), and the
helpers are called MCP servers. This document calls them **tool servers**. (See
the **Model Context Protocol** entry in the [Glossary](09-glossary.md).)

The conclusion to draw from the table below is that connected tool servers are
expensive, and they are expensive on every single turn rather than once.

| What Claude Code sends before your question | Size |
|---|---|
| With its usual tool servers connected | 38054 tokens |
| With the tool servers switched off, which this repository does by default | 20909 tokens |

Both figures MEASURED on the test machine. The difference, about 17000 tokens, is
the description of those tool servers, and it is re-sent on **every** turn. That
is why this repository switches them off by default, using a Claude Code setting
named `--strict-mcp-config`. [05 — Run it](05-run-it.md) explains the setting and
how to turn the tool servers back on.

And here is the cache working, MEASURED on the test machine on the second turn of
a conversation:

```
[hot-cache] reused 16384/20906 tokens
```

Sixteen thousand tokens of that block were not re-read. They were resumed from the
cache.

### An analogy, and where it stops being true

Think of it like a bookmark. You read 20000 words yesterday, you place a bookmark,
and today you continue from the bookmark instead of starting at page one.

The analogy stops being true in a way that is the entire point of this section. A
bookmark works because a book can be opened at any page. Section 5 introduced a
kind of layer whose memory **cannot** be opened at an arbitrary page, and the next
part explains what is done about that.

### The problem the index cards create

Recall the two kinds of note-taker from section 5.

The sixteen transcript-keepers can be bookmarked. A transcript is a list. You
can cut a list at token 5000 and keep the first part.

The forty-eight index-card holders cannot be bookmarked. Their card was rewritten
after every single token. The card as it stands at token 9000 does not contain,
anywhere inside it, the card as it stood at token 5000. There is nothing to cut.

```
   transcript at token 9000        index card at token 9000
   ------------------------        ------------------------
   one entry per token, in order      one fixed-size state, rewritten
   [ t1 ][ t2 ][ t3 ][ t4 ] and so    after every single token
   on up to [ t9000 ]
                                      [ state after t9000 ]
   [ t1 ][ t2 ][ t3 ] <- cut here
   and keep this part                 there is no "here" to cut.
                                      The state after t5000 was
                                      overwritten, not stored.
```

Legend, one line per element:

- **transcript** — the growing notes kept by the 16 full-attention layers. A list
  of per-token entries, so any prefix of it is itself valid.
- **index card** — the fixed-size state kept by the 48 linear-attention layers.
  One state, repeatedly overwritten. Earlier versions no longer exist.
- **the cut mark on the left** — where a prefix cache slices a transcript to
  resume from an earlier point.
- **the absence of a cut mark on the right** — the problem. Without a fix, the
  hybrid design would make prefix caching impossible and every turn would pay the
  full prefill cost.

### The fix

The server takes a photograph of the index cards at regular intervals as it reads,
and stores the photographs. This is called **SSM checkpointing**, and the interval
is a setting named `--ssm-checkpoint-stride` whose default value is 256 tokens.
(See the **SSM checkpoint** entry in the [Glossary](09-glossary.md).)

A later request that shares a prefix restores the nearest photograph and re-reads
only the tokens after it — at most 255 of them, rather than 20000.

This is a good example of a general pattern in engineering, and it is worth
naming: an architectural win, constant-size memory, created a new systems problem,
un-resumable state, which then needed its own engineering answer. The win was
still worth it. It was not free.

### The evidence you can check

The cache settings this repository uses are in `bin/env.sh` at the repository
root, as `PREFIX_CACHE_MEM` with a default of `1536MB` and `PREFIX_CACHE_DISK`
with a default of `10GB`. The second one writes the cache to your SSD, so the work
survives restarting the server rather than being paid again.

The `[hot-cache]` line above appears in the server's own log when a cache
resume happens. Where the log is, and how `./bin/doctor.sh` reads it for you,
is covered in [05 — Run it, §7d](05-run-it.md#7d-the-repeated-instructions-are-remembered-not-re-read).

---

## 9. Why speaking Claude Code's own message format matters

### The claim, in plain words

Claude Code and the model server have to agree on a format for talking to each
other. Two formats are common. Claude Code speaks Anthropic's, at an address
ending in `/v1/messages`. Most local model servers speak OpenAI's, at an address
ending in `/v1/chat/completions`.

Older setups bridged the gap with a translator program sitting in the middle. The
server used here speaks Anthropic's format directly, so there is no translator.

That is not merely tidier. Translation genuinely loses information in the one
place a coding assistant depends on most: describing which tool to run and what
came back from it.

### An analogy, and where it stops being true

Think of it like an interpreter in a meeting. For ordinary conversation, an
interpreter is fine. For reading out a legal contract clause by clause, an
interpreter who paraphrases loses exactly the details that make it a contract.

The analogy stops being true in one place: a human interpreter can ask for
clarification. The translator program cannot. When two formats cannot express the
same thing, it has to guess, and the guess is silent.

### Drawn

```
   THE OLD WAY (three programs)

     Claude Code  --Anthropic format-->  translator  --OpenAI format-->  server
                                              |
                                    tool descriptions reshaped here

   THIS SETUP (two programs)

     Claude Code  --Anthropic format-->  server
```

Legend, one line per element:

- **Claude Code** — the app you type into. It only speaks Anthropic's format.
- **translator** — a separate program, such as LiteLLM, that rewrites messages
  from one format into the other. This setup does not use one.
- **server** — the program that holds the model in memory and answers requests.
  Here it is mlx-serve, and it understands Anthropic's format itself.
- **tool descriptions reshaped here** — the lossy step. See the deep dive below
  for exactly what gets lost.
- **the arrows** — one network request each, all of them staying inside your own
  Mac.

The practical result: this stack is two programs instead of three, with one fewer
thing to install, one fewer thing to configure, one fewer thing to crash, and one
fewer place for tool calls to be mangled.

<details>
<summary>For the curious: exactly what a translator loses</summary>

The two formats model tool use differently, and the difference is structural
rather than cosmetic.

Anthropic's format puts typed blocks inside a message. A single assistant message
can contain a paragraph of text, then a `tool_use` block, then another `tool_use`
block. The order is preserved, and each result comes back as a `tool_result` block
carrying the identifier of the call it answers.

OpenAI's format puts tool calls in a separate `tool_calls` array attached to the
message, and results come back as separate messages with `role: "tool"`.

Round-tripping between the two loses three things a coding assistant relies on:
the ordering of blocks within a message, the grouping of several tool calls issued
together in one turn, and the association between a reasoning block and the tool
call it justifies.

A model that already struggles with long tool-calling chains, as section 12
records honestly, does not need a translation layer adding failures of its own.
This is the single largest reliability difference between this stack and the
`local server plus proxy` recipes published in 2025.
</details>

---

## 10. Why not vLLM

vLLM is excellent software. It is the wrong tool for this specific job, for four
independent reasons — any one of them would be enough on its own.

The conclusion to draw from this table is that the mismatch is about hardware and
workload, not about quality.

| Reason | Detail |
|---|---|
| No CUDA on a Mac | vLLM's core is built for NVIDIA graphics cards. Apple Silicon has no CUDA, and vLLM's Apple support does not deliver its main advantages. |
| Wrong file format | These weights are rounded in MLX's own 5-bit format, as you confirmed in section 4. vLLM reads GPTQ, AWQ, FP8 and bitsandbytes formats. It cannot read these files at all. |
| Wrong goal | vLLM's headline features maximize total output across many users at once. You are one user. Your bottleneck is how fast a single answer arrives, and serving many users at once does not help with that. |
| Wrong memory model | MLX is built for Apple's design, where the processor and the graphics processor share one pool of memory. There is no copying between two pools, because there are not two pools. Software designed around a separate graphics card carries copying steps you do not need. |

The rule generalizes, and it is worth carrying away from this page: **match the
runtime to the file format and to the workload.** vLLM for NVIDIA servers with
many users. MLX for one person on Apple Silicon waiting for one answer.

---

## 11. The one line of code that decides which runtime this stack uses

### The claim, in plain words

This is the most concrete decision in the whole repository, and it comes down to a
single line.

The program you would reach for first to run this model is `mlx-lm`, the standard
Python library
for running MLX models. It cannot use the built-in guesser from section 6. When it
loads the model, it explicitly throws the guesser's 29 pieces away. The feature
that would use them is an open, unmerged proposal to that library.

So this stack uses `mlx-serve` instead, which supports the built-in guesser today.
That is the reason. It is not a preference.

### The evidence you can check

If you built the optional Python environment during setup by setting
`WITH_VENV=1`, the library is on your disk and you can read the line yourself.

**Go to the repository folder.** Replace `<YOUR_REPO_FOLDER>` with the full path
to your copy.

```bash
cd <YOUR_REPO_FOLDER>
```

**Find the line that discards the guesser.** The path is relative to the
repository folder.

```bash
grep -n 'if "mtp." not in k' .venv/lib/python3.12/site-packages/mlx_lm/models/qwen3_5.py
```

You should see something like this:

```
313:        weights = {k: v for k, v in weights.items() if "mtp." not in k}
```

MEASURED on the test machine against mlx-lm version 0.31.3. The line number will
move as the library changes. The Python version folder in the path will be
different if your Python is not 3.12.

Read the line in plain words: keep every piece of the model whose name does not
contain `mtp.`. The 29 pieces you counted in section 6 all contain `mtp.` in their
names. They are dropped during loading, and the loaded model has no built-in
guesser.

**If you do not see that**, and instead the command prints nothing and exits, one
of three things is true. Either you did not build the optional Python environment,
in which case the folder does not exist and this is expected. Or your Python is a
different version, so `python3.12` in the path is wrong — run
`ls .venv/lib` from the repository folder to see which version you have. Or the
library has been updated and the proposal has been merged, which would be good
news. The proposal is `ml-explore/mlx-lm` pull request number 990, and it was
still open when this repository was written.

This one line is the whole justification for the runtime choice. The 29 pieces are
in the files, they are worth 0.34 GiB, they make generation measurably faster
according to the publisher, and the standard library deletes them.

---

## 12. What this will not do

Setting expectations correctly is part of the engineering. None of the following
is softened.

**A 27B model at 5 bits is not Sonnet or Opus.** Expect materially weaker
multi-step planning, weaker adherence to instructions, and more malformed tool
calls. Claude Code is a demanding program to drive: it issues long chains of tool
calls and recovers poorly when a model produces invalid arguments. Short,
well-scoped tasks work far better than open-ended ones. "Rename this function
everywhere in this file" is a good fit. "Refactor this service and update the
tests" is not.

**Context is not free.** 262144 tokens is the architectural maximum, not a
practical setting on a 36 GB Mac. The memory is affordable, as the table in
section 5 shows. The time spent reading that much text is not.
[07 — Tuning](07-tuning.md) has the honest trade.

**Quality losses compound.** The weights are rounded to 5 bits, and the
conversation notes are rounded to 4. Both cost quality, and they add up. If output
degrades on long conversations, raise `KV_QUANT` from `turbo4` to `8` first. That
is the cheaper of the two to give back.

**This model is abliterated.** Per the publisher, its refusal behavior was removed
by mathematically subtracting the internal direction associated with refusing from
the model's own processing. It has essentially no built-in guardrails and will
comply with requests the original Qwen3.8 would decline. (See the **abliterated
model** entry in the [Glossary](09-glossary.md).)

That is a reasonable thing to run for local research on your own machine, which is
what this setup is. It is not a thing to put behind an address other people can
reach. This repository sets the server's address to `127.0.0.1`, which means "this
Mac only" and cannot be reached from any other device. The server's own default is
`0.0.0.0`, which means "every network this Mac is on". This repository overrides
that on purpose, and the override is not optional.
[04 — Memory safety](04-memory-safety.md) and
[05 — Run it](05-run-it.md) both restate this.

**No speed figures have been recorded for this model on the test machine.** No
tokens-per-second number, no prefill rate, no locally reproduced speed comparison
between the guesser on and off. Every timing figure on this page is
PUBLISHER-REPORTED and came from a different Mac. `./bin/bench.sh` exists so you
can measure your own; the only figures it has produced so far are the 9B's, in
[07 §10](07-tuning.md#bench).

---

## How to check everything on this page yourself

Every command below reads files and changes nothing. All of them run from the
repository folder.

| Claim on this page | Command that checks it |
|---|---|
| The model works in word-pieces, and there are 248044 of them | The `vocab.json` block in section 1 |
| Each token of conversation costs 64 KiB, from 16 layers of 4 heads of 256 dimensions | The `config.json` one-liner in section 2 |
| The weights are 19.12 GiB once the picture part is skipped | The byte-breakdown block in section 3 |
| The weights are rounded to 5 bits in batches of 64 | The `quantization` one-liner in section 4 |
| 2207 pieces in total, 504 of them rounded, 333 of them for pictures | The counting one-liner in section 4 |
| 48 layers keep fixed-size notes, 16 keep growing notes, every 4th | The `layer_types` one-liner in section 5 |
| The built-in guesser is physically present, in 29 pieces | The `mtp` one-liner in section 6 |
| The standard Python library deletes that guesser | The `grep` in section 11 |

Two further checks need the server running, so they are not on this page. Asking
the server which model it is holding, and proving that no traffic leaves your Mac,
are both in [05 — Run it](05-run-it.md).

`./bin/verify-model.sh`, run from the repository folder, performs most of these
checks in one step and prints a pass or fail. [03 — Get the model](03-get-the-model.md)
walks through its output line by line.

## Nothing on this page changed your Mac

There is no undo section here, because there is nothing to undo. Every command on
this page opened files for reading. None of them started the server, loaded the
model into memory, wrote a file, changed a macOS setting, or asked for your
password.

If you want to stop a server that is already running from an earlier session, the
command is `./bin/stop.sh`, run from the repository folder. It reports how much
memory came back. [05 — Run it](05-run-it.md) covers it properly.

To remove the model entirely and get the disk space back, see
[03 — Get the model](03-get-the-model.md).

---

## Where to go next

- Words on this page that are still unclear: [09 — Glossary](09-glossary.md).
- Change the context window, the note precision, or turn the tool servers back on:
  [07 — Tuning](07-tuning.md), which also has the full list of settings and the
  benchmark script.
- Run it: [05 — Run it](05-run-it.md).
- Something is broken: [06 — Troubleshooting](06-troubleshooting.md).

---

## Sources

- [ml-explore/mlx-lm pull request 990 — native MTP speculative decoding](https://github.com/ml-explore/mlx-lm/pull/990)
- [ddalcu/mlx-serve](https://github.com/ddalcu/mlx-serve)
- [vLLM — Claude Code integration](https://docs.vllm.ai/en/stable/serving/integrations/claude_code/)
- [llama.cpp — Anthropic Messages API](https://huggingface.co/blog/ggml-org/anthropic-messages-api-in-llamacpp)
- The model folder's own `README.md`, `LINEAGE.json`, `ARTIFACT-MANIFEST.json` and
  `config.json`, all of which you downloaded with the weights.
