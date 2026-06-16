# 04 — Implementation Packet (LICENSE TO CODE)
**Task:** TASK-2026-06-16-massoh-review · **Branch:** `feat/massoh-review` · Authorized: owner +
product-scope BUILD(01) + arch/safety YES(03).

## Scope
1. `bin/massoh` — `cmd_review()` (inline): gather + print packets / backlog / delivery / branches /
   version (+ `--run-tests`); unless `--no-write`, append `## Snapshot <ts>` to
   `agent-project/METRICS.md`. Flags: `--since DAYS` (default 7), `--no-write`, `--run-tests`.
   Dispatch `review) shift; cmd_review "$@"`; usage string. Degrade gracefully (no git / no packets).
2. `VERSION` → `0.4.0`. `CHANGELOG.md` `[0.4.0]`.
3. `test/run.sh` — T8 (per `03`).

## Out of scope
`standup`/`plan`/`retro`, cron wiring, manifest changes, any non-additive write.

## Acceptance
Per `01`/`03`. Prior 45 green. `massoh version` → 0.4.0.

## Rollback
Revert branch. Additive.

## Handoff
implementer → `05` → reviewer → `06` → PR.
