# AGENT_BACKLOG.md — {{PROJECT}} prioritized autonomous work queue

The queue the optional **idle cron** drains. When the owner is away, the cron takes the **top
unblocked TODO**, works it **to completion** (build → real test → local gate → PR → merge+deploy
only if flag-dark + additive + all green, else leave the PR open + a note), marks it **DONE**, and
re-syncs `AGENT_SYNC.md`. Full rules: `~/.claude/agent-os/docs/AUTONOMOUS_CRON.md`.

## Rules (summary)
- **Re-rank on add** (value × safety). **One at a time, to completion.**
- Every item obeys the guardrails (`~/.claude/agent-os/policies/09_GUARDRAILS.md`): flag-gate, never
  touch a designated safety-critical file/policy, keep-older-data, a **real** test, local gate
  before any PR.
- Flag-dark + additive + green → may auto-merge + deploy. Otherwise PR + note. Never force-merge
  past a failing required check.
- **Default to recommended when stuck** — take the safe/reversible/flag-dark option and proceed;
  only BLOCK + escalate for owner-gated calls (safety/policy, irreversible, significant cost).
- **Status:** TODO / DOING / DONE / BLOCKED / DEFERRED. Done items move to the bottom (kept, never deleted).

## Priority key
`P0` urgent/bug · `P1` high-value usability/functionality · `P2` nice-to-have · `P3` someday.

## Queue (top = next)
| # | Pri | Item | Why | Status |
|---|-----|------|-----|--------|
| 1 | {{P?}} | {{ … }} | {{ … }} | TODO |

## Done (newest first — kept, never deleted)
| Pri | Item | PR | Date |
|---|---|---|---|
