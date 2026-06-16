# 05 — Implementation Handoff

**Agent:** massoh-implementer · **Date:** 2026-06-16 · **Branch:** `feat/massoh-autonomous-fleet`

## Files changed
| File | Change |
|---|---|
| `bin/massoh-cron` | **new** — the runner: `once`/`install`/`off`/`status`; idleness gate, backlog parse, serial worktree creation, parallel agent+gate, single-writer collect (backlog DONE + one `[cron]` sync block + opt-in merge), cleanup trap |
| `bin/massoh` | +`cmd_cron` (forwards to `bin/massoh-cron`); dispatch `cron)`; usage string |
| `VERSION` | `0.2.0` → `0.3.0` |
| `CHANGELOG.md` | `[0.3.0]` entry |
| `docs/AUTONOMOUS_CRON.md` | "Wiring it (the runner)" section |
| `.gitignore` | ignore `.agent_tasks/cron/cron.log` |
| `test/run.sh` | +T7 (idleness, dry-run-no-call, run, parallel-no-corruption, auto-merge on/off, empty) |

## Capability delivered (full fleet, owner-overridden) — with safe defaults
cron tick → idleness gate → top-N disjoint TODOs → **worktree per item** → injectable agent →
gate → serialized DONE + one `[cron]` AGENT_SYNC block → optional merge. **dry-run default,
auto-merge OFF default, idleness ON, `install` prints unless `--apply --yes-spend`.**

## Tests run (verbatim)
```
$ bash test/run.sh
... T1–T6 ...
== T7: cron (idleness, dry-run, run, parallel, auto-merge) ==
  ok idleness gate / dry-run-no-agent-call / run-marks-DONE+sync+branch+worktree-clean
  ok auto-merge OFF by default / parallel x2 marks 2 DONE + 2 lines + ONE [cron] block
  ok auto-merge ON merges green branch / empty backlog clean
ALL GREEN — 45 checks passed.   (exit 0)
```
Fakes only (`MASSOH_AGENT_CMD`/`MASSOH_GATE_CMD`) — **zero API spend in tests.**

## Bug found + fixed during impl (honest record)
Parallel jobs first wrote to the **same** result file → only 1 item collected. Cause: bash
`local slug="$1" rfile="$RESULTS/$slug.result"` on one line + dynamic scope read the outer loop's
leaked `slug`. Fixed by splitting the `local` declaration. T7 parallel checks now green.

## Live verification
`cron status` → 6 TODOs, not scheduled. `cron once` → idleness-skips (dirty tree). `--no-idle-check`
→ dry-run plan picks the real top TODO. `install` → prints crontab line, does **not** apply.

## Risks
- Real `claude -p` path is exercised only via fakes (can't spend in CI). The wiring (`$AGENT_CMD "$prompt"`)
  is trivial + matches `claude -p`. Real-agent behaviour is the agent's responsibility, not the runner's.
- Auto-merge trusts the gate; default OFF + explicit flag + green-only. Owner-gated to enable.

## Handoff for reviewer
Verify safe defaults are truly default; serialized single-writer (no AGENT_SYNC race); worktree
cleanup; manifest untouched. Independence caveat: one session — owner is final reviewer/merger.
