# 01 — Product Scope
**Agent:** massoh-product-scope · **Date:** 2026-06-16

## Decision: **BUILD** (read-only ceremonies, same low-risk profile as `review`)

## Minimal version
- **`massoh standup [--since DAYS] [--no-write]`** — the progress delta: commits since `--since`
  (default 1d), DOING + BLOCKED backlog items, in-flight packets (have `04_` but no `06_`). Prints;
  unless `--no-write`, appends `## [standup] <ts>` to `AGENT_SYNC.md`.
- **`massoh plan [--no-write]`** — the planning pulse: the prioritized TODO queue (the "now/next"),
  + **surface owner decisions** (rows under `AGENT_SYNC.md` §Open questions) + BLOCKED items. Prints;
  unless `--no-write`, appends `## [plan] <ts>` to `AGENT_SYNC.md`.

## Non-goals
No auto re-rank (plan *surfaces*; the owner/agent decides). No cron wiring (next slice). No mutate
beyond the AGENT_SYNC append. No network (PR list only if `gh` present, best-effort).

## Safety
Read-only except additive AGENT_SYNC append (`--no-write` inert). Edits `bin/massoh` (safety-critical)
→ owner authorized. No manifest change. Degrade gracefully (no backlog / no sync / non-git).

## Acceptance
- `standup` lists recent commits + DOING/BLOCKED + in-flight packets; `--no-write` changes nothing.
- `plan` lists TODO queue + surfaces an Open-questions row + BLOCKED; `--no-write` changes nothing.
- both append exactly one timestamped block when writing; append-only.
- degrade in a non-git/empty dir (exit 0). Prior 53 tests green.

## Routing
BUILD → `massoh-architecture-safety`.
