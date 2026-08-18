# 10 — Other harnesses

**Who this is for.** Anyone who does not use Claude Code, or who uses more than
one coding app and wants all of them talking to the model on this Mac. It is
also the page to read before you write an adapter for an app this repository
does not ship yet.

**What you will have at the end.** One command that starts your app against your
own Mac, one more that proves the wiring worked, and the exact list of things an
adapter has to do before it is listed here.

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
point. It sends one question through your app and prints whether the answer
came back, how long it took, and how much text your app sent before you had
typed anything.

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
  you ─▶ your harness ─▶ 127.0.0.1:11234 ─▶ mlx-serve ─▶ MLX / Metal ─▶ your Mac
              ▲
              └── started by ./bin/run.sh <name>, wired by harness/<name>.sh —
                  the only file that knows what your app calls each setting
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
    hermes
    pi

For example:  ./bin/run.sh claude-code
```

That list is read from the `harness/` folder every time, so it is always the
truth about your copy.

| What you type | What happens |
|---|---|
| `./bin/run.sh claude-code` | starts Claude Code in the current folder |
| `./bin/run.sh codex` | starts the Codex CLI in the current folder |
| `./bin/run.sh pi` | starts Pi in the current folder |
| `./bin/run.sh hermes` | starts Hermes Agent in the current folder |
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
probe  codex  AIRGAP OK  3.4 s  9,336 prompt tokens
```

Three things in that line, and it is worth knowing what each one is:

- **`AIRGAP OK`** — the answer came back through your app, from the model on
  your Mac. Nothing else produces that phrase. The exit code is 0.
- **`3.4 s`** — wall clock, MEASURED, this run only, to the fifth of a second
  the probe polls at. The **first** turn is much slower: after an idle server
  the weights are read back into memory, and either way the app's own
  instructions — thousands of tokens, before you have typed anything — have to
  be processed before the model can answer. That is the reload and the prefix,
  not the app being slow.
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
probe  claude-code  AIRGAP OK  55.4 s  20,718 prompt tokens     (first turn, weights being reloaded)
probe  claude-code  AIRGAP OK  4.8 s   20,718 prompt tokens     (a later turn, model already in memory)
```

The cold figure was 55.4 s on the first turn after the server started, and
59.1 s on a first Claude Code turn after Codex had been talking to the same
server — the weights were in memory by then, but this harness's own
20,718-token prefix still had to be processed. The warm figure was 4.8 s and
3.7 s. The token figure was identical on all four runs. Nothing here has been
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
probe  codex  AIRGAP OK  29.8 s  9,336 prompt tokens     (first turn, weights being reloaded)
probe  codex  AIRGAP OK  3.4 s   9,336 prompt tokens     (a later turn, model already in memory)
```

What is worth knowing about Codex here, before you use it:

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

## 6. Pi — verified

```
./bin/run.sh pi
```

Six lines appear before Pi's own screen:

```
pi       -> http://127.0.0.1:11234   model Qwen3.8-9B-mlx-4Bit  (anthropic)
context  65536 tokens declared to the harness
timeout  client gives up after 360s of silence, the server after 300s — so the server reports it
provider airgap in /Users/you/.pi/agent/models.json — the one file this script writes; your other providers there are kept
retries  Pi's own (settings.json "retry", default 3) — not changed by this script; idle limit is Pi's httpIdleTimeoutMs (default 300s)
mcp      extensions off (LEAN_MCP=1, Pi's --no-extensions) — saving not measured: none installed on the test machine
```

**The verified line.** MEASURED on the test machine (Apple M3 Max, 36 GB,
macOS 26.5.2) on **2026-08-18**, with **Pi 0.84.2**, **mlx-serve 26.8.8**,
the model **Qwen3.8-9B-mlx-4Bit**, `CTX_SIZE=65536`, `SERVE_TIMEOUT=300`,
`LEAN_MCP=1`:

```
probe  pi  AIRGAP OK  5.2 s  2,024 prompt tokens     (first turn against a freshly started server)
probe  pi  AIRGAP OK  1.5 s  2,024 prompt tokens     (a later turn)
```

The token figure was identical across four runs, and identical again with
`LEAN_MCP=0` — the test machine has no Pi extensions installed, so their cost
is honestly **not measured**, and the banner says so.

What is worth knowing about Pi here, before you use it:

**This adapter writes one file under your home folder, and says so.** Pi has
no command-line or environment way to be told about a provider: its one route
is `~/.pi/agent/models.json` (the alternative its docs offer is an extension —
TypeScript that runs inside Pi, which this repository does not ship). So
`run.sh pi` writes one provider, `airgap`, into that file, keeps every other
provider and key in it exactly as they were, and rewrites it only when the
address, model or context size changed. It is the only file this repository
changes under a home folder, for any harness. If the file cannot be read back
as plain JSON — Pi allows comments in it; this script does not rewrite what it
cannot round-trip — the run refuses and prints the block for you to paste in
yourself, once.

