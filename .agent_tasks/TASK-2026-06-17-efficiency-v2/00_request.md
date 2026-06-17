# 00 — Request
**Task:** TASK-2026-06-17-efficiency-v2 · **Date:** 2026-06-17 · **Source:** owner
("monitor efficiency · is tick time implemented · self-recommendation on better/faster/easier")

Build the **efficiency v2 bundle** (all read-only / heuristic / zero LLM spend):
1. **`review` v2** — add **cycle time** (per packet: `00`→`06` dates, or branch-first-commit→merge),
   **rework rate** (count packets whose `06` shows REQUEST-CHANGES before APPROVE), and **throughput**
   (packets done per week). Into `agent-project/METRICS.md` snapshots.
2. **cron tick-time fixes** — log per-tick **duration** (seconds) to the cron output; **fix the
   hardcoded `every_mins=30`** in `bin/massoh-cron` (`period_ticks` must derive from the ACTUAL
   `--every`, not assume 30m). This is a real correctness bug flagged in the cadence-cron handoff.
3. **`massoh recommend`** — forward self-recommendation: heuristic rules over the `METRICS.md`
   snapshot trend → ranked suggestions (cycle-time climbing → tighten product-scope; high reject rate
   → arch/safety too shallow; revert spike → more real tests; backlog grows while done flat →
   throughput bottleneck). Read-only.

**Driven by the massoh-* agent team.** Classification: PRODUCT_SCOPE (entry). Owner authorized build +
`bin/massoh*` edits (both `bin/massoh` and `bin/massoh-cron` are safety-critical) via the
"Full efficiency v2 bundle (agent-driven)" selection. Branch: `feat/efficiency-v2`.
Product-scope to **slice + sequence** (recommend: cron-fix first = correctness, then review-v2 = data,
then recommend = consumes the data).
