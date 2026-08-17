# 05 — Run it

**Who this is for.** Anyone who has downloaded the model and read the memory
page, and now wants the thing to actually work. You do not need to know what a
server is, what a port is, or what any word here means before you read it.

**What you will have at the end.** A coding assistant answering your questions in
a Terminal window, with the answers produced entirely by your own Mac. You will
also be able to prove that nothing left the machine, and you will know how to
stop it and get the memory back.

**How long it takes.** About 15 minutes of your attention. The only wait is about
one minute the first time the model loads.

**What it costs.** Memory, and this is the page where that becomes real: the
amount `./bin/doctor.sh` reports for your Mac, which is 22 GB on the 36 GB test
machine. No disk beyond what you already used. No money. Nothing leaves your Mac.

**What you need first.**

- [03 — get the model](03-get-the-model.md) finished, with `verify PASS`.
- [04 — memory safety](04-memory-safety.md) read. Not skimmed. This page starts
  the thing that uses the memory.
- Two Terminal windows. You will use one for the server and one for the app.

**If you only read one thing:** free memory *before* you start, not after. Close
your browser and Docker Desktop. Step 1 shows you the exact number to beat.

---

## 1. What is about to happen

Three programs, in this order.

**`./bin/serve.sh`** starts the **server**
([Glossary](09-glossary.md#inference-server)) — the program that holds the
model's numbers in memory and turns a question into an answer. It stays running
in one Terminal window and prints as it works. This is the program that uses the
memory.

**`./bin/claude-local.sh`** starts **Claude Code**
([Glossary](09-glossary.md#claude-code)) — the app you type into — in a second
Terminal window, with every one of its settings pointed at the server on your own
Mac instead of at Anthropic's.

**`./bin/stop.sh`** ends the first one and gives the memory back.

Between Claude Code and the server there is nothing at all. Claude Code speaks a
specific request format called the **Anthropic Messages API**
([Glossary](09-glossary.md#anthropic-messages-api-v1messages)) — the agreed shape
of a message an app sends to a model. The server understands that exact format
already. Most local setups need an extra translating program in the middle; this
one does not.

---

## 2. Step 1 — Free memory, and prove you did

**This is the step people skip and then get a slow Mac.**

Close, in this order, whatever you have running:

1. **Docker Desktop**, if you use it. It runs a whole virtual machine — 2.7 GB of
   memory on the test machine, MEASURED — and quitting the app is not always
   enough. From a Terminal window: `docker desktop stop`.
2. **Your web browser.** All of it, not just the window. Browsers hold several
   gigabytes across their tabs.
3. **Any virtual machine**, and any large editor project you are not using.

Now measure. Every command from here runs from the repository folder, and this
puts your Terminal window there. Throughout these documents the folder is written
as `~/dev/local-llms/qwen3.8free`; if you put it somewhere else, use your path.

```
cd ~/dev/local-llms/qwen3.8free
```

This prints nothing. That is success.

**What this does.** It prints how much memory is free right now, and next to it
the amount this Mac needs before the server will agree to start.

```
bash -c 'source bin/env.sh && echo "$(available_gb) GB available, need $MIN_FREE_GB GB"'
```

You should see something like this:

```
24.3 GB available, need 22 GB
```

**Both numbers are yours.** The first changes minute to minute as you use your
Mac. The second is worked out from your Mac's memory size and is 22 on the 36 GB
test machine, 19 on a 32 GB Mac, 26 on a 48 GB Mac. Do not compare your first
number against 22; compare it against your own second number.

**If you do not see that.** `No such file or directory` means you are not in the
repository folder — run the `cd` command above first.

### CHECKPOINT

**Stop here.** Confirm that **the first number is at least as large as the
second**. If it is not, close more apps and run the command again. `./bin/doctor.sh`
lists your biggest memory users if you are not sure what to close.

Do not continue until the first number wins. `./bin/serve.sh` will refuse anyway,
so the only thing you gain by pushing on is a confusing error message.

---

## 3. Step 2 — Start the server

**WHAT THIS CHANGES ON YOUR MAC.** This command loads about 19.1 GB of numbers
into your Mac's memory and keeps them there. Your Mac has that much less memory
for everything else while it runs. It does not change any macOS setting, write
anything outside this repository and its own log file, or install anything.

**IS IT REVERSIBLE.** Completely, and immediately. Press Control-C in that window,
or run `./bin/stop.sh` from another one. The memory comes back at once.

**WHAT HAPPENS IF IT GOES WRONG.** If you force it past the memory check on a Mac
that is too full, the machine becomes slow, the fans spin up, and clicks stop
responding for a while. It recovers on its own once the server is stopped. That
is why the check exists and why you should not switch it off.

**WHY YOU MIGHT NOT WANT TO RUN IT.** If you did not finish Step 1, do that
first. There is no other reason to hesitate.

**CONFIRM FIRST** that Step 1's first number was at least as large as its second.

Use your first Terminal window for this.

```
./bin/serve.sh
```

You should see something like this, and then the window keeps printing:

```
memory   24.3 GB available (need 22 GB) — ok
model    /Users/<YOUR_USER_NAME>/dev/local-llms/qwen3.8free/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
endpoint http://127.0.0.1:11234   (Anthropic: http://127.0.0.1:11234/v1/messages)
context  65536 tokens, kv-quant turbo4
budget   weights<=21GB, prefix 1536MB, idle-evict 900s
log      ~/.mlx-serve/logs/mlx-serve-11234.log

Loading about 19.1 GB. The first load takes about a minute.
Leave this window open. Press Ctrl-C to stop, or run ./bin/stop.sh elsewhere.
Next: open another window and run ./bin/claude-local.sh
```

After that the server prints its own startup messages, and finally a line saying
it is listening.

Six of those values differ on your Mac: the two memory figures, the path (it
contains your account name), the context size, the two budget figures, and the
folder name if you have the 4-bit or 8-bit build. The `endpoint` line is the same
on every Mac, because `127.0.0.1` means "this Mac" everywhere.

**Leave this window open and alone.** The server runs in it. Closing the window
stops the server.

**If you do not see that.** Four things can stop it, and the first three are
STOP-and-fix, not warnings.

- `REFUSING TO START — not enough free memory.` — **STOP.** This is the guard
  doing its job. It lists the biggest memory users, in order. Close them, then
  run the command again. Full entry:
  [06 — troubleshooting](06-troubleshooting.md#not-enough-memory).
- `error: <file> is still a git-lfs pointer, not weights.` — FIX THIS by running
  the command the message names.
  [06 — troubleshooting](06-troubleshooting.md#lfs-pointers).
- `REFUSING TO START — HOST is '<something>', not 127.0.0.1.` — FIX THIS. You, or
  a line in `config.env`, changed the address the server listens on. Remove it.
  [06 — troubleshooting](06-troubleshooting.md#exposed-server).
- `error: Address already in use` — FIX THIS. Something already holds the number
  the server wants. [06 — troubleshooting](06-troubleshooting.md#port-in-use).

### CHECKPOINT

**Stop here.** Open your **second** Terminal window and confirm the server is
answering before you go any further.

This asks the server whether it is awake. It sends one tiny request to your own
Mac.

```
curl http://127.0.0.1:11234/health
```

You should see a short line of text in braces, something like this:

```
{"status":"ok"}
```

The exact wording depends on the version of the server. What matters is that
something came back rather than an error.

**If you do not see that.** `Connection refused` means the server is not running
yet — look at the first window. If it is still printing its startup messages,
wait for the line that says it is listening and try again.
[06 — troubleshooting](06-troubleshooting.md#no-server).

---

## 4. Step 3 — Start Claude Code, pointed at your Mac

Use your **second** Terminal window, the one you just ran `curl` in.

**What this does.** It starts Claude Code with every model setting pointed at
your own Mac, and with any real Anthropic key in your shell blanked out so it
cannot take priority.

```
cd ~/dev/local-llms/qwen3.8free && ./bin/claude-local.sh
```

That is one action expressed as two commands, because the script needs to be
found and the folder it starts in becomes the folder Claude Code works on. To
work on a different project, see Section 8.

You should see these four lines before Claude Code's own screen appears:

```
claude   -> http://127.0.0.1:11234   model Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
context  65536 tokens declared to the harness, 8192 max output
mcp      strict (LEAN_MCP=1) — MCP servers off, saves ~17k prompt tokens per turn
note     a one-line "unrecognized_model" warning at startup is EXPECTED and cosmetic
```

The model name and the context number differ if you have the 4-bit or 8-bit
build, or a different context size. The address is the same on every Mac.

That third line mentions **MCP**, which stands for Model Context Protocol
([Glossary](09-glossary.md#model-context-protocol-mcp)). MCP servers are optional
add-ons that give Claude Code extra tools — a connection to a database, a
web-search tool, and so on. This setup switches them off, because the
*descriptions* of those tools alone cost about 17,000 tokens of the model's
limited memory on **every single turn**. Section 7 has the measured numbers and
how to turn them back on.

**If you do not see that.**

- `error: no server at http://127.0.0.1:11234 — start ./bin/serve.sh first` —
  FIX THIS. Go back to Step 2 in your first window.
  [06 — troubleshooting](06-troubleshooting.md#no-server).
- `command not found: claude` — FIX THIS. Claude Code is not installed, or is
  installed under another name. [06 — troubleshooting](06-troubleshooting.md#claude-code-missing).

### 4a. What Claude Code shows on a brand new install — EXPECTED

If you have never started Claude Code on this Mac before, it does not go straight
to an input box. It runs a short first-time setup, on its own screens, before
anything on this page continues. This is Claude Code's own behavior, not
something these scripts do.

Expect to be asked, roughly in this order:

1. **A color theme.** Pick whichever you like with the arrow keys and press
   Return. It changes nothing but colors.
2. **Whether you trust the files in this folder.** Claude Code asks this the
   first time it opens any folder. The folder in question is the one you ran the
   command from — your own repository folder, containing the scripts you have
   already read. Answering yes is safe and is required to continue.

Exact wording and the number of screens vary between versions of Claude Code.
This description was written against Claude Code 2.1.233, the version measured on
the test machine. If you meet a screen not listed here, read it: none of them
asks for a password, a card, or a key, because this setup uses none of those.

Once through, you reach the normal Claude Code input prompt.

### 4b. The one warning you will see — EXPECTED

Somewhere in Claude Code's startup you will see a one-line warning mentioning
`unrecognized_model`.

**That is EXPECTED. It is cosmetic. Nothing is broken.**

It happens because Claude Code keeps a list of model names it knows about, and
the name of a model that exists only on your Mac is not on it. Claude Code says
so once and then works normally.

This one string produces more confused questions than anything else in this
setup, which is why it is named here before you meet it. Full entry:
[06 — troubleshooting](06-troubleshooting.md#unrecognized-model).

---

## 5. Step 4 — Ask it something

Type a question at the prompt and press Return. A good first one, because you can
check the answer yourself:

```
Read bin/stop.sh and tell me in two sentences what it does.
```

**What to expect.** The first answer after a quiet period is slow — the model has
to be read off the disk again, which takes about a minute. Answers after that
start much sooner. That difference is normal and Section 9 explains it.

**How to know it worked.** The answer describes a script that stops the model
server and reports how much memory came back. If it describes something else, the
model is answering without having read the file, which a 27B model does
sometimes; ask again more explicitly.

**If you do not see that.**

- The reply is very slow the first time. That is EXPECTED, and
  [06 — troubleshooting](06-troubleshooting.md#slow-first-response) explains it.
- `Prompt exceeds maximum context length` — FIX THIS.
  [06 — troubleshooting](06-troubleshooting.md#context-length).
- The answer is confused or the tool use fails. That is the honest limit of a 27B
  model, described in [01 — requirements](01-requirements.md#6-what-you-get-and-what-you-do-not).
  Start a fresh conversation and give it a smaller job.

---

## 6. Prove it never leaves your Mac

You do not have to take this on trust. Four checks, from weakest to strongest.

### 6a. Ask the server what it is serving

**What this does.** It asks the server which model it is offering.

```
curl http://127.0.0.1:11234/v1/models
```

You should see a line of text containing the model's name, something like this:

```
{"object":"list","data":[{"id":"Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit","object":"model"}]}
```

The exact shape depends on the server version. The `id` must be the name of your
model folder — that is the whole rule for what the server calls a model.

**If you do not see that.** If the `id` is a different name, Claude Code will be
asking for something the server does not have.
[06 — troubleshooting](06-troubleshooting.md#model-id).

### 6b. Read the address in the server's own banner

The `endpoint` line printed by `./bin/serve.sh` says `http://127.0.0.1:11234`.
`127.0.0.1` is called **loopback**
([Glossary](09-glossary.md#localhost--127001--loopback)) and it means "this same
computer". A request sent there physically cannot leave your Mac; it does not
reach a network card.

### 6c. Have doctor check the real socket

**What this does.** It asks macOS which address the server is really listening on,
rather than which one it was asked to use.

```
./bin/doctor.sh
```

Among the other lines you should see:

```
PASS  bind address      127.0.0.1:11234 (loopback only)
```

If your server is not running you get a `bind setting` line instead, which
reports what `./bin/serve.sh` *will* use.

**If you do not see that.** A `FAIL bind address` line means the server is
reachable from your network. **STOP** and read
[06 — troubleshooting](06-troubleshooting.md#exposed-server). This matters more
here than in most setups, because this model has had its refusal behavior
removed.

### 6d. Turn off Wi-Fi

The strongest check, and the simplest. Turn off Wi-Fi from the menu bar, unplug
any network cable, and ask Claude Code another question.

It answers exactly as before. Nothing changes, because nothing was ever going
anywhere. Turn Wi-Fi back on when you are done.

---

## 7. What the wrapper script does that is not obvious

`./bin/claude-local.sh` is short, and two of the things it does are worth
understanding because they are the reason this works at all.

### 7a. It points *every* model setting at your Mac, not just the main one

Claude Code does not use one model. It uses a main one for your questions and a
smaller, faster one in the background for housekeeping — naming a conversation,
summarizing, and so on. There are seven separate settings that name a model, and
different versions of Claude Code read different ones.

The script sets all seven to your local model. If it set only the main one, the
background work would quietly reach for the real Anthropic service, and you would
have a setup that is local except when it is not.

It also sets the key Claude Code uses for authentication to an empty value rather
than removing it. An empty value still wins over a real key sitting in your
shell; a removed one does not. That is what stops a key you already have from
silently redirecting your questions.

### 7b. It tells Claude Code the truth about how much text fits

Claude Code has never heard of your local model, so it assumes the 200,000-token
window that the hosted models have. Left alone, it happily builds a question far
larger than your server can accept, and the server has to reject it. You see
`Prompt exceeds maximum context length` and it looks like a bug.

The script sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS` to your actual context size, so
Claude Code sizes its own summarizing against the truth.

If you change `CTX_SIZE`, this follows automatically. You never set the two
separately.

### 7c. It switches off the optional tool servers, and why

**MCP servers** ([Glossary](09-glossary.md#model-context-protocol-mcp)) are
optional add-ons that give Claude Code extra tools. Each one describes its tools
to the model, and those descriptions are sent as part of the instructions on
every single turn.

MEASURED on the test machine, with Claude Code 2.1.233:

| Setting | Claude Code's instructions, per turn |
|---|---|
| MCP servers loaded | 38,054 tokens |
| MCP servers off (`--strict-mcp-config`) | 20,909 tokens |

The conclusion to draw: those descriptions cost about **17,000 tokens on every
turn**, before you have typed anything. On a 65,536-token window that is more
than a quarter of everything the model can hold, spent on tools it will mostly
not use.

That is why `LEAN_MCP=1` is the default here. It is not a judgement about MCP; it
is arithmetic about a small window.

**To turn them back on**, run the script with the setting in front of it:

```
LEAN_MCP=0 ./bin/claude-local.sh
```

The banner's `mcp` line then reads `your normal config (LEAN_MCP=0)`. Expect
noticeably less room for your actual conversation.

### 7d. The repeated instructions are remembered, not re-read

Claude Code sends almost the same block of instructions every turn. Reading a
block of text into the model is called **prefill**
([Glossary](09-glossary.md#prefill)), and it is the slow part of a short reply.

The server keeps the processed form of that block, so an unchanged beginning does
not have to be read again. This is the **prefix cache**
([Glossary](09-glossary.md#prefix-cache)).

> **Think of it like** a bookmark in a long document you keep reopening at the
> same page. **Where the comparison stops:** the bookmark here stores the
> *result* of reading those pages, not just the position, so reopening costs
> almost nothing.

MEASURED on the test machine: on the second turn of a conversation the server's
own log reported `[hot-cache] reused 16384/20906 tokens`. About four fifths of
Claude Code's instructions were not re-read at all.

---

## 8. Using it on a different project

Claude Code works on the folder it is started in. To use the local model on
another project, go to that project and run the script by its full path.

```
cd ~/my-other-project
```

This prints nothing. That is success. Then:

```
~/dev/local-llms/qwen3.8free/bin/claude-local.sh
```

Everything works exactly as in Section 4. The server keeps running in its own
window and does not care which folder is asking.

**If you do not see that.** `No such file or directory` means the path to the
repository is different on your Mac. Use your own.

---

## 9. Two speed behaviors that are not faults

**The first answer after a quiet period takes about a minute.** After 15 minutes
with no questions, the server hands the model's memory back to macOS so you get
your Mac back. The next question makes it read the 20 GB off disk again. This is
the setting `IDLE_EVICT_SECS`, it defaults to 900 seconds, and it is the single
most useful setting for running this on a Mac you are also working on. Set it to
`0` in `config.env` to keep the model in memory permanently, at the cost of
19.1 GB you cannot use for anything else.

**Editing files is fast and writing new prose is slower.** The server notices
when the model is about to repeat text you already sent — which happens
constantly while editing a file — and produces those parts in large jumps instead
of piece by piece. The technique is **prompt lookup decoding (PLD)**
([Glossary](09-glossary.md#prompt-lookup-decoding-pld)). New prose has nothing to
copy from, so it goes at the ordinary rate. That is the feature working as
designed, not a fault.
[06 — troubleshooting](06-troubleshooting.md#slow-always) covers the case where
*everything* is slow, which is a different problem.

---

## How to know it worked

Five checks, in order:

1. `./bin/doctor.sh` ends with `doctor: OK`.
2. The first window shows the server's banner and a line saying it is listening.
3. `curl http://127.0.0.1:11234/health` returns something rather than an error.
4. Claude Code answers a question you typed.
5. It still answers with Wi-Fi turned off.

## How to stop

Either press **Control-C** in the server's window, or, from any other window:

```
cd ~/dev/local-llms/qwen3.8free && ./bin/stop.sh
```

You should see something like this:

```
stopped.
memory: 12.4 GB -> 31.8 GB available
```

Both figures are yours. If nothing was running you get `nothing running on port
11234.` instead, followed by the same memory line. The command is safe to run
when nothing is running.

**If you do not see that.** If it says it is sending a stronger signal because the
server did not exit cleanly, that is fine — it waits ten seconds first and then
stops it firmly. The memory still comes back.

## How to undo everything

- **Get the memory back:** `./bin/stop.sh`. Immediate.
- **Get the disk back:** delete the model folder inside the repository. See
  [03 — get the model](03-get-the-model.md#how-to-undo-everything).
- **Remove the two tools:** they were installed with Homebrew. The exact commands
  are at the end of [02 — install](02-install.md).
- **Remove everything:** delete the repository folder.
- **Nothing to revert in macOS.** None of these scripts changes a system setting.
  [04 — memory safety](04-memory-safety.md#wired-limit) describes the one setting
  other guides tell you to change, explains why this repository leaves it alone,
  and gives the undo command in case you already changed it.

## What this will not do

It will not match Claude Sonnet or Claude Opus. It loses the thread on long
chains of steps, drifts from complicated instructions, and sometimes produces a
malformed request to its own tools, which Claude Code recovers from badly. Long
conversations degrade. Give it one job at a time and start fresh often. The full
honest description is in
[01 — requirements](01-requirements.md#6-what-you-get-and-what-you-do-not).

No tokens-per-second figure has been measured for this model on any machine, so
this repository does not print one.

---

**Read next:** [06 — troubleshooting](06-troubleshooting.md) if anything above
went wrong — it is organised by what you saw, not by what caused it. Otherwise
[07 — tuning](07-tuning.md) for a longer memory, better long-conversation
quality, or a speed measurement, and [08 — how it works](08-how-it-works.md) for
the engineering behind all of it.
