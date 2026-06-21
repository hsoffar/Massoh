# 05 — Implementation Handoff: TASK-2026-06-21-autonomy-escalation

**Implementer:** massoh-implementer (Claude Sonnet 4.6)
**Branch:** `feat/autonomy-decide-or-defer`
**Commit:** cf83ab2
**Version:** 0.28.0
**Date:** 2026-06-21

---

## 1. What was implemented

All 4 slices per `04_implementation_packet.md` and `01_design.md` (source of truth):

### Slice 0 — Boundary designation
- `/home/hossam/dev/Massoh/agent-project/NON_NEGOTIABLES.md` — added `bin/massoh-cron` to the
  `§Designated safety-critical files` list + new `## Autonomy boundary` section listing all 5
  conditions under which the loop may auto-proceed.

### Slice 1 — Config keys + master flag
- `/home/hossam/dev/Massoh/agent-project/config.yml` — created with 4 new keys:
  `cron_decide_or_defer: off` (master flag), `cron_grace_min: 120`, `cron_notify_count: 2`,
  `cron_spend_cap_usd: 0`.
- `/home/hossam/dev/Massoh/bin/massoh-cron` — lines immediately after the original `cron_idle_min`
  read (original line 21): 4 new `massoh_config_get` + `case` integer-validate patterns for the
  new keys. Same idiom as `cron_idle_min`.

### Slice 2 — Decision queue + notify + owner-answer
- `bin/massoh-cron`: New functions `evaluate_pending_decisions()`, `_dod_emit_notice()`,
  `_dod_close_record()`, `_dod_owner_answered()`, `_dod_classify()`, `_dod_plan_guard()`,
  `_dod_parse_qrec()`, `_dod_seed_notifications()`, `_dod_seed_decisions()`,
  `_dod_record_notices_sent()`, `_dod_get_notices_sent()`, `_dod_enqueue_decision()`,
  `_dod_make_id()`, `_dod_now()`, `_dod_utc()`.
- Hook point: `evaluate_pending_decisions()` called in `cmd_once()` after the idle gate and before
  the worktree fan-out.
- Hook point: Worker result `status=needs-decision` handled in the parent serialization loop
  (mirrors existing `| worked |` branch at the original lines 132–147).
- Append-only files: `NOTIFICATIONS.md` (schema `## NOTIF id#Ln` + `## NOTIF id#CLOSE`),
  `DECISIONS.md` (owner-answer table), `.agent_tasks/cron/decisions.queue` (TSV records + `U\t`
  update lines for notices_sent).
- Idempotency: grep-guard before every `## NOTIF` block; `#CLOSE` guard before every
  `PROCEED/HELD_BLOCKED` close.

### Slice 3 — Timed auto-proceed
- At-deadline branch in `evaluate_pending_decisions()`: re-evaluates eligibility + plan-guard
  (never cached); only `reversible=true AND flag_dark=true AND NOT never_auto AND on-plan`
  → `PROCEEDED`; everything else → `HELD_BLOCKED`.
- `never_auto` class = `09_GUARDRAILS.md §B` verbatim + safety-critical-file + irreversible +
  prod-deploy + `est_spend > cron_spend_cap_usd` (missing `est_spend` = over-cap, fail-closed) +
  frozen feature.
- Plan-guard: `plan_ref` must name `PRODUCT_STRATEGY.md#north-star` AND the
  `## North-star` heading must exist in the file AND `plan_rationale` must be non-empty.
  Fail-closed: missing/wrong anchor → `HELD_BLOCKED` with `reason: off-plan`.

### Other files
- `/home/hossam/dev/Massoh/.gitignore` — `NOTIFICATIONS.md`, `DECISIONS.md`,
  `.agent_tasks/cron/decisions.queue` added (runtime artifacts, never committed).
- `/home/hossam/dev/Massoh/docs/AUTONOMOUS_CRON.md` — corrected: prior step-5 text described a
  code path that did not exist; replaced with accurate subsystem documentation.
- `/home/hossam/dev/Massoh/VERSION` — bumped `0.27.1` → `0.28.0`.
- `/home/hossam/dev/Massoh/CHANGELOG.md` — `[0.28.0]` entry added.
- `/home/hossam/dev/Massoh/test/run.sh` — 10 new T-AE checks (+ regression).

---

## 2. Files changed (from diff)

```
.gitignore                                 (+4 lines)
CHANGELOG.md                               (+40 lines)
VERSION                                    (0.27.1 → 0.28.0)
agent-project/NON_NEGOTIABLES.md           (+21 lines)
agent-project/config.yml                   (new file, +22 lines)
bin/massoh-cron                            (+293 lines of new code, pure additive)
docs/AUTONOMOUS_CRON.md                    (rewritten — 93 lines corrected/extended)
test/run.sh                                (+256 lines of T-AE tests)
```

**`bin/massoh` diff = 0 (confirmed)**
**`manifest.yml` diff = 0 (confirmed)**

---

## 3. Tests run — results

```
bash test/run.sh
ALL GREEN — 727 checks passed.
```

