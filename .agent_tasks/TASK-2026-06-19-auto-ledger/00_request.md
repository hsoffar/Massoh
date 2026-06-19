# 00 — Request: auto-ledger via SubagentStop hook (24h queue #5)

- **Task ID:** TASK-2026-06-19-auto-ledger
- **Date:** 2026-06-19
- **Raised by:** owner (24h queue #5)
- **Classification:** ARCHITECTURE_SAFETY (feasibility + safety) → IMPLEMENTATION. Owner
  **batch-authorized** + **auto-merge-on-green**.

## Goal (AGENT_BACKLOG acceptance stub #5)
Capture each stage's tokens/seconds into `.agent_tasks/ledger.tsv` **automatically** (via a
SubagentStop hook) instead of a manual `massoh ledger add` call. Degrade silently if the ledger is
absent; no double-count; documented opt-in.

## Open feasibility question (arch-safety MUST resolve first)
Does the Claude Code **SubagentStop** hook receive the stopped subagent's **token usage + duration**?
- If YES → the hook maps that to `massoh ledger add <task-id> <stage> <tokens> <seconds>`.
- If NO (hook only gets a stop signal) → reduced scope: capture **wall-time only** (and a token
  estimate if any signal exists), OR recommend DEFER with the reason. Do not invent token numbers.

This is the first **harness-hook** surface. The hook config lives in `settings.json` (project or
global), NOT a NON_NEGOTIABLES safety-critical file — but it is an **automation that fires on every
subagent stop**, so treat blast-radius/cost/loop-risk carefully.

## Safety concerns to condition on
- Opt-in (off unless installed); a documented enable step; never auto-installed globally without consent.
- No double-count (idempotent per subagent stop); degrade silently if `massoh`/ledger unavailable.
- The hook must be fast + non-blocking + never fail the subagent; `|| true` throughout.
- `task-id`/`stage` derivation must be safe (sanitized) — reuse cmd_ledger's L1/L2 validation.
- No secrets; no network; bounded.

## Routing
`massoh-architecture-safety` → `03` (feasibility verdict + conditions + tests, or DEFER recommendation)
→ if feasible: `04` (batch-auth) → implementer → reviewer-qa → auto-merge on green. If arch-safety
finds it infeasible/unsafe, it routes back to owner with a DEFER + re-entry condition.
