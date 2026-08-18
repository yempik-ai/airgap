# Release gate

What is re-run before a tag, on what, and what blocks it. Kept in the
repository so the MEASURED / PUBLISHER-REPORTED / ARITHMETIC convention is
enforced by a checklist, not by memory. `AUDIT.md` B5 is why this file exists.

## Before every tag

Run on the reference machine, or on a named one; record the row below either
way. Every step is a real run — no dry runs, no "should still work".

| # | Run | Passes when | Blocks the tag when |
|:--|:--|:--|:--|
| 1 | CI on the tagged commit (`bash tests/run.sh`; `shellcheck -S warning start.sh bin/*.sh tests/*.sh`) | both jobs green | anything red |
| 2 | `./bin/doctor.sh` with the server up on the machine's default build | every row PASS, or a WARN the docs already name (`truncated` on the tool-call rows; `mtp_loaded` WARN on a build that ships no head) | any FAIL; a WARN no doc explains |
| 3 | `PROMPT_FILE=docs/08-how-it-works.md ./bin/bench.sh` | `outputs IDENTICAL`; decode, prefill and peak recorded | `outputs DIFFER`; a repeatable decode slowdown over 10 % against the previous tag's figure for the same prompt and build, unless the trade is written down in `CHANGELOG.md` |
| 4 | `./bin/claude-local.sh -p 'reply AIRGAP OK'` from a project folder | `AIRGAP OK`, and the server log shows the request (`thinking=` and the prompt token count) | anything else |
| 5 | If a guard was touched since the last tag: make it refuse | the refusal fires and names the fix (`AGENT.md` § "Before you claim something works", 4) | a guard that no longer refuses |
| 6 | If `serve.sh`'s argv changed: `ps -o args= -p <pid>` before and after | the flag/value pairs differ only as intended | an unintended pair |
| 7 | Every figure added or changed in `README.md`, `docs/`, `CHANGELOG.md`, `llms.txt`, `AGENT.md` | carries MEASURED / PUBLISHER-REPORTED / ARITHMETIC (or "not measured") | an unlabelled number |
| 8 | `CHANGELOG.md` has the version and date; `CITATION.cff` has the version | both updated in the tag commit | either stale |

## The row that goes in the release notes

One line per manual run, so a reader can tell what was actually tested:

```
commit · chip / RAM / macOS · mlx-serve · Claude Code · build · CTX_SIZE · non-default settings · doctor: N PASS / N WARN · bench: decode X tok/s, prefill Y tok/s at N tokens, peak Z GB · e2e: AIRGAP OK
```

Example, assembled from the figures already recorded for `main` on 2026-08-18
(several sittings, not one; not a tag):

```
9b0d355 · M3 Max / 36 GB / macOS 26.5.2 · mlx-serve 26.8.8 · Claude Code 2.1.234 · 9b-4bit · 65536 · none · doctor: 29 PASS (with server) · bench: 36.7 tok/s after 41 tokens, 15.6 after 16,377; prefill 374 tok/s at 16,377; peak 5.63 GB · e2e: AIRGAP OK
```

## What 0.1.0 still owes

`ROADMAP.md` Phase 0. Recorded here so a tag cannot quietly skip them: the
27B has never been loaded on the reference machine (needs 22 GB free), the
fresh-account run of `start.sh` has not been done, and the 16 GB path is
arithmetic. A tag before those are done says so in its notes, in these words.
