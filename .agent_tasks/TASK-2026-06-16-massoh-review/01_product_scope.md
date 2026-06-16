# 01 — Product Scope
**Agent:** massoh-product-scope · **Date:** 2026-06-16

## Decision: **BUILD** (smallest cadence slice — read-only, zero risk)
`massoh review` proves the cadence idea with the cheapest, safest piece. No spend, no merges, no
network. Pure read + an additive METRICS snapshot.

## Minimal version
`massoh review [--since DAYS] [--no-write] [--run-tests]`:
- **packets**: total `.agent_tasks/TASK-*`, reviewed (have `06_*`), licensed (have `04_*`), open.
- **backlog**: TODO / DOING / DONE / BLOCKED counts from `AGENT_BACKLOG.md`.
- **delivery (git)**: merged PRs (`(#N)` in log), commits since `--since` (default 7d), reverts.
- **branches**: `feat/*`, `cron/*` counts.
- **quality**: `--run-tests` runs `test/run.sh` → "N checks green"; else "skipped".
- **version**: from `VERSION`.
- Prints the report; unless `--no-write`, appends a `## Snapshot <ts>` block to `METRICS.md`
  (append-only — keep-older-data).

## Non-goals
No `standup`/`plan`/`retro` yet (next slices). No network. No cron wiring yet. No mutate beyond the
METRICS append.

## Safety/guardrail impact
Read-only except the METRICS.md append (additive, not safety-critical). Edits `bin/massoh`
(safety-critical) for the verb → owner authorized. No manifest change.

## Acceptance
- `massoh review` prints packet/backlog/delivery/branch KPIs; exit 0.
- `--no-write` makes no file changes (verified by snapshot).
- default appends one `## Snapshot` block to `METRICS.md`; re-run appends another (never overwrites).
- `--run-tests` reports the suite result.
- runs read-only on a fixture; prior 45 tests green.

## Routing
BUILD → `massoh-architecture-safety`.
