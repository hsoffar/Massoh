# 00 — Request
**Task:** TASK-2026-06-17-ledger-aware · **Date:** 2026-06-17 · **Source:** owner ("go on continue")

Make the ledger **actionable** — wire `.agent_tasks/ledger.tsv` into the cadence loop so cost is
visible + drives recommendations. Serves the north-star (self-measurement → efficiency).

Idea (product-scope to refine):
- **`review`**: add a `cost:` line — total tokens + seconds from the ledger, and avg tokens per task
  (read the ledger read-only; degrade if absent). Optionally into the METRICS snapshot.
- **`recommend`**: add cost-aware heuristic rules over the ledger, e.g.:
  - a task/stage far above the average cost → "expensive — review scope/rework";
  - cost-per-merged-PR trending up across METRICS snapshots → "efficiency dropping";
  - reviewer+implementer cost dominating (rework signal) → "tighten earlier gates".

**Non-goals (explicit):** NO auto-capture (the SubagentStop hook / cron-dispatch integration is a
separate NEXT — assess data availability first); no dollar-cost; no new write paths beyond the
existing additive METRICS/AGENT_SYNC appends. All read-only over the ledger.

**Driven by the massoh-* agent team.** Classification: PRODUCT_SCOPE. Owner authorized build +
`bin/massoh` edits (north-star). Branch: `feat/ledger-aware`. Read-only, zero LLM spend.

Note: this session's own ledger shows reviewer-qa (89.7k) + implementer (85.8k) dominate a task's
cost — driven by the 3 gate-caught rev2s. That's exactly the signal the cost-aware rules should surface.
