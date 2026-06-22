# 01 — Design: autonomy "decide-or-defer" — timed-escalation tier + long-term-plan guard

**Task:** TASK-2026-06-21-autonomy-escalation · **Role:** massoh-system-architect · **DESIGN ONLY**
**Status:** PROPOSED — **needs OWNER SIGN-OFF before any implementation.**

> ⚠️ **SAFETY-BOUNDARY CHANGE.** This feature expands what the autonomous loop may do **unattended**:
> after a grace window with no owner reply, an eligible recommended option may **auto-proceed** with no
> human in the loop. `bin/massoh-cron` is not currently on the NON_NEGOTIABLES safety-critical list, but
> **the autonomy boundary it now encodes should be treated as safety-critical.** This design therefore
> recommends (slice 0) **adding `bin/massoh-cron` to `agent-project/NON_NEGOTIABLES.md` §Designated
> safety-critical files** so future edits to the timed-proceed logic require fresh sign-off. `bin/massoh`
> and `manifest.yml` stay **diff = 0** throughout (the new logic lives entirely in `bin/massoh-cron` +
> new lib/data files). **Nothing in this design ships until the owner signs off.**

---

## 0. Anchors verified against the real code

| Fact | Where (verified) |
|---|---|
| The idle gate | `bin/massoh-cron:50-56` (`owner_active()`), called at `:95`. |
| Config read pattern to mirror | `bin/massoh-cron:21` — `massoh_config_get … cron_idle_min "25"` + `case` integer-validate; helper at `lib/verbs/_config.sh:26`. |
| Parent-only serialization (sole writer of backlog/sync, sole merger) | `bin/massoh-cron:128-149`. |
| Cadence-state precedent (tick-driven counter, corruption-tolerant, persisted to a state file) | `bin/massoh-cron:157-184` (`.agent_tasks/cron/cadence_state`). |
| Owner-gated action set (§B) to reuse verbatim for eligibility | `policies/09_GUARDRAILS.md:26-37`. |
| Append-only / keep-older-data invariant | `policies/09_GUARDRAILS.md:13-14`; `NON_NEGOTIABLES.md:26-30`. |
| **There is NO "decision-needs-owner" code path in the runner today.** The doc's "step 5 escalate" lives *inside* the worktree agent, which just leaves a PR open + a note. | `bin/massoh-cron` has zero `escalat\|awaiting\|notify\|decision` matches; `docs/AUTONOMOUS_CRON.md:18-21` is the conceptual contract. |

**Consequence:** the escalation tier is a **new subsystem in the parent process**, not a tweak to an
existing branch. It needs (a) a queue of pending owner-gated decisions, (b) a pre-tick evaluator, and
(c) a hook in the parent serialization loop where a worker reports "this item needs an owner decision".

---

## 1. Escalation state machine (the per-item lifecycle)

Tick-driven, no daemon. Each pending decision is one append-only record in a **decision queue file**
(see §4). State is **derived on each idle tick** by comparing the record's stored fields to `now`; the
tick is the only clock. The machine:

```
                          (worker reports an owner-gated decision on item X,
                           OR architect classifies a backlog decision as owner-gated)
                                            │
                                            ▼
   ┌──────────────────────── DECISION_NEEDED ───────────────────────┐
   │  classify eligibility (§5) + plan-guard (§2); compute deadline  │
   └────────────────────────────┬──────────┬────────────────────────┘
                                 │          │
              eligible+on-plan   │          │  ineligible (never-auto class)  OR  off-plan/untraceable
                                 ▼          ▼
                         AWAITING_OWNER   HELD_BLOCKED ──────────────► (escalate to architect;
                         (deadline=now+grace)   │                       notify #1 once, status=HELD;
                                 │              │                       NEVER auto-proceeds; stays until
        ── on each later idle tick ──          │                       owner records a decision)
                                 ▼              │
         notices_sent < notify_count           │
            & now < deadline?                   │
                 │ yes → emit next notice (#1 then #2), idempotently
                 │       (one notice per (id, level); never re-emit a level)
                 ▼
         now >= deadline  AND  notices_sent == notify_count?
                 │ yes
                 ▼
            re-check eligibility (§5) + plan-guard (§2) AT DEADLINE   ← guards re-run, never cached
                 │
       eligible+on-plan ──► PROCEED  (take recommended option; record
                 │          "auto-proceeded after grace, no owner reply"; close record)
       otherwise ────────► HELD_BLOCKED  (degrade safely; keep escalated; keep notice open)

   ── at ANY tick, in ANY non-terminal state ──
   owner recorded a decision for this id (§4)?  ─yes─► RESOLVED_BY_OWNER
                                                       (timer cancelled; apply owner's verdict;
                                                        close record; no further notices)
```

