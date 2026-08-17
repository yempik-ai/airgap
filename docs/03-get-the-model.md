# 03 — Get the model

**Who this is for.** Anyone who has finished [02 — install](02-install.md) and
now needs the model's numbers on their Mac. You do not need to know what git is,
what a large file is, or what any word on this page means before you read it.

**What you will have at the end.** About 20 GB of model files in a folder inside
this repository, proved complete, and an understanding of what is actually
inside them. You will also know the single mistake that catches more beginners
than everything else on this page combined, and why it cannot happen to you.

**How long it takes.** About five minutes of your attention, then a long wait.
The wait is the download: about 20 GB, so on a 100 Mbit connection roughly half
an hour. You do not have to watch it, and you can stop and resume it safely.

**What it costs.** About 45 GB of free disk space while it runs, and about 20 GB
once it finishes. No memory — nothing here loads the model. No money and no
account. The download is the last thing on your Mac that touches the network.

**What you need first.**

- [01 — requirements](01-requirements.md) read, and your Mac's verdict known.
- [02 — install](02-install.md) finished, so that `git-lfs` is installed **and
  switched on**. `./bin/doctor.sh` shows both as PASS.
- About 45 GB free on the disk holding this repository.

**If you only read one thing:** without `git-lfs`, copying a model with `git`
**succeeds** and leaves 135-byte text files where the 20 GB of numbers should be,
and nothing tells you until much later. Section 1 is about that.

---

## 1. <a id="the-pointer-trap"></a>The trap, before you meet it

