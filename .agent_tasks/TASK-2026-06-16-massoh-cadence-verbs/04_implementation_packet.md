# 04 — Implementation Packet (LICENSE TO CODE)
**Task:** TASK-2026-06-16-massoh-cadence-verbs · **Branch:** `feat/massoh-cadence-verbs`
Authorized: owner + product-scope BUILD(01) + arch/safety YES(03).

## Scope
1. `bin/massoh` — `cmd_standup` + `cmd_plan` (inline), dispatch `standup)` / `plan)`, usage. Both
   read-only + optional `## [standup]` / `## [plan]` append to `AGENT_SYNC.md`; flags `--no-write`
   (+ `--since DAYS` on standup). Degrade gracefully.
2. `VERSION` → `0.4.1`. `CHANGELOG.md` `[0.4.1]`.
3. `test/run.sh` — T9.

## Out of scope
cron wiring, auto re-rank, manifest changes, non-additive writes.

## Acceptance
Per `01`/`03`. Prior 53 green. `massoh version` → 0.4.1.

## Rollback
Revert branch.

## Handoff
implementer → `05` → reviewer → `06` → PR.
