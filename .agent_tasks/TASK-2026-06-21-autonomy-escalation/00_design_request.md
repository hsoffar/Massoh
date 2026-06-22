# 00 — Design request: autonomy timed-escalation + long-term-plan guard (DESIGN ONLY)

- **Date:** 2026-06-21 · owner wants the autonomous loop to **decide-or-defer** without nagging, and
  to **always check decisions against the long-term plan**.
- **This is a DESIGN spec for OWNER SIGN-OFF — no build.** It expands what the loop may do UNATTENDED
  → it is a **safety-boundary change** (treat the autonomy boundary as safety-critical even though
  `bin/massoh-cron` is not on the NON_NEGOTIABLES list; `bin/massoh`/`manifest.yml` ARE and must stay diff=0).

## Context — what exists today (`docs/AUTONOMOUS_CRON.md`, `bin/massoh-cron`)
The cron loop, when owner idle (~25m gate), drains the backlog and on a decision **takes the
recommended safe/reversible/flag-dark option + proceeds**, or **BLOCK + escalate to
`massoh-system-architect`** for owner-gated calls (safety/policy/irreversible/cost). Two gaps vs what
the owner wants:
1. Owner-gated decisions **hard-block forever** — no notification, no timed proceed.
2. No explicit **long-term-plan check** in the decision step.

## What to design (the two additions)
### A. Timed escalation tier ("notify twice → grace → proceed-or-hold")
For a decision that needs owner input but is **eligible** (see boundary below):
- On the tick it arises: write **notification #1** and mark the item `AWAITING_OWNER` with a deadline.
- On a later idle tick still unanswered: **notification #2** ("notify me twice").
- After the **grace window (default 2h)** with no owner decision recorded:
  - **IF the recommended option is reversible + flag-dark → proceed** with it; record what+why +
    "auto-proceeded after grace, no owner reply".
  - **ELSE (safety-critical-file/policy change, irreversible/destructive op, paid-spend over
    threshold, production deploy) → NEVER auto-proceed.** Stay blocked, keep escalated to architect,
    keep the notification open. (OWNER DECISION LOCKED: timeout unlocks **reversible+flag-dark only**.)
- **Owner override cancels the timer:** if the owner records a decision any time, the timer/notice closes.

### B. Long-term-plan guard (every decision, attended or not)
Before proceeding with ANY recommended option, **validate it against the long-term plan** and only
proceed if it is traceable to the plan; if it conflicts or isn't traceable → do NOT proceed, escalate.
- Pick the **canonical in-repo plan anchor** (candidates: `agent-project/PRODUCT_STRATEGY.md`
  §North-star, `agent-project/CHARTER.md` North-star, `AGENT_SYNC.md` §Current strategic mode). The
  owner's personal north-star memory is NOT in-repo — anchor to an in-repo doc.

## The design must answer (load-bearing)
- **Notification sink (OWNER DECISION LOCKED):** append-only `NOTIFICATIONS.md` (or similar) + an
  `AGENT_SYNC` line. Design the format: one entry per (item, escalation-level) with id, ts, the
  decision, the recommended option, the deadline, status. No spam — exactly two notices, then
  proceed-or-hold. Zero new deps / zero network (matches Massoh posture).
- **"Has the owner answered THIS?" check:** how the loop detects an owner decision keyed to a
  notification id (e.g. owner writes a DECISIONS entry / AGENT_SYNC decision-log row / edits status).
  Must be unforgeable-enough and append-only.
- **Eligibility classifier:** the precise predicate for "reversible + flag-dark" vs the never-auto
  class (reuse `09_GUARDRAILS.md` §B owner-gated definition). What is the paid-spend threshold?
- **Grace/notify config:** `cron_grace_min` (default 120), `cron_notify_count` (default 2) in
  `agent-project/config.yml` (mirror `cron_idle_min`). **The whole timed-proceed behavior must be
  flag-gated, default OFF** (opt-in — it expands unattended authority).
- **Clock without a daemon:** the loop is tick-driven (idle ticks). Design how the 2h deadline is
  evaluated across discrete ticks (store deadline timestamp; compare on each tick) — no background timer.
- **Idempotency / crash-safety:** re-running a tick must not double-notify or double-proceed.
- **Tests:** notify-once-then-twice-then-proceed (reversible) ; never-auto for safety/irreversible/cost
  even past deadline ; owner-decision-cancels-timer ; plan-guard blocks an off-plan recommendation ;
  flag default OFF = today's behavior byte-identical ; idempotent tick.
- **Sliced build order** + exactly what needs **OWNER SIGN-OFF** before each slice.

## Deliverable
`.agent_tasks/TASK-2026-06-21-autonomy-escalation/01_design.md` — the escalation state machine, the
plan-guard + chosen anchor, the notification format + owner-answer detection, the eligibility
classifier + spend threshold, config + default-OFF flag, the tick-based clock, tests, sliced build
order, and a clear "needs OWNER SIGN-OFF" marker. NOTHING ships until the owner signs off.

## Routing
`massoh-system-architect` → `01_design.md` → owner reviews + signs off → then (and only then) impl
under the gate. `bin/massoh` + `manifest.yml` stay diff=0.
