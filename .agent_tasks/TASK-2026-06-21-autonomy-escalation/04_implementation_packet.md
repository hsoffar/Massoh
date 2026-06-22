# 04 — License: autonomy decide-or-defer (timed escalation + plan guard) — slices 0–3

- **Gate:** architect `01_design.md` + **OWNER SIGN-OFF #1 AND #2** (2026-06-21: owner approved BOTH —
  build all 4 slices, including slice 3 authority expansion). This is the new safety-risk-class the
  away-grant parked; now explicitly authorized by the owner.
- **Branch:** `feat/autonomy-decide-or-defer` (off current main). **VERSION → 0.28.0**; CHANGELOG [0.28.0].
- **Source of truth:** build EXACTLY `01_design.md` (state machine, schemas, hook points, tests). This
  packet is the license + acceptance; `01_design.md` is the spec.

## Scope — slices 0→3 (in order)
- **Slice 0 (markdown):** add `bin/massoh-cron` to `agent-project/NON_NEGOTIABLES.md` safety-critical
  list + an autonomy-boundary note. (Owner signed off on subsequently editing it for this feature.)
- **Slice 1:** config keys `cron_decide_or_defer` (master flag, **default OFF**), `cron_grace_min`
  (default 120), `cron_notify_count` (default 2), `cron_spend_cap_usd` (default 0) in
  `agent-project/config.yml`; same parse+integer-validate pattern as `cron_idle_min`
  (`bin/massoh-cron:21`). With the master flag OFF the loop is **byte-identical to today** (evaluator
  is a no-op). Hook the config read after `bin/massoh-cron:21`.
- **Slice 2:** the decision queue + notify + owner-answer detection. Append-only `NOTIFICATIONS.md`
  (schema per design: id, ts, decision, recommended option, deadline, status; `## NOTIF <id>#L<n>`
  grep-guard so each level notifies at most once). Append-only `DECISIONS.md` owner-answer channel,
  keyed by record id; an owner answer at any tick → `RESOLVED_BY_OWNER`, timer cancelled. **At-deadline
  in this slice = HOLD only (`HELD_BLOCKED`); NO auto-proceed yet.** Evaluator runs after the idle gate
  (`:95`) / before fan-out (`:97`); queue append in the parent-only serialization loop (`:132-147`);
  deadline clock mirrors the cadence-counter tick pattern (`:157-184`).
- **Slice 3 (the authority expansion):** at deadline, **re-evaluate (never cached)** eligibility +
  plan-guard; only `reversible AND flag_dark AND NOT never_auto AND on-plan` → `PROCEED` (record
  what+why + "auto-proceeded after grace, no owner reply"). Everything else → `HELD_BLOCKED` forever
  (still notified/escalated). `never_auto` = `09_GUARDRAILS §B` verbatim + safety-critical-file (incl.
  `bin/massoh-cron`) + irreversible/destructive + prod-deploy + paid-spend `> cron_spend_cap_usd`
  (missing estimate ⇒ over-cap). Plan-guard **fail-closed**: record must carry `plan_ref` (naming
  `agent-project/PRODUCT_STRATEGY.md` §North-star) + non-empty rationale, else off-plan → hold.

## Mandatory conditions
- **`bin/massoh` + `manifest.yml` diff = 0.** Touch: `bin/massoh-cron`, `agent-project/config.yml`(+
  template if one exists), `agent-project/NON_NEGOTIABLES.md`, `docs/AUTONOMOUS_CRON.md` (correct it —
  the step-5 escalation it described did not exist; document the real new subsystem), `test/run.sh`,
  `VERSION`, `CHANGELOG`. NOTIFICATIONS.md/DECISIONS.md are runtime artifacts (gitignore or seed empty
  per design — follow `01_design.md`).
- **Master flag default OFF ⇒ byte-identical to today** (prove it). `set -euo pipefail`; degrade safe.
- Idempotent + crash-safe: re-running a tick must NOT double-notify or double-proceed.
- Plan-guard + eligibility re-evaluated at deadline, never cached. Spend cap default 0.
- Append-only for NOTIFICATIONS/DECISIONS (never rewrite/delete prior entries).

## Required tests (per `01_design.md` §7; additive)
notify-once-then-twice-then-(slice3)proceed for a reversible+flag-dark+on-plan item; **never-auto**
holds forever for safety-file / irreversible / cost-over-cap / off-plan even past deadline; owner
DECISIONS entry cancels the timer; plan-guard blocks an off-plan recommendation; **flag-default-OFF =
today byte-identical**; idempotent tick (no double-notify/double-proceed). Use injectable
`MASSOH_AGENT_CMD`/`MASSOH_GATE_CMD` + a fake clock so tests are zero-spend + deterministic.
Run `bash test/run.sh` green.

## Acceptance
1. Slices 0–3 per design; conditions (file:line). 2. Tests green; suite green; paste: flag-OFF
byte-identical proof, the notify→twice→proceed (reversible) trace, a never-auto hold-past-deadline
(safety + cost + off-plan), owner-cancels-timer, idempotent-tick. 3. VERSION 0.28.0 + CHANGELOG.
4. `bin/massoh` + `manifest.yml` diff = 0; `massoh doctor` healthy.

## Routing
`massoh-implementer` (branch `feat/autonomy-decide-or-defer`) → `05_handoff.md` → `massoh-reviewer-qa`
(verify flag-OFF byte-identical + never-auto-class holds past deadline + plan-guard fail-closed +
idempotency + spend-cap + bin/massoh/manifest diff=0) → owner merge (NOT auto-merge — this is the
authority-expansion feature; owner does the final merge).
