# 06 — Troubleshooting

**Who this is for.** Anyone who hit a message they did not expect. You do not need
to have read the other documents. Every entry stands on its own and explains its
own terms.

**What you will have at the end.** The specific thing that went wrong, in plain
words, and the exact command that fixes it. Every entry ends with a way to check
that the fix worked.

**How long it takes.** Most entries take under a minute of your attention. Two of
them — a re-download and a model reload — involve waiting, and each says so before
you start.

**What it costs.** Nothing on this page costs money. One entry re-downloads about
19.1 GB. One entry asks for your password. Both are marked. Nothing on this page
sends any of your text or code off your Mac.

**What you need first.**

- This repository cloned to your Mac. See [02 — install](02-install.md).
- Terminal open, in the repository folder. Every section below starts with the
  `cd` command that puts you there.

**If you only read one thing:** run `./bin/doctor.sh`. It checks the whole setup
without changing anything, and every failure it prints ends with a link to the
exact entry on this page.

---

## How to use this page

Do not read this document from top to bottom. Find your symptom.

Entries are ordered by how often the failure happens. The first entry is the most
common failure in the whole project.

There are two ways in:

1. **You saw a message.** Search this page for a distinctive phrase from it.
2. **`./bin/doctor.sh` told you where to go.** Each failure line it prints ends
   with a link like `-> docs/06-troubleshooting.md#lfs-pointers`. That is the
   name of an entry on this page.

Before anything else, move into the repository folder. Terminal windows get
closed, so no section on this page assumes you are already there.

This moves you into the repository folder. Replace `<PATH_TO_THE_REPO_FOLDER>`
with the full path where you cloned it — for example,
`~/dev/local-llms/airgap`.

```bash
cd <PATH_TO_THE_REPO_FOLDER>
```

This prints nothing. That is success. If you see `cd: no such file or directory`,
find the folder in Finder and drag it onto the Terminal window; the correct path
is typed for you.

### The one command that diagnoses everything

This checks your Mac, your tools, the model files, the server, and the Claude Code
settings. It reads only. It never starts, stops, or changes anything.

```bash
./bin/doctor.sh
```

You should see something like this:

```
airgap doctor
── environment ──────────────────────────────
PASS  macos             26.5.2 (arm64)
PASS  apple silicon     Apple M3 Max, 30 GPU cores
PASS  ram tier          36 GB total — workable, default build 27b-5bit at 65536 tokens
PASS  gpu ceiling       weights + conversation (19.1 + 1.00 GB) fit under Apple's 27.0 GB ceiling
PASS  memory            36 GB total, 24.3 GB available (need 22)
PASS  wired limit       iogpu.wired_limit_mb=0 (auto, about 27.0 GB) — recommended
PASS  disk              460.4 GB free
── tools ────────────────────────────────────
PASS  homebrew          6.0.17
PASS  git-lfs           3.7.1
PASS  git-lfs enabled   switched on for your account
PASS  mlx-serve         26.8.8
PASS  claude code       2.1.233
─────────────────────────────────────────────
21 pass, 0 warn, 0 fail, 1 skipped
doctor: OK — next: ./bin/serve.sh
```

Output trimmed — the real command prints five sections and the middle three are
left out here. Your macOS version, chip, memory figures, disk figure and tool
versions will all be different, and so will the `ram tier`, `gpu ceiling` and
`memory` lines, which are worked out from your own Mac's memory size.

`PASS` is good. `WARN` means you can continue. `FAIL` means fix it first, and the
line tells you which entry below to open. `SKIP` on the server section means the
server is not running, which is normal when you have not started it yet.

If you see `zsh: permission denied: ./bin/doctor.sh`, the script is not marked as
runnable. Fix it with `chmod +x bin/*.sh` from the repository folder.

---

<a id="lfs-pointers"></a>
## 1. The model files are about 135 bytes each

**Frequency: this is the most common failure in the project.**

### What you see

When you start the server:

```
error: model-00002-of-00005.safetensors is still a git-lfs pointer, not weights.
       run: cd '/Users/<YOUR_USER_NAME>/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit' && git lfs pull
```

Or, if you look at the model folder, the large files are tiny — around 135 bytes
instead of several gigabytes.

### What it means

