# 10 — Other harnesses

**Who this is for.** Anyone who does not use Claude Code, or who uses more than
one coding app and wants all of them talking to the model on this Mac. It is
also the page to read before you write an adapter for an app this repository
does not ship yet.

**What you will have at the end.** One command that starts your app against your
own Mac, a way to prove the wiring worked in about four seconds, and the exact
list of things an adapter has to do before it is listed here.

**How long it takes.** Five minutes to start the app you already have. A day, at
most, to write an adapter for one that is not here yet — most of which is
checking settings against the app's own binary rather than writing shell.

**What it costs.** No extra memory beyond the server that is already running.
No money. Nothing leaves your Mac.

**What you need first.**

- [05 — run it](05-run-it.md) finished at least once, so the server and the
  model are known to work. Everything on this page assumes `./bin/serve.sh` is
  already running in another window.

**If you only read one thing:** `./bin/run.sh --probe <name>` is the whole
point. It sends one question through your app, and prints whether the answer
came back, how long it took, and how much the app said before you typed
anything.

---

## 1. What a harness is here

A **harness** ([Glossary](09-glossary.md#harness)) is the program you type into:
Claude Code, the Codex CLI, and the rest of that family. It holds the
conversation, adds its own instructions, offers the model tools, and decides
what to send next. The model itself does none of that.

Every one of them has the same three questions to answer before it can talk to
your Mac instead of to a company's servers:

1. **Which address?** `http://127.0.0.1:11234`, which means this Mac and
   nothing else.
2. **Which model name?** The one your server answers to.
3. **How much text fits?** Your `CTX_SIZE`. An app that assumes the
   200,000-token window a hosted model has will build a question your server
   has to reject.

An **adapter** is a small file that answers those three for one app, plus that
app's own switches for telemetry, retries and tool servers. One file per app,
in `harness/`. Adding a file adds a harness; nothing else in this repository
has to change.

```text
  you ─▶ your harness ─▶ bin/run.sh ─▶ 127.0.0.1:11234 ─▶ mlx-serve ─▶ your Mac
                             │
                    harness/<name>.sh — the only file that knows
                    what your particular app calls each setting
```

---

## 2. The one command

Run it from the folder you want to work in, with the server already running in
another window.

```
./bin/run.sh
```

With no name it lists what this repository can start, and stops:

```
error: which harness? Name one.

This repo can start:
    claude-code
    codex

For example:  ./bin/run.sh claude-code
```

That list is read from the `harness/` folder every time, so it is always the
truth about your copy.

| What you type | What happens |
|---|---|
| `./bin/run.sh claude-code` | starts Claude Code in the current folder |
| `./bin/run.sh codex` | starts the Codex CLI in the current folder |
| `./bin/run.sh claude-code -p "hello"` | one question, one answer, then exit |
| `./bin/run.sh --probe codex` | sends one test question and reports |
| `./bin/run.sh <name> --help` | the settings that apply to that one harness |
| `./bin/run.sh --help` | the settings that apply to all of them |

Options come **before** the name. Everything after the name is passed to your
app exactly as you typed it.

`./bin/claude-local.sh` is the same thing as `./bin/run.sh claude-code`. It is
one line that hands over to `run.sh`, and the name stays because dozens of
places in these documents use it. Neither command is better than the other;
use whichever you have in your fingers.

**If it says there is no server.** Open another Terminal window, go to the
repository folder, and run `./bin/serve.sh`. Full entry:
[06 — troubleshooting](06-troubleshooting.md#no-server).

---

## 3. Prove the wiring worked — `--probe`

```
./bin/run.sh --probe codex
```

**What this does.** It starts your app the same way the normal command does,
sends it exactly one question — `Reply with exactly: AIRGAP OK` — with nothing
on its input, waits for the answer, and prints one line.

```
probe  codex  AIRGAP OK  3.1 s  9,336 prompt tokens
```

Three things in that line, and it is worth knowing what each one is:

- **`AIRGAP OK`** — the answer came back through your app, from the model on
  your Mac. Nothing else produces that phrase. The exit code is 0.
- **`3.1 s`** — wall clock, MEASURED, this run only. The **first** turn after
  the server has been idle is much slower, because the weights are read back
  into memory first. That is the reload, not the app.
- **`9,336 prompt tokens`** — what the **server** counted for that one turn,
  every request the app made included, housekeeping ones as well. It is the
  fixed cost of one turn before you have typed a word: the app's own
  instructions, its tool descriptions, and anything it asks in the background.

That last figure is read from the server's own counters, not from anything the
app says about itself. If you have set `METRICS=0` the line says so instead of
guessing.

**A figure from one harness never means anything about another.** Two apps'
prompt-token counts are not a race: each one sends its own instructions, its
own tools and its own background questions, and the number simply says what
that app costs your window on every turn. Compare a harness with itself — with
its tool servers on and off, say — and not with its neighbour.

When the answer does not arrive:

```
probe  codex  FAIL after 12.0 s
  … the last 20 lines your app printed …
```

The exit code is 1, and the lines underneath are your app's own output, which
is where the reason will be. A probe that had to be stopped at the time limit
says so and names the limit.

---

## 4. Claude Code — verified

```
./bin/claude-local.sh            # or: ./bin/run.sh claude-code
```

Eight lines appear before Claude Code's own screen:

```
claude-code -> http://127.0.0.1:11234   model Qwen3.8-9B-mlx-4Bit  (anthropic)
context  65536 tokens declared to the harness
timeout  client gives up after 360s of silence, the server after 300s — so the server reports it
output   8192 max output tokens per answer (CLAUDE_CODE_MAX_OUTPUT_TOKENS)
mcp      strict (LEAN_MCP=1) — MCP servers off, saves ~17k prompt tokens per turn
thinking on, as the model ships — MAX_THINKING_TOKENS=0 turns it off (measured 3x faster on the 9B; quality cost not measured)
note     an "unrecognized_model" line at startup is EXPECTED and cosmetic; so is
         "claude.ai connectors are disabled" — that is this script keeping it local
```

**The verified line.** MEASURED on the test machine (Apple M3 Max, 36 GB,
macOS 26.5.2) on **2026-08-18**, with **Claude Code 2.1.234**, **mlx-serve
26.8.8**, the model **Qwen3.8-9B-mlx-4Bit**, `CTX_SIZE=65536`,
`SERVE_TIMEOUT=300`, `LEAN_MCP=1`:

```
probe  claude-code  AIRGAP OK  47.4 s  20,718 prompt tokens     (first turn, weights being reloaded)
probe  claude-code  AIRGAP OK  4.1 s   20,718 prompt tokens     (a later turn, model already in memory)
```

The cold figure was 47.4 s and 47.6 s on two runs; the warm one 4.1 s and
5.1 s. The token figure was identical on all five runs. Nothing here has been
measured on the 27B, and nothing here has been measured on another Mac.

What the adapter does, in one list: every model slot Claude Code reads is
pointed at your Mac (including the small background one it uses to name a
conversation), any real key in your shell is blanked so it cannot take
priority, telemetry and the auto-updater are off, the real context size is
declared, the answer cap is 8,192 tokens, and the non-streaming retry is off so
a stall is reported where it happens. [05 — run it](05-run-it.md) §7 explains
each of those in full, and is the page to read for Claude Code specifically.

Its own settings: `CLAUDE_BIN`, `CLAUDE_CODE_MAX_OUTPUT_TOKENS`,
`MAX_THINKING_TOKENS`. `./bin/run.sh claude-code --help` lists them.

---

## 5. Codex CLI — verified

```
./bin/run.sh codex
```

Seven lines appear before Codex's own screen:

```
codex    -> http://127.0.0.1:11234   model Qwen3.8-9B-mlx-4Bit  (openai)
context  65536 tokens declared to the harness
timeout  client gives up after 360s of silence, the server after 300s — so the server reports it
provider airgap, wire_api responses (-c overrides only; your ~/.codex is not changed)
retries  off — one attempt per request, so a stall is reported where it happens
mcp      plugins off (LEAN_MCP=1), saves 935 prompt tokens per turn (measured, 9B) —
         the MCP servers in your own config.toml stay on; 0.147.0 cannot switch those off
```

**The verified line.** MEASURED on the test machine (Apple M3 Max, 36 GB,
macOS 26.5.2) on **2026-08-18**, with **Codex CLI 0.147.0**, **mlx-serve
26.8.8**, the model **Qwen3.8-9B-mlx-4Bit**, `CTX_SIZE=65536`,
`SERVE_TIMEOUT=300`, `LEAN_MCP=1`:

```
probe  codex  AIRGAP OK  21.3 s  9,336 prompt tokens     (first turn, weights being reloaded)
probe  codex  AIRGAP OK  3.1 s   9,336 prompt tokens     (a later turn, model already in memory)
```

Four things about Codex are worth knowing before you use it here.

**Your ChatGPT sign-in is not sent.** Left alone, Codex falls back to the
sign-in token in `~/.codex/auth.json` and sends it, with your account id, to
whatever address the provider names. Here that address is your own Mac, so
nothing leaves the machine — but a server that never asked for your token
should not be given it. The adapter puts a placeholder in `CODEX_API_KEY`
instead, which was MEASURED to take priority over both the sign-in token and
`OPENAI_API_KEY`. No Codex account is needed at all: that was checked by
running it with an empty configuration folder.

**Nothing in your `~/.codex` is read specially, and nothing there is changed.**
The wiring is passed on the command line for that one run and disappears when
the command ends.

**Codex 0.147.0 speaks only one of the two formats.** The obvious choice was
the OpenAI chat format, which the server also serves. Codex refuses to start on
it: *`wire_api = "chat"` is no longer supported*. So the adapter uses the
Responses format, `/v1/responses`, which mlx-serve 26.8.8 serves and which is
what the probe above verified. This is a fact about version 0.147.0, and it is
why Codex's row in `./bin/doctor.sh` names `/v1/responses` while the other
OpenAI-format harnesses would name `/v1/chat/completions`.

**`LEAN_MCP=1` switches off Codex's plugins, and only the plugins.** MEASURED
with `codex mcp list` on the test machine: 10 tool servers with them, 4
without — the 6 that go are every one that reaches the network. The 4 that
stay are the ones written in your own `~/.codex/config.toml`, and Codex 0.147.0
has **no command-line switch for those**. They keep their prompt cost, and if
any of them talks to the internet, it still does. The banner says this on every
run rather than leaving you to find out.

What the plugins cost, MEASURED on the same machine, model and date, two runs
of each: **9,336 prompt tokens** per probe turn with `LEAN_MCP=1` against
**10,271** with `LEAN_MCP=0` — **935 tokens per turn**. That is Codex's number
and only Codex's; Claude Code's 17,000-token figure is a different app's and is
never reused here.

**One flag you may have to type yourself.** Outside a git repository,
`codex exec` refuses to run unless it is given `--skip-git-repo-check`.
`--probe` adds it for you, which is why the probe works from any folder. If you
type the one-shot form by hand outside a checkout, add it:

```
./bin/run.sh codex exec --skip-git-repo-check "hello"
```

Its own settings: `CODEX_BIN`, and the shared `LEAN_MCP`.
`./bin/run.sh codex --help` lists them. Codex gets **no** answer-length setting
and **no** thinking setting in this repository: its own reasoning effort comes
from your `~/.codex/config.toml` and is left exactly as you set it, because
nothing here has measured what changing it costs on a local model.

**Two lines at startup are EXPECTED.** *failed to refresh available models* is
Codex asking the server for a model list in a shape mlx-serve does not send,
and *Model metadata for … not found* is Codex having never heard of a model
that only exists on your Mac. Neither stops the answer.

---

## 6. What `./bin/doctor.sh` shows

`./bin/doctor.sh` prints one row per adapter, in a section called
**harness wiring**:

```
── harness wiring ───────────────────────────
PASS  claude-code       2.1.234 -> http://127.0.0.1:11234/v1/messages
PASS  codex             codex-cli -> http://127.0.0.1:11234/v1/responses
```

Each row says the app is installed, and which address and endpoint
([Glossary](09-glossary.md#endpoint)) `run.sh` would point it at. The version
shown is the first word of what that app prints for `--version`, which for
Codex is the word `codex-cli`.

A harness you have not installed gets a `WARN`, and that is **not a problem**:

```
WARN  codex             'codex' not found — run.sh will refuse  -> docs/10-other-harnesses.md
```

It means exactly what it says: this repository ships an adapter for Codex, you
do not have Codex, and `./bin/run.sh codex` would tell you so rather than fail
strangely. Nothing about your setup is wrong, and `doctor` ending with
`1 WARNING(S)` for that reason is safe to continue past. Install the app, or
ignore the row.

Doctor never calls the wiring; it only reads what each adapter declares. It
changes nothing, here as everywhere.

---

## 7. The contract an adapter is written against

`harness/<name>.sh` is a Bash file that `bin/run.sh` reads after the settings.
It may read `BASE_URL`, `MODEL_ID`, `CTX_SIZE`, `LEAN_MCP`, `SERVE_TIMEOUT`,
`API_KEY` and its own `*_BIN` setting, and it provides:

| Name | Kind | What it is |
|---|---|---|
| `HARNESS_DIALECT` | variable | `anthropic`, `openai` or `ollama` — which of the three request formats the server already speaks this app will use |
| `HARNESS_BIN` | variable | the command that starts the app, from that harness's own setting (`CLAUDE_BIN`, `CODEX_BIN`) |
| `HARNESS_ONESHOT` | array | the arguments that make the app answer one question and exit. The question is always the last argument (`(-p)` for Claude Code, `(exec --skip-git-repo-check)` for Codex) |
| `harness_wire` | function | points every one of that app's model settings at `BASE_URL` for `MODEL_ID` with `CTX_SIZE` declared, by exporting variables and adding flags to `HARNESS_ARGS`. Refuses, and names the fix, on a setting that is not valid. Prints nothing: its banner lines go into `HARNESS_NOTES` |
| `harness_usage` | function, optional | that harness's own `--help` text |
| `HARNESS_ENDPOINT` | variable, optional | the exact path this wiring hits, when it is not the usual one for its dialect. `harness/codex.sh` sets `/v1/responses`, because it speaks the OpenAI family but not that family's usual endpoint. Only `./bin/doctor.sh` reads it, for its row |

An adapter does **not** check the server, parse `run.sh`'s options, work out a
timeout, print the shared banner lines, or run the probe. Those live once, in
`bin/run.sh` and `bin/env.sh`, for every harness. The surface is deliberately
small — two variables, one array, one function, and two optional extras — so
that it can grow without breaking the adapters already written against it.

---

## 8. The six rules an adapter meets before it is listed

1. **Verified.** `./bin/run.sh --probe <name>` returned `AIRGAP OK` on a real
   machine against a real model, and the app version, the server version, the
   model, the date, the time and the token figure are written on this page.
2. **Air gap.** Every setting of that app that can carry a model request points
   at `BASE_URL`. A real provider key sitting in your shell cannot win over it.
   Telemetry, update checks and other non-essential traffic the app lets you
   switch off are switched off, and each setting name was checked against the
   installed binary rather than remembered.
3. **Token overhead, measured or admitted.** Tool servers are off when
   `LEAN_MCP=1`, which is the default. What that saves is stated per harness,
   as a measurement, or stated as not measured. Claude Code's 17,000-token
   figure is never borrowed for another app.
4. **Own knobs, own names.** That app's answer cap, thinking budget and
   timeouts are exposed under the app's own names, defaulted in the adapter,
   and documented in `config.env.example` under a section for that harness.
   No translation layer, and no default without a measurement behind it.
5. **Fail fast.** Retries and silent fallbacks the app offers are off, and the
   client waits a minute longer than the server, so the server — the side that
   can name the reason — reports a stall first.
6. **The truth about size.** `CTX_SIZE` is declared to the app as its context
   window, unchanged.

Rule 3 has a shared setting behind it, `LEAN_MCP`, in the
`# --- Harnesses ---` section of `config.env.example`. It is deliberately not
in any one app's section: it means the same thing to all of them, and each
adapter states its own measured cost.

---

## 9. Adding one

The order that works:

1. **Copy the nearest adapter.** `harness/claude-code.sh` if your app reads
   environment variables; `harness/codex.sh` if it takes command-line
   overrides.
2. **Check every setting name against the installed binary**, not against its
   documentation and not against memory. Both shipped adapters were written
   this way, and both found something that was not true any more — the exact
   commands used are in `AGENT.md` under "Verified environment facts".
3. **Meet the six rules above.**
4. **Run the probe** and keep the output:
   `./bin/run.sh --probe <name>`.
5. **Send the probe output with the change.** A claim without the transcript is
   not merged — not out of distrust, but because every figure in this
   repository is supposed to be real. `ROADMAP.md` says the same thing about
   benchmark rows and catalog entries.

Two offline tests already cover whatever you add, and they find your file by
themselves: `tests/harness-contract.sh` checks that the adapter declares what
the table in section 7 requires and that its wiring really names your Mac's
address, and `tests/run-dispatch.sh` checks that `run.sh` lists and refuses
correctly. Run them with `bash tests/run.sh`. Neither needs a server or the
weights.

Harnesses people have asked for and that are **not shipped**: Pi, Hermes Agent,
a DeepSeek harness, OpenCode, Aider. None of them is installed on the machine
this repository is developed on, and rule 1 has no shortcut.

---

## 10. Where this stops

This repository wires one harness to one model on one Mac, under guards. That
is the whole job.

Above it there is another layer: **control planes** — tools such as t3code that
drive one or more harnesses over a protocol built for that purpose (ACP, or a
harness's own app-server mode) and add sessions, worktrees, diff review and a
user interface on top. Those are a different kind of program, they sit above
this one, and they **compose** with it: a control plane can drive a harness
that this repository has pointed at your Mac. What they provide is theirs, not
this repository's, and nothing here tries to reproduce it. Session control,
worktrees, diff review and UIs are deliberately out of scope, and will stay
out.

---

**Read next:** [05 — run it](05-run-it.md) for Claude Code in full detail,
[07 — tuning](07-tuning.md) for the settings every harness shares, or
[06 — troubleshooting](06-troubleshooting.md) if something above did not
happen. Contributors: [`AGENT.md`](../AGENT.md) for the verified facts behind
both adapters, and [`ROADMAP.md`](../ROADMAP.md) for where the abstraction is
going.
