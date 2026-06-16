# 00 — Request

**Task ID:** TASK-2026-06-16-massoh-autonomous-fleet · **Date:** 2026-06-16 · **Source:** owner

## Request
Make the autonomous cron real **and** parallel: a timer fires → an orchestrator fans disjoint
`AGENT_BACKLOG.md` items out to parallel **worktree** agents → merges → one `AGENT_SYNC.md` update.
("Both — cron drives parallel", v0.3 flagship.)

## Classification
**PRODUCT_SCOPE** (entry). High-risk: unattended execution, **paid API spend** (Guardrail B
owner-gated), auto-merge, concurrent writes to shared state. Product-scope must slice + sequence;
arch/safety must gate; some sub-parts are owner-gated and will NOT ship unattended in v0.3.

## Code edits allowed?
No (until an approved `04`). Will touch `bin/massoh` + add new scripts → safety-critical + owner sign-off.

## Shortcut
UX skipped (CLI/ops, not user-facing). Recorded.
