# 00 — Request
**Task:** TASK-2026-06-17-cadence-cron · **Date:** 2026-06-17 · **Source:** owner ("use the agents to self-improve")

Wire the cadence ceremonies into the cron cadence: a cron tick should also run `massoh standup`
(progress delta), and a period boundary should run `massoh review` + `massoh plan`. The ceremonies
are read-only local bash (no LLM spend) → low-risk. Completes v0.4.

**Driven by the massoh-* agent team** (product-scope → architecture/safety → implementer →
reviewer-qa), each writing its packet file. Classification: PRODUCT_SCOPE (entry). Owner authorized
the build + any `bin/massoh*` edits. Branch: `feat/massoh-cadence-cron`.
