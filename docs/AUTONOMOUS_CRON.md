# Autonomous cron — "let it work" (portable, opt-in)

A way to let the team make calculated progress while the owner is away. Optional, off by default,
and bounded by every guardrail. Proven in production on a real project before being templated here.

## The loop
A scheduled tick (e.g. every 30 min) that, **only when the owner is idle**:
1. **Idleness gate.** Check last commit/message time. If the owner was active within ~25 min →
   **STOP this tick, do nothing.** (Never compete with the owner.)
2. **Evaluate pending decisions** (v0.28.0+, opt-in — see §Decide-or-defer below). Walk the
   decision queue; emit notices, detect owner answers, proceed or hold at deadline. Only runs when
   `cron_decide_or_defer=on` (default OFF); with the flag off this step is a no-op.
3. **Read `AGENT_BACKLOG.md`** (re-rank if anything changed).
4. Skip BLOCKED items. Take the **top unblocked TODO**.
5. **Build to completion** under all guardrails (`policies/09_GUARDRAILS.md`): flag-gate new
   features (default OFF), never touch a designated safety-critical file/policy, keep-older-data,
   write a **real** test that exercises the actual path (a stub-only test can miss a real
   regression), run the local gate (tests + build/lint) **before** any PR.
6. **When a decision is needed (opt-in path):** workers report `status=needs-decision` in their
   result file; the parent loop enqueues the decision with a timed grace window. The owner is
   notified via `NOTIFICATIONS.md` (+ one `[escalation]` line in `AGENT_SYNC.md`). The owner
   answers in `DECISIONS.md`. At deadline, only **reversible + flag-dark + on-plan** options that
   are NOT in the never-auto class may auto-proceed; everything else stays `HELD_BLOCKED`.
   **Without the flag, the parent never auto-acts — BLOCK + escalate for owner-gated calls
   (`09_GUARDRAILS.md §B`).**
7. **Branch → PR.** Auto-merge + deploy **only** if flag-dark **and** additive/low-risk **and** all
   gates/CI green. Otherwise leave the PR open + a note. Never force-merge past a failing check.
8. **Mark DONE** (move to the Done table — kept, never deleted; link the PR) and **`/sync`** with
   what you did + why. One calculated, fully-tested, reversible action. Quality over quantity.

## Why each rule exists
- *Idleness gate* — autonomy is for idle time, not for racing the owner.
- *One at a time + system-architect escalation* — prevents half-finished pile-ups.
- *Real test* — lesson of record: a stub-only test let a real 500 regression ship.
- *Owner-gated stops* — the few actions that are expensive/irreversible always wait for a human.
- *Flag-dark auto-merge only* — "merge while away" never means "behavior change for everyone".
- *Decide-or-defer timer* — the owner gets `cron_notify_count` (default 2) notices over
  `cron_grace_min` (default 120 min) before any unattended action; they can always cancel by
  appending to `DECISIONS.md`. Flag default OFF = zero behavior change for existing users.

## Wiring it (the runner — `massoh cron`, since v0.3)
Massoh ships the runner; you supply the clock.

```bash
massoh cron once                 # ONE tick, DRY-RUN (default): prints what it would do. No spend.
massoh cron once --run           # execute: worktree(s) + agent + gate + DONE + [cron] sync entry
massoh cron once --run --parallel 3       # fan 3 disjoint TODOs to parallel worktree agents
massoh cron once --run --auto-merge       # merge a branch ONLY if its gate is green (opt-in)
massoh cron status               # config + whether a schedule is installed
massoh cron install --every 30m           # PRINTS a crontab line (does not install)
massoh cron install --every 30m --apply --yes-spend   # actually install (recurring paid spend)
massoh cron off                  # remove the installed schedule
```

**Safe by default:** dry-run unless `--run`; auto-merge OFF unless `--auto-merge`; idleness gate ON
(`--no-idle-check` for tests only). Paid `claude -p` spend + auto-merge stay owner-gated — the flags
are the switch, the defaults keep them off.

**Injectable (zero-cost testing / BYO agent):** `MASSOH_AGENT_CMD` (default `claude -p`) and
`MASSOH_GATE_CMD` (default: `test/run.sh` if present, else `true`). Clock injection for the
decide-or-defer subsystem: `MASSOH_NOW` (Unix epoch integer, overrides `date +%s`).

