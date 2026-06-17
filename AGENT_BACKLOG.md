# AGENT_BACKLOG.md — Massoh prioritized autonomous work queue

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
| 1 | P1 | **`massoh-meta` (self-improvement engineer)** — watch Massoh's own operation (ledger/rework/cost/comms/over-process) → bottleneck findings → gated engine upgrades → new version. See [[massoh-meta-improvement]]. (IN FLIGHT this branch) | The system improves its own process, shipped as versions | DOING |
| 2 | P1 | **`massoh-intake` (idea triage)** — on a task request: auto-queue + auto-allocate priority (unless stated) + guarantee **closure** (record/remember/reprioritize); absorb a fast-firing owner without dropping ideas. See [[massoh-idea-intake]]. | Owner fires ideas fast; nothing should be lost or mis-ordered | TODO |
| 3 | P1 | Reconcile AGENT_BACKLOG across branches (shipped items still TODO; meta-item on another branch) | Backlog drift — exactly what `massoh-meta`/`intake` should auto-fix | TODO |
| 4 | P1 | Enforce license-to-code gate (pre-commit/pre-push + CI) | The one hard gate is honor-system today; make it mechanical | TODO |
| 3 | P2 | Emit `AGENTS.md` from the 6 roles | Multi-harness portability (Cursor/Codex/Antigravity) | TODO |
| 4 | P3 | Profiles + single `config.yml` | Project archetypes; consolidate config | TODO |
| 5 | P3 | Upgrade `test/run.sh` → `bats`; commit-conv ratio in discover | Nicer test UX; fewer discover false-negatives | TODO |
| 6 | P3 | Rename `manifest.yml version:` → `schema_version:` | Disambiguate from product `VERSION` | TODO |

## Done (newest first — kept, never deleted)
| Pri | Item | PR | Date |
|---|---|---|---|
| P1 | v0.4 cadence ceremonies — `review` + `standup` + `plan` (KPIs, progress delta, queue+decisions) | #6 + this | 2026-06-16 |
| P1 | `massoh cron` — autonomous parallel worktree loop runner (safe-by-default) | #4 → main `1f02151` | 2026-06-16 |
| P1 | Version stamp (`massoh version`) + `doctor` update-check + `CHANGELOG.md` | TASK-version-notify (branch, pending merge) | 2026-06-16 |
| P1 | `massoh discover` + `STANDARDS.md` layer (wired into implementer/reviewer) | TASK-massoh-cli-verbs (branch, pending merge) | 2026-06-16 |
| P2 | `massoh doctor` + first CLI test suite (`test/run.sh`, 21 checks) | TASK-massoh-cli-verbs | 2026-06-16 |
| P1 | Harden `massoh update` (stash→pull→pop, fail-safe) | TASK-massoh-cli-verbs | 2026-06-16 |
