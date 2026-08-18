# Release gate

What is re-run before a tag, on what, and what blocks it. Kept in the
repository so the MEASURED / PUBLISHER-REPORTED / ARITHMETIC convention is
enforced by a checklist, not by memory. `AUDIT.md` B5 is why this file exists.

## Before every tag

Run on the reference machine, or on a named one; record the row below either
way. Every step is a real run — no dry runs, no "should still work".

| # | Run | Passes when | Blocks the tag when |
|:--|:--|:--|:--|
| 1 | CI on the tagged commit (`bash tests/run.sh`; `shellcheck -S warning start.sh bin/*.sh harness/*.sh tests/*.sh`) | both jobs green | anything red |
| 2 | `./bin/doctor.sh` with the server up on the machine's default build | every row PASS, or a WARN the docs already name (`truncated` on the tool-call rows; `mtp_loaded` WARN on a build that ships no head) | any FAIL; a WARN no doc explains |
| 3 | `PROMPT_FILE=docs/08-how-it-works.md ./bin/bench.sh` | `outputs IDENTICAL`; decode, prefill and peak recorded | `outputs DIFFER`; a repeatable decode slowdown over 10 % against the previous tag's figure for the same prompt and build, unless the trade is written down in `CHANGELOG.md` |
| 4 | `./bin/claude-local.sh -p 'reply AIRGAP OK'` from a project folder, then one probe per shipped adapter: `./bin/run.sh --probe claude-code`, `codex`, `pi` and `hermes` | `AIRGAP OK` from all five, the server log shows the requests (`thinking=` and the prompt token count), and every probe line is kept verbatim for the notes | anything else; a shipped adapter with no probe transcript from this tag |
| 5 | If a guard was touched since the last tag: make it refuse | the refusal fires and names the fix (`AGENT.md` § "Before you claim something works", 4). Since 2026-08-18 the memory and ceiling guards are per model and per `KV_QUANT`: `KV_QUANT=off CTX_SIZE=131072 ./bin/serve.sh` on the 27B must refuse at the ceiling on 36 GB (19.1 + 8.00 > 27.0), and `tests/kv-figure.sh` holds the reference numbers | a guard that no longer refuses |
| 6 | If `serve.sh`'s argv changed: `ps -o args= -p <pid>` before and after | the flag/value pairs differ only as intended | an unintended pair |
| 7 | Every figure added or changed in `README.md`, `docs/`, `CHANGELOG.md`, `llms.txt`, `AGENT.md` | carries MEASURED / PUBLISHER-REPORTED / ARITHMETIC (or "not measured") | an unlabelled number |
| 8 | `CHANGELOG.md` has the version and date; `CITATION.cff` has the version | both updated in the tag commit | either stale |

## The row that goes in the release notes

One line per manual run, so a reader can tell what was actually tested:

```
commit · chip / RAM / macOS · mlx-serve · harness versions · build · CTX_SIZE · non-default settings · doctor: N PASS / N WARN · bench: decode X tok/s, prefill Y tok/s at N tokens, peak Z GB · e2e: AIRGAP OK · probe <name>: T s, N prompt tokens — one pair per shipped adapter
```

Example, assembled from the figures already recorded for `main` on 2026-08-18
(several sittings, not one; not a tag). The probe figures are the warm ones
MEASURED that day on this machine (the claude-code and codex pair on
`phase-1/harness-adapters`, because `run.sh --probe` does not exist at
`9b0d355`; the pi and hermes pair on the commit that shipped those adapters):

```
9b0d355 · M3 Max / 36 GB / macOS 26.5.2 · mlx-serve 26.8.8 · Claude Code 2.1.234 / Codex CLI 0.147.0 / Pi 0.84.2 / Hermes Agent 0.20.4 · 9b-4bit · 65536 · none · doctor: 29 PASS (with server) · bench: 36.7 tok/s after 41 tokens, 15.6 after 16,377; prefill 374 tok/s at 16,377; peak 5.63 GB · e2e: AIRGAP OK · probe claude-code: 4.8 s, 20,718 prompt tokens · probe codex: 3.4 s, 9,336 prompt tokens · probe pi: 1.5 s, 2,024 prompt tokens · probe hermes: 7.5 s, 15,060 prompt tokens
```

## What 0.1.0 still owes

`ROADMAP.md` Phase 0. Recorded here so a tag cannot quietly skip them: the
27B has never been *measured* on the reference machine — it was loaded once,
on 2026-08-17, for a single turn that produced no figure, and `serve.sh` wants
22 GB free for another go — the fresh-account run of `start.sh` has not been
done, and the 16 GB path is arithmetic. A tag before those are done says so in
its notes, in these words.