Model files are large, so the sites that host them do not store them the way
ordinary code is stored. They use an addition to git called **git-lfs**
([Glossary](09-glossary.md#git-lfs)) — Large File Storage. **git**
([Glossary](09-glossary.md#git)) is the program that copies a project folder from
the internet onto your Mac.

Here is what makes this dangerous rather than merely inconvenient.

When git-lfs is not installed, or is installed but not switched on for your
account, the copy still runs. It prints no warning. It finishes. It reports
success. And in place of each 4.6 GB file of numbers, it leaves a text file of
about **135 bytes** that contains the address of the real file.

That small text file is called an **LFS pointer file**
([Glossary](09-glossary.md#lfs-pointer-file)).

> **Think of it like** ordering four heavy boxes and receiving four postcards,
> each printed with the address of a warehouse where a box is kept. The postcards
> arrive on time. The delivery is marked complete. **Where the comparison stops:**
> a postcard is plainly not a box. These files have the right names, sit in the
> right folder, and look correct in Finder.

You find out much later, when the server fails in a way that has no visible
connection to the download.

**Three defenses are already in place, so this should never reach you:**

1. [02 — install](02-install.md) installs git-lfs and switches it on before this
   page ever runs.
2. `./bin/download-model.sh` checks every file after the download and refuses to
   report success if any of them is still a pointer file.
3. `./bin/serve.sh` checks again before it loads anything, and stops with the
   exact command that fixes it.

If you meet the problem anyway, the fix is one command and is in
[06 — troubleshooting](06-troubleshooting.md#lfs-pointers).

---

## 2. Move into the repository folder

Every command on this page runs from the folder you copied this repository into.
Throughout these documents that folder is written as
`~/dev/local-llms/airgap`. If you put it somewhere else, use your own path.
Do not assume your Terminal window is still where an earlier page left it;
windows get closed.

This puts your Terminal window inside the repository folder.

```
cd ~/dev/local-llms/airgap
```

This prints nothing. That is success.

**If you do not see that.** A message ending in `No such file or directory`
means the folder is somewhere else, or the repository was never copied. Go back
to [02 — install](02-install.md), Step 4.

---

## 3. Check that git-lfs is really switched on

Installing git-lfs and switching it on for your account are two separate things,
and only the second one makes the download work. This checks both.

This prints the version of git-lfs and, on the next line, proves it is switched
on for your account.

```
./bin/doctor.sh
```

You should see, among the other lines, these two:

```
PASS  git-lfs           3.7.1
PASS  git-lfs enabled   switched on for your account
```

The version number will differ on your Mac. Both lines must say `PASS`.

You will probably also see this line, and it is EXPECTED at this point:

```
FAIL  model dir         nothing at ~/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit. Run: ./bin/download-model.sh  -> docs/03-get-the-model.md
```

That is the page you are on, telling you to do the thing you are about to do.
You may also see `FAIL memory` if you have been using your Mac today; that is
also EXPECTED here, because nothing is being loaded on this page.

**If you do not see that.**

- `FAIL git-lfs not installed` — FIX THIS. Run `./bin/setup.sh`, then run
  `./bin/doctor.sh` again. Detail:
  [06 — troubleshooting](06-troubleshooting.md#git-lfs-missing).
- `FAIL git-lfs enabled installed but not switched on` — FIX THIS with the one
  command that line names: `git lfs install`. Then run `./bin/doctor.sh` again.

---

## 4. Download the weights

Now the long part.

**What this does.** It downloads the model's numbers into a folder inside this
repository, checking before, during and after that the download is real.

**What to expect before you start it:**

- It downloads about 20 GB. That is a lot of data, and on a metered or slow
  connection it matters. Check that first.
- It needs about **45 GB free on disk**, not 20 GB, and Section 5 explains why.
  It checks this before downloading anything and stops in two seconds if you are
  short.
- It uses no memory worth mentioning and never starts the server.
- **You can stop it at any time with Control-C, and run it again to continue.**
  Nothing is corrupted by interrupting it. This is the single most reassuring
  fact on the page.

```
./bin/download-model.sh
```

You should see something like this:

```
repo     chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
target   /Users/<YOUR_USER_NAME>/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
disk     460.4 GB free (need 45 GB)

[1/5] git-lfs                ok (3.7.1)
[2/5] resolving repo         checking huggingface.co
[2/5] resolving repo         ok — huggingface.co/chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
[3/5] cloning metadata       GIT_LFS_SKIP_SMUDGE=1 (pointers now, weights next)
[4/5] git lfs pull           about 20 GB — this is the long part
      Press Ctrl-C to stop. Running this command again resumes it.
[4/5] git lfs pull           ok — no pointer files left
[5/5] git lfs dedup          reclaimed 20.1 GB (462.5 GB free before, 482.6 GB after)

download complete — next: ./bin/verify-model.sh
```

Four things differ on your Mac: the `target` path contains your own account
name, the three disk figures are your own, the git-lfs version may be newer, and
the repository name changes if your Mac was recommended the 4-bit or 8-bit build
(see Section 7). The step numbers and their order never change.

Between the `[4/5]` lines there is a long silence with a progress display from
git-lfs. That is the download. It is normal for it to sit at a high percentage
for a while at the end.

**If you do not see that.** Four failures are possible here and each names its
own fix.

- `error: git-lfs not installed. Run ./bin/setup.sh first.` — FIX THIS. You
  skipped Step 3 of this page or a step in [02 — install](02-install.md).
- `error: repo not found on huggingface.co: <name>` — FIX THIS. The address is
  wrong, or the publisher renamed or removed it. Open
  `https://huggingface.co` in a browser, search for the model, and copy the
  `<ORGANIZATION>/<NAME>` text from the top of its page. Then run the command
  again with that address in front of it. For a worked example, if the page said
  `someone/Qwen3-14B-MLX-4bit`, you would type:
  `MODEL_REPO=someone/Qwen3-14B-MLX-4bit ./bin/download-model.sh`
- `error: only N GB free, need 45 GB` — FIX THIS. See
  [06 — troubleshooting](06-troubleshooting.md#disk-space), and read Section 5
  below for why the number is 45 and not 20.
- `error: the download did not finish.` — FIX THIS by running
  `./bin/download-model.sh` again. Nothing is corrupted. It continues from where
  it stopped.

### CHECKPOINT

**Stop here.** Before you continue, confirm the last line of the output was
exactly this:

```
download complete — next: ./bin/verify-model.sh
```

If the command stopped anywhere earlier, fix the failure it named and run it
again. Do not continue to Step 6 with a partial download; the checks there will
only tell you the same thing more slowly.

---

## 5. Why 45 GB of disk for a 20 GB model

This surprises people, so here is the whole story.

git-lfs writes each large file **twice**: once into the model folder where you
can see it, and once into a hidden store inside the folder's `.git` directory.
The second copy is git-lfs's own bookkeeping. So partway through, 20 GB of model
occupies about 40 GB of disk, and the tool needs some room to work in on top of
that.

Step 5 of the download fixes this. The command `git lfs dedup` replaces one copy
with a reference to the other. On the APFS disk that every modern Mac uses, this
is instant and loses nothing: both names now point at the same blocks.

**How much does it actually reclaim?** The download script measures your free
disk before and after and prints both numbers, so the figure you see is your
machine's, not somebody else's. On the test machine it reclaimed **20.1 GB**,
taking free disk from 462.5 GB to 482.6 GB — MEASURED.

### <a id="du-lies"></a>Why `du` still says 40G, and why that is correct

This trips up everyone, so read it before you conclude something went wrong.

```
du -sh ~/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
```

After a successful dedup this still prints about **40G**:

```
 40G	/Users/<YOUR_USER_NAME>/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
```

**That is not a failure.** Deduplication does not delete the second copy — it
makes both copies point at the *same blocks* on disk. `du` adds up what each file
claims, and two files each claiming 20 GB of the same shared blocks add up to
40 GB. `df` measures the disk itself, and the disk really does have the space
back.

So check `df`, not `du`:

```
df -h ~
```

The `Avail` column is the honest number, and it is the one the download script
printed as "free before" and "free after".

**If you genuinely want to re-run dedup** — because you set `DEDUP=0`, or the
step printed an error — it is safe to run more than once:

```
cd ~/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit && git lfs dedup
```

That is one action expressed as two commands joined by `&&`, because `git lfs
dedup` has to run inside the model folder. It is safe to run more than once.

**If you do not see that.** `du: command not found` cannot happen on macOS; a
`No such file or directory` means the folder name is different, which happens if
your Mac was recommended the 4-bit or 8-bit build. Use the name that
`./bin/doctor.sh` prints on its `model dir` line.

---

## 6. Prove the download is complete, and see what is in it

This is where the download stops being an act of faith.

**What this does.** It opens each weights file just far enough to read the short
description at the front of it, and reports what is inside. It reads a few
hundred kilobytes in total. It never loads the 20 GB, never uses meaningful
memory, and never starts the server. It finishes in under a second.

```
./bin/verify-model.sh
```

You should see exactly this:

```
model    Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
config   model_type = qwen3_5   (correct, not a typo -- Qwen3.8-27B is built on
         the qwen3_5 architecture family, the way Llama 3.1/3.2/3.3 all report
         model_type "llama". Runtimes dispatch on model_type.)
layers   64 = 48 linear_attention (Gated DeltaNet) + 16 full_attention
         (full_attention_interval 4) -- only the 16 hold a growing KV cache
quant    5-bit affine, group size 64
shards   5/5 headers parsed, no git-lfs pointers
tensors  2207 total | 504 quantized | 333 vision | 29 MTP
MTP head PRESENT -- the reason this stack runs mlx-serve, not stock mlx-lm
size     19.1 GB of text-only weights on disk (the vision tower is skipped at
         run time via --no-vision, so it costs disk but not memory)
manifest matches ARTIFACT-MANIFEST.json (2207 tensors, 504 quantized)

verify PASS

next: read docs/04-memory-safety.md, then ./bin/doctor.sh
```

**Nothing in this output changes between Macs**, as long as you downloaded the
same 5-bit build. It describes the files, not your machine. If your Mac was
recommended the 4-bit or 8-bit build, the `model`, `quant`, `shards`, `tensors`
and `size` lines describe that build instead.

**If you do not see that.** Three failures are possible.

- `verify FAIL: <file> is 135 bytes — git-lfs pointer, not weights` — FIX THIS.
  This is the trap from Section 1. Run the command the message names, then run
  `./bin/verify-model.sh` again. Full entry:
  [06 — troubleshooting](06-troubleshooting.md#lfs-pointers).
- `verify FAIL: expected 2207 tensors, found <n> — download is incomplete` —
  FIX THIS by running `./bin/download-model.sh` again. It continues where it
  stopped.
- `verify FAIL: no mtp.* tensors found` — FIX THIS. You have a different
  checkpoint from the one these documents describe. Everything still runs, but
  without the speed feature Section 6d is about.
  [06 — troubleshooting](06-troubleshooting.md#mtp-missing).

### What the output is telling you

Four of those lines carry real information. Here is what each one means.

#### 6a. `model_type = qwen3_5` is correct, not a mistake

The model's own description file says its type is `qwen3_5`, even though the
model is called Qwen3.8-27B. That looks like somebody typed the wrong version
number. It is not.

A model's **model_type** ([Glossary](09-glossary.md#model_type-and-why-it-says-qwen3_5))
names the *family of designs* it was built on, not its release name. Programs
that run models read this field to decide which code to use.

The same thing happens elsewhere: Llama 3.1, 3.2 and 3.3 all report `model_type`
`llama`, because they share one design. Qwen3.8-27B is built on the `qwen3_5`
design, so that is what it reports, and that is what makes the right code run.

**Check it yourself.** This prints the type line from the model's own description
file.

```
grep model_type ~/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit/config.json
```

You should see something like this:

```
  "model_type": "qwen3_5",
```

The leading spaces and the trailing comma are part of the file. Nothing here
differs between machines.

**If you do not see that.** `No such file or directory` means the download did
not finish, or the folder has a different name because you have the 4-bit or
8-bit build. Use the path `./bin/doctor.sh` prints on its `model dir` line.

#### 6b. 64 layers, split 48 and 16

A model passes your text through a stack of stages called **layers**
([Glossary](09-glossary.md#layer)). This one has 64.

As a conversation grows, most models make every layer keep notes on everything
said so far, so they do not have to re-read it for each new word. Those notes are
the **KV cache** ([Glossary](09-glossary.md#kv-cache)), and they grow without
limit as you talk.

In this model, **only 16 of the 64 layers keep growing notes**. The other 48 keep
a single fixed-size summary that is rewritten each time.

> **Think of the 16 as a notebook that gets longer as you talk, and the 48 as one
> sticky note that is erased and rewritten.** Where the comparison stops: the
> sticky note is not losing information at random. It holds a deliberate
> compressed summary, and the design that produces it has a name — **Gated
> DeltaNet** ([Glossary](09-glossary.md#gated-deltanet-gdn)).

The consequence is the reason this fits on a laptop: the growing notes cost about
four times less memory than in an ordinary 64-layer model. The arithmetic is in
[07 — tuning](07-tuning.md#kv-arithmetic) and the design reasoning is in
[08 — how it works](08-how-it-works.md).

#### 6c. `2207 total | 504 quantized | 333 vision | 29 MTP`

Those are counts of the individual arrays of numbers inside the files, called
**tensors** ([Glossary](09-glossary.md#tensor)).

- **2207 total** — every array in the checkpoint.
- **504 quantized** — the large ones, stored compressed at 5 bits each. See
  [Glossary](09-glossary.md#quantization).
- **333 vision** — the part that reads images. Claude Code sends text, so this
  repository tells the server to skip loading it. It costs disk but not memory,
  which is why the 20 GB on disk becomes 19.1 GB in memory.
- **29 MTP** — the next section.

The line below them, `manifest matches ARTIFACT-MANIFEST.json`, means those four
counts were compared against the publisher's own list of what should be there and
they agreed. That is a stronger statement than "the files are present".

#### 6d. `MTP head PRESENT` — the line this whole repository hangs on

Producing text one word at a time is slow, and slow for a boring reason: the chip
spends most of its time moving 20 GB of numbers around rather than doing
arithmetic.

This model ships with a small extra piece whose only job is to guess several of
the next chunks of text ahead of time. The full model then checks all the guesses
in one pass. Right guesses are kept, wrong guesses are thrown away. The technique
is called **speculative decoding**
([Glossary](09-glossary.md#speculative-decoding)) and this model's built-in
version is **multi-token prediction (MTP)**
([Glossary](09-glossary.md#multi-token-prediction-mtp)).

> **Think of it like** a fast typist guessing the end of your sentence while an
> editor checks each guess before it is printed. **Where the comparison stops:**
> this editor is mathematically strict. Any wrong guess is discarded completely,
> so the final text is exactly what the slow method would have produced. This is
> not an approximation and it is not a quality trade.

**The evidence, and its label.** The model's publisher measured 6.81 seconds with
the feature on against 10.15 seconds with it off, and the two answers had an
identical SHA-256 fingerprint — a digital signature that only matches for
identical text. Those figures are PUBLISHER-REPORTED. They have NOT YET been
reproduced on the test machine, and no tokens-per-second figure for this model
has been measured anywhere in this repository. You can run the comparison
yourself with `./bin/bench.sh`, described in [07 — tuning](07-tuning.md#bench).

**And here is the catch that explains the runtime choice.** The most common
program for running MLX models, `mlx-lm`, **deletes** that extra piece as it
loads the file. One line of its source code filters those 29 arrays out by name.
The change that would add a switch for it has been proposed and not accepted. So
this repository uses `mlx-serve` instead, where the piece survives loading. The
detail, including the exact line, is in
[08 — how it works](08-how-it-works.md).

That single fact is why `MTP head PRESENT` is worth printing.

---

## 7. If your Mac was recommended a different build

You do not have to go and find another model yourself. One command lists every
build this repository knows about, with its real download size and whether it
fits **your** Mac:

```
./bin/models.sh list
```

It marks each row `ok`, `TIGHT` or `NO` against your own memory, `*` if you have
already downloaded it, and `->` for the one selected right now. To change build:

```
./bin/stop.sh
./bin/models.sh pull 27b-4bit
./bin/models.sh use  27b-4bit
./bin/serve.sh
```

`use` writes one line into `config.env` and changes nothing else, so your other
settings survive. Both models stay on disk, so switching back is instant and
costs no download.

The catalog covers seven builds, from 4.7 GB to 29.1 GB:

| Key | Download | Free memory needed | Refusals removed? |
|---|---|---|---|
| `9b-4bit` | 4.7 GB | 8 GB | **No** — stock Qwen3.8-9B |
| `27b-2bit` | 7.8 GB | 11 GB | Yes — smallest abliterated, and 2 bits costs real quality |
| `27b-4bit-aeon` | 14.1 GB | 18 GB | Yes — a different abliteration (AEON) |
| `27b-4bit` | 16.9 GB | 21 GB | Yes — sensible on a 32 GB Mac |
| `27b-5bit` | 20.0 GB | 23 GB | Yes — **the tested build** |
| `27b-6bit` | 23.0 GB | 26 GB | Yes |
| `27b-8bit` | 29.1 GB | 32 GB | Yes — wants a 48 GB Mac |

Download sizes are the real totals of the weight files, read from
huggingface.co in August 2026. The free-memory figures are those sizes plus
roughly 3 GB for the conversation and the caches; they are what
`./bin/serve.sh` will insist on before it starts.

Only the 5-bit row has been run on the test machine. The others are listed
because they exist and their sizes are known, not because they were benchmarked
here.

**Any other MLX model works too**, whether or not it is in the list:

```
./bin/download-model.sh <org>/<repo>
./bin/models.sh use <org>/<repo>
```

The rest of this section explains the same choice made by hand, if you would
rather see the mechanism than use the command.

**You do not have to choose.** `bin/detect-hardware.sh` reads your Mac's memory
and picks; `./bin/download-model.sh` then downloads that build into a folder
named after it. The folder name matters, because the name the server answers to
is the folder's own name — so a folder that says `5bit` always contains the
5-bit build.

**To choose by hand**, put a line in your settings file. Copy the example file
first if you have not:

```
cp ~/dev/local-llms/airgap/config.env.example ~/dev/local-llms/airgap/config.env
```

This prints nothing. That is success. Then open `config.env` in any text editor
and change the `MODEL_QUANT` line to one of `4bit`, `5bit` or `8bit`, removing
the `#` at the start of the line.

**To download a completely different model**, pass its address on the command
line. Replace `<ORGANIZATION>/<NAME>` with the text at the top of its page on
huggingface.co. For a worked example, that might be `mlx-community/Qwen3-14B-4bit`:

```
./bin/download-model.sh <ORGANIZATION>/<NAME>
```

The folder is named after the model you asked for, so nothing ends up in a folder
claiming to be something else. Be aware that these documents describe the 27B
checkpoint specifically; the memory arithmetic in [07 — tuning](07-tuning.md)
does not apply to any other model, because it depends on this one's unusual layer
split.

---

## 8. Confirm nothing large went into version control

This repository must never contain model weights, and the `.gitignore` file
([Glossary](09-glossary.md#gitignore)) is what enforces it. Confirm it worked.

```
cd ~/dev/local-llms/airgap && git status --short
```

That is one action expressed as two commands, because the check only means
anything inside the repository folder.

You should see nothing at all, or a short list of files you have edited yourself,
such as:

```
 M config.env.example
```

**The model folder name must not appear in that list.** Nor must any file name
ending in `.safetensors`.

**If you do not see that.** If the model folder or a `.safetensors` file appears,
STOP. Do not run `git add`. The rules in `.gitignore` did not match your folder
name, which happens if you renamed the folder or chose a model with an unusual
name. Fix it by adding the folder's exact name to `.gitignore` on its own line,
then run the check again.

---

## 9. <a id="license"></a>Two honest things about this model

### It has had its refusal behavior removed

The publisher did this deliberately. The technical name is an **abliterated**
model ([Glossary](09-glossary.md#abliterated-model)). The method identifies the
internal direction the model uses to represent "decline this" and mathematically
removes that direction from what flows through it. In plain words: most models
decline certain requests, and this one declines very little.

That is workable for research on your own machine, alone, which is what this
setup is for. It is not something to put where other people can reach it.

This is exactly why the server here listens only on `127.0.0.1`, the address that
means "this Mac and nothing else". The server's own default is `0.0.0.0`, which
means every network your Mac is connected to. This repository overrides that
default, and the override is enforced rather than merely suggested:
`./bin/serve.sh` refuses to start with any other address, and `./bin/doctor.sh`
reports the address the server is really listening on rather than the one it was
asked for.

Do not make this server reachable from your network or from the internet.

### It has its own license, and it is not this repository's license

The checkpoint ships under the **Apache License 2.0**. Two files inside the model
folder record this, and you should read both.

This prints the first lines of the model's own license.

```
head -5 ~/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit/LICENSE
```

You should see something like this:

```
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION
```

Nothing here differs between machines.

The second file, `LINEAGE.json` in the same folder, records what the model was
built from: the base model, the source files, and their fingerprints.

**If you do not see that.** `No such file or directory` means the download did
not finish, or your folder has a different name. Use the path `./bin/doctor.sh`
prints on its `model dir` line.

**What this means for you.** The MIT license covering the scripts and documents
in this repository grants you no rights at all over the weights. This repository
does not redistribute them; `./bin/download-model.sh` fetches them from the
publisher. Reading the model's license is your responsibility, not this
repository's.

---

## How to know it worked

Four checks, each of which you have already run:

1. `./bin/download-model.sh` ended with `download complete`.
2. `./bin/verify-model.sh` ended with `verify PASS`.
3. `./bin/doctor.sh` shows `PASS` on its `model dir`, `weights` and `model id`
   lines.
4. `git status --short` inside the repository folder does not list the model
   folder.

## How to stop

Nothing on this page is still running. If a download is in progress, press
Control-C in that window. Nothing is corrupted, and running
`./bin/download-model.sh` again continues from where it stopped.

## How to undo everything

Deleting the model folder is the whole undo, and it reclaims the disk
immediately. Replace the folder name if yours is different — use the one
`./bin/doctor.sh` prints.

```
rm -rf ~/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
```

This prints nothing. That is success. Nothing else on your Mac depends on that
folder, and you can download it again later with the same command as before.

## What this page will not do

It does not start the server, load the model, or use any meaningful memory.
Nothing you have done so far can make your Mac slow. The page that starts using
memory is [05 — run it](05-run-it.md), and the page that must be read before it
is [04 — memory safety](04-memory-safety.md).

---

**Read next:** [04 — memory safety](04-memory-safety.md). Read it *before* your
first run, not after. It explains why `./bin/serve.sh` will refuse to start, what
to close, and which single macOS setting is genuinely worth being careful about.
