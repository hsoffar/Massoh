# 00 — Request
**Task:** TASK-2026-06-17-massoh-ledger · **Date:** 2026-06-17 · **Source:** owner (north-star)

Build the **time/token/cost ledger** — the primitive that gives agents *understanding of time +
tokens per task*. Serves the north-star (`PRODUCT_STRATEGY.md` §North-star): governed, **self-
measuring**, autonomous.

**Key insight — reuse, don't reinvent:** the Claude Code harness ALREADY reports `subagent_tokens`
and `duration_ms` for every agent run (visible to the orchestrator that dispatched the agent). Massoh
must **capture + persist + analyze** that — NOT re-measure it.

Minimal idea (product-scope to refine):
- **`massoh ledger add <task-id> <stage> <tokens> <seconds>`** — append a row to a ledger
  (e.g. `.agent_tasks/<task>/ledger.tsv` or a central `.agent_tasks/ledger.tsv`). The orchestrator
  (or cron, or a future SubagentStop hook) calls this when an agent returns.
- **`massoh ledger`** — aggregate report: tokens + duration per task and per stage
  (product-scope/arch-safety/implementer/reviewer), totals, averages per task.
- Later: `review`/`recommend` read it ("a gated feature ≈ N tokens, ~M min"); durable budgets → memory.

Open design question for product-scope + arch/safety: **capture mechanism for v1** — the simple
orchestrator-called `ledger add` verb (testable, no harness coupling) vs a `settings.json` SubagentStop
**hook** (auto-capture, harness-specific). Recommend v1 = the verb; note the hook as a NEXT.

**Driven by the massoh-* agent team.** Classification: PRODUCT_SCOPE. Owner authorized build +
`bin/massoh*` edits (north-star selection). Branch: `feat/massoh-ledger`. Read-only/append-only,
zero LLM spend.