**States (exact names, stored in the record's `state` field):**
`DECISION_NEEDED` → `AWAITING_OWNER` → (`PROCEED` | `HELD_BLOCKED`) ; plus `RESOLVED_BY_OWNER`
(reachable from any non-terminal state). `PROCEED`, `HELD_BLOCKED` after final, and `RESOLVED_BY_OWNER`
are terminal-for-this-record (a record is closed by appending a closing line — see §4 append-only rule).

**In 3-4 sentences:** A decision that needs the owner is appended to a queue with a deadline of
`now + cron_grace_min`; on each idle tick the loop emits at most `cron_notify_count` notices (default 2,
one per escalation level, idempotently) and checks whether the owner has recorded an answer keyed to the
record id. If the owner answered, the timer is cancelled and the owner's verdict applied
(`RESOLVED_BY_OWNER`). If the deadline passes with no answer, the eligibility classifier and plan-guard
are **re-evaluated at the deadline** — only a **reversible + flag-dark + on-plan** option may `PROCEED`;
everything in the never-auto class (§5) or anything off-plan stays `HELD_BLOCKED` forever, escalated and
notified, until the owner acts.

---

## 2. Long-term-plan guard

**Run before proceeding with ANY recommended option — attended path AND timed path.** If the recommended
option is not traceable to the chosen plan anchor, **do not proceed → `HELD_BLOCKED` + escalate**.

**Chosen canonical anchor: `agent-project/PRODUCT_STRATEGY.md` §North-star.** Justification:

- It is **in-repo** (the request bars the owner's private north-star memory, which is not in the repo).
- It is the **stable, decision-grade** statement of direction: "decided 2026-06-17", explicitly the goal
  + the moat + the roadmap (`PRODUCT_STRATEGY.md:1-21`). `CHARTER.md` North-star *defers to it*
  ("See `PRODUCT_STRATEGY.md` §North-star", `CHARTER.md:14`), and `AGENT_SYNC.md` §Current strategic mode
  is a **rolling, frequently-rewritten dashboard line** (it changes almost every session) — too volatile
  to be the traceability spine. Anchoring the guard to the most-edited file would make the guard's verdict
  non-deterministic across ticks. PRODUCT_STRATEGY §North-star is the right granularity: durable enough to
  be a contract, specific enough to reject off-plan work.
- **Tie-in to existing capability:** Massoh already ships requirements-traceability (RMT, PR #25/#26).
  The plan-guard reuses that posture: a recommended option is "on-plan" if it is traceable to the anchor.

**Predicate `on_plan(item, recommended_option)` (concrete, conservative, no LLM in the runner):**
The runner cannot semantically judge plans, so the guard is a **traceability assertion the proposer must
supply**, checked mechanically:

1. The decision record (§4) MUST carry a non-empty `plan_ref` field — a literal anchor reference of the
   form `PRODUCT_STRATEGY.md#north-star` (the canonical anchor) **plus** a one-line `plan_rationale`
   ("how this option advances the north-star").
2. The runner verifies, with `grep`-guarded `|| true`: (a) `plan_ref` names the canonical anchor file +
   section that **exists** (the `## North-star / global goal` heading is present in
   `agent-project/PRODUCT_STRATEGY.md`); (b) `plan_rationale` is non-empty. **Missing/empty/anchor-not-
   found ⇒ off-plan ⇒ `HELD_BLOCKED`** (fail-closed).
3. The **architect** (who classifies the decision and writes the record) is responsible for the semantic
   judgement that the option genuinely advances the north-star; the runner enforces that the judgement was
   *recorded and points at the real anchor*. This keeps the loop deterministic (no model call mid-tick)
   while making "off-plan ⇒ never auto-proceed" structurally enforced.

**Why fail-closed:** an untraceable recommendation is exactly the case the owner most wants to review.
Defaulting off-plan→hold means a sloppy/empty `plan_ref` can never silently auto-proceed.

---

## 3. Notification format — `NOTIFICATIONS.md` (append-only, no spam)

**Sink (OWNER-LOCKED):** repo-root `NOTIFICATIONS.md`, append-only, **plus** one `[escalation]`-tagged
line into `AGENT_SYNC.md` per notice (so it surfaces on the existing dashboard scan, alongside `[cron]`).
Zero new deps, zero network — matches Massoh posture.

**Rule: exactly `cron_notify_count` (default 2) notices per record, one per escalation level, then
proceed-or-hold. Never re-emit a level (idempotency, §6).** One entry per `(id, level)`.

**Schema — one Markdown block appended per notice:**

```markdown
## NOTIF <notif_id>                          <!-- notif_id = <decision_id>#L<level>, e.g. AESC-20260621T1430Z-3f2a#L1 -->
- decision_id: AESC-20260621T1430Z-3f2a      <!-- stable per decision; ties all levels + the answer -->
- level: 1                                    <!-- 1 = first notice, 2 = second/final notice -->
- ts: 2026-06-21T14:30:00Z                    <!-- UTC ISO-8601, when this notice was emitted -->
- item: "<backlog item text>"                 <!-- the AGENT_BACKLOG row this decision is for -->
- decision: "<one-line: what must be decided>"
- recommended: "<the architect's recommended option>"
- eligibility: reversible+flag-dark | NEVER-AUTO(<reason: safety-file|irreversible|cost|prod-deploy>)
- plan_ref: PRODUCT_STRATEGY.md#north-star
- deadline: 2026-06-21T16:30:00Z              <!-- = decision-open ts + cron_grace_min -->
- on_grace_expiry: AUTO-PROCEED | HOLD-FOREVER   <!-- derived from eligibility+on_plan; owner sees the consequence -->
- status: AWAITING_OWNER
- answer_how: "append a row to DECISIONS.md keyed by decision_id (see header)"
```

The file carries a fixed top-of-file header (written create-if-missing) explaining how to answer. Notices
are **append-only** — status transitions (e.g. to `PROCEEDED`/`HELD`/`RESOLVED_BY_OWNER`) are recorded by
**appending a new closing block** `## NOTIF <decision_id>#CLOSE` with the final status + reason, never by
editing an existing block (keep-older-data, `09_GUARDRAILS.md:13-14`).

---

## 4. Owner-answer detection — `DECISIONS.md` (append-only, unambiguous)

**How a tick knows the owner answered THIS decision:** the owner appends a row to a new repo-root,
append-only **`DECISIONS.md`**, keyed by `decision_id`. (A dedicated file, not the AGENT_SYNC decision
log, so the runner can parse it deterministically and the owner's answer is unambiguous and greppable.)

**Schema — append-only table; the runner reads it `|| true`:**

```markdown
# DECISIONS.md — owner answers to autonomous-escalation notices (append-only; never edit/delete a row)
| decision_id | verdict | note | ts | by |
|---|---|---|---|---|
| AESC-20260621T1430Z-3f2a | APPROVE | go with the recommended option | 2026-06-21T15:05Z | owner |
| AESC-20260621T1612Z-9c1b | REJECT  | not now — revisit after fleet ships | 2026-06-21T16:20Z | owner |
| AESC-20260621T1709Z-77de | DEFER   | park; needs design first | 2026-06-21T17:30Z | owner |
```

- **`verdict ∈ {APPROVE, REJECT, DEFER}`.** APPROVE ⇒ apply the recommended option (architect/implementer
  picks it up next attended tick — the runner does NOT auto-build on APPROVE in v1; it records
  `RESOLVED_BY_OWNER:APPROVE` and lets the normal gated flow build it). REJECT/DEFER ⇒ close the record,
  drop it from the queue, leave the backlog item BLOCKED with the owner's note.
- **Detection on a tick:** a record is "answered" iff `DECISIONS.md` contains a row whose `decision_id`
  exactly matches **and** whose `ts` is **at or after** the decision-open ts (a later row supersedes;
  read the **last** matching row, mirroring `_config.sh`'s "duplicate keys → predictable" stance, but
  here last-wins so the owner can change their mind by appending).
- **"Owner override cancels the timer":** the mere presence of a matching post-open row ⇒
  `RESOLVED_BY_OWNER` regardless of how close the deadline is. Owner action always wins over the clock.
- **Unforgeable-enough:** `decision_id` embeds the open-timestamp (`AESC-<UTC>-<4hex>`); only the runner
  mints ids (into `NOTIFICATIONS.md`), so a stray/guessed id in DECISIONS.md won't match an open record.
  `by` is informational (single-user local tool, per `09_GUARDRAILS §C` posture). Append-only + git
  history is the audit trail.

---

## 5. Eligibility classifier (reuse `09_GUARDRAILS.md §B`)

`eligible_to_auto_proceed(decision) = reversible(decision) AND flag_dark(decision) AND NOT never_auto(decision)`

**`never_auto(decision)` — TRUE if ANY (the §B owner-gated set, `09_GUARDRAILS.md:26-37`, verbatim):**

1. **Safety-critical-file/policy change** — the recommended option would touch any path designated in
   `agent-project/NON_NEGOTIABLES.md §Designated safety-critical files` (currently `bin/massoh`,
   `manifest.yml`, the `<!-- massoh:start/end -->` block + `templates/CLAUDE.global-block.md`,
   `templates/CLAUDE.project.template.md`) **and, per slice 0, `bin/massoh-cron` itself**.
2. **Irreversible / destructive op** — data deletion, production-data mutation, force-push, history
   rewrite, dropping a column/table without expand→contract.
3. **Production deploy** to a real-user environment (ship via PR; the deploy is owner-run).
4. **Significant cost** — paid API spend / infra spin-up / quota purchase **above the spend threshold**.
5. **Unfreezing** a `AGENT_SYNC.md §Frozen` feature.

**`reversible` + `flag_dark`** (must BOTH be asserted in the record, fail-closed if absent):
the option is **additive + behind a default-OFF flag** (or otherwise no-behavior-change for existing
users) **and** has a stated one-step rollback (revert the PR / flip the flag). This is the same bar the
loop already uses for auto-merge (`docs/AUTONOMOUS_CRON.md:22-23`, `09_GUARDRAILS §E`).

**Paid-spend threshold (concrete): `cron_spend_cap_usd`, default `0` (USD).** Default `0` means **any
non-zero paid spend is never-auto** — the safest default for an unattended loop, and it matches today's
posture (cron's only paid action, `claude -p`, is already owner-gated by the `--run` flag). The owner may
raise it (e.g. `5`) in `config.yml` to let small, bounded spends auto-proceed. The recommended option's
record carries an `est_spend_usd` field; `never_auto` rule 4 fires when `est_spend_usd > cron_spend_cap_usd`.
**Any record lacking a numeric `est_spend_usd` is treated as over-cap (fail-closed).**

**Classifier is re-run AT THE DEADLINE, never cached** (state-machine §1): if circumstances changed
between open and deadline (e.g. the option now touches a safety file), the deadline re-check catches it.

---

## 6. Config + flag

**New keys in `agent-project/config.yml`** (parsed exactly like `cron_idle_min`, `bin/massoh-cron:21` —
`massoh_config_get` + `case` integer-validate, malformed → default; mirror that line per key):

| Key | Default | Validate | Meaning |
|---|---|---|---|
| `cron_decide_or_defer` | `off` | `on`/`off` only; anything else → `off` | **MASTER FLAG. Default OFF.** Whole timed-proceed subsystem. |
| `cron_grace_min` | `120` | integer ≥ 1; malformed → `120` | Grace window (minutes) before timed proceed-or-hold. |
| `cron_notify_count` | `2` | integer in 1..2; malformed/out-of-range → `2` | Notices before proceed-or-hold. |
| `cron_spend_cap_usd` | `0` | non-negative integer; malformed → `0` | Max auto-proceed paid spend (§5 rule 4). |

**Flag default OFF = today's behavior byte-identical.** The entire subsystem is wrapped so control never
enters it when off:

- A **single early guard** reads `cron_decide_or_defer`; when `off`, the new pre-tick evaluator returns
  immediately and the parent serialization loop runs the **unchanged** path. No `NOTIFICATIONS.md`/
  `DECISIONS.md`/decision-queue file is created, no new lines are written. The diff is **purely additive
  blocks gated behind `if [ "$DECIDE_OR_DEFER" = on ]`** — with the flag off, output is identical to
  v0.27.0 (the byte-identical test, §7, asserts this against a captured baseline).

**Where it hooks in `bin/massoh-cron` (anchors):**

- **Config read:** new lines immediately after `:21` (same idiom), one per key above.
- **Pre-tick decision evaluator** (`evaluate_pending_decisions()`): called once at the top of `cmd_once`,
  **after** the idle gate at `:95` and **before** the worktree fan-out at `:97`. It walks the decision
  queue, emits due notices, applies owner answers, and proceeds/holds at deadline. Guarded by the master
  flag; returns immediately when off. (Tick-driven clock: it compares stored `deadline` to `date +%s`,
  exactly like the cadence counter at `:157-184` — no daemon.)
- **Worker→parent "needs owner decision" channel:** extend the worker result contract
  (`work_item()` writes a `.result`, `:78-79`) with an optional `status=needs-decision` plus
  `decision=…`/`recommended=…`/`eligibility=…`/`plan_ref=…`/`est_spend_usd=…` lines. In the parent
  serialization loop (`:132-147`), a `needs-decision` result **appends a new record to the decision
  queue** (instead of `mark_done`) — fully inside the existing parent-only-writer section.
- **Decision queue file:** `.agent_tasks/cron/decisions.queue` (append-only, one record/line, mirrors the
  `cadence_state`/`.result` convention under `.agent_tasks/cron/`). The runner's view is derived from this
  file + `DECISIONS.md` each tick.

**Idempotency / crash-safety:**
- **No double-notify:** a notice for `(decision_id, level)` is emitted only if `NOTIFICATIONS.md` does not
  already contain `## NOTIF <decision_id>#L<level>` (grep-guard before append). Re-running the same tick
  finds the marker and skips.
- **No double-proceed:** before `PROCEED`, check `NOTIFICATIONS.md` for a `#CLOSE` block for that
  `decision_id`; if present, skip. The PROCEED action itself is "record `RESOLVED`/branch the
  recommendation" — writing the `#CLOSE` block is the commit point; a crash before it ⇒ retried next tick
  (at-least-once with a dedupe marker = effectively-once).
- **Append-only everywhere** (NOTIFICATIONS, DECISIONS, decisions.queue closing lines, AGENT_SYNC) ⇒ a
  half-written tick never corrupts prior state; the next tick re-derives.

---

## 7. Tests (specify, don't write — extend `test/run.sh`, all injectable/zero-cost)

Use existing injection (`NO_IDLE=1`, `MASSOH_AGENT_CMD`/`MASSOH_GATE_CMD` fakes, ephemeral `$REPO`).
All run offline, no `claude -p` spend.

| ID | Name | Asserts |
|---|---|---|
| T-AE-a | **flag default OFF = byte-identical** | With `cron_decide_or_defer` unset/off, `massoh cron once` output + side-effects md5-identical to a captured v0.27.0 baseline; `NOTIFICATIONS.md`/`DECISIONS.md`/`decisions.queue` are NOT created. (The single most important safety test.) |
| T-AE-b | **notify→twice→proceed (reversible)** | Flag on; a reversible+flag-dark+on-plan decision: tick 1 emits NOTIF `#L1`; tick 2 (still unanswered, < deadline) emits `#L2`; tick after `deadline` (no DECISIONS row) ⇒ `PROCEED` + `#CLOSE status=PROCEEDED`, exactly 2 NOTIF level blocks (no 3rd). |
| T-AE-c | **never-auto past deadline — safety file** | Decision whose `recommended` touches `bin/massoh`: even with `now > deadline`, stays `HELD_BLOCKED`; `#CLOSE status=HELD reason=safety-file`; backlog item NOT marked done; no branch created. |
| T-AE-d | **never-auto past deadline — irreversible** | `eligibility=NEVER-AUTO(irreversible)` ⇒ HELD past deadline (same assertions as T-AE-c). |
| T-AE-e | **never-auto past deadline — cost over cap** | `est_spend_usd=3`, `cron_spend_cap_usd=0` ⇒ HELD; then `cron_spend_cap_usd=5` ⇒ eligible (proceeds) — proves the threshold is live. Also: missing `est_spend_usd` ⇒ HELD (fail-closed). |
| T-AE-f | **owner-decision-cancels-timer** | Append `APPROVE` row to `DECISIONS.md` for the id **before** deadline ⇒ next tick = `RESOLVED_BY_OWNER`, no `#L2` emitted, no auto-proceed; `REJECT`/`DEFER` ⇒ record closed, item left BLOCKED with note. Also: owner row dated **before** the open ts does NOT count (ts-after rule). |
| T-AE-g | **plan-guard blocks off-plan** | Decision with empty/missing `plan_ref` (or anchor that doesn't exist) ⇒ HELD even though reversible+flag-dark+past-deadline; `#CLOSE reason=off-plan`. Valid `plan_ref=PRODUCT_STRATEGY.md#north-star` + non-empty rationale ⇒ allowed. |
| T-AE-h | **idempotent tick (no double-notify / no double-proceed)** | Run the identical tick twice at each stage: no second `#L1`/`#L2` block; after a PROCEED, a re-run does not re-proceed (CLOSE marker honored); md5 of NOTIFICATIONS stable across the duplicate run. |
| T-AE-i | **AGENT_SYNC `[escalation]` line emitted** | Each notice appends exactly one `[escalation]`-tagged line to `AGENT_SYNC.md`; append-only (prior content unchanged). |
| T-AE-j | **crash-safety** | Kill the tick (simulate) after queue-append but before notice; next tick emits `#L1` exactly once (no loss, no dup). |

Target: existing 685 + ~10 new T-AE checks (plus per-check sub-assertions). Every test exercises the
**real** `evaluate_pending_decisions()` path, not a stub (lesson of record, `09_GUARDRAILS.md:17-18`).

---

## 8. Sliced build order (each with its OWNER SIGN-OFF point)

> **Global gate:** the *whole feature* needs **OWNER SIGN-OFF on this design (§ all)** before slice 0,
> because it expands unattended authority. Per-slice arch-safety + reviewer-qa + green suite still apply.

| Slice | Scope | Reversible? | **OWNER SIGN-OFF needed** |
|---|---|---|---|
| **0. Boundary designation** | Add `bin/massoh-cron` to `NON_NEGOTIABLES.md §Designated safety-critical files`; add a `## Autonomy boundary` note that timed-proceed is owner-gated. **Markdown only.** | yes | **SIGN-OFF #1** — accept the design + treat the autonomy boundary as safety-critical. Edits `NON_NEGOTIABLES.md` (itself safety-critical) ⇒ explicit owner sign-off required. |
| **1. Config + flag (default OFF), no behavior** | Add the 4 keys to `agent-project/config.yml` + parse them in `bin/massoh-cron` (mirror `:21`). Master flag wired but the evaluator is a no-op stub returning immediately. **Byte-identical when off (T-AE-a).** | yes | Covered by SIGN-OFF #1 (config + cron parsing only; flag-dark; no new authority yet). |
| **2. Notify + owner-answer (NO auto-proceed yet)** | Decision queue + `NOTIFICATIONS.md` + `DECISIONS.md` + `evaluate_pending_decisions()` that emits ≤2 notices, detects owner answers, and **at deadline only HOLDS** (no PROCEED branch yet). Plan-guard + classifier implemented but only used to *label* `on_grace_expiry`. T-AE-a/f/g/h/i/j. | yes (notices are just files) | Covered by SIGN-OFF #1 — this slice still **never auto-acts**; it only notifies + records. Safe to run unattended. |
| **3. Timed auto-proceed (the actual authority expansion)** | Enable the `PROCEED` transition for `eligible+on-plan` at deadline. T-AE-b/c/d/e + re-run h. **This is the slice that lets the loop act without a human.** | yes (revert PR; flip flag off; flag default OFF ⇒ opt-in) | **SIGN-OFF #2 — explicit, separate.** Do NOT enable slice 3 under SIGN-OFF #1. The owner must confirm the eligibility predicate (§5), the spend cap default (`0`), and the plan anchor (§2) before any unattended auto-proceed is allowed. |

**Recommended path:** ship 0→1→2 under SIGN-OFF #1 (pure notification + governance, no new authority),
let the owner watch a few real notify-cycles, then take SIGN-OFF #2 to flip on slice 3. This is the most
reversible sequence: the loop becomes *more transparent* before it becomes *more autonomous*.

---

## 9. What stays untouched (hard constraints honored)

- `bin/massoh` + `manifest.yml`: **diff = 0** (all logic is in `bin/massoh-cron` + new lib/data files;
  no new verb, no manifest entry — `bin/massoh-cron` is already invoked via the existing `cron` path).
- Keep-older-data: NOTIFICATIONS / DECISIONS / decisions.queue / AGENT_SYNC are **append-only**; status
  changes are new closing blocks, never edits.
- No new network, no new runtime deps (pure bash + the existing `_config.sh` parser).
- Flag default OFF ⇒ existing users unaffected (`09_GUARDRAILS.md:14-16`, `NON_NEGOTIABLES.md:33-34`).
- Owner-gated set (`09_GUARDRAILS §B`) reused verbatim as the never-auto class — no new policy invented.

---

## 10. Decision record (architect)

- **DECISION:** Approve the design as specified; **recommend** building it in the 0→1→2 (SIGN-OFF #1) then
  3 (SIGN-OFF #2) order. This is reversible (flag default OFF, additive, PR-revertable) and stays inside
  every guardrail — but because it **expands unattended authority**, it is **owner-gated** and is being
  surfaced for sign-off rather than auto-proceeded (correct application of `09_GUARDRAILS §B`).
- **Plan anchor chosen:** `PRODUCT_STRATEGY.md#north-star` (durable, decision-grade, in-repo; CHARTER
  defers to it, AGENT_SYNC is too volatile).
- **Spend cap default:** `0` USD (fail-closed; matches today's "paid spend is owner-gated" posture).
- **NEXT:** owner reviews → SIGN-OFF #1 (slices 0-2) and/or SIGN-OFF #2 (slice 3) → route to
  `massoh-architecture-safety` for the per-slice conditions, then `massoh-implementer`.