**Pi is started offline.** `PI_OFFLINE=1` is Pi's own switch for every network
thing it does at startup: the version check against pi.dev, the anonymous
install ping, the package update check, and the model-catalog refresh for its
built-in providers. All requests for the model go to your Mac; with the flag,
nothing else is sent anywhere.

**No key is written.** The provider carries the placeholder `mlx-serve`,
because Pi treats a keyless model as unusable and its own docs say a local
server should keep a dummy value. A real `API_KEY`, when you set one, is not
copied into the file: the server does not ask a loopback client for it, and a
real key does not belong in a file this repository rewrites.

**Retries and the idle limit are Pi's own, and are not changed.** They live in
`~/.pi/agent/settings.json` (`retry.*`, default 3 attempts with backoff, and
`httpIdleTimeoutMs`, default 300 s) — your global Pi configuration for every
provider you use, which this script does not touch. Two consequences the
banner states: a stall may be retried before it is reported, and Pi's 300 s
idle default is the same moment the server's `SERVE_TIMEOUT=300` fires, so if
you want the server to always be the side that reports, raise
`httpIdleTimeoutMs` to `360000` there yourself.

**The dialect is Anthropic Messages.** Pi also speaks the OpenAI chat format,
and that pairing was tried and answered — but Pi sends its system prompt under
the OpenAI `developer` role there, which the server logged as an empty system
prompt (`sys=0b`), and this repository does not ship wiring it cannot vouch
for. On `/v1/messages` the system prompt lands as itself, and Pi's
`--thinking` flag maps exactly onto the thinking switch the server
understands: `--thinking off` was MEASURED to log `thinking=false` — though
the one probe tried that way answered wrongly (n=1; the quality cost of
thinking off is not measured on any harness here).

Its own settings: `PI_BIN`, and the shared `LEAN_MCP` (Pi's
`--no-extensions`). `./bin/run.sh pi --help` lists them. Pi gets **no**
answer-length or thinking setting in this repository: `maxTokens` in
models.json keeps Pi's own 16,384-token default, and `--thinking` is already
Pi's own flag, typed after the name.

---

## 7. Hermes Agent — verified

```
./bin/run.sh hermes
```

Eight lines appear before Hermes's own screen:

```
hermes   -> http://127.0.0.1:11234   model Qwen3.8-9B-mlx-4Bit  (openai)
context  65536 tokens declared to the harness
timeout  client gives up after 360s of silence, the server after 300s — so the server reports it
provider custom, CUSTOM_BASE_URL (environment only; your ~/.hermes is not changed)
context  Hermes reads it from the server's /v1/models — the CTX_SIZE it was started with
retries  stream reconnects off (HERMES_STREAM_RETRIES=0); Hermes's own whole-request retry (config.yaml agent.api_max_retries, default 3) stays
mcp      MCP servers, plugins and shell hooks off (LEAN_MCP=1, HERMES_SAFE_MODE=1) — saving not measured: none configured on the test machine
note     Hermes may say its "tirith" scanner is unavailable, and mention a TERMINAL_CWD line its
         installer left in ~/.hermes/.env — both EXPECTED and cosmetic; `hermes` also runs a git fetch of its own checkout at start
```

**The verified line.** MEASURED on the test machine (Apple M3 Max, 36 GB,
macOS 26.5.2) on **2026-08-18**, with **Hermes Agent 0.20.4**, **mlx-serve
26.8.8**, the model **Qwen3.8-9B-mlx-4Bit**, `CTX_SIZE=65536`,
`SERVE_TIMEOUT=300`, `LEAN_MCP=1`:

```
probe  hermes  AIRGAP OK  36.7 s  15,060 prompt tokens     (first Hermes turn: its own 15,060-token prefix processed)
probe  hermes  AIRGAP OK  7.5 s   15,060 prompt tokens     (a later turn)
```

The token figure is the probe's `-z` turn. Two things about it, both seen at
the server: Hermes also sends a small background request after a turn — the
session title, 311 prompt tokens — which goes to your Mac like everything
else, and lands inside the probe's counting window on some runs (one run read
15,371 for exactly that reason). And an interactive `hermes chat` turn is
bigger than a `-z` one: MEASURED once, 17,402 prompt tokens, with thinking on
where `-z` runs with it off — Hermes's own difference between its two entry
points, not a setting of this repository. `LEAN_MCP=0` read the same 15,060:
the test machine has no MCP servers configured for Hermes, so their cost is
honestly **not measured**.

What is worth knowing about Hermes here, before you use it:

**The wiring is environment-only, and one line in your `~/.hermes/.env` could
beat it — so that case is refused.** Hermes's `custom` provider takes its
address from `CUSTOM_BASE_URL`, which this script exports for the one run;
nothing under `~/.hermes` is written. But Hermes loads `~/.hermes/.env` *over*
the process environment (MEASURED: a throwaway `.env` naming a closed port
won against the export), so a `CUSTOM_BASE_URL` line in that file would
silently send every question wherever it says. `run.sh hermes` checks the file
first and refuses, naming the line and the fix, unless it already names this
server. `tests/hermes-env-guard.sh` holds exactly this.

**No key is sent.** Hermes gates every key it knows on the host it belongs to
(`OPENAI_API_KEY` on openai.com, and so on), so a loopback address is sent its
own placeholder and nothing from your `.env`. No Hermes account is needed.

**The context size is read from the server, not declared.** Hermes asks
`GET /v1/models` before trusting any default, and mlx-serve answers with the
`CTX_SIZE` it was started with — so Hermes sizes its own compression against
the truth without being told. The `context` banner line states this; the
declared-size rule (rule 6) is met by the server's own answer.

**`LEAN_MCP=1` is `HERMES_SAFE_MODE=1`.** That is Hermes's one switch that
skips its MCP servers, plugin discovery, shell hooks and outbound webhooks in
one move — the environment variable alone, deliberately not the `--safe-mode`
flag, which would also drop your `config.yaml` and `AGENTS.md`. Your
configuration files are read as normal.

**Two retry layers, one switched off.** Mid-stream reconnects
(`HERMES_STREAM_RETRIES`, Hermes default 2) are off, so a broken stream is
reported where it broke. Hermes's whole-request retry
(`agent.api_max_retries` in `config.yaml`, default 3) has no flag or
environment variable in 0.20.4, so it stays as you have it — the banner says
so rather than pretending otherwise. The stall detectors are set a minute
past the server's limit (`HERMES_LOCAL_STREAM_STALE_TIMEOUT` and
`HERMES_API_CALL_STALE_TIMEOUT`), so the server reports first, as with every
harness here.

**One startup network operation has no switch.** The interactive `hermes`
command checks for updates by running a `git fetch` of its own checkout under
`~/.hermes`, cached for six hours. Hermes 0.20.4 has no way to turn that off;
this repository found none in its sources, and says so rather than claiming
an air gap it cannot enforce. Everything sent *for the model* goes to your
Mac; Hermes's own tools (web search, browser, image generation) reach the
internet only where you have set them up with keys, exactly as under any
model.

Its own settings: `HERMES_BIN`, `HERMES_MAX_TOKENS` (Hermes's own name for
the answer cap; unset by default), and the shared `LEAN_MCP`.
`./bin/run.sh hermes --help` lists them. Hermes's thinking level is its own
`--reasoning` flag, typed after the name.

---

## 8. What `./bin/doctor.sh` shows

`./bin/doctor.sh` prints one row per adapter, in a section called
**harness wiring**:

```
── harness wiring ───────────────────────────
PASS  claude-code       2.1.234 -> http://127.0.0.1:11234/v1/messages
PASS  codex             0.147.0 -> http://127.0.0.1:11234/v1/responses
PASS  hermes            0.20.4 -> http://127.0.0.1:11234/v1/chat/completions
PASS  pi                0.84.2 -> http://127.0.0.1:11234/v1/messages
```