**Race-free parallel:** each agent works only its own `cron/<slug>` branch in its own worktree; the
parent process is the *single* writer of `AGENT_BACKLOG.md`/`AGENT_SYNC.md` and the only one that
merges. Keep the **`[cron]`** marker on sync entries so unattended work is scannable
(`policies/13_MONITORING.md`). Turn it off with `massoh cron off`, or `massoh off` for the repo.

---

## Decide-or-defer subsystem (v0.28.0, opt-in)

> **Safety boundary.** This subsystem expands what the loop may do unattended. It is **opt-in**
> (`cron_decide_or_defer: off` by default) and **owner-gated** (the owner signs off in
> `agent-project/NON_NEGOTIABLES.md §Autonomy boundary`). `bin/massoh-cron` is now a designated
> safety-critical file; changes to the eligibility classifier, plan-guard, or proceed/hold branch
> require fresh owner sign-off.

### State machine (per decision record)

```
Worker reports status=needs-decision → parent loop enqueues record (id, deadline=now+grace)
                          │
                    DECISION_NEEDED → classify eligibility + plan-guard
                          │
          eligible+on-plan │ │ ineligible OR off-plan
                           ▼ ▼
              AWAITING_OWNER   HELD_BLOCKED (notify #1; never auto-proceeds)
                     │
      on each idle tick: emit notice up to notify_count (idempotently)
      check DECISIONS.md for owner answer → RESOLVED_BY_OWNER (any tick)
                     │
              now >= deadline?
                     │ yes: re-evaluate eligibility + plan-guard (never cached)
                     ▼
      reversible+flag-dark+on-plan+not-never-auto → PROCEED (record what+why)
      anything else                                → HELD_BLOCKED (stay; keep notifying)
```

**Terminal states:** `PROCEED`, `HELD_BLOCKED` (after deadline), `RESOLVED_BY_OWNER`.

### Files
| File | Role |
|---|---|
| `NOTIFICATIONS.md` | Append-only notice log (owner-visible). Schema: `## NOTIF <id>#L<n>` per notice; `## NOTIF <id>#CLOSE` per terminal state. Never edit prior blocks. |
| `DECISIONS.md` | Append-only owner-answer channel. Append a row `| decision_id | APPROVE\|REJECT\|DEFER | note | ts | by |` to answer. Last matching row (by ts >= open_ts) wins. |
| `.agent_tasks/cron/decisions.queue` | Append-only internal queue (tab-separated records + `U\t<id>\t<n>` update lines for notices_sent). |

### Config keys (`agent-project/config.yml`)
| Key | Default | Meaning |
|---|---|---|
| `cron_decide_or_defer` | `off` | Master flag. `off` = byte-identical to pre-v0.28.0. |
| `cron_grace_min` | `120` | Grace window (minutes) before timed proceed-or-hold. |
| `cron_notify_count` | `2` | Number of notices before proceed-or-hold (max 2). |
| `cron_spend_cap_usd` | `0` | Max paid spend for auto-proceed. `0` = any spend is never-auto. |

### Never-auto class (items that stay HELD_BLOCKED regardless of grace)
Per `policies/09_GUARDRAILS.md §B` verbatim:
- Safety-critical-file/policy change (incl. `bin/massoh-cron` itself).
- Irreversible/destructive op (data deletion, force-push, history rewrite, etc.).
- Production deploy to a real-user environment.
- Paid spend above `cron_spend_cap_usd` (default 0; missing estimate = over-cap).
- Unfreezing a frozen feature.

### Plan guard (fail-closed)
A decision record must carry `plan_ref: PRODUCT_STRATEGY.md#north-star` + non-empty
`plan_rationale`. The runner verifies the canonical anchor section exists in-repo. Missing/empty/
anchor-not-found → `HELD_BLOCKED`. This keeps the loop deterministic (no model call mid-tick).

### Answering a notice
Append a row to `DECISIONS.md`:
```
| AESC-20260621T1430Z-3f2a | APPROVE | go with the recommended option | 2026-06-21T15:05Z | owner |
```
Verdicts: `APPROVE` (apply recommended; architect/implementer picks it up), `REJECT` (close,
leave BLOCKED), `DEFER` (close, park for later). The loop checks on the next idle tick.
