# Autonomous cron — "let it work" (portable, opt-in)

A way to let the team make calculated progress while the owner is away. Optional, off by default,
and bounded by every guardrail. Proven in production on a real project before being templated here.

## The loop
A scheduled tick (e.g. every 30 min) that, **only when the owner is idle**:
1. **Idleness gate.** Check last commit/message time. If the owner was active within ~25 min →
   **STOP this tick, do nothing.** (Never compete with the owner.)
2. **Read `AGENT_BACKLOG.md`** (re-rank if anything changed).
3. If the previous item is **DOING/unfinished** or a **decision is pending** → hand it to
   `massoh-system-architect` to finish/unblock; don't start a new item. Skip BLOCKED items.
   Else take the **top unblocked TODO**, mark it **DOING**.
4. **Build to completion** under all guardrails (`policies/09_GUARDRAILS.md`): flag-gate new
   features (default OFF), never touch a designated safety-critical file/policy, keep-older-data,
   write a **real** test that exercises the actual path (a stub-only test can miss a real
   regression), run the local gate (tests + build/lint) **before** any PR.
5. **When a decision is needed:** take the **recommended** safe/reversible/flag-dark option and
   **proceed** — record what + why. Only **BLOCK + escalate** for owner-gated calls
   (`09_GUARDRAILS.md` §B): a safety/policy change, an irreversible/destructive op, or significant
   cost. Production deploy to a real-user environment is owner-gated.
6. **Branch → PR.** Auto-merge + deploy **only** if flag-dark **and** additive/low-risk **and** all
   gates/CI green. Otherwise leave the PR open + a note. Never force-merge past a failing check.
7. **Mark DONE** (move to the Done table — kept, never deleted; link the PR) and **`/sync`** with
   what you did + why. One calculated, fully-tested, reversible action. Quality over quantity.

## Why each rule exists
- *Idleness gate* — autonomy is for idle time, not for racing the owner.
- *One at a time + system-architect escalation* — prevents half-finished pile-ups.
- *Real test* — lesson of record: a stub-only test let a real 500 regression ship.
- *Recommended-when-stuck* — keeps progress moving without nagging; the owner reviews the trail.
- *Owner-gated stops* — the few actions that are expensive/irreversible always wait for a human.
- *Flag-dark auto-merge only* — "merge while away" never means "behavior change for everyone".

## Wiring (project-specific)
The scheduler is whatever the environment provides (a cron tool, a CI schedule, a runner). Keep the
**marker convention** (`[cron]`) on its `AGENT_SYNC.md` entries so unattended work is scannable
(`policies/13_MONITORING.md`). Turn it off by removing the schedule, or `massoh off` for the repo.
