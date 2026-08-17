# 02 — Install: from a fresh Mac to a working local assistant

## Before you start

**Who this is for.** Anyone with an Apple Silicon Mac. You do not need to know
how to program. You do not need to have opened Terminal before. Every command on
this page is written out in full, and every command shows you what it prints when
it works.

**What you will have at the end.** A coding assistant that runs entirely on your
own Mac. You type into [**Claude Code**](09-glossary.md#claude-code), the app made
by Anthropic. Claude Code sends your words to a program on your own machine
instead of over the internet. Nothing you type leaves your Mac.

**How long it takes.**

| Part | Your attention | Waiting |
|---|---|---|
| Steps 1 to 9 (checks and tools) | about 20 minutes | a few minutes of downloads |
| Step 10 (the model files) | about 1 minute to start it | 20 to 90 minutes, unattended |
| Steps 11 to 16 (check and first run) | about 15 minutes | about 1 minute for the first load |

The waiting in step 10 needs no attention. You can close the laptop lid only if
you have set it to stay awake; otherwise leave the screen on.

**What it costs.**

- Money: nothing. No account, no subscription, no card, no key.
- Disk space: about 45 GB free while downloading, about 20 GB kept afterward.
  45 GB is roughly nine HD movies.
- Memory: a block of your Mac's memory must be free at the moment you start the
  server. The exact figure is worked out from your Mac's size — 22 GB on the
  36 GB test machine, 19 GB on a 32 GB Mac, 26 GB on a 48 GB Mac. Step 13 prints
  yours. See step 3 for whether your Mac qualifies at all.
- Network: nothing leaves your Mac once the setup is done. The downloads in
  steps 6 to 10 are the only network use.

**What you need first.**

- An Apple Silicon Mac (an M1, M2, M3, M4 or newer chip). Step 2 checks this.
- 36 GB of memory or more for the model this guide uses. Step 3 checks this and
  gives you smaller options if your Mac has less.
- About 45 GB of free disk space. Step 3 checks this.
- An internet connection for the downloads.
- You have read [`01-requirements.md`](01-requirements.md). That document is the
  honest version of "will this work on my Mac".

**If you only read one thing:** read step 7. Without one small command in that
step, the model download appears to succeed and gives you 135-byte placeholder
files instead of the model. That is the most common way this setup fails.

---

## Three things worth naming out loud before you begin

These are the parts that surprise people. None of them is a fault in the setup.

1. **The download is about 20 GB.** On a slow connection that is hours. It can
   be stopped and restarted without losing what you already have. Step 10 shows
   how.
2. **Running the model makes your Mac busy.** It holds about 19.1 GB of memory
   (MEASURED on the test machine). Other apps get slower. The fans may spin. The
   scripts refuse to start rather than let this get dangerous, and step 16 stops
   it and gives the memory straight back.
3. **Two commands ask for your Mac password.** One installs Homebrew (step 5).
   One is optional and this guide tells you to skip it. Both are named clearly
   with a warning block above them.

Two terms you will meet repeatedly:

- The **model** is the file set that does the thinking. It is about 19.1 GB of
  numbers, called [**weights**](09-glossary.md#weights). See
  [Glossary](09-glossary.md#model).
- The **server** is the program that loads those weights and answers questions.
  Its name is [**mlx-serve**](09-glossary.md#mlx-serve). It is an
  [**inference server**](09-glossary.md#inference-server), which means a program
  that runs a model and waits for questions. See [Glossary](09-glossary.md).

---

## The whole path, in order

You are going to do these sixteen steps. Each one has a check at the end.

1. Open Terminal
2. Check that your Mac has an Apple Silicon chip
3. Check memory and disk space
4. Get this repository folder onto your Mac
5. Install Homebrew, including the step that trips people up
6. Install git-lfs
7. Turn git-lfs on for your user account — the step that prevents the #1 failure
8. Install mlx-serve, including the trust step Homebrew requires
9. Install Claude Code
10. Download the model, and how to resume if it stops
11. Check the model files are real files
12. Run the doctor script
13. Free enough memory
14. Start the server
15. Run Claude Code against it
16. Stop everything

---

## Step 1 — Open Terminal

[**Terminal**](09-glossary.md#terminal) is the Mac app where you type commands
instead of clicking buttons. It is already installed on every Mac. It cannot
break anything by being opened.

Do this:

1. Press `Command` and `Space` together. A search box opens in the middle of
   the screen.
2. Type the word `Terminal`.
3. Press `Return`.

A window opens with white or black background and a line of text ending in a
`%` sign or a `$` sign. That line is called the **prompt**. It means Terminal is
waiting for you.

**How to use the command blocks on this page.** Every gray block below is one
command. Select it, copy it, click into the Terminal window, paste it, and press
`Return`. The blocks never include the `%` or `$` you see in your own window. Do
not type those.

### Check that Terminal works

This prints the name of the folder Terminal is currently pointed at. That folder
is called the [**working directory**](09-glossary.md#working-directory).

```bash
pwd
```

You should see something like this:

```
/Users/<YOUR_USER_NAME>
```

The name after `/Users/` is your own account name and will be different from the
example. That is the only part that changes.

**If you do not see that.** If nothing happens, click once inside the Terminal
window and press `Return` again. Terminal only accepts typing when its window is
selected.

---

## Step 2 — Check that your Mac has an Apple Silicon chip

This setup runs on Apple Silicon only. [**Apple Silicon**](09-glossary.md#apple-silicon)
is Apple's own chip family, sold as M1, M2, M3, M4 and later. Macs sold before
late 2020 use Intel chips instead, and the software here cannot run on them.

The reason is [**MLX**](09-glossary.md#mlx), Apple's math library. MLX is built
for [**unified memory**](09-glossary.md#unified-memory), which is Apple Silicon's
design where the main chip and the graphics chip share one pool of memory. Intel
Macs do not share memory that way, so there is no version of this that works
there.

### 2a. Print your chip name

This asks macOS which chip is in this Mac.

```bash
sysctl -n machdep.cpu.brand_string
```

You should see something like this:

```
Apple M3 Max
```

Your line must start with the words `Apple M`. The part after it (`Max`, `Pro`,
or nothing at all) is your specific model and will differ.

**If you do not see that.** If the line names Intel, for example
`Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz`, then stop here. This setup cannot run
on your Mac. [`01-requirements.md`](01-requirements.md) lists what to use instead.

### 2b. Confirm with a second check

This prints the chip architecture as a single short word.

```bash
uname -m
```

You should see exactly this:

```
arm64
```

Nothing in this output changes between machines. Apple Silicon always prints
`arm64`.

**If you do not see that.** If it prints `x86_64`, your Mac has an Intel chip, or
Terminal is running under Rosetta translation. Stop here and read
[`01-requirements.md`](01-requirements.md).

---

## Step 3 — Check memory and disk space

The whole model must sit in memory at once. That is the hard limit of this
project, and it is the reason the next two commands matter more than they look.

### 3a. Print your total memory

This asks macOS how much memory is installed, and converts the answer to GB.

```bash
echo "$(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
```

You should see something like this:

```
36 GB
```

The number is yours and will differ. Common values are 8, 16, 18, 24, 32, 36,
48, 64, 96 and 128.

**If you do not see that.** If the command prints an error, copy the command
again. The most common cause is a missing character from a partial copy.

### 3b. Find your row in this table

The conclusion to draw from the table below: only 36 GB and above runs the model
this guide uses without a fight. Everything below that gets an honest smaller
recommendation instead of a workaround.

| Your memory | Verdict for the 27B model | What to do |
|---|---|---|
| 8 GB | Does not fit | Use a much smaller model. See [`01-requirements.md`](01-requirements.md). |
| 16 GB | Does not fit | Use a much smaller model. Do not start the 20 GB download. |
| 18 GB | Does not fit | Use a smaller model. The extra 2 GB changes nothing here. |
| 24 GB | Not recommended | Even the 4-bit build lands at your Mac's graphics memory ceiling. `./bin/serve.sh` refuses to start here. Choose a smaller model. |
| 32 GB | Tight | Continue. The scripts download the smaller 4-bit build for you automatically. Expect to close your browser. |
| 36 GB | Workable — this is the tested setup | Continue. The scripts download the 5-bit build. Close memory-hungry apps before each run. |
| 48 GB | Comfortable | Continue. 5-bit build, and a larger context window also fits. |
| 64 GB and above | Comfortable | Continue. The scripts download the higher-quality 8-bit build for you. |

**You do not choose the build yourself.** `bin/detect-hardware.sh` reads your
Mac's memory and picks one of the three the publisher offers — 4-bit, 5-bit or
8-bit — and `./bin/download-model.sh` downloads that one into a folder named
after it. To override the choice, put a `MODEL_QUANT` line in `config.env`; see
[`07-tuning.md`](07-tuning.md#8-moving-to-a-different-build-of-the-model).

The test machine used for every measured number in this repository is an Apple
M3 Max with 30 graphics cores, 36 GB of unified memory, running macOS 26.5.2.
It is called "the test machine" throughout. It is not your Mac, and the numbers
from it are not promises about yours.

Every row except the 36 GB row is arithmetic from the model sizes, not a
measurement. Those rows are labeled NOT YET MEASURED. They predict whether the
model **fits**. They say nothing about how fast it will feel.

**If your row says the model does not fit:** stop here. Read
[`01-requirements.md`](01-requirements.md) and pick a smaller model. Stopping now
saves you a 20 GB download that cannot be used.

### 3c. Print your free disk space

This asks macOS how much free space is left on your Mac's main disk.

```bash
df -g / | awk 'NR==2 {print $4 " GB free"}'
```

You should see something like this:

```
460 GB free
```

The number is yours and will differ.

**If you do not see that.** If the number is below 45, you do not have room for
the download yet. Free space first. Emptying the Trash and removing old disk
images are the usual quick wins.

Why 45 GB and not 20 GB: the download tool keeps a second copy of every file
while it works, so partway through, 20 GB of model occupies about 40 GB of disk.
The last step of step 10 reclaims that second copy instantly, and prints the free
disk it measured before and after on your own Mac. The before-and-after pair has
NOT YET been measured on the test machine, so this page does not quote one.

---

## Step 4 — Get this repository folder onto your Mac

A [**repository**](09-glossary.md#repository), usually shortened to **repo**, is
a folder of files tracked by a program called [**git**](09-glossary.md#git). This
project is a repo. It holds the [**scripts**](09-glossary.md#script) you will run.
A script is a saved list of commands with a name, so you run one short thing
instead of twenty long ones.

Copying a repo to your Mac is called a [**git clone**](09-glossary.md#git-clone).

### 4a. Make a folder to keep it in

This creates the folder `~/dev/local-llms` inside your home folder. The `~`
character means "my home folder". If the folder already exists, nothing happens
and nothing breaks.

```bash
mkdir -p ~/dev/local-llms
```

This prints nothing. That is success.

**If you do not see that.** If it prints `Permission denied`, you are not in your
own home folder. Run `cd ~` first, then run the command again.

### 4b. Move into that folder

[**cd**](09-glossary.md#cd) means "change directory". It moves Terminal's
attention to a different folder.

```bash
cd ~/dev/local-llms
```

This prints nothing. That is success.

### 4c. Copy the repo

Copy this command exactly as it is written. It downloads the repository — the
scripts and these documents, about half a megabyte. It does **not** download the
model; that is step 10.

```bash
git clone https://github.com/yempik-ai/airgap.git airgap
```

You should see something like this:

```
Cloning into 'airgap'...
remote: Enumerating objects: 74, done.
remote: Counting objects: 100% (74/74), done.
remote: Compressing objects: 100% (52/52), done.
remote: Total 74 (delta 18), reused 66 (delta 12), pack-reused 0
Receiving objects: 100% (74/74), 68.42 KiB | 3.21 MiB/s, done.
Resolving deltas: 100% (18/18), done.
```

Every number in that output changes with the repository's size and your
connection speed. The last line always ends with `done.`.

**If you do not see that.** Two common cases:

- A window appears saying "The `git` command requires the command line developer
  tools." This is EXPECTED on a fresh Mac. Click **Install**, wait for it to
  finish, then run the clone command again.
- A line starting `fatal: repository` and ending `not found` means the address is
  wrong. Copy it again from the green Code button on the repository page.

### 4d. Move into the repo folder

```bash
cd ~/dev/local-llms/airgap
```

This prints nothing. That is success.

### Checkpoint

Stop here. Before continuing, confirm you are in the right folder and the scripts
arrived.

This lists the scripts in the repo's `bin` folder.

```bash
ls ~/dev/local-llms/airgap/bin
```

You should see something like this:

```
bench.sh		doctor.sh		serve.sh
claude-local.sh		download-model.sh	setup.sh
detect-hardware.sh	env.sh			stop.sh
			verify-model.sh
```

The column layout changes with your Terminal window width. The ten file names do
not change. `detect-hardware.sh` is the one that reads your Mac's size and works
out the memory settings the other scripts use.

**If you do not see that.** If it prints `No such file or directory`, the clone
in step 4c did not finish. Run step 4c again.

**From this point on, every command in this guide is run from
`~/dev/local-llms/airgap`.** Each section repeats the `cd` command, because
Terminal windows get closed and folders get forgotten.

---

<a id="homebrew"></a>
## Step 5 — Install Homebrew

[**Homebrew**](09-glossary.md#homebrew-brew) is a program that installs other
programs on a Mac. Its command name is `brew`. You need it because the two main
pieces of this setup are published through Homebrew and not through the App Store.

Move into the repo folder first.

```bash
cd ~/dev/local-llms/airgap
```

### 5a. Check whether you already have it

This asks Homebrew to print its version.

```bash
brew --version
```

You should see something like this:

```
Homebrew 6.0.17
```

The version number is yours and will differ.

If you saw a version, **skip to step 6**. Homebrew is already installed.

If instead you saw `zsh: command not found: brew`, continue with 5b.

### 5b. Install Homebrew

> **WARNING — this command asks for your Mac password.**
>
> - **What it changes on your Mac:** it creates the folder `/opt/homebrew` and
>   puts the `brew` program inside it. It does not change any of your files, your
>   settings, or your apps.
> - **Why it asks for a password:** creating a folder outside your home folder
>   needs administrator permission. That is what
>   [**sudo**](09-glossary.md#sudo) means. Nothing is typed on screen while you
>   type your password. That is normal, not a frozen Terminal.
> - **Is it reversible:** yes. Homebrew publishes an uninstall script, and the
>   "How to undo everything" section at the end of this page links to it.
> - **If it goes wrong:** the installer stops and prints an error. It does not
>   leave your Mac in a broken state. Nothing is deleted.
> - **Why you might skip it:** you would need to install git-lfs and mlx-serve by
>   hand instead, which is more work and more error-prone. This guide does not
>   cover that path.

This downloads and runs Homebrew's official installer.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

You should see something like this, at the end of a long output:

```
==> Installation successful!

==> Next steps:
- Run these commands in your terminal to add Homebrew to your PATH:
    echo >> /Users/<YOUR_USER_NAME>/.zprofile
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/<YOUR_USER_NAME>/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
```

The account name in the paths is yours and will differ. The lines above are the
end of a long output; the earlier lines list the files being installed.

**If you do not see that.** If it stops with `Password:` and appears frozen, it is
waiting for your Mac password. Type it and press `Return`. The characters do not
appear on screen.

### 5c. The step that trips everyone up on Apple Silicon

Read this even if the installer output looked finished.

On Apple Silicon, Homebrew installs into `/opt/homebrew`. Your
[**shell**](09-glossary.md#shell) — the program inside Terminal that reads your
commands — does not look in that folder unless you tell it to. The list of folders
it does look in is an [**environment variable**](09-glossary.md#environment-variable)
called `PATH`. An environment variable is a named setting that programs read when
they start.

Until you add Homebrew to `PATH`, every `brew` command answers
`command not found`, even though Homebrew is installed correctly. This is the
single most common confusion at this step.

Do both of the next two commands, in order.

The first appends one line to `~/.zprofile`, a settings file your shell reads
each time you open Terminal. This makes the change permanent.

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
```

This prints nothing. That is success.

The second applies the same change to the Terminal window you have open right
now, so you do not have to close and reopen it.

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

This prints nothing. That is success.

### Checkpoint

Stop here. Before continuing, confirm `brew` now answers.

```bash
brew --version
```

You should see something like this:

```
Homebrew 6.0.17
```

The version number is yours and will differ.

**If you do not see that.**

- `zsh: command not found: brew` means the `PATH` line did not take effect. Run
  the `eval` command in 5c again, in the same window.
- If it still fails after that, close the Terminal window completely, open a new
  one with `Command` + `Space`, and run `brew --version` again. A new window reads
  `~/.zprofile` from scratch.

---

<a id="git-lfs"></a>
## Step 6 — Install git-lfs

[**git-lfs**](09-glossary.md#git-lfs) stands for git Large File Storage. Plain
git was built for text files of a few kilobytes. It handles multi-gigabyte files
badly. git-lfs is the add-on that fetches those large files properly.

The model in this project is five files of roughly 4.5 GB each. Without git-lfs
you cannot get them.

Move into the repo folder first.

```bash
cd ~/dev/local-llms/airgap
```

This installs git-lfs through Homebrew.

```bash
brew install git-lfs
```

You should see something like this, at the end of the output:

```
==> Pouring git-lfs--3.7.1.arm64_sequoia.bottle.tar.gz
==> Caveats
Update your git config to finish installation:

  # Update global git config
  $ git lfs install

==> Summary
🍺  /opt/homebrew/Cellar/git-lfs/3.7.1: 82 files, 14.5MB
```

The version number and the file count are yours and will differ. The lines above
are the end of a longer output; the earlier lines list what is being downloaded.

If Homebrew answers `Warning: git-lfs 3.7.1 is already installed and up-to-date.`
that is EXPECTED and fine. Continue.

Notice the `Caveats` section in that output. It tells you to run one more
command. That command is step 7, and skipping it is the failure this guide keeps
warning you about.

### Checkpoint

This prints the installed git-lfs version.

```bash
git lfs version
```

You should see something like this:

```
git-lfs/3.7.1 (GitHub; darwin arm64; go 1.25.3)
```

The three version numbers are yours and will differ. The words `darwin arm64`
should match, and confirm you have the Apple Silicon build.

**If you do not see that.** `git: 'lfs' is not a git command` means the install
did not finish. Run `brew install git-lfs` again and read its output for an error.

---

## Step 7 — Turn git-lfs on for your user account

**This is the most important single command on this page.**

Installing git-lfs in step 6 put the program on your Mac. It did not connect it
to git. Until you connect them, git ignores git-lfs completely.

### What goes wrong if you skip this

When you copy a repository that uses git-lfs, git does not download the large
files. Instead it writes a tiny text file in each large file's place. That
placeholder is called an [**LFS pointer file**](09-glossary.md#lfs-pointer-file).
It is about 135 bytes and contains a line of text describing where the real file
lives.

The trap is the silence. `git clone` prints `done.` and exits successfully. The
folder looks right. The file names are all correct. Only the sizes are wrong: 135
bytes instead of 4.5 GB. Nothing warns you. You discover it much later, when the
server fails in a way that seems unrelated.

This is the number one beginner failure in this whole setup. One command prevents
it.

### 7a. Connect git-lfs to git

This writes a few lines into your personal git settings file so git hands large
files to git-lfs from now on. It changes settings for your user account only, not
for the whole Mac, and it does not ask for a password.

```bash
git lfs install
```

You should see exactly this:

```
Git LFS initialized.
```

Nothing in this output changes between machines. If you have run it before, you
may also see a line reading `Updated Git hooks.` above it. That is EXPECTED.

**If you do not see that.** `git: 'lfs' is not a git command` means step 6 did not
finish. Go back and run `brew install git-lfs`.

### 7b. Confirm the connection

This prints the one git setting that step 7a created. It is the proof the
connection exists.

```bash
git config --global --get filter.lfs.clean
```

You should see exactly this:

```
git-lfs clean -- %f
```

Nothing in this output changes between machines.

**If you do not see that.** If it prints nothing at all, `git lfs install` did not
take effect. Run step 7a again and read its output carefully.

### A note for later

The download script in step 10 fetches the large files by an explicit command, so
it works even if this setting were missing. You should still set it. Any other
repository you copy by hand will silently produce 135-byte placeholder files
without it, and you will not be told.

---

<a id="mlx-serve"></a>
## Step 8 — Install mlx-serve

[**mlx-serve**](09-glossary.md#mlx-serve) is the program that loads the model and
answers questions about it. It is published through a Homebrew
[**tap**](09-glossary.md#brew-tap).

### What a tap is, and what trusting one means

Homebrew ships with a large built-in catalog of install recipes. A **tap** is an
extra catalog, published by somebody who is not the Homebrew project. Adding a
tap tells Homebrew "also look here for recipes".

Because a tap is written by a third party, Homebrew will not run its code until
you say so. That is what `brew trust` does. Running it is a real decision, not a
formality: you are allowing code written by `ddalcu`, not by Apple and not by
Homebrew, to run on your Mac during installation.

You can look at that code before you agree. It is public at
`https://github.com/ddalcu/mlx-serve`. Open that address in your browser if you
want to read it first.

If you are not comfortable with that, stop here. This guide has no alternative
path, because mlx-serve is the reason the setup needs no extra translation
program between Claude Code and the model.

Undoing it later is one command, listed in "How to undo everything" at the end of
this page.

Move into the repo folder first.

```bash
cd ~/dev/local-llms/airgap
```

### 8a. Add the tap

This tells Homebrew about the extra catalog. It downloads recipe text only. It
installs nothing and runs nothing.

```bash
brew tap ddalcu/mlx-serve https://github.com/ddalcu/mlx-serve
```

You should see something like this:

```
==> Tapping ddalcu/mlx-serve
Cloning into '/opt/homebrew/Library/Taps/ddalcu/homebrew-mlx-serve'...
remote: Enumerating objects: 312, done.
Tapped 1 formula (14 files, 28.7KB).
```

The object count and file size are yours and will differ. The last line always
starts with `Tapped`.

**If you do not see that.** `Error: Invalid tap name` means a character was lost
in the copy. Copy the whole command again.

### 8b. Trust the tap

This records your decision to allow this third party's install code to run.

```bash
brew trust ddalcu/mlx-serve
```

You should see something like this:

```
==> Trusting ddalcu/mlx-serve
```

**If you do not see that.** If Homebrew says the tap is unknown, step 8a did not
finish. Run it again.

Skipping this step is a common mistake, because the failure message it produces
in step 8c looks like a broken tap rather than a missing permission.

### 8c. Install mlx-serve

This downloads and installs the server program.

```bash
brew install mlx-serve
```

You should see something like this, at the end of the output:

```
==> Pouring mlx-serve--26.8.8.arm64_sequoia.bottle.tar.gz
==> Summary
🍺  /opt/homebrew/Cellar/mlx-serve/26.8.8: 24 files, 118.3MB
```

The version number, file count and size are yours and will differ. The lines
above are the end of a longer output.

**If you do not see that.** If Homebrew refuses with a message about an untrusted
or unverified tap, you skipped step 8b. Run `brew trust ddalcu/mlx-serve` and then
run this install command again.

### Checkpoint

This asks mlx-serve to print its version and the versions of the libraries inside
it. It does not load the model and does not start a server.

```bash
mlx-serve --version
```

You should see something like this:

```
mlx-serve 26.8.8
mlx 0.32.0
mlx-c fba4470b8907
nax off (requires M5-class GPU)
ggml 0.16.0 (505b1ed15)
llama.cpp b10034
gguf 3
ds4 unknown
```

Your version numbers may differ. A line starting with `[mem] MLX buffer-pool cap`
may also appear before or after these. That line is EXPECTED and harmless.

The line `nax off (requires M5-class GPU)` is EXPECTED on every Mac up to and
including M4. It reports an optional acceleration feature that your chip does not
have. It is not an error.

**If you do not see that.** `zsh: command not found: mlx-serve` means the install
did not finish, or your `PATH` is not set. Run the `eval` command from step 5c
again, then retry.

---

<a id="claude-code"></a>
## Step 9 — Install Claude Code

[**Claude Code**](09-glossary.md#claude-code) is Anthropic's coding assistant for
Terminal. In this setup it is the part you talk to. It is a
[**harness**](09-glossary.md#harness): a program that manages the conversation,
reads and writes your files, and decides what to send to a model. It does not
contain a model itself. That is exactly why it can be pointed at one running on
your own Mac.

Move into the repo folder first.

```bash
cd ~/dev/local-llms/airgap
```

### 9a. Check whether you already have it

```bash
claude --version
```

You should see something like this:

```
2.1.233 (Claude Code)
```

The version number is yours and will differ. This guide was written and checked
against 2.1.233.

If you saw a version, **skip to step 10**.

If you saw `zsh: command not found: claude`, continue with 9b.

### 9b. Install it

This downloads and runs Anthropic's official installer for Claude Code.

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

You should see something like this, at the end of the output:

```
Claude Code installed successfully

Installed to: /Users/<YOUR_USER_NAME>/.local/bin/claude
```

The account name in the path is yours and will differ.

**If you do not see that.** If the last line mentions adding
`/Users/<YOUR_USER_NAME>/.local/bin` to your `PATH`, close the Terminal window
completely, open a new one, and run `claude --version` again.

### Checkpoint

```bash
claude --version
```

You should see something like this:

```
2.1.233 (Claude Code)
```

**Do not start Claude Code yet.** Running `claude` on its own would connect to
Anthropic's servers over the internet. Step 15 uses a wrapper script that points
it at your Mac instead.

### The one-command version of steps 5 to 9

If you would rather have a script do it, the repo includes one. It checks all
four tools and **installs the two it can**: git-lfs (including switching it on
for your account) and mlx-serve. Homebrew and Claude Code have their own
installers, so for those it prints the address and stops — Homebrew because its
installer changes system folders and asks for your password, Claude Code because
it has its own sign-in.

That means on a brand new Mac you will run it more than once: it stops at
Homebrew, you install Homebrew yourself, you run it again.

It is safe to run at any time, including after doing every step by hand: it
checks before it acts and does nothing when a tool is already present. It never
downloads the model and never starts the server.

```bash
cd ~/dev/local-llms/airgap
```

```bash
./bin/setup.sh
```

You should see something like this:

```
airgap — setup
[1/5] homebrew        ok (6.0.17)
[2/5] git-lfs         ok (3.7.1)
[2/5] git-lfs         ok (switched on for your account)
[3/5] mlx-serve       ok (26.8.8)
[4/5] claude code     ok (2.1.233)
[5/5] python venv     skipped (set WITH_VENV=1 to build it)
setup complete — next: ./bin/doctor.sh
```

The version numbers are yours and will differ. **Step 2 prints twice on purpose.**
Installing git-lfs and switching it on for your account are two separate things,
and only the second one stops the 135-byte placeholder problem from step 7. Step
5 is an optional extra that this guide does not need; `skipped` is the correct
result.

**If you do not see that.** A line reading
`setup FAILED at step 3 (mlx-serve) — see docs/02-install.md` names which tool
failed. Go back to that tool's step above and do it by hand.

---

## Step 10 — Download the model

This is the long step. It is also the step the whole guide has been protecting.

### What you are downloading

A [**checkpoint**](09-glossary.md#checkpoint) is one saved copy of a trained
model. This one is named `Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit`. It arrives
as five files in the [**safetensors**](09-glossary.md#safetensors) format, which
is a plain, safe file format for storing model numbers. Each of the five files is
called a [**shard**](09-glossary.md#shard) — one slice of a set that is too large
for a single file.

The `5bit` in the name refers to [**quantization**](09-glossary.md#quantization).
Quantization stores each of the model's numbers using fewer bits, which makes the
whole thing smaller. Think of it like saving a photo as a JPEG instead of a RAW
file: much smaller, slightly less detail. The analogy stops being true because
model quantization loses detail evenly across all the numbers, while JPEG throws
away detail your eye is bad at noticing. Five bits per number is why this model
is 19.1 GB instead of about 54 GB.

> **WARNING — this step downloads about 20 GB.**
>
> - **What it changes on your Mac:** it creates one folder inside the repo and
>   fills it with model files. It changes nothing outside that folder and nothing
>   in your system settings. It does not ask for a password.
> - **Peak disk use:** about 40 GB while it runs, dropping to about 20 GB at the
>   end (MEASURED on the test machine). That is why step 3 asked for 45 GB free.
> - **Is it reversible:** yes, completely. Deleting the folder removes every
>   byte. The command is in "How to undo everything" at the end of this page.
> - **If it goes wrong:** it stops with an error and leaves a partly finished
>   folder. Nothing is corrupted. You re-run the same command and it resumes.
> - **How long:** 20 GB at 100 Mbit/s is roughly 30 minutes; at 25 Mbit/s it is
>   roughly two hours. This is arithmetic from your connection speed, NOT YET
>   MEASURED in this repository.

Move into the repo folder first.

```bash
cd ~/dev/local-llms/airgap
```

This downloads the model. Leave the Terminal window open and let it run.

```bash
./bin/download-model.sh
```

You should see something like this:

```
repo     chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
target   /Users/<YOUR_USER_NAME>/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
disk     460.0 GB free (need 45 GB)

[1/5] git-lfs                ok (3.7.1)
[2/5] resolving repo         checking huggingface.co
[2/5] resolving repo         ok — huggingface.co/chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
[3/5] cloning metadata       GIT_LFS_SKIP_SMUDGE=1 (pointers now, weights next)
[4/5] git lfs pull           about 20 GB — this is the long part
      Press Ctrl-C to stop. Running this command again resumes it.
[4/5] git lfs pull           ok — no pointer files left
[5/5] git lfs dedup          reclaimed 19.4 GB (460.0 GB free before, 479.4 GB after)

download complete — next: ./bin/verify-model.sh
```

Your account name in the `target` path, your three disk numbers, and your git-lfs
version will differ. If your Mac was recommended the 4-bit or 8-bit build, the
repository and folder names end in `-4bit` or `-8bit` instead. The gap between the
first `[4/5]` line and the second is where the waiting happens, and it can be an
hour or more; git-lfs shows its own progress display there.

**If you do not see that.** Four named failures, with their fixes:

1. `error: git-lfs not installed. Run ./bin/setup.sh first.` You skipped step 6.
   Go back and install git-lfs.

2. `error: only 31 GB free, need 45 GB` — free disk space and run the command
   again. Nothing was downloaded.

3. `error: repo not found on huggingface.co: <name>` — the model's address has
   changed. Open `https://huggingface.co` in your browser, search for the model
   name, and copy the exact `owner/name` text from its page. Then run the command
   with that address. Replace `<ORGANIZATION>/<NAME>` with the exact text you
   copied. Worked example: if the page showed `someone/Qwen3.8-27B-MLX-5bit-v2`,
   you would type that in place of `<ORGANIZATION>/<NAME>`:

   ```bash
   MODEL_REPO=<ORGANIZATION>/<NAME> ./bin/download-model.sh
   ```

   The address the script uses by default was checked against huggingface.co and
   resolved at the time this page was written. If it ever stops resolving, this
   is the fix.

4. `error: model-00002-of-00005.safetensors is still a git-lfs pointer (135
   bytes, expected >1 MB)` — the large-file download did not complete. The fix is
   in the resume section directly below.

### How to stop it, and how to resume

You can stop the download at any time. Click into its Terminal window and press
`Control` and `C` together. Nothing is corrupted. Everything already downloaded
stays on disk.

To resume, run the same command again from the repo folder.

```bash
cd ~/dev/local-llms/airgap
```

```bash
./bin/download-model.sh
```

It notices the partly finished folder and continues from step `[4/5]` instead of
starting over. Files already downloaded are not downloaded twice.

If the script refuses to touch the existing folder, fetch the remaining large
files directly. This is the same command the script runs internally.

```bash
cd ~/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
```

```bash
git lfs pull
```

You should see something like this:

```
Downloading LFS objects: 100% (5/5), 20 GB | 48 MB/s
```

The transfer speed and the object count are yours and will differ.

**If you do not see that.** `git: 'lfs' is not a git command` means step 6 did not
complete. Install git-lfs and try again.

---

## Step 11 — Check the model files are real files

This is the mandatory checkpoint that catches the 135-byte placeholder problem.
Do not skip it. Finding this now takes one minute. Finding it in step 14 wastes
twenty.

### 11a. Look at the file sizes yourself

Move into the model folder first.

```bash
cd ~/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
```

This lists the five model files with their sizes in human-readable units.

```bash
ls -lh *.safetensors
```

You should see something like this:

```
-rw-r--r--  1 <YOUR_USER_NAME>  staff   4.5G Aug 17 09:14 model-00001-of-00005.safetensors
-rw-r--r--  1 <YOUR_USER_NAME>  staff   4.6G Aug 17 09:18 model-00002-of-00005.safetensors
-rw-r--r--  1 <YOUR_USER_NAME>  staff   4.5G Aug 17 09:22 model-00003-of-00005.safetensors
-rw-r--r--  1 <YOUR_USER_NAME>  staff   4.5G Aug 17 09:26 model-00004-of-00005.safetensors
-rw-r--r--  1 <YOUR_USER_NAME>  staff   1.8G Aug 17 09:28 model-00005-of-00005.safetensors
```

Your account name, group and timestamps will differ. The five file names and the
approximate sizes do not.

**The only thing that matters is the size column.** Four files of roughly 4.5G
and one of roughly 1.8G means you have the model.

**If you do not see that.** If the sizes read `135B` or anything under `1M`, you
have placeholder files and not the model. This is FIX THIS, not STOP. The fix:

```bash
cd ~/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
```

```bash
git lfs pull
```

Then run the `ls -lh *.safetensors` command again and confirm the sizes changed.
If they did not, go back to step 7 and confirm `git lfs install` printed
`Git LFS initialized.`

### 11b. Run the verify script

This reads only the small description block at the front of each model file. It
reads a few hundred kilobytes in total. It does not load the 20 GB and does not
start a server.

Move into the repo folder first.

```bash
cd ~/dev/local-llms/airgap
```

```bash
./bin/verify-model.sh
```

You should see something like this:

```
model    Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
config   model_type = qwen3_5   (correct, not a typo — Qwen3.8-27B is built on
         the qwen3_5 architecture family, the way Llama 3.1/3.2/3.3 all report
         model_type "llama". Runtimes dispatch on model_type.)
layers   64 = 48 linear_attention (Gated DeltaNet) + 16 full_attention
         (full_attention_interval 4) — only the 16 hold a growing KV cache
quant    5-bit affine, group size 64
shards   5/5 headers parsed, no git-lfs pointers
tensors  2207 total | 504 quantized | 333 vision | 29 MTP
MTP head PRESENT — the reason this stack runs mlx-serve, not stock mlx-lm
size     19.1 GB of text-only weights on disk (the vision tower is skipped at
         run time via --no-vision, so it costs disk but not memory)
manifest matches ARTIFACT-MANIFEST.json (2207 tensors, 504 quantized)

verify PASS

next: read docs/04-memory-safety.md, then ./bin/doctor.sh
```

Nothing in this output changes between machines, as long as you downloaded the
5-bit build. It describes the files, not your Mac. Those tensor counts were
MEASURED on the test machine, and the `manifest matches` line means they were
compared against the publisher's own list of what should be there and agreed.

Two figures for the same model appear across these documents and both are
correct: **19.1 GB** is what gets loaded into memory, and **20 GB** is what the
five files occupy on disk. The difference is the image-reading part, which is
stored but never loaded.

Three lines are worth understanding, and none of them needs understanding today:

- **`model_type = qwen3_5` is correct and is not a mistake.** A model file
  declares which family it belongs to, so programs know how to run it. This model
  is named Qwen3.8 but belongs to the qwen3_5 family, in the same way Llama 3.1,
  3.2 and 3.3 all declare themselves as `llama`. If you were expecting `qwen3_8`,
  its absence is not a sign of a wrong download.
- **`29 MTP`** counts a small extra piece built into this model that lets it
  guess several words ahead and check them in one pass. It makes answers arrive
  faster. Some other programs delete it when loading; mlx-serve keeps it. That is
  the main reason this setup uses mlx-serve.
- **`no git-lfs pointers`** is the same check you did by hand in 11a, done
  automatically.

The full explanation of all three lives in
[`08-how-it-works.md`](08-how-it-works.md). You do not need it to finish this
guide.

**If you do not see that.** Three named failures:

- `verify FAIL: model-00002-of-00005.safetensors is 135 bytes — git-lfs pointer,
  not weights` — this is the placeholder problem. Run the `git lfs pull` fix from
  11a.
- `verify FAIL: expected 2207 tensors, found 1904 — download is incomplete` — the
  download stopped partway. Run `./bin/download-model.sh` again from the repo
  folder.
- `verify FAIL: no mtp.* tensors found` — you have a different checkpoint than
  this guide expects. It may still run, but the speed advantage described above
  will not apply.

### One honest note about this model

This particular checkpoint is [**abliterated**](09-glossary.md#abliterated-model).
The publisher removed the model's ability to decline requests. It has essentially
no built-in safety behavior.

That is workable for research on your own machine, which is what this setup is
for. It is the reason the server in step 14 accepts connections only from your own
Mac and from nothing else on your network. Do not change that.

The model also carries its publisher's own license, which is separate from this
repository's license. This repository contains no model weights; the script in
step 10 downloads them from the publisher. The license text is in the model folder
as `LICENSE`. [`03-get-the-model.md`](03-get-the-model.md) covers both points in
full.

---

## Step 12 — Run the doctor script

`doctor.sh` checks the whole setup and tells you what is ready and what is not.
It reads only. It starts nothing, stops nothing and changes nothing.

Move into the repo folder first.

```bash
cd ~/dev/local-llms/airgap
```

```bash
./bin/doctor.sh
```

At this point the server is not running yet, so you should see something like
this:

```
airgap doctor
── environment ──────────────────────────────
PASS  macos             26.5.2 (arm64)
PASS  apple silicon     Apple M3 Max, 30 GPU cores
PASS  ram tier          36 GB total — workable, recommends 5-bit at 65536 tokens
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
── model ────────────────────────────────────
PASS  model dir         ~/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
PASS  weights           5 shards, no pointers, 20.0 GB on disk (19.1 GB is loaded)
PASS  model id          Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
── server ───────────────────────────────────
PASS  bind setting      HOST=127.0.0.1 — serve.sh will listen on this Mac only
SKIP  server            not running — start ./bin/serve.sh
── claude code wiring ───────────────────────
PASS  ANTHROPIC_API_KEY not set in this shell
PASS  base url          claude-local.sh will point at http://127.0.0.1:11234
PASS  context declared  CLAUDE_CODE_MAX_CONTEXT_TOKENS follows CTX_SIZE (65536)
PASS  mcp mode          strict (LEAN_MCP=1) — saves about 17,000 prompt tokens per turn
─────────────────────────────────────────────
19 pass, 0 warn, 0 fail, 1 skipped
doctor: OK — next: ./bin/serve.sh
```

Your macOS version, chip name, memory numbers, disk number, tool versions and
folder path will all differ. So will the `ram tier` line, which is the row of the
table in [`01-requirements.md`](01-requirements.md#ram-tiers) that describes your
Mac, and the two numbers on the `context declared` and `gpu ceiling` lines, which
are worked out from your Mac's memory size.

**How to read this output.** The `SKIP server` line is EXPECTED right now. The
server section can only be checked while the server is running, and you have not
started it yet. `SKIP` means "not checked", not "broken". Learn this now, while
nothing is wrong, so the output is familiar later when something is.

**A `FAIL memory` line is also EXPECTED right now** if you have been using your
Mac today. It looks like this:

```
FAIL  memory            13.1 GB available, need 22  -> docs/04-memory-safety.md#free-memory
                        EXPECTED before you free memory. Close these, then run this again:
                          1.0 GB  /Applications/Arc.app/Contents/MacOS/Arc
```

Step 13 is the step that fixes it, and it comes next. Nothing is wrong.

The four labels mean:

- `PASS` — checked and correct.
- `WARN` — checked, unusual, safe to continue.
- `FAIL` — checked and wrong. Fix before continuing.
- `SKIP` — not checked, because something it depends on is not running.

**If you do not see that.** Every `FAIL` line ends with a pointer to the exact
entry that explains it, like this:

```
FAIL  weights           model-00002 is a 135-byte pointer  -> docs/06-troubleshooting.md#lfs-pointers
```

Open [`06-troubleshooting.md`](06-troubleshooting.md) and find that entry. That
document is organized by symptom, so you can also search it for the exact text
you see.

**A `FAIL  memory` line here is EXPECTED** if you have been using your Mac
today. Step 13 is the step that fixes it, and it comes next on purpose. Any
*other* `FAIL` must be fixed before you continue.

If the last line reads `doctor: 2 FAILURE(S) — fix these first` and one of them
is not the memory line, fix that one before step 13. Starting the server on top
of a `FAIL` wastes twenty minutes.

---

## Step 13 — Free enough memory

The model needs about 19.1 GB of memory for the 5-bit build (MEASURED on the
test machine). The scripts insist on more than that being free before they will
start, to leave room for the conversation and for macOS itself.

**That number is different on every Mac.** It is called `MIN_FREE_GB`, it is
worked out from your Mac's memory size, and it is 22 GB on the 36 GB test
machine, 19 GB on a 32 GB Mac and 26 GB on a 48 GB Mac. Do not compare your free
memory against 22. Compare it against your own number, which the command in 13a
prints for you.

Your Mac's total memory is not the number that matters. What matters is how much
is free right now, and on a normal working Mac that is much less than you expect.
On the test machine, 36 GB total gave only 10.5 GB actually free with a browser
and Docker running (MEASURED).

### 13a. Check what is free right now

Move into the repo folder first.

```bash
cd ~/dev/local-llms/airgap
```

This reads macOS's memory statistics and prints two numbers: how much memory is
available for a new program right now, and how much this Mac needs before the
server will agree to start.

```bash
bash -c 'source bin/env.sh && echo "$(available_gb) GB available, need $MIN_FREE_GB GB"'
```

You should see something like this:

```
14.9 GB available, need 22 GB
```

**Both numbers are yours.** The first changes minute by minute as you use your
Mac. The second is worked out from your Mac's memory size and does not change.

**If the first number is at least as large as the second,** go to step 14.

**If the first number is smaller,** continue with 13b. That is the normal case on
a Mac you have been using all day.

### 13b. Free memory, largest first

Close applications. These are the usual largest consumers, in the order worth
trying:

1. **Docker Desktop.** Its virtual machine held 2.7 GB on the test machine
   (MEASURED). Quit Docker Desktop from its menu bar icon, or run this command:

   ```bash
   docker desktop stop
   ```

   You should see something like this:

   ```
   Docker Desktop is stopping...
   ```

   If you do not have Docker installed, `zsh: command not found: docker` is
   EXPECTED. Move to the next item.

2. **Your web browser.** Browsers with many tabs open routinely hold several GB.
   Quit the browser entirely with `Command` + `Q`. Closing the window is not
   enough.

3. **Other virtual machines**, such as Parallels or VMware.

4. **Video editors, photo editors, and music production apps.**

This lists the six largest memory users on your Mac right now, so you can see
what is actually holding memory instead of guessing.

```bash
ps -Ao rss,comm -m | awk 'NR>1 && $1>500000 {rss=$1; $1=""; sub(/^[ \t]+/,""); printf "%5.1f GB  %s\n", rss/1048576, $0}' | head -6
```

You should see something like this:

```
  2.7 GB  com.apple.Virtualization.VirtualMachine
  1.4 GB  /Applications/Arc.app/Contents/MacOS/Arc
  0.9 GB  /Applications/Arc.app/Contents/Frameworks/Arc Helper
  0.7 GB  /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
  0.6 GB  /Applications/Slack.app/Contents/MacOS/Slack
  0.5 GB  /Applications/Slack.app/Contents/MacOS/Slack
```

Every line is yours and will differ. Some apps appear more than once because they
run several processes. Quit those apps from their own menus, not from this list.

### Checkpoint

Stop here. Before continuing, confirm that **the first number is now at least as
large as the second**.

```bash
cd ~/dev/local-llms/airgap
```

```bash
bash -c 'source bin/env.sh && echo "$(available_gb) GB available, need $MIN_FREE_GB GB"'
```

You should see something like this:

```
24.3 GB available, need 22 GB
```

**If you do not see that.** If the first number will not go above the second
after closing everything, restart your Mac and run this command again before
opening any other
app. If the first number still will not reach the second after a restart, your
Mac does not have the room for this model. Read [`04-memory-safety.md`](04-memory-safety.md), which explains
what to change and which smaller options exist.

### A command this guide tells you not to run

You may find advice elsewhere to raise a macOS setting called
[`iogpu.wired_limit_mb`](09-glossary.md#iogpuwired_limit_mb) with
[`sudo sysctl`](09-glossary.md#sysctl). Do not do it.

That setting controls how much memory the graphics side of the chip may lock
away. [**Wired memory**](09-glossary.md#wired-memory) is memory macOS is not
allowed to move to disk when things get tight. Every other kind of memory can be
moved to disk, which makes your Mac slow. Wired memory cannot, which makes your
Mac stall.

Raising that limit is the one change in this whole setup that can make a Mac stop
responding entirely and need a forced restart, by holding the power button. The
setting resets on reboot, so the damage is temporary, but the stall is real.

Apple's automatic value is correct for this setup. Leave it alone. The full
reasoning is in [`04-memory-safety.md`](04-memory-safety.md).

---

## Step 14 — Start the server

> **WARNING — this command allocates about 19.1 GB of your Mac's memory.**
>
> - **What it changes on your Mac:** it starts one program that holds about
>   19.1 GB of memory while it runs. Other apps become slower. The fans may spin
>   up. Nothing on disk is changed and no settings are changed.
> - **Is it reversible:** yes, immediately. Press `Control` + `C` in its window,
>   or run `./bin/stop.sh` from another window. The memory comes straight back.
> - **If it goes wrong:** the most likely outcome by far is that it refuses to
>   start and prints why. If your Mac does become slow and unresponsive, running
>   `./bin/stop.sh` from a second Terminal window fixes it. A forced restart, by
>   holding the power button, is the last resort and loses only unsaved work.
> - **Why you might skip it:** you would not have a working setup. This is the
>   step everything else was preparing for.
> - **Before you run it:** confirm step 13's first number was at least as large
>   as its second. The script checks this too and refuses if it is short.

Open a **new Terminal window** for this. Press `Command` + `N` while Terminal is
in front. The server keeps this window busy for as long as it runs, so you need a
second window for step 15.

In the new window, move into the repo folder.

```bash
cd ~/dev/local-llms/airgap
```

This starts the server. It stays running until you stop it.

```bash
./bin/serve.sh
```

You should see something like this first:

```
memory   24.3 GB available (need 22 GB) — ok
model    /Users/<YOUR_USER_NAME>/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
endpoint http://127.0.0.1:11234   (Anthropic: http://127.0.0.1:11234/v1/messages)
context  65536 tokens, kv-quant turbo4
budget   weights<=21GB, prefix 1536MB, idle-evict 900s
log      ~/.mlx-serve/logs/mlx-serve-11234.log
```

After those six lines the script prints three more:

```

Loading about 19.1 GB. The first load takes about a minute.
Leave this window open. Press Ctrl-C to stop, or run ./bin/stop.sh elsewhere.
Next: open another window and run ./bin/claude-local.sh
```

Six values differ on your Mac: the two memory figures, the account name in the
path, the context size, and the two budget figures. They are worked out from your
Mac's memory size, so a 32 GB Mac shows `context  32768` and a 48 GB Mac shows
`context  131072`. To see yours before you start, run
`./bin/detect-hardware.sh`. The `endpoint` line is the same on every Mac.

Reading that banner:

- `endpoint http://127.0.0.1:11234` — `127.0.0.1` is the address your Mac uses to
  mean "this same machine, and nothing else". It is called
  [**localhost**](09-glossary.md#localhost--127001--loopback). No other computer,
  not even one on your own home network, can reach this address. `11234` is the
  [**port**](09-glossary.md#port), which is a numbered door on that address so
  several programs can each have their own.
- `context 65536 tokens` — a [**token**](09-glossary.md#token) is a chunk of
  text, usually a short word or part of one. Think of it like a syllable, in that
  one word can be two or three of them. The analogy stops being true because token
  boundaries follow patterns in the training text, not pronunciation. The
  [**context window**](09-glossary.md#context-window) is how much text the model
  can hold in mind at once, including everything already said. 65,536 tokens is
  roughly 49,000 English words, or a short novel. This number is your Mac's, not
  a fixed one: run `bash -c 'source bin/env.sh && echo $CTX_SIZE'` to print it.

After the banner, the server reads 19.1 GB from disk. **This takes about a minute
on the test machine and the window looks idle while it happens.** That is
EXPECTED. Wait for a line telling you it is listening. Its exact wording depends
on your mlx-serve version.

**Leave this window open and running.** Closing it stops the server.

### Checkpoint

Open a **third Terminal window** with `Command` + `N` and do this check there.

This asks the server whether it is awake. [**curl**](09-glossary.md#curl) is a
built-in Mac command that sends a request to an address and prints the reply.

```bash
curl -s http://127.0.0.1:11234/health
```

You should see something like this:

```
{"status":"ok"}
```

The exact wording of the reply may vary between mlx-serve versions. Any reply at
all means the server is answering.

**If you do not see that.** Two named failures:

1. **Nothing is printed and the command returns instantly.** The server is not
   running or is still loading. Look at the server's own window. If it is still
   loading, wait and try again.

2. **A block starting `REFUSING TO START — not enough free memory.`** appeared in
   the server window instead of the banner. This is STOP, not FIX THIS. It looks
   like this:

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

   This is the safety guard working. It stopped before your Mac started
   struggling. Go back to step 13, close what it lists, and run `./bin/serve.sh`
   again.

   The last line offers a way to bypass the check. Do not use it. It is there for
   people who have measured their own machine. Bypassing it is how a Mac ends up
   unresponsive.

---

## Step 15 — Run Claude Code against your Mac

Go to the third Terminal window, or open a new one with `Command` + `N`. The
server window from step 14 must stay open and running.

Move into the repo folder.

```bash
cd ~/dev/local-llms/airgap
```

This starts Claude Code and points it at your own Mac instead of at the internet.

```bash
./bin/claude-local.sh
```

You should see something like this before Claude Code's own screen appears:

```
claude   -> http://127.0.0.1:11234   model Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
context  65536 tokens declared to the harness, 8192 max output
mcp      strict (LEAN_MCP=1) — MCP servers off, saves ~17k prompt tokens per turn
note     a one-line "unrecognized_model" warning at startup is EXPECTED and cosmetic
```

Two values in that banner differ on your Mac: the model name changes if you have
the 4-bit or 8-bit build, and the context number is worked out from your Mac's
memory size. The address is the same everywhere, because `127.0.0.1` means "this
Mac" on every Mac.

That third line mentions **MCP**, which is short for Model Context Protocol
([Glossary](09-glossary.md#model-context-protocol-mcp)). MCP servers are optional
add-ons that give Claude Code extra tools — a database connection, a web search,
and so on. This setup switches them off, because the *descriptions* of those
tools alone cost about 17,000 tokens of the model's limited memory on every
single turn (MEASURED on the test machine: Claude Code's instructions are 20,909
tokens with them off and 38,054 tokens with them on). Nothing you need for this
guide is missing. [`07-tuning.md`](07-tuning.md#mcp) shows how to turn them back
on.

### On a brand new install, Claude Code asks you two things first — EXPECTED

If Claude Code has never been started on this Mac, it does not go straight to an
input box. It runs its own short first-time setup on full-screen prompts, before
anything described below happens. This is Claude Code's own behavior, not
something these scripts do, and it is not a sign that the setup failed.

Expect, roughly in this order:

1. **A color theme.** Choose one with the arrow keys and press `Return`. It
   changes nothing but colors.
2. **"Do you trust the files in this folder?"** Claude Code asks this the first
   time it opens any folder. The folder in question is
   `~/dev/local-llms/airgap` — your own copy of this repository, containing
   the scripts you have been reading. Answering yes is safe and is required to
   continue.

The exact wording and the number of screens differ between versions. **These
screens were NOT observed on the test machine** — Claude Code 2.1.233 was already
set up there, so no first run ever happened. The list above is from Claude Code's
documented behaviour, not a transcript of screens anyone here saw. If you meet a
screen not listed, read it: none of them asks for a password, a card, or an
account, because this setup uses none of those.

After that you reach the normal Claude Code input prompt.

### The warning you are about to see

Claude Code will print a warning containing the words `unrecognized_model`.

**This is EXPECTED. It is not an error and nothing is broken.** Claude Code keeps
a list of Anthropic's own model names. Your local model is not on that list, so it
notes that it does not recognize the name. It then uses it anyway, which is
exactly what you want.

This warning produces more confused questions than any other single line in this
setup. You can ignore it every time.

### What the wrapper script did for you

Two things that are not obvious:

1. **It pointed every model slot at your Mac.** Claude Code uses more than one
   model internally: a main one for your requests, and a smaller faster one for
   background work like naming a conversation. If only the main slot were
   redirected, the background work would quietly try to reach Anthropic's servers
   and fail. The script sets all of them.

2. **It told Claude Code how much text the model can hold.** Claude Code assumes
   200,000 tokens when it does not recognize a model. Your server is set to
   65,536. Without being told, Claude Code would build a request too large to
   answer and the server would reject it.

It also blanks the setting that holds an Anthropic key, so a real key already in
your Terminal cannot quietly send your words to Anthropic instead.

### Try your first request

Type this into Claude Code and press `Return`:

```
Write a one-sentence description of what a JSON file is.
```

Words appear one at a time. On the first request the model may take longer to
start answering, because the server is filling its caches. Later requests start
faster.

Speed in words per second on this 27B model is NOT YET MEASURED in this
repository. Do not expect the speed of Anthropic's hosted models.

### Prove it is really running on your Mac

This asks the server which models it offers, and confirms the name Claude Code is
using is the one your Mac is serving.

Open another Terminal window with `Command` + `N` and run this. Claude Code stays
running in its own window.

```bash
curl -s http://127.0.0.1:11234/v1/models
```

You should see something like this:

```
{"object":"list","data":[{"id":"Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit","object":"model","mtp_loaded":...}]}
```

The exact fields may vary between mlx-serve versions. The `id` value must match
the model name shown in the Claude Code banner in step 15.

That `id` is the [**model id**](09-glossary.md#model-id). It is the name of the
folder the model lives in, and nothing more. If you rename that folder, the id changes and the
wrapper script picks up the new name automatically.

The stronger proof: turn off your Wi-Fi and keep using Claude Code. Nothing
changes. Nothing in this loop touches the internet.

**If you do not see that.** If Claude Code answers with an error about
`api.anthropic.com`, then a real Anthropic setting in your Terminal overrode the
wrapper. Inside Claude Code, type `/status` and press `Return`. It shows which
address it is actually using. [`06-troubleshooting.md`](06-troubleshooting.md) has
the entry for this.

### Using it in your own project

The wrapper works from any folder. Move to your project folder first, then run the
wrapper by its full path.

```bash
cd ~/some/other/project
```

Replace `~/some/other/project` with the folder you want to work in. Worked
example: `cd ~/dev/my-website`.

```bash
~/dev/local-llms/airgap/bin/claude-local.sh
```

The banner is the same as above. Claude Code now reads and writes files in the
folder you moved to.

---

## Step 16 — Stop everything

There are two ways. Both give the memory back immediately.

**The direct way:** click into the server's Terminal window from step 14 and press
`Control` and `C` together. The server exits.

**The command way**, which works from any window. Move into the repo folder first.

```bash
cd ~/dev/local-llms/airgap
```

```bash
./bin/stop.sh
```

You should see something like this:

```
stopped.
memory: 12.4 GB -> 31.8 GB available
```

Both numbers are yours and will differ. The second number should be much larger
than the first. That is the 19.1 GB coming back.

If nothing was running, you see this instead, which is EXPECTED and harmless:

```
nothing running on port 11234.
memory: 31.8 GB -> 31.8 GB available
```

**If you do not see that.** If it prints
`did not exit cleanly — sending SIGKILL`, that is EXPECTED occasionally. The
script noticed the server was not responding and stopped it forcefully. Nothing is
damaged. The next line still reports the memory recovered.

To leave Claude Code, type `/exit` and press `Return`, or press `Control` and `C`
twice.

---

## How to know it worked

Run these three checks with the server running. All three passing means the setup
is complete.

1. The doctor reports no failures. From the repo folder:

   ```bash
   cd ~/dev/local-llms/airgap
   ```

   ```bash
   ./bin/doctor.sh
   ```

   The last line should read `doctor: OK — next: ./bin/serve.sh`. With the server
   running, the five server-section lines show `PASS` instead of one `SKIP` line.

2. The server answers. From any folder:

   ```bash
   curl -s http://127.0.0.1:11234/health
   ```

   Any reply means yes.

3. Claude Code answered a question, and its banner named
   `http://127.0.0.1:11234`.

---

## How to stop

Covered in step 16. In short, from the repo folder:

```bash
cd ~/dev/local-llms/airgap
```

```bash
./bin/stop.sh
```

The memory comes back the moment it prints `stopped.`

---

## How to undo everything

Every part of this is removable. Do these in any order, or only the ones you want.

**Remove the model and reclaim about 20 GB of disk.** This deletes the model
folder and everything in it. It cannot be undone except by downloading again.

```bash
rm -rf ~/dev/local-llms/airgap/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit
```

This prints nothing. That is success.

**Remove the repository folder itself.** This deletes the scripts and these
documents. Do the model removal first, or this removes both at once.

```bash
rm -rf ~/dev/local-llms/airgap
```

This prints nothing. That is success.

**Uninstall mlx-serve.**

```bash
brew uninstall mlx-serve
```

You should see something like this:

```
Uninstalling /opt/homebrew/Cellar/mlx-serve/26.8.8... (24 files, 118.3MB)
```

**Remove the third-party tap you trusted in step 8.**

```bash
brew untap ddalcu/mlx-serve
```

You should see something like this:

```
Untapping ddalcu/mlx-serve...
Untapped 1 formula (14 files, 28.7KB).
```

**Uninstall git-lfs.** Other projects may use it, so consider leaving it.

```bash
brew uninstall git-lfs
```

**Uninstall Claude Code.** It is a single file in your home folder.

```bash
rm -f ~/.local/bin/claude
```

This prints nothing. That is success.

**Uninstall Homebrew.** Many other tools depend on it. Only do this if you
installed it for this project and want it gone. The official uninstall
instructions are at `https://docs.brew.sh/FAQ#how-do-i-uninstall-homebrew`.

**About macOS settings:** this guide changed none. The only setting it discussed,
`iogpu.wired_limit_mb`, it told you not to change. If you changed it anyway, a
restart resets it, or run `sudo sysctl iogpu.wired_limit_mb=0`.

---

## What this will not do

Being honest about the limits is more useful than being encouraging.

- **It is not as capable as Anthropic's hosted models.** This is a 27 billion
  parameter model compressed to 5 bits per number, running on a laptop. Claude
  Sonnet and Claude Opus are far larger and run on server hardware. On long chains
  of steps, where the assistant must read a file, decide something, edit, then
  check its work, this model loses track more often. Short, clearly described
  tasks are where it earns its keep.

- **It does not remember more than the context size your Mac was given** — 65,536
  tokens on the test machine, which is roughly 49,000 English words. About 21,000
  of those tokens are spent on Claude Code's own instructions before you type
  anything (MEASURED on the test machine: 20,909 tokens with the optional tool
  servers off, 38,054 with them on). Long conversations run out of room. See
  [07 — tuning](07-tuning.md) for a larger window.

- **It occupies your Mac while it runs.** Other work is slower. This is not a
  background service to leave running all day, although the server does hand the
  memory back after 15 minutes with no requests, and reloads when you return.

- **Speed on this model is NOT YET MEASURED in this repository.** Any number you
  find elsewhere was measured on different hardware.

- **It has no safety behavior.** As covered in step 11, this checkpoint is
  abliterated. Keep it on your own machine. Do not put it on a network.

---

## Where to go next

This page is the whole path in one document, which suits a reader who wants to
go start to finish in one sitting. Three of its steps have a slower page of their
own, with more explanation and more escape routes:

- Step 10, downloading the model: [`03-get-the-model.md`](03-get-the-model.md).
  Read it if the download failed, or if you want to understand what is inside the
  files and what the model's own license says.
- Step 13, freeing memory: [`04-memory-safety.md`](04-memory-safety.md).
- Steps 14 and 15, running it: [`05-run-it.md`](05-run-it.md). Read it for how to
  prove nothing left your Mac, and how to use the model on another project.

Then:

- Something went wrong: [`06-troubleshooting.md`](06-troubleshooting.md), which is
  organized by the exact text of the error you saw.
- You want to understand the memory limits properly:
  [`04-memory-safety.md`](04-memory-safety.md).
- You want a larger context window, your MCP servers back, or a speed test:
  [`07-tuning.md`](07-tuning.md).
- You want to know how any of this actually works:
  [`08-how-it-works.md`](08-how-it-works.md).
- A word here meant nothing to you: [`09-glossary.md`](09-glossary.md).