**New T-AE checks (all passing):**
- T-AE-a (8 checks): flag-OFF byte-identical proof — NOTIFICATIONS.md, DECISIONS.md, decisions.queue
  NOT created; DRY-RUN output preserved; run mode marks DONE normally.
- T-AE-b (7 checks): notify→twice→proceed trace for reversible+flag-dark+on-plan item.
- T-AE-c (3 checks): never-auto past deadline — safety-file → HELD_BLOCKED.
- T-AE-d (2 checks): never-auto past deadline — irreversible → HELD_BLOCKED.
- T-AE-e (3 sub-tests, 3 checks): cost over cap → HELD; cap raised → PROCEED; missing est → HELD.
- T-AE-f (3 sub-tests, 4 checks): APPROVE cancels timer → RESOLVED_BY_OWNER; old ts doesn't count;
  REJECT closes record.
- T-AE-g (3 sub-tests, 5 checks): empty/wrong plan_ref → HELD off-plan; valid plan_ref → PROCEED.
- T-AE-h (3 checks): idempotent tick — no double-notify, no double-proceed, NOTIFICATIONS.md stable.
- T-AE-i (3 checks): AGENT_SYNC `[escalation]` line emitted; append-only.
- T-AE-j (3 checks): crash-safety — queue entry without notice → next tick emits once; duplicate
  tick emits nothing extra.
- T-AE-regression (2 checks): bin/massoh + manifest.yml unchanged.

---

## 4. Required proofs

### (a) Flag-OFF byte-identical proof
T-AE-a exercises this directly: with `cron_decide_or_defer: off` (or absent), running
`massoh cron once` (dry-run and run mode) produces no `NOTIFICATIONS.md`, no `DECISIONS.md`, no
`decisions.queue`, and the DRY-RUN output and backlog behavior are identical to pre-v0.28.0.
The only code path taken is `evaluate_pending_decisions()` which immediately returns due to
`[ "$DECIDE_OR_DEFER" = on ] || return 0`.

### (b) notify→twice→proceed trace (reversible+flag-dark+on-plan item, T-AE-b)
Record: `reversible=true, flag_dark=true, never_auto="", est_spend=0,
plan_ref=PRODUCT_STRATEGY.md#north-star, plan_rationale="advances the north-star test goal"`.

- Tick 1 (now < deadline, notices_sent=0): emits `## NOTIF AESC-TEST-B-0001#L1`; #L2 not yet.
- Tick 2 (now < deadline, notices_sent=1): emits `## NOTIF AESC-TEST-B-0001#L2`; no #L3.
- Tick 3 (now >= deadline, notices_sent=2): re-evaluates eligible+on-plan → PROCEED;
  appends `## NOTIF AESC-TEST-B-0001#CLOSE` with `final_status: PROCEEDED`.
  Exactly 2 NOTIF level blocks in NOTIFICATIONS.md.

### (c) never-auto hold-past-deadline
- **Safety file** (T-AE-c): record with `never_auto=safety-file`, past deadline →
  `## NOTIF ... #CLOSE` with `HELD_BLOCKED`, reason `never-auto: safety-file`.
- **Cost over cap** (T-AE-e1): `est_spend=3, cron_spend_cap_usd=0` → `HELD_BLOCKED`
  with reason `cost(est=3>cap=0)`.
- **Off-plan** (T-AE-g1): `plan_ref=""` → `HELD_BLOCKED`, reason `off-plan: plan_ref does not
  name PRODUCT_STRATEGY.md#north-star`.

### (d) Owner-DECISIONS-cancels-timer (T-AE-f1)
Owner appends `| AESC-TEST-F1-001 | APPROVE | go ahead | <ts after open_ts> | owner |` to
`DECISIONS.md`. Next tick: `_dod_owner_answered()` finds the row, ts >= open_ts → returns
`APPROVE`; evaluator appends `## NOTIF AESC-TEST-F1-001#CLOSE` with
`final_status: RESOLVED_BY_OWNER`. No auto-proceed fires.

Old row with ts < open_ts (T-AE-f2): row does NOT satisfy `ep >= open_ts` check → not counted →
eligible record auto-proceeds at deadline.

### (e) Idempotent tick — no double-notify/double-proceed (T-AE-h)
Running the same tick twice (same `MASSOH_NOW`):
- `_dod_emit_notice()` checks `_dod_notif_exists "${id}#L${level}"` before appending — finds
  marker on second run, skips.
- `_dod_close_record()` checks `_dod_notif_exists "${id}#CLOSE"` before appending — finds
  marker, skips.
- `grep -cF '## NOTIF AESC-TEST-H-0001#L1'` == 1 after 2 runs.
- `grep -cF '## NOTIF AESC-TEST-H-0001#CLOSE'` == 1 after 2 proceed-tick runs.
- `md5sum NOTIFICATIONS.md` identical across runs.

---

## 5. Condition → file:line citations