Each row says the app is installed, and which address and endpoint
([Glossary](09-glossary.md#endpoint)) `run.sh` would point it at. The version
shown is the first thing that looks like a version number in what that app
prints for `--version`, because not every app leads with it: `claude` prints
`2.1.234 (Claude Code)`, and `codex` prints `codex-cli 0.147.0`.

A harness you have not installed gets a `WARN`, and that is **not a problem**:

```
WARN  codex             'codex' not found — run.sh will refuse  -> docs/10-other-harnesses.md
```

It means exactly what it says: this repository ships an adapter for Codex, you
do not have Codex, and `./bin/run.sh codex` refuses by name rather than failing
strangely later:

```
error: 'codex' is not installed, or not on your PATH — codex cannot start

fix:   install it, or point this repo at the command you do have. The
       setting that chooses it is named in this harness's own help:
           ./bin/run.sh codex --help
       Set it in config.env. See docs/10-other-harnesses.md
```

That refusal comes before the server check, so you get it whether or not
`./bin/serve.sh` is running. Nothing about your setup is wrong, and `doctor`
ending with `1 WARNING(S)` for that reason is safe to continue past. Install the
app, or ignore the row.

Doctor never calls the wiring; it only reads what each adapter declares. It
changes nothing, here as everywhere.

---

## 9. The contract an adapter is written against

`harness/<name>.sh` is a Bash file that `bin/run.sh` reads after the settings.
It may read `BASE_URL`, `MODEL_ID`, `CTX_SIZE`, `LEAN_MCP`, `SERVE_TIMEOUT`,
`API_KEY` and its own `*_BIN` setting, and it provides:

| Name | Kind | What it is |
|---|---|---|
| `HARNESS_DIALECT` | variable | `anthropic`, `openai` or `ollama` — which of the three request formats the server already speaks this app will use |
| `HARNESS_BIN` | variable | the command that starts the app, from that harness's own setting (`CLAUDE_BIN`, `CODEX_BIN`, `PI_BIN`, `HERMES_BIN`) |
| `HARNESS_ONESHOT` | array | the arguments that make the app answer one question and exit. The question is always the last argument (`(-p)` for Claude Code and Pi, `(exec --skip-git-repo-check)` for Codex, `(-z)` for Hermes) |
| `harness_wire` | function | points every one of that app's model settings at `BASE_URL` for `MODEL_ID` with `CTX_SIZE` declared, by exporting variables and adding flags to `HARNESS_ARGS`. Refuses, and names the fix, on a setting that is not valid. Prints nothing: its banner lines go into `HARNESS_NOTES` |
| `harness_usage` | function, optional | that harness's own `--help` text |
| `HARNESS_ENDPOINT` | variable, optional | the exact path this wiring hits, when it is not the usual one for its dialect. `harness/codex.sh` sets `/v1/responses`, because it speaks the OpenAI family but not that family's usual endpoint. Only `./bin/doctor.sh` reads it, for its row |
| `harness_prepare` | function, optional | for a harness that cannot be told about a provider on the command line or in the environment: writes the one file that harness reads. `harness/pi.sh` writes `~/.pi/agent/models.json`; the others do not define it. Runs after every refusal — the wiring guards, the binary check, the server check — and never in the offline contract test's wire-only pass. It may refuse too (a file it cannot round-trip), and prints nothing on success |

An adapter does **not** check the server, parse `run.sh`'s options, work out a
timeout, print the shared banner lines, or run the probe. Those live once, in
`bin/run.sh` and `bin/env.sh`, for every harness. The surface is deliberately
small — two variables, one array, one function, and three optional extras — so
that it can grow without breaking the adapters already written against it.
`harness_prepare` is the deliberate exception to "an adapter only sets
variables": it exists because Pi reads providers from a file and from nowhere
else, it is the last thing to run before the banner, and an adapter that can
wire itself without touching a file must not define it.

---

## 10. The six rules an adapter meets before it is listed

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
   listed on `ENV_KEYS` in `bin/env.sh`, and documented in
   `config.env.example` under a section for that harness. `ENV_KEYS` is not
   paperwork: a setting that is not on that list still works in `config.env`,
   but not written in front of a command, which is where most people try it
   first (`AGENT.md`, "Layout"). No translation layer, and no default without
   a measurement behind it.
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

## 11. Adding one

The order that works:

1. **Copy the nearest adapter.** `harness/claude-code.sh` if your app reads
   environment variables; `harness/codex.sh` if it takes command-line
   overrides.
2. **Check every setting name against the installed binary**, not against its
   documentation and not against memory. That is how the Codex adapter was
   written, and it is how the plan for it was found to be wrong: the format it
   was going to use had been removed from the version installed here. The exact
   commands are in `AGENT.md` under "Verified environment facts".
3. **Meet the six rules above.**
4. **Run the probe** and keep the output:
   `./bin/run.sh --probe <name>`.
5. **Send the probe output with the change.** A claim without the transcript is
   not merged — not out of distrust, but because every figure in this
   repository is supposed to be real. `ROADMAP.md` says the same thing about
   benchmark rows and catalog entries.

Two offline tests already cover whatever you add, and they find your file by
themselves: `tests/harness-contract.sh` checks that the adapter declares what
the table in section 9 requires and that its wiring — together with anything
its `harness_prepare` writes, run under a scratch `HOME` — really names your
Mac's address, and `tests/run-dispatch.sh` checks that `run.sh` lists and
refuses correctly. Run them with `bash tests/run.sh`. Neither needs a server
or the weights. An adapter with behaviour of its own beyond the contract earns
a test of its own beside them: `tests/pi-models-json.sh` holds the rules for
the one file `harness/pi.sh` writes, and `tests/hermes-env-guard.sh` holds
`harness/hermes.sh`'s refusal when a `~/.hermes/.env` line would beat its
wiring.

Harnesses people have asked for and that are **not shipped**: Aider,
OpenCode, mini-swe-agent, little-coder. None of them is installed on the
machine this repository is developed on, and rule 1 has no shortcut. (Pi and
Hermes Agent were on this list until 2026-08-18, and left it the only way
anything does: installed, checked against their own binaries, and probed.)

---

## 12. Where this stops

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
every adapter, and [`ROADMAP.md`](../ROADMAP.md) for where the abstraction is
going.
