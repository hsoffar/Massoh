# 01 — Product Scope

**Agent:** massoh-product-scope · **Date:** 2026-06-16

## Decision: **BUILD — but sliced + phased** (do NOT ship a full unattended auto-merge fleet at once)
The full "cron drives parallel auto-merge" is real, but shipping it in one go would be build-trap:
it couples four independent risks (scheduling, headless cost, parallel state, auto-merge). Slice so
each risk is provable on its own and the dangerous parts stay owner-gated.

## The core design decision (makes it real-testable + safe)
The agent invocation is an **injectable command**: `MASSOH_AGENT_CMD` (default `claude -p`). Tests +
dry-runs use a **fake agent script** → we exercise the whole loop (idleness gate, backlog parse,
worktree setup, sync merge) with **zero API cost**. This is what lets us write a *real* test for an
autonomous feature (Guardrail A5) without owner-gated spend.

## Minimal version — Phase 1 only this session
`massoh cron once` — **one tick, foreground, manual, dry-run-capable, NO auto-merge**:
1. **Idleness gate** — check last commit/activity; if owner active < ~25 min → exit 0, do nothing.
2. Parse `AGENT_BACKLOG.md` → top unblocked `TODO` (skip BLOCKED; if prev is DOING → would escalate).
3. `--dry-run` (default): print what it WOULD do (item, branch, agent cmd) and exit. No spend, no edits.
4. `--run`: invoke `$MASSOH_AGENT_CMD` on the item in an isolated **git worktree**, leave a branch +
   PR, mark DONE in backlog, append a `[cron]` `AGENT_SYNC.md` entry. **Never auto-merges.**
Ships `massoh cron once|install|off` skeleton; `install`/`off` wire a scheduler (Phase 2 fills clock).

## Sequencing (one phase per packet — re-rank on add)
- **Phase 1 (now):** `massoh cron once` runner — idleness gate + backlog parse + worktree + dry-run +
  injectable agent cmd + `[cron]` sync entry. **No scheduler, no parallel, no auto-merge.**
- **Phase 2:** `massoh cron install/off` → wire a real clock (harness `/schedule` or OS cron/systemd).
- **Phase 3:** parallel fan-out — N disjoint items, worktree-per-agent, **per-agent AGENT_SYNC
  section** (kills the write-race), orchestrator merges. (system-architect = the orchestrator.)
- **Phase 4 (OWNER-GATED, may never auto-run):** unattended auto-merge — only flag-dark + additive +
  all-green, per AUTONOMOUS_CRON.md. Defaults OFF; owner opts in per repo.

## Non-goals (v0.3)
No unattended **auto-merge** by default (Phase 4, owner-gated). No real API spend in tests/dry-run.
No remote/cloud runner. No cross-repo fleet.

## Safety/guardrail impact (for arch/safety)
- **Paid API spend** (`claude -p`) = Guardrail B owner-gated → Phase 1 defaults to `--dry-run`; `--run`
  requires an explicit flag; `install` (a recurring spender) requires explicit owner opt-in.
- Concurrent `AGENT_SYNC.md` writers = race → Phase 3 introduces per-agent sections.
- Worktrees must be cleaned; never operate on the owner's working tree.
- Edits `bin/massoh` (safety-critical) → owner sign-off.

## Metric / events
`cron_tick`, `cron_item_taken`, `cron_pr_opened` (hand-counted). Serves the autonomy/throughput goal.

## Acceptance criteria — Phase 1
- `massoh cron once` with owner "active" (recent commit) → exits 0, does nothing (idleness gate).
- `--dry-run` (default) prints the chosen TODO + planned branch/agent-cmd, makes **no** edits, **no**
  `$MASSOH_AGENT_CMD` call. Verified with a fake agent cmd asserting it was NOT invoked.
- `--run` with a **fake** `MASSOH_AGENT_CMD` → creates a worktree, invokes the fake once, marks the
  item DONE, appends a `[cron]` AGENT_SYNC entry, cleans the worktree. **No auto-merge.**
- Empty/all-BLOCKED backlog → exits 0 cleanly.
- All prior 28 tests green.

## Routing
BUILD → `massoh-architecture-safety`. **Owner confirmation needed on the slice** (you asked for
"Both/biggest"; product-scope recommends Phase 1 only this session, Phases 2–4 sequenced). Phase 4
auto-merge stays owner-gated regardless.