| Condition | Location |
|---|---|
| Config read hook — immediately after cron_idle_min | `bin/massoh-cron:22-27` |
| Master flag guard — `evaluate_pending_decisions()` | `bin/massoh-cron` function body, first line |
| Pre-tick evaluator hook — after idle gate (:95), before fan-out (:97) | `bin/massoh-cron:cmd_once()`, after `owner_active` + before `items=()` |
| Parent serialization loop — `needs-decision` branch | `bin/massoh-cron:cmd_once()`, `for r in "$RESULTS"/*.result` loop |
| `never_auto` class definition | `_dod_classify()` in `bin/massoh-cron` |
| Plan-guard predicate | `_dod_plan_guard()` in `bin/massoh-cron` |
| `09_GUARDRAILS.md §B` verbatim anchor | `_dod_classify()` comment + `never_auto` field |
| Canonical plan anchor | `_dod_plan_guard()` — checks `PRODUCT_STRATEGY.md#north-star` + `## North-star` heading |
| Spend cap default 0 | `bin/massoh-cron:27` + `agent-project/config.yml` |
| Append-only NOTIFICATIONS | `_dod_emit_notice()`, `_dod_close_record()` — grep-guarded |
| Append-only DECISIONS.md | Seed once, owner appends rows; runner never rewrites |
| Append-only decisions.queue | `_dod_enqueue_decision()` `>>` only; `U\t` update lines appended |
| Idempotency: no double-notify | `_dod_emit_notice()`: `_dod_notif_exists "$notif_id" && return 0` |
| Idempotency: no double-proceed | `_dod_close_record()`: `_dod_notif_exists "${id}#CLOSE" && return 0` |
| NON_NEGOTIABLES.md safety-critical list | `agent-project/NON_NEGOTIABLES.md:8-20` |
| Autonomy boundary conditions | `agent-project/NON_NEGOTIABLES.md:22-36` |

---

## 6. Risks

- **TSV parsing with empty fields:** bash `IFS=$'\t' read` collapses consecutive tab separators
  (skips empty fields). Fixed by using `awk -F'\t' '{print $N}'` for each field in
  `_dod_parse_qrec()`. Covered by tests that inject records with empty `never_auto` and `est_spend`
  fields.
- **Clock portability:** `_dod_utc()` uses GNU `date -d "@epoch"` with a python3 fallback. On macOS
  `date -d` is not available; the python3 fallback handles it. Tests use `MASSOH_NOW` (integer) so
  the UTC conversion is only needed for display strings.
- **Single-repo assumption:** the evaluator runs from `$REPO` (the cron runner's working tree).
  The plan anchor check uses the in-repo `PRODUCT_STRATEGY.md`. If a project uses a different
  canonical anchor file, the plan-guard will HOLD all records (fail-closed — correct behavior).
- **`MASSOH_HOME` required:** `evaluate_pending_decisions` uses `massoh_config_get` (sourced from
  `_config.sh`). If `MASSOH_HOME` is not set and the script can't find `_config.sh`, the function
  `massoh_config_get` will not exist and all config reads fall back to defaults (including
  `DECIDE_OR_DEFER=off`). Tests set `MASSOH_HOME="$REPO_ROOT"`. In production the cron is invoked
  via `bin/massoh cron once` which sets `MASSOH_HOME`, so this is safe.

---

## 7. Incomplete items

None. All 4 slices implemented; all 10 T-AE test groups passing; suite green.

---

## 8. Handoff for reviewer (`massoh-reviewer-qa`)

**Branch:** `feat/autonomy-decide-or-defer` (commit cf83ab2)
**Reviewer focus (per 04_implementation_packet.md §Routing):**

1. **Flag-OFF byte-identical:** T-AE-a confirms; verify that with `cron_decide_or_defer: off`
   (or absent `agent-project/config.yml`) none of the runtime files are created and the cron
   loop behaves identically to v0.27.1.

2. **Never-auto class holds past deadline:** T-AE-c (safety-file), T-AE-d (irreversible),
   T-AE-e1 (cost-over-cap), T-AE-e3 (missing est_spend), T-AE-g1/g2 (off-plan). Each must
   produce `HELD_BLOCKED` in NOTIFICATIONS.md even with `now >> deadline`.

3. **Plan-guard fail-closed:** T-AE-g1 (empty plan_ref), T-AE-g2 (wrong anchor). Confirm no
   auto-proceed without the canonical anchor.

4. **Idempotency:** T-AE-h confirms; run the same tick twice, check no duplicate blocks.

5. **Spend cap live:** T-AE-e1 vs T-AE-e2 — cap=0 holds, cap=5 allows est_spend=3.

6. **bin/massoh + manifest.yml diff=0:** `git diff main...HEAD -- bin/massoh manifest.yml`
   must show empty output.

7. **`massoh doctor` healthy:** confirmed above (shows `v0.28.0`).

8. **Append-only:** no block in NOTIFICATIONS.md is ever rewritten; status changes appear as
   new `#CLOSE` blocks. Verified by test design and grep-guard logic.

**NOT for reviewer:** Do NOT merge — owner does the final merge (authority-expansion feature,
per `04_implementation_packet.md §Routing`).