Very large files are not stored inside a git repository directly. They are stored
elsewhere, and the repository holds a small text file that points at them. That
small text file is called a **pointer file** (see
[Glossary](09-glossary.md#lfs-pointer-file)). The tool that swaps pointers for
real files is called **git-lfs**.

Without git-lfs installed, the download **succeeds**. It reports no error. It
leaves you 135-byte text files where 4 GB of model should be. Nothing tells you
until something later fails strangely.

This is a **FIX THIS** problem. Nothing is broken and nothing is lost.

### What to do

**Step 1.** This checks whether git-lfs is installed at all.

```bash
git lfs version
```

You should see something like this:

```
git-lfs/3.7.1 (GitHub; darwin arm64; go 1.25.0)
```

The version numbers will differ. If you see `git: 'lfs' is not a git command`,
git-lfs is missing — go to [entry 2](#git-lfs-missing) first, then come back here.

**Step 2.** This moves you into the model folder.

```bash
cd Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
```

This prints nothing. That is success. If you see `no such file or directory`, the
model was never downloaded. Go to
[03 — get the model](03-get-the-model.md) instead.

**Step 3.** This downloads the real files in place of the pointers. It transfers
about 20 GB and can take tens of minutes. Leave the window open.

```bash
git lfs pull
```

You should see something like this:

```
Downloading LFS objects: 100% (5/5), 19 GB | 42 MB/s
```

The speed and the file count will differ. If it stops partway, run the same
command again — it resumes rather than restarting.

**Step 4.** This returns you to the repository folder.

```bash
cd ..
```

This prints nothing. That is success.

### How to know it is fixed

This inspects the model files without loading them. It reads a few hundred
kilobytes, not 20 GB.

```bash
./bin/verify-model.sh
```

You should see something like this:

```
shards   5/5 headers parsed, no git-lfs pointers
tensors  2207 total | 504 quantized | 333 vision | 29 MTP
MTP head PRESENT -- the reason this stack runs mlx-serve, not stock mlx-lm
size     19.1 GB of text-only weights on disk (the vision tower is skipped at
         run time via --no-vision, so it costs disk but not memory)
manifest matches ARTIFACT-MANIFEST.json (2207 tensors, 504 quantized)

verify PASS
```

Output trimmed — the real command prints four more lines above these.
`verify PASS` on the last line is what you are looking for. If it still says
`git-lfs pointer`, repeat Step 3; the transfer did not finish.

---

<a id="git-lfs-missing"></a>
## 2. git-lfs is not installed

### What you see

One of these:

```
git: 'lfs' is not a git command. See 'git --help'.
```

```
error: git-lfs not installed. Run ./bin/setup.sh first.
```

### What it means

The tool that fetches large files is missing. Without it, downloading the model
appears to work and produces the 135-byte files described in
[entry 1](#lfs-pointers).

This is a **FIX THIS** problem. Installing git-lfs takes under a minute.

### What to do

**Step 1.** This installs git-lfs using Homebrew, the package installer for macOS.
Run it from anywhere.

```bash
brew install git-lfs
```

You should see something like this:

```
==> Pouring git-lfs--3.7.1.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/git-lfs/3.7.1: 78 files, 13.6MB
```

The version and file counts will differ. If you see `zsh: command not found: brew`,
Homebrew itself is missing. Install it from the instructions at
[https://brew.sh](https://brew.sh), then run this step again.

**Step 2.** This registers git-lfs with git, once per user account.

```bash
git lfs install
```

You should see something like this:

```
Updated git hooks.
Git LFS initialized.
```

If you see `Git LFS initialized.` on its own, that is also correct.

**Step 3.** If you already downloaded the model before installing git-lfs, follow
[entry 1](#lfs-pointers) now to replace the pointer files.

### How to know it is fixed

```bash
git lfs version
```

You should see something like this:

```
git-lfs/3.7.1 (GitHub; darwin arm64; go 1.25.0)
```

Your version number will differ.

---

<a id="clone-hung-up"></a>
## 3. "fatal: the remote end hung up unexpectedly"

### What you see

During the download:

```
fatal: the remote end hung up unexpectedly
```

Sometimes with an extra line about a failed index pack, or a percentage that
stopped moving.

### What it means

The connection to the server holding the model dropped partway through. This is a
network problem, not a problem with your Mac or with this repository. It happens
most on large transfers over unstable Wi-Fi.

The download is resumable. You do not start from zero.

This is a **FIX THIS** problem.

### What to do

**Step 1.** This moves you into the model folder, which already exists from the
partial download.

```bash
cd Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
```

This prints nothing. That is success. If you see `no such file or directory`, the
download failed before creating anything. Run `./bin/download-model.sh` from the
repository folder instead.

**Step 2.** This resumes the large-file transfer from where it stopped.

```bash
git lfs pull
```

You should see something like this:

```
Downloading LFS objects: 100% (5/5), 19 GB | 42 MB/s
```

If it fails again immediately, your connection is the problem. Move closer to the
router, or use a wired connection, and run the same command again. Each attempt
keeps what the previous attempt fetched.

**Step 3.** This returns you to the repository folder.

```bash
cd ..
```

This prints nothing. That is success.

### How to know it is fixed

```bash
./bin/verify-model.sh
```

You should see `verify PASS` on the last line. If it names a file that is still a
pointer, run Step 2 again.

---

<a id="untrusted-tap"></a>
## 4. Homebrew refuses to install mlx-serve from an untrusted source

### What you see

When installing the server:

```
Error: Refusing to load formula because tap ddalcu/mlx-serve is not trusted.
```

The exact wording changes between Homebrew versions. The part that identifies this
problem is the phrase **Refusing to load formula** together with the word
**trusted** or **untrusted**.

### What it means

The server used here, **mlx-serve**, is not in Homebrew's built-in catalog. It
comes from a third-party source, which Homebrew calls a **tap**. Recent Homebrew
versions will not install anything from a third-party tap until you say
explicitly that you trust it. That is a deliberate safety feature.

This is a **FIX THIS** problem. It needs one extra command that most guides
forget.

### What to do

Installing takes three commands, in this order. Run each from anywhere.

**Step 1.** This tells Homebrew where to find mlx-serve.

```bash
brew tap ddalcu/mlx-serve https://github.com/ddalcu/mlx-serve
```

You should see something like this:

```
==> Tapping ddalcu/mlx-serve
Tapped 1 formula (14 files, 24.5KB).
```

The file count will differ. If you see `Error: Tap ddalcu/mlx-serve already
tapped.`, that step is already done. Continue to Step 2.

**Step 2.** This is the step people miss. It records that you trust this source.
Nothing is installed yet.

```bash
brew trust ddalcu/mlx-serve
```

You should see something like this:

```
Trusted ddalcu/mlx-serve
```

If you see `Error: Unknown command: trust`, your Homebrew is older than the
version that added this requirement. In that case you did not need this step at
all — go straight to Step 3.

**Step 3.** This installs the server.

```bash
brew install mlx-serve
```

You should see something like this:

```
==> Installing mlx-serve from ddalcu/mlx-serve
🍺  /opt/homebrew/Cellar/mlx-serve/26.8.8: 412 files, 88.2MB
```

The version and file counts will differ.

`./bin/setup.sh` runs all three of these for you. This entry exists for people who
installed by hand and hit the middle step.

### How to know it is fixed

```bash
mlx-serve --version
```

You should see something like this:

```
mlx-serve 26.8.8
```

Your version number may be higher.

---

<a id="not-enough-memory"></a>
## 5. "REFUSING TO START — not enough free memory"

### What you see

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

The program names and sizes will be different on your Mac.

### What it means

The model needs about 19.1 GB of memory, all at once, plus room to work. Your Mac
does not have that much free at this moment. The script checked before loading
anything and stopped.

This is a **STOP** message, and it is the guard working correctly. Nothing broke.
Nothing needs repairing. The Mac is exactly as it was.

The list of programs is sorted largest first. Those are the things worth closing.

### What to do

**Step 1.** If you use Docker, stop it. It runs a whole virtual machine and is
usually the largest single win. Your containers and images are not deleted.

```bash
docker desktop stop
```

You should see something like this:

```
Docker Desktop is stopping...
```

If you see `command not found: docker`, Docker is not installed. Move to Step 2.

**Step 2.** Quit your browser using the app itself, not by closing tabs. Browsers
spread memory across many helper processes, and quitting the whole app frees far
more than closing tabs does.

**Step 3.** This reports how much memory macOS could hand to the server right now.
Run it from the repository folder.

```bash
bash -c 'source bin/env.sh && echo "$(available_gb) GB available"'
```

You should see something like this:

```
24.3 GB available
```

Your number will differ and changes every time you run it. You need at least the
number the refusal message asked for — 22 GB by default.

If you see `bash: bin/env.sh: No such file or directory`, you are not in the
repository folder. Repeat the `cd` command at the top of this page.

**Step 4.** Start the server again.

```bash
./bin/serve.sh
```

You should see something like this:

```
memory   24.3 GB available (need 22 GB) — ok
```

Output trimmed — the full banner is five more lines.

### Do not do this

Do not set `MIN_FREE_GB=0` to get past the check. That check protects the Mac you
are typing on. If your Mac genuinely cannot free 22 GB, the correct answer is a
smaller build, not a disabled guard: `./bin/models.sh list` marks the ones that
fit, and [04 — memory safety](04-memory-safety.md) explains the trade.

### How to know it is fixed

The first line the server prints ends with `— ok` instead of `REFUSING TO START`.

---

<a id="no-server"></a>
## 6. "no server at http://127.0.0.1:11234"

### What you see

```
error: no server at http://127.0.0.1:11234 — start ./bin/serve.sh first
```

Or Claude Code starts and then fails on your first message with a connection
error.

### What it means

Claude Code is set to talk to a program running on your own Mac. That program is
not running. `127.0.0.1` is the address a computer uses to mean "myself", so
nothing here involves the internet.

This is a **FIX THIS** problem.

### What to do

**Step 1.** Open a second Terminal window. The server occupies its window for as
long as it runs, so you need one window for the server and one for Claude Code.

**Step 2.** In the new window, move into the repository folder. Replace
`<PATH_TO_THE_REPO_FOLDER>` with your path, for example
`~/dev/local-llms/airgap`.

```bash
cd <PATH_TO_THE_REPO_FOLDER>
```

This prints nothing. That is success.

**Step 3.** Start the server. It stays in the foreground and prints as it works.
The first load takes about a minute while it reads 19.1 GB from disk. Read
[04 — memory safety](04-memory-safety.md) before the first run.

```bash
./bin/serve.sh
```

You should see something like this:

```
memory   24.3 GB available (need 22 GB) — ok
endpoint http://127.0.0.1:11234   (Anthropic: http://127.0.0.1:11234/v1/messages)
```

Output trimmed. If you see `REFUSING TO START`, go to [entry 5](#not-enough-memory).
If you see `Address already in use`, go to [entry 10](#port-in-use).

### How to know it is fixed

Leave the server window open. In the other window, ask the server whether it is
awake.

```bash
curl -s http://127.0.0.1:11234/health
```

You should see something like this:

```
{"status":"ok"}
```

The exact wording may differ between server versions. Any short reply means the
server answered. If you see nothing at all, the server is not running yet — check
the other window for an error.

---

<a id="unrecognized-model"></a>
## 7. Claude Code warns about an "unrecognized_model"

### What you see

A single warning line when Claude Code starts. It contains the phrase
`unrecognized_model` and names the local model.

### What it means

**This is EXPECTED. It is not an error. Ignore it.**

Claude Code keeps a list of model names it knows about. The local model is not on
that list, because it is not one of Anthropic's models. Claude Code says so once
and then continues normally.

Everything still works. This warning generates more confused questions than any
other message in this project, which is why it is called out here and in
[05 — run it](05-run-it.md) before you meet it.

### What to do

Nothing. Continue using Claude Code.

The one thing that warning *could* have caused is handled already. Because Claude
Code does not recognize the model, it would otherwise assume a very large
conversation limit and build messages the server has to reject. `bin/claude-local.sh`
sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS` to the real limit, so that does not happen.
If you see a length error anyway, go to [entry 8](#context-length).

### How to know it is fine

Send any short message in Claude Code and get a reply. That is the whole check.

---

<a id="context-length"></a>
## 8. "Prompt exceeds maximum context length"

### What you see

```
API Error: 400 Prompt exceeds maximum context length: 38054 tokens requested, 8192 available
```

The two numbers will be different for you.

### What it means

Text is fed to a model in pieces called **tokens** (see
[Glossary](09-glossary.md#token)) — roughly three quarters of an English word
each. The model can hold a fixed number of tokens at once. That limit is the
**context window** (see [Glossary](09-glossary.md#context-window)), and this repo
sets it to 65,536 tokens.

Claude Code tried to send more than the server will accept. There are three
reasons this happens, in order of likelihood:

1. You started Claude Code without the wrapper script, so it never learned the
   real limit.
2. The conversation genuinely grew past the limit.
3. You have many extra tool integrations loaded. These are called **MCP servers**
   (see [Glossary](09-glossary.md#model-context-protocol-mcp)). Their descriptions
   are re-sent on every single turn. MEASURED on the test machine: the fixed
   instructions cost **38,054 tokens** with all MCP servers loaded, and **20,909
   tokens** without them. That is about 17,000 tokens of overhead per turn.

This is a **FIX THIS** problem.

### What to do

**Step 1.** Start Claude Code with the wrapper script rather than by typing
`claude`. The wrapper tells Claude Code the real limit. Run it from the repository
folder, in a second Terminal window, with the server already running.

```bash
./bin/claude-local.sh
```

You should see something like this:

```
claude   -> http://127.0.0.1:11234   model Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
context  65536 tokens declared to the harness, 8192 max output
timeout  client gives up after 360s of silence, the server after 300s — so the server reports it
mcp      strict (LEAN_MCP=1) — MCP servers off, saves ~17k prompt tokens per turn
note     an "unrecognized_model" line at startup is EXPECTED and cosmetic; so is
         "claude.ai connectors are disabled" — that is this script keeping it local
```

If you see `error: no server at`, go to [entry 6](#no-server).

**Step 2.** If the error still appears, start a new conversation. Type `/clear`
inside Claude Code and press Return. The old conversation is what is too long.

**Step 3.** If you had set `LEAN_MCP=0` to load your tool integrations, remove
that. The default already excludes them, which is worth about 17,000 tokens per
turn.

**Step 4.** If you need longer conversations, raise the limit. Every extra 65,536
tokens costs about 1 GB of memory. Check
[04 — memory safety](04-memory-safety.md) first.

```bash
CTX_SIZE=131072 ./bin/serve.sh
```

You should see something like this:

```
memory   24.3 GB available (need 23 GB) — ok
context  131072 tokens, kv-quant turbo4
```

Output trimmed. **You do not have to raise the free-memory guard yourself** — the
`need` figure on the first line is recomputed for the larger window, which is why
it reads 23 rather than 22 on the 36 GB test machine. Both numbers are yours.

Restart `./bin/claude-local.sh` afterwards so it picks up the new number. If you
see `REFUSING TO START`, your Mac cannot spare the extra memory — go to
[entry 5](#not-enough-memory).

### How to know it is fixed

The `context` line in the `./bin/claude-local.sh` banner shows the same number as
the `context` line in the `./bin/serve.sh` banner. Send a message and get a reply.

---

<a id="model-id"></a>
## 9. The server does not recognize the model name

### What you see

Claude Code returns an error mentioning the model name, often with `404` or
`model not found`, even though the server is clearly running.

### What it means

The server advertises exactly one name for the model, and that name is the **name
of the folder the model lives in**. Not the name on the download page. Not the
name in any settings file. The folder name.

If you renamed or moved that folder, the name changed with it, and Claude Code is
asking for a name that no longer exists.

This is a **FIX THIS** problem.

### What to do

**Step 1.** This asks the server which model names it accepts. Run it from
anywhere, with the server running.

```bash
curl -s http://127.0.0.1:11234/v1/models
```

You should see something like this:

```
{"object":"list","data":[{"id":"Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit","object":"model"}]}
```

The formatting may differ between server versions. The value after `"id"` is the
only name the server accepts. If you get no reply, the server is not running — go
to [entry 6](#no-server).

**Step 2.** This shows the name the scripts will send. Run it from the repository
folder.

```bash
bash -c 'source bin/env.sh && echo "$MODEL_ID"'
```

You should see something like this:

```
Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
```

The two names from Step 1 and Step 2 must match character for character.

**Step 3.** If they do not match, point the scripts at the folder you actually
have. Replace `<FULL_PATH_TO_MODEL_FOLDER>` with the real path — for example,
`/Users/<YOUR_USER_NAME>/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit`.

```bash
MODEL_DIR=<FULL_PATH_TO_MODEL_FOLDER> ./bin/serve.sh
```

You should see the path you gave on the `model` line of the startup banner. To
make this permanent, put the same `MODEL_DIR=` line in `config.env` in the
repository folder.

### How to know it is fixed

Repeat Steps 1 and 2. The two names match. Send a message in Claude Code and get a
reply.

---

<a id="port-in-use"></a>
## 10. "Address already in use"

### What you see

```
OSError: [Errno 48] Address already in use
```

The wording varies. The identifying part is **Address already in use**, sometimes
with **48**.

### What it means

A **port** is a numbered door on your Mac that one program at a time may use. This
project uses door number 11234. Something is already standing in it — almost
always a copy of the server you started earlier and forgot.

This is a **FIX THIS** problem.

### What to do

**Step 1.** This stops any server this project started, and reports the memory
that came back. Run it from the repository folder. It is safe to run when nothing
is running.

```bash
./bin/stop.sh
```

You should see something like this:

```
stopped.
memory: 12.4 GB -> 31.8 GB available
```

Both numbers will differ. If it prints `nothing running on port 11234.`, this
project is not the program holding the door. Continue to Step 2.

**Step 2.** This lists what is using door 11234.

```bash
lsof -nP -iTCP:11234 -sTCP:LISTEN
```

You should see something like this:

```
COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
mlx-serve 48210 you     12u  IPv4 0x9f2a1b4c8d3e1f00      0t0  TCP 127.0.0.1:11234 (LISTEN)
```

If it prints nothing at all, the door is free and you can start the server again.
The number in the `PID` column identifies the program.

**Step 3.** If some other program owns the door, use a different door instead of
fighting for this one. Any number between 1024 and 65535 that nothing else uses
will work.

```bash
PORT=11500 ./bin/serve.sh
```

You should see something like this:

```
endpoint http://127.0.0.1:11500   (Anthropic: http://127.0.0.1:11500/v1/messages)
```

Output trimmed. You must use the same `PORT=11500` in front of
`./bin/claude-local.sh`, or put a `PORT=11500` line in `config.env` so both
scripts agree.

### How to know it is fixed

`./bin/serve.sh` reaches its `endpoint` line without an error, and
`curl -s http://127.0.0.1:11234/health` returns a short reply.

---

<a id="real-api"></a>
## 11. Claude Code is still calling the real Anthropic service

### What you see

Any of these:

- Claude Code answers noticeably faster and better than a local model should.
- Your Anthropic usage goes up while you thought you were offline.
- Claude Code works when the server is stopped.
- `./bin/doctor.sh` prints a failure on the `ANTHROPIC_API_KEY` line.

### What it means

Claude Code decides where to send your messages by reading settings in your
Terminal called **environment variables**. If you already have a real Anthropic
key set — in your `.zshrc` file, or from another tool — that key can take priority
and send your messages to Anthropic instead of to your Mac.

This is a **FIX THIS** problem. It is a privacy issue, not a breakage.

### What to do

**Step 1.** This shows whether a real key is set in this Terminal window.

```bash
env | grep ANTHROPIC
```

You should see something like this, if nothing is set:

```
(no output)
```

No output means nothing is set, which is what you want before starting. If you see
lines containing `ANTHROPIC_API_KEY=` or `ANTHROPIC_BASE_URL=` with a value, those
are the problem.

**Step 2.** Always start Claude Code through the wrapper script. It blanks the key
before starting Claude Code, so a key in your shell cannot win. Run it from the
repository folder.

```bash
./bin/claude-local.sh
```

You should see something like this:

```
claude   -> http://127.0.0.1:11234   model Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
```

Output trimmed. The address on that line must be `127.0.0.1`. If it names anything
else, an `ANTHROPIC_BASE_URL` in your shell overrode it — remove that line from
your shell startup file and open a new Terminal window.

**Step 3.** To be certain, prove it. See [entry 16](#verify-local).

### How to know it is fixed

Stop the server with `./bin/stop.sh`, then start `./bin/claude-local.sh`. It must
refuse with `error: no server at http://127.0.0.1:11234`. If it starts anyway, it
is not talking to your Mac.

---

<a id="slow-first-response"></a>
## 12. The first reply is slow, then the rest are quick

### What you see

You send a message. Nothing happens for several seconds, sometimes much longer.
Then the answer appears at a steady speed. The next message in the same
conversation starts much faster.

### What it means

**This is EXPECTED. It is how the model works, not a fault.**

Answering happens in two stages.

**Stage one: reading.** The model reads everything you sent — your message, the
conversation so far, and a long block of fixed instructions Claude Code always
includes. This stage is called **prefill** (see
[Glossary](09-glossary.md#prefill)). Its cost scales with how much text there is.

**Stage two: writing.** The model produces the answer one token at a time. This
stage runs at a steady rate that does not depend on how much you sent.

The pause before the first word is stage one.

Two things make this better, and both are already switched on.

The first is a **prefix cache** (see [Glossary](09-glossary.md#prefix-cache)): the
server keeps its reading notes for text that has not changed.

> **Think of it like** keeping the answer to a question you get asked every
> morning on a sticky note. **Where the comparison stops:** the note is only valid
> while the text matches from the very beginning. Change the first sentence and
> the note is thrown away.

MEASURED on the test machine, on the second turn of a conversation: the server
reported `reused 16384/20906 tokens`. About 78 percent of the reading was skipped.

The second is a longer-term consequence: after 15 minutes with no messages, the
server releases the model to give your memory back. The next message reloads it,
which takes about a minute. That reload is the long version of this pause.

### What to do

Nothing is required. If the pause after an idle period bothers you more than the
memory does, keep the model loaded permanently. Run this from the repository
folder.

```bash
IDLE_EVICT_SECS=0 ./bin/serve.sh
```

You should see something like this:

```
budget   weights<=21GB, prefix 1536MB, idle-evict 0s
```

Output trimmed. `idle-evict 0s` means the model stays in memory. About 19.1 GB
stays occupied for as long as the server runs. On a 36 GB Mac, expect to keep
other large apps closed.

### If the pause never ends

Everything above describes a pause that finishes. There is a limit on how long
it is allowed to take, and this is the turn most likely to reach it: a reload of
about a minute, then roughly 21,000 tokens of reading, before the first word.

The limit is `SERVE_TIMEOUT`, 300 seconds by default, and it counts only time
spent producing **nothing**. An answer that keeps arriving is never cut off,
however long it runs.

When it is reached, the server abandons that one question. The server window
records it; the session stays usable and the next question is unaffected.

Raise it, for that one run or in `config.env`:

```bash
SERVE_TIMEOUT=900 ./bin/serve.sh
```

The server prints the value it is using at startup, so you can check it:

```
timeout  300s without a token before a question is given up on
```

`./bin/claude-local.sh` reads the same setting and gives Claude Code a minute
more than the server, so the server is the side that gives up first and the
side that can say why. Its own startup line shows both numbers.

Claude Code will not accept less than 300 seconds on its side whatever you set
— version 2.1.233 raises anything smaller back to 300. So `SERVE_TIMEOUT` below
240 makes the server the only limit that can fire, which is the sensible way
round if you are deliberately shortening it.

### How to know it is working as designed

The second message in a conversation starts answering noticeably sooner than the
first one did. That is the prefix cache doing its job.

---

<a id="slow-always"></a>
## 13. Writing is quick on file edits and slow on new prose

### What you see

When the model rewrites a file you gave it, text appears quickly. When it writes
something original, the same model is noticeably slower.

### What it means

**This is EXPECTED. It is a feature working as designed.**

The server can guess several tokens ahead and then check the guesses in one pass.
This is called **speculative decoding** (see
[Glossary](09-glossary.md#speculative-decoding)).

> **Think of it like** finishing someone's sentence and then checking whether you
> got it right. When you are right, you saved the time of hearing it out. When you
> are wrong, you throw the guess away and lose almost nothing. **Where the
> comparison stops:** a person guesses one ending. The server guesses several
> tokens at once and keeps only the run that verified.

Guessing is checked, never trusted. The output is exactly what the model would
have produced without any guessing. The model card publishes a measurement of this
in both modes with an **identical** SHA-256 checksum of the output — the same text
to the byte. (PUBLISHER-REPORTED. NOT YET MEASURED in this repository.)

When the model is copying your file back with edits, the next tokens are highly
predictable and most guesses land. When it is writing something new, fewer guesses
land and the speed falls back to normal.

### What to do

Nothing. Do not pass `--no-mtp` or `--no-pld` to turn the guessing off. Those
features are on by default and they are a large part of why this stack is usable.

If you want to see the difference yourself, there is a benchmark. Stop the server
first — the benchmark loads its own copy of the model and two copies will not fit.

```bash
./bin/stop.sh
```

You should see `stopped.` or `nothing running on port 11234.` Then run the
benchmark from the repository folder. It loads the model twice and takes several
minutes.

```bash
./bin/bench.sh
```

You should see something like this:

```
── result ──────────────────────────────────
  outputs IDENTICAL  <- speculative decoding is exact, as expected
```

Output trimmed. If it says `outputs DIFFER`, something is wrong and the timings
should not be trusted. If it refuses with `serve.sh is running on port 11234`, run
`./bin/stop.sh` first.

---

<a id="mac-sluggish"></a>
## 14. Your whole Mac becomes slow while the model runs

### What you see

The pointer stutters. Apps take seconds to switch. The fans run loudly. Typing
lags behind your fingers.

### What it means

macOS ran out of memory and started moving pages to disk to cope. Disk is far
slower than memory, so everything crawls. This is called **swapping**.

This is uncomfortable and **recoverable**. It is not damage, and nothing on your
disk is at risk.

### What to do

**Step 1.** Stop the server. This is always the first move and it is always safe.
Run it from the repository folder.

```bash
./bin/stop.sh
```

You should see something like this:

```
stopped.
memory: 12.4 GB -> 31.8 GB available
```

Both numbers will differ. The second number should be much larger than the first.

**Step 2.** Confirm the memory came back.

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

Output trimmed. This command only reports; it changes nothing. `Pages free` should
be much larger than before Step 1.

**Step 3.** Before starting again, free more memory and lower the settings. Read
[04 — memory safety](04-memory-safety.md), then start with a smaller conversation
window.

```bash
CTX_SIZE=32768 ./bin/serve.sh
```

You should see `context  32768 tokens, kv-quant turbo4` in the banner.

### If Terminal itself will not respond

The Mac is swapping, not frozen. Wait 30 seconds. It recovers on its own.

### If nothing responds at all for several minutes

Hold the power button until the Mac turns off, then start it again. This is the
one failure that costs you unsaved work in open apps. Nothing on disk is damaged.

That failure comes from a system setting called `iogpu.wired_limit_mb` being
raised by hand. A restart resets it on its own, so it will not repeat. See
[entry 15](#wired-limit) and
[04 — memory safety, Section 8](04-memory-safety.md).

### How to know it is fixed

The `memory:` line from `./bin/stop.sh` shows a large second number, and your Mac
responds normally again.

---

<a id="wired-limit"></a>
## 15. A warning about `iogpu.wired_limit_mb`

### What you see

A few lines when the server starts:

```
warning  iogpu.wired_limit_mb=30720 — that is over 80% of this Mac's 36 GB.
         Memory reserved this way cannot be swapped out, so this lets the model
         squeeze macOS itself, which is how a Mac stops responding to clicks.
         To put it back:
         sudo sysctl iogpu.wired_limit_mb=0    (it also resets when you restart)
```

A hand-set value below that 80% line gets a milder two-line version of the same
warning. `./bin/doctor.sh` reports the same thing on its `wired limit` line,
marked `WARN` (or `FAIL` above 80%).

### What it means

Some memory used by the graphics processor is locked in place. macOS cannot
compress it, move it to disk, or take it back. `iogpu.wired_limit_mb` is the
ceiling on how much may be locked that way.

Somebody raised that ceiling on this Mac. Older versions of these instructions
recommended it; that advice has been withdrawn.

Raising the ceiling does not make the model smaller. It only removes the margin
macOS keeps for itself. It is the one change in this whole project that can stall
a Mac hard enough to need a forced restart.

This is a **WARN**, not a failure. The server still starts.

### What to do

> ### WARNING — this command changes a macOS system setting
>
> - **What it changes.** The ceiling on memory the graphics processor may lock.
>   Setting it to `0` hands that decision back to macOS.
> - **Is it reversible?** Yes, completely. It affects no files and no data.
> - **A restart also reverts it.** The setting is never saved to disk. If you
>   prefer not to run a command, restart the Mac instead. That is equally
>   effective.
> - **It asks for your password.** `sudo` means "run as administrator". Terminal
>   will not display the characters you type. That is normal.
> - **Why you might skip it.** If `sysctl -n iogpu.wired_limit_mb` already prints
>   `0`, there is nothing to do.

**Step 1.** This checks the current value and changes nothing.

```bash
sysctl -n iogpu.wired_limit_mb
```

You should see something like this:

```
0
```

`0` means macOS decides, which is the recommended state. If you see a number such
as `30720`, continue to Step 2. If you see `sysctl: unknown oid`, your Mac does not
have this setting and there is nothing to do.

**Step 2.** This returns the ceiling to the macOS default.

```bash
sudo sysctl iogpu.wired_limit_mb=0
```

You should see something like this:

```
iogpu.wired_limit_mb: 30720 -> 0
```

The first number is whatever it was before. If the reply contains the words
`is read only`, restart the Mac instead; the reboot resets the setting.

### How to know it is fixed

`sysctl -n iogpu.wired_limit_mb` prints `0`, and `./bin/serve.sh` no longer prints
the warning.

---

<a id="quality-degrades"></a>
## 16. Answers get worse as the conversation gets longer

### What you see

Early answers are reasonable. After a long session the model repeats itself,
forgets things you said earlier, or loses the thread.

### What it means

Two different things can cause this, and they have different fixes.

**First cause: compression of the model's working notes.** As the model reads, it
keeps notes about everything so far. Those notes are the **KV cache** (see
[Glossary](09-glossary.md#kv-cache)). To save memory, this repo stores those notes
in a compressed form (`KV_QUANT=turbo4`, 4-bit). Compression loses a little
precision, and the loss adds up over a long conversation.

**Second cause: the model itself.** A 27-billion-parameter model at 5-bit is
materially weaker than the large hosted models at long chains of tool use. This is
a real limitation and no setting removes it. Short, well-scoped tasks are where
this model earns its keep.

### What to do

**Step 1.** Relax the note compression before changing anything else. This is the
cheapest quality improvement available. It costs about 1 GB more memory at a
65,536-token window. Run it from the repository folder.

```bash
KV_QUANT=8 ./bin/serve.sh
```

You should see something like this:

```
context  65536 tokens, kv-quant 8
```

Output trimmed. If you see `REFUSING TO START`, your Mac cannot spare the extra
memory — go to [entry 5](#not-enough-memory).

**Step 2.** If you have memory to spare, turn compression off entirely. At a
65,536-token window this costs about 4 GB instead of 1 GB.

```bash
KV_QUANT=off ./bin/serve.sh
```

You should see `kv-quant off` on the `context` line.

**Step 3.** Start a fresh conversation for each new task. Type `/clear` inside
Claude Code and press Return. This helps more than any setting.

### How to know it is fixed

Answers on long sessions improve. This is a judgment, not a measurement — no
quality benchmark has been run in this repository, and none is claimed.

---

<a id="verify-local"></a>
## 17. How to prove that nothing leaves your Mac

This is not a failure. It is the check people most want and least often know how
to run.

### What "local" means here

`127.0.0.1` is the address a computer uses to mean "myself". Traffic sent there
never reaches a network card. It cannot leave the Mac even if you wanted it to.
This repository sets the server to that address deliberately, and there is a good
reason: the server's own default is to accept connections from your whole local
network.

### Check 1 — the server is listening only to itself

This lists the network address the server is using.

```bash
lsof -nP -iTCP:11234 -sTCP:LISTEN
```

You should see something like this:

```
COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
mlx-serve 48210 you     12u  IPv4 0x9f2a1b4c8d3e1f00      0t0  TCP 127.0.0.1:11234 (LISTEN)
```

The numbers will differ. The part that matters is `127.0.0.1:11234`.

**If it says `*:11234` or `0.0.0.0:11234` instead, stop the server.** That means it
is accepting connections from your whole network, and this model has had its
built-in refusals removed. Run `./bin/stop.sh`, then start it again with
`./bin/serve.sh` rather than by running the server program by hand.

### Check 2 — Claude Code points at your Mac

This shows the address the wrapper will use. Run it from the repository folder.

```bash
bash -c 'source bin/env.sh && echo "$BASE_URL"'
```

You should see exactly this:

```
http://127.0.0.1:11234
```

If the port number differs because you changed it, that is fine. If the address
part is anything other than `127.0.0.1`, see [entry 11](#real-api).

### Check 3 — no Anthropic key is active

This lists Anthropic-related settings in your Terminal.

```bash
env | grep ANTHROPIC
```

You should see something like this:

```
(no output)
```

No output is the result you want before starting. If a real key appears here,
`./bin/claude-local.sh` blanks it before starting Claude Code — but see
[entry 11](#real-api) so you understand what is happening.

### Check 4 — the strongest test: turn off the network

1. Start the server with `./bin/serve.sh` in one Terminal window.
2. Start Claude Code with `./bin/claude-local.sh` in a second window.
3. Turn off Wi-Fi from the menu bar. Unplug any network cable.
4. Ask the model a question.

It answers normally. That is the proof. Nothing that needs a network can work
without one.

Turn Wi-Fi back on when you are finished.

### What this does not prove

It does not prove that some *other* program on your Mac is offline. It proves that
this model, this server, and this Claude Code session are. That is the claim this
repository makes, and it is the only one.

---

<a id="apple-silicon"></a>
## 18. "MLX requires Apple Silicon"

### What you see

```
FAIL  apple silicon     this Mac reports Intel(R) Core(TM) i9  -> docs/01-requirements.md#apple-silicon
```

Or the server fails to install or start with an architecture error.

### What it means

The math library this project uses runs only on Apple's own chips — the M-series.
It uses a feature those chips have and Intel Macs do not: one shared pool of
memory for the processor and the graphics processor.

This is a **STOP**. No setting changes it. This is not a bug and there is no
workaround.

### What to do

Nothing on this Mac. Your options are a Mac with an Apple chip, a different
project built on `llama.cpp` that runs on Intel processors, or a hosted service.

### How to check which chip you have

```bash
sysctl -n machdep.cpu.brand_string
```

You should see something like this:

```
Apple M3 Max
```

Anything beginning with `Apple M` works. Anything beginning with `Intel` does not.

---

<a id="disk-space"></a>
## 19. "only N GB free, need 45 GB"

### What you see

```
error: only 22 GB free, need 45 GB
       git-lfs keeps a second copy under .git/lfs until step 5 reclaims it,
```

Your number will differ.

### What it means

The model is about 20 GB on disk. During the download, the tool that fetches large files
keeps a second copy of everything, so the folder is about 40 GB while it works.
The download script asks for 45 GB up front so it cannot run out partway.

After the download, a step called dedup reclaims the duplicate. That step copies
no data and loses none — it checks each file first, so it takes a minute or two
on modern Macs. The disk ends up with about 20 GB more free than it had at the
peak.

This is a **FIX THIS** problem.

### What to do

**Step 1.** This shows free space on the disk holding the repository. Run it from
the repository folder.

```bash
df -h .
```

You should see something like this:

```
Filesystem      Size    Used   Avail Capacity iused ifree %iused  Mounted on
/dev/disk3s5   926Gi   402Gi   512Gi    45%    1.2M  5.4G    0%   /
```

The `Avail` column is what matters.

**Step 2.** Free space. Empty the Trash, and use the Apple menu, **About This
Mac**, **More Info**, **Storage** to find the largest items.

**Step 3.** Run the download again. It resumes rather than restarting.

```bash
./bin/download-model.sh
```

You should see something like this:

```
disk     512.3 GB free (need 45 GB)
```

Output trimmed.

### How to know it is fixed

`./bin/download-model.sh` gets past the `disk` line and starts the transfer.

---

<a id="claude-code-missing"></a>
## 20. "command not found: claude"

### What you see

```
zsh: command not found: claude
```

### What it means

Claude Code, the app this project drives, is not installed, or your Terminal
cannot find it.

This is a **FIX THIS** problem.

### What to do

**Step 1.** Install Claude Code following the instructions at
[https://claude.com/claude-code](https://claude.com/claude-code). Then confirm.

```bash
claude --version
```

You should see something like this:

```
2.1.233 (Claude Code)
```

Your version number may be higher.

**Step 2.** If Claude Code is installed somewhere your Terminal does not search,
tell the wrapper where it is. Replace `<FULL_PATH_TO_CLAUDE>` with the real path —
for example, `/Users/<YOUR_USER_NAME>/.local/bin/claude`.

```bash
CLAUDE_BIN=<FULL_PATH_TO_CLAUDE> ./bin/claude-local.sh
```

To make this permanent, put the same `CLAUDE_BIN=` line in `config.env` in the
repository folder.

### How to know it is fixed

```bash
./bin/doctor.sh
```

The `claude code` line reads `PASS` with a version number.

---

<a id="mtp-missing"></a>
## 21. The speed-up feature did not load

### What you see

```
WARN  mtp_loaded        false — the fast-answer head is not in use. See docs/08-how-it-works.md
```

Note that this is a `WARN`, not a `FAIL`. Warnings do not stop `./bin/doctor.sh`,
so the last line still reads `doctor: N WARNING(S) — safe to continue` and the
command still succeeds. Everything works without this; it is a speed feature.

You may instead see this, which is a third state and means something different:

```
SKIP  mtp_loaded        this server version does not report it
```

`SKIP` means the question could not be asked, not that the answer was no. Your
version of the server does not publish whether the head is loaded. Use
`./bin/verify-model.sh` to check the files instead — if it prints
`MTP head PRESENT`, the part is there and there is nothing to fix.

Or, from `./bin/verify-model.sh`:

```
verify FAIL: the publisher's manifest lists an MTP head (15 tensors) and none was found -- download is incomplete
```

Or, also from `./bin/verify-model.sh`, this line — which is **not** a failure
and needs nothing done:

```
MTP head absent  -- this checkpoint ships none. It runs; the MTP speed-up
         described in the docs does not apply to it. Not a failure.
```

### What it means

The OrcaRouter 27B builds ship with an extra part that lets the model guess
several tokens ahead and verify them in one pass. That part is called a
**multi-token prediction (MTP)** head (see
[Glossary](09-glossary.md#multi-token-prediction-mtp)). It makes the model faster
without changing a single character of the output.

Three things cause these messages, and only two of them are problems.

**First: the checkpoint simply has no MTP head.** The 9B, the 2-bit and AEON
27B builds and the stock `mlx-community` 27B builds ship none — checked against
each repository's weight index. For those, `verify-model.sh` prints `MTP head
absent` and passes, and `doctor.sh` prints `PASS mtp_loaded false — expected`.
Nothing is wrong; the speed feature does not apply to them.

**Second: the download is incomplete.** For an OrcaRouter build the extra part
lives in the model files, and the publisher's manifest says so. If the files are
still pointer files, it is not there. MEASURED in this repository: the complete
5-bit checkpoint contains 2,207 pieces of data in total, of which 29 belong to
this feature.

**Third: the wrong server program.** The widely used library `mlx-lm` **deletes**
this part of the model while loading it. That is not a bug report; it is a visible
line of its source code, and the change that would add an option to keep it is
still an open proposal. This is the specific reason this project uses `mlx-serve`
rather than `mlx-lm`.

The second and third are **FIX THIS** problems.

### What to do

**Step 1.** This inspects the model files without loading them.

```bash
./bin/verify-model.sh
```

You should see something like this:

```
tensors  2207 total | 504 quantized | 333 vision | 29 MTP
MTP head PRESENT — the reason this stack runs mlx-serve, not stock mlx-lm
verify PASS
```

Output trimmed. If the command names a pointer file, or reports that the
manifest lists an MTP head that was not found, go to
[entry 1](#lfs-pointers). If it says `MTP head absent` and passes, your
checkpoint ships none, and there is nothing to fix.

**Step 2.** Confirm you are running the right server program.

```bash
which mlx-serve
```

You should see something like this:

```
/opt/homebrew/bin/mlx-serve
```

If this prints nothing, the server is not installed — go to
[entry 4](#untrusted-tap).

**Step 3.** Start the server with the repo script rather than by hand. It never
passes `--no-mtp`, which would switch the feature off.

```bash
./bin/serve.sh
```

### How to know it is fixed

```bash
./bin/doctor.sh
```

The `mtp_loaded` line reads `PASS  mtp_loaded        true`.

---

<a id="bind-address"></a>
<a id="exposed-server"></a>
## 22. The server is reachable from other machines

### What you see

Another device on your network can open `http://<YOUR_MACS_ADDRESS>:11234` and get
a reply. Or `lsof` shows `0.0.0.0:11234` instead of `127.0.0.1:11234`.

### What it means

**This is a STOP. Fix it before continuing.**

The server program's own default is to accept connections from every device on
your network. This repository overrides that to accept connections only from your
own Mac, and `./bin/serve.sh` refuses to start with any other address. So if you
see the network-wide address, the server was started by hand rather than through
`./bin/serve.sh`.

`./bin/doctor.sh` reports this too, and it reads the address the socket is really
listening on rather than the one the settings ask for:

```
FAIL  bind address      0.0.0.0:11234 — reachable from your network  -> docs/06-troubleshooting.md#exposed-server
```

You may instead see a `FAIL bind setting` line, which means `HOST` has been set
to something other than `127.0.0.1` in `config.env` or in your Terminal. Remove
that line; `./bin/serve.sh` will not start with it.

That matters more here than it normally would. This particular model has had its
built-in refusal behavior removed by the publisher. It will answer requests that a
normal assistant declines. That is acceptable for private research on your own
machine and is the reason this repository binds it to your Mac alone.

### What to do

**Step 1.** Stop the server. Run it from the repository folder.

```bash
./bin/stop.sh
```

You should see something like this:

```
stopped.
memory: 12.4 GB -> 31.8 GB available
```

Both numbers will differ.

**Step 2.** Start it again using the repository script, which sets the address
correctly.

```bash
./bin/serve.sh
```

You should see something like this:

```
endpoint http://127.0.0.1:11234   (Anthropic: http://127.0.0.1:11234/v1/messages)
```

Output trimmed. The address must read `127.0.0.1`.

### Never do this

Do not set `HOST=0.0.0.0`. Do not pass the server's network-sharing or
network-discovery options. There is no configuration in this repository that
exposes this model beyond your own Mac, and that is deliberate.

### How to know it is fixed

```bash
lsof -nP -iTCP:11234 -sTCP:LISTEN
```

The last column reads `127.0.0.1:11234 (LISTEN)`. See
[entry 17](#verify-local) for the full set of checks.

---

## How to know everything is working

Run these three in order, from the repository folder.

1. `./bin/verify-model.sh` ends with `verify PASS`.
2. `./bin/doctor.sh` ends with `doctor: OK — next: ./bin/serve.sh`.
3. `curl -s http://127.0.0.1:11234/health` returns a short reply while the server
   runs.

## How to stop everything

```bash
./bin/stop.sh
```

You should see `stopped.` followed by a `memory:` line showing memory returned. If
it says `nothing running on port 11234.`, nothing was running, which is also fine.

## How to undo everything

- **Free the disk space:** delete the model folder inside the repository. It is
  about 20 GB and it is the only large thing this project creates.
- **Remove your settings:** delete `config.env` from the repository folder. The
  built-in defaults apply again.
- **Restore the macOS graphics memory setting:** `sudo sysctl
  iogpu.wired_limit_mb=0`, or restart the Mac, which does the same thing.
- **Uninstall the server:** `brew uninstall mlx-serve`, then
  `brew untap ddalcu/mlx-serve`.
- **Remove the repository:** delete the whole folder. Nothing outside it is
  modified.

<a id="model-lock"></a>
## 23. "something else on this Mac is already holding the weights"

### What you see

```
REFUSING TO START — something else on this Mac is already holding the weights.
  holder : pid 41207 — serve.sh, port 11234
  lock   : /Users/you/.airgap/model.lock
```

### What it means

Only one process on this Mac may hold the model at a time. Something already
does, and starting a second one would put another ~19.1 GB on top of it.

This is usually the honest answer: a `./bin/serve.sh` in a window you forgot
about, or a `./bin/bench.sh` still running. The `holder` line names its process
id and what it said it was.

The check exists because nothing else catches this. The free-memory check is a
snapshot taken before anything is allocated, and after 15 minutes of silence the
first server hands its weights back to macOS — so the memory really is free,
right up until the second server loads and it is not. The port cannot catch it
either: the server claims its port *before* it loads, so a second one started on
a different port passes every other check.

### What to do

Stop the other one:

```bash
./bin/stop.sh
```

Or look at what it is first:

```bash
ps -p $(cat ~/.airgap/model.lock/pid)
```

### If nothing is actually running

A process that was killed outright — a `kill -9`, a crash, a Mac that restarted
— cannot tidy up after itself, so its lock is left standing.

That is recognised rather than obeyed. `./bin/serve.sh` checks whether the
recorded process still exists and takes the lock anyway if it does not, so a
crash never leaves this Mac unable to start a server. You should not see the
refusal in that case at all.

`./bin/doctor.sh` reports one either way:

```
PASS  model lock        free — nothing is holding the weights
WARN  model lock        left behind by pid 41207, which is gone — ./bin/stop.sh clears it
```

and `./bin/stop.sh` clears a left-behind lock. It never touches one whose holder
is alive, so it cannot silently make room for the very second copy the lock
exists to prevent.

### How to know it is working as designed

With the server running in another window, `./bin/doctor.sh` reports the lock as
held and names that server. Start a second `./bin/serve.sh` and it refuses,
naming the first one's process id, rather than loading a second copy.

### Turning it off

`LOCK_DIR=` (empty) switches the check off, the way `MIN_FREE_GB=0` switches off
the memory check. Both are for people who know why they want it. There is no
good reason to do this on a Mac that cannot hold two copies of the weights.

---

## What this page will not do

- It will not make the model as capable as a large hosted model. A
  27-billion-parameter model at 5-bit is materially weaker at long chains of tool
  use. Short, well-scoped tasks are where it earns its keep.
- It will not make the 27B fit on a Mac with less than 32 GB of memory. See
  [04 — memory safety](04-memory-safety.md) for the smaller build that does fit.
- It will not tell you how fast the 27B runs on your Mac. No speed figure for it
  has been measured on any machine, including the test machine (Apple M3 Max, 30
  GPU cores, 36 GB unified memory, macOS 26.5.2). `./bin/bench.sh` measures
  yours.

---

**Still stuck?** Open an issue and paste the complete output of `./bin/doctor.sh`.
It reports versions, memory, model files, and settings in one block, and it never
includes your code or your conversations.
