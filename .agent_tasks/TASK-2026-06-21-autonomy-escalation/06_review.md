# 06 — Review Result: TASK-2026-06-21-autonomy-escalation (decide-or-defer)

**Reviewer:** massoh-reviewer-qa
**Date:** 2026-06-22
**Branch:** `feat/autonomy-decide-or-defer` (commit cf83ab2)
**Verdict: REQUEST CHANGES**

---

## Summary

Suite: 726/727 green (1 pre-existing T-FLN-6a flake; all 42 T-AE checks PASS).
Flag-OFF: byte-identical CONFIRMED (independently reproduced).
Never-auto class holds past deadline: CONFIRMED for safety-file, cost-over-cap, off-plan.
Genuine eligible PROCEED: CONFIRMED (reversible+flag-dark+on-plan, past deadline).
Plan-guard fail-closed: CONFIRMED (empty plan_ref, wrong anchor).
Owner-cancels-timer: CONFIRMED (RESOLVED_BY_OWNER, no auto-proceed).
Idempotent tick: CONFIRMED by grep-cF count assertion (1 CLOSE after 2 deadline runs).
Scope: CLEAN (bin/massoh + manifest.yml diff = 0; 8 files changed as claimed).
`massoh doctor`: HEALTHY (v0.28.0, `healthy — install matches manifest`).

**One blocking issue (non-safety, test only):** T-AE-h's md5-stability check is a
tautology — it compares the same file to itself in the same expression, so it is always
true and never detects double-appending. This is a test correctness issue, not a product
defect. The real guard (grep-cF CLOSE count = 1) is substantive and does catch double-proceed.
The tautology check must be replaced with a before/after snapshot pattern.

**Zero safety, guardrail, or never-auto blocking issues found.**

---

## 1. Approve / Request Changes / Reject

**REQUEST CHANGES** — 1 blocking issue (BLOCK-1, test only). No product code blockers.
Authority boundary is sound. All safety-critical conditions independently reproduced.
Fast-track re-review permitted after BLOCK-1 fix (single-line test change).

---

## 2. Blocking Issues

### BLOCK-1 — T-AE-h md5-stability check is a tautology (test/run.sh:5586-5587)

**File:** `test/run.sh`, lines 5586-5587.
**Severity:** Test correctness failure — the check passes unconditionally and cannot catch
the regression it claims to catch.

**What the code says:**
```bash
check "T-AE-h deadline x2: NOTIFICATIONS.md stable (md5 identical)" \
  "[ \"$(md5sum '$AEh/NOTIFICATIONS.md' | awk '{print $1}')\" = \"$(md5sum '$AEh/NOTIFICATIONS.md' | awk '{print $1}')\" ]"
```

**Why it is vacuous:**
- The single-quoted `'$AEh/NOTIFICATIONS.md'` is not expanded (the outer `"..."` does not
  expand single-quoted content at the shell level where `$AEh` would be set). The
  `md5sum` invocations are comparing the literal string `$AEh/NOTIFICATIONS.md` against
  itself inside the check function's `eval "..."` — so the check always asserts
  `"X = X"` (same file computed twice in the same eval, trivially true).
- Additionally, line 5578 attempts to capture a baseline md5 before the second run:
  `md5_notif_h="$(md5sum '$AEh/NOTIFICATIONS.md' ...)"` — but again the single-quote
  prevents `$AEh` expansion, so `md5_notif_h` is set to empty string and is never
  referenced in any assertion anyway.

**Why the core safety still holds:** The preceding check on lines 5584-5585
(`grep -cF '## NOTIF ${AEh_ID}#CLOSE' ... -eq 1`) is a real assertion that independently
reproduced: running the deadline tick twice yields exactly 1 CLOSE block — this substantively
verifies no double-proceed. The tautology is the weaker "stability" assertion only.

**How to fix (in test/run.sh):**
Replace lines 5577-5587 with the snapshot-before/snapshot-after pattern used in prior
tests (T8/T13g/T14g). Replace the two vacuous lines with:
```bash
md5_notif_h="$(cd "$AEh" && find . -name NOTIFICATIONS.md -exec md5sum {} \; | awk '{print $1}')"
# [run second tick]
( cd "$AEh" && MASSOH_NOW=$(( AEh_DEADLINE + 1 )) ... ) || true
check "T-AE-h deadline x2: NOTIFICATIONS.md stable (md5 identical)" \
  "[ \"\$(cd '$AEh' && find . -name NOTIFICATIONS.md -exec md5sum {} \\; | awk '{print \$1}')\" = '$md5_notif_h' ]"
```
This follows the exact same pattern as T-DG-1/T8/T13g in the existing suite and would
actually detect double-appending between the two deadline ticks.

---

## 3. Non-Blocking Issues

### NB-1 — CHANGELOG.md states "total suite ≥ 695 checks" (line 40)
The actual total is 727 checks (685 baseline + 42 new T-AE). "≥ 695" is a
conservative undercount. Not incorrect, but could mislead the owner. Fix by stating
"total suite: 727 checks" if a v0.28.0 re-release note is written. Does not affect
behavior.

### NB-2 — T-FLN-6a pre-existing flake (test/run.sh, T-FLN-6a)
Pre-existing timestamp-fragility flake documented in multiple prior review records
(A1, fleet-observability-slice-3). Unrelated to this feature. Non-blocking but
tracking note: this flake will eventually need a fix.

### NB-3 — `dod_id` field not read from worker result file (bin/massoh-cron:608)
When a worker reports `status=needs-decision`, the `dod_id` is freshly minted by
`_dod_make_id()` (correct per spec §4: "only the runner mints ids"). However, if a
future spec ever allows workers to propose a suggested id, the parse loop would need
to add a `dod_id` case. Note for future maintainers: by design, id minting is
parent-only.

### NB-4 — Handoff claims 10 T-AE check groups = 42 checks; CHANGELOG says "≥ 695"
Minor discrepancy in counts. Actual independently counted T-AE assertions: the
grep of check() calls in T-AE section shows 42 checks (a/b/c/d/e1-3/f1-3/g1-3/h/i/j
plus 2 regression). All passing. Non-blocking.

---

## 4. Missing Tests

No materially missing tests. T-AE-a through T-AE-j cover all spec §7 items. The
design requested T-AE-j (crash-safety) and T-AE-h (idempotent) — both present with real
assertions. The md5 check in T-AE-h is vacuous (see BLOCK-1) but the CLOSE-count check
is substantive. After BLOCK-1 is fixed, coverage is complete per spec.

---

## 5. Safety / Guardrail Concerns

None found. All independently verified:

- **Master flag guard** (`bin/massoh-cron:368`): `[ "$DECIDE_OR_DEFER" = on ] || return 0`
  — exits immediately when off. Reproduced: with `cron_decide_or_defer: off`, NOTIFICATIONS.md,
  DECISIONS.md, and decisions.queue are NOT created; DRY-RUN output unchanged.
- **Never-auto class** (`_dod_classify()` in bin/massoh-cron):
  - safety-file: injected `never_auto=safety-file` past deadline → HELD_BLOCKED (reproduced).
  - cost > cap(0): injected `est_spend=3, cap=0` → HELD_BLOCKED (reproduced).
  - missing est_spend: T-AE-e3 passes (HELD_BLOCKED, fail-closed — confirmed via suite).
  - off-plan: injected empty `plan_ref` past deadline → HELD_BLOCKED, reason "off-plan: plan_ref
    does not name PRODUCT_STRATEGY.md#north-star (got: empty)" (reproduced).
  - irreversible: T-AE-d passes (HELD_BLOCKED — confirmed via suite).
- **Re-evaluation at deadline is never cached** (`bin/massoh-cron:457-464`): `_ELIG=""`,
  `_ON_GRACE=""`, `_ON_PLAN=""`, `_PLAN_FAIL_REASON=""` all re-initialized; `_dod_classify`
  and `_dod_plan_guard` called fresh. Independently verified in code.
- **Append-only**: `_dod_emit_notice` and `_dod_close_record` use `>>` only. `_dod_seed_notifications`
  and `_dod_seed_decisions` use `cat >` only when file does not exist (`[ -f "$f" ] && return 0`).
  Zero `sed -i`, zero `mv ...NOTIFICATIONS`, zero `> NOTIFICATIONS` in bin/massoh-cron
  (confirmed by grep).
- **Idempotency guards**: `_dod_notif_exists "$notif_id" && return 0` before every emit;
  `_dod_notif_exists "${id}#CLOSE" && return 0` before every close. Running deadline tick
  twice yields exactly 1 CLOSE block (independently reproduced).
- **Owner-cancels-timer**: Owner APPROVE row (ts >= open_ts) → RESOLVED_BY_OWNER, no
  PROCEEDED (independently reproduced). Old row (ts < open_ts) → timer NOT cancelled,
  eligible record auto-proceeds (T-AE-f2, suite confirms).
- **Genuine eligible PROCEED**: injected reversible=true, flag_dark=true, never_auto="",
  est_spend=0, plan_ref=PRODUCT_STRATEGY.md#north-star, valid rationale, past deadline →
  `final_status: PROCEEDED`, reason "auto-proceeded after grace=5min, no owner reply"
  (reproduced).
- **NON_NEGOTIABLES.md autonomy boundary**: conditions match design §5 verbatim —
  `agent-project/NON_NEGOTIABLES.md:19-29` lists all 5 conditions exactly.
- **bin/massoh-cron now safety-critical**: listed in NON_NEGOTIABLES.md §Designated safety-critical
  files (lines 12-16). Owner sign-off #1 and #2 confirmed on record (TASK-2026-06-21-autonomy-
  escalation sign-off #1 and #2, 2026-06-21 per NON_NEGOTIABLES.md:16).

---

## 6. Hidden Scope Concerns

None. The diff touches exactly:
1. `.agent_tasks/TASK-2026-06-21-autonomy-escalation/05_implementation_handoff.md` (task artifact)
2. `.gitignore` (3 new runtime artifact entries)
3. `AGENT_SYNC.md` (rolling dashboard update + 1 decision log row — additive)
4. `CHANGELOG.md` ([0.28.0] entry — additive)
5. `VERSION` (0.27.1 → 0.28.0)
6. `agent-project/NON_NEGOTIABLES.md` (additive: safety-critical list + autonomy boundary)
7. `agent-project/config.yml` (new file with 4 keys, all default-safe)
8. `bin/massoh-cron` (additive only: 483 new lines, 0 deletions of existing logic)
9. `docs/AUTONOMOUS_CRON.md` (rewrite to document the real new subsystem — licensed in scope)
10. `test/run.sh` (additive: 535 new lines of T-AE tests)

**bin/massoh diff = 0. manifest.yml diff = 0.** Confirmed by `git --no-pager diff
main...feat/autonomy-decide-or-defer -- bin/massoh manifest.yml` (empty output).

---

## 7. Expansion / Localization Concerns

None. The implementation is pure bash (`set -euo pipefail` pattern maintained). No new
network deps, no new runtime deps beyond the existing `_config.sh` parser and `awk`/`grep`.
Clock portability handled: `_dod_utc()` uses GNU `date -d @epoch` with a python3 fallback
(`bin/massoh-cron:112-115`). Injectable `MASSOH_NOW` ensures all T-AE tests are zero-spend
and deterministic (no real wall-clock 2h wait; no real `claude -p` invocation in any test).

---

## 8. Independently Reproduced Proofs

| Proof | Result |
|---|---|
| Flag-OFF byte-identical (dry-run + run mode) | PASS: NOTIFICATIONS.md, DECISIONS.md, decisions.queue NOT created; DRY-RUN output preserved; backlog item marked DONE normally |
| Never-auto: safety-file past deadline | PASS: `final_status: HELD_BLOCKED`, `reason: never-auto: safety-file`; PROCEEDED NOT in file |
| Never-auto: cost(3) > cap(0) past deadline | PASS: HELD_BLOCKED; PROCEEDED NOT found |
| Never-auto: off-plan (empty plan_ref) past deadline | PASS: HELD_BLOCKED; reason "off-plan: plan_ref does not name PRODUCT_STRATEGY.md#north-star (got: empty)" |
| Genuine eligible PROCEED (reversible+flag-dark+on-plan, past deadline) | PASS: `final_status: PROCEEDED`, "auto-proceeded after grace=5min, no owner reply" |
| Owner-cancels-timer (APPROVE before deadline) | PASS: `final_status: RESOLVED_BY_OWNER`, `reason: verdict=APPROVE`; PROCEEDED NOT found |
| Idempotent tick (deadline tick run twice) | PASS: exactly 1 CLOSE block after 2 runs |
| Re-evaluation at deadline never cached | PASS: code verified (`bin/massoh-cron:457-464`) |
| Plan-guard fail-closed (empty plan_ref) | PASS: HELD_BLOCKED (see off-plan proof above) |
| Plan-guard fail-closed (wrong anchor) | PASS: T-AE-g2 passes in suite |
| Append-only NOTIFICATIONS/DECISIONS/queue | PASS: zero `sed -i`, zero destructive writes; seeds guarded by `[ -f ] && return 0` |
| bin/massoh + manifest.yml diff = 0 | PASS: git diff main...feat/... empty |
| massoh doctor healthy | PASS: v0.28.0, `healthy — install matches manifest` |
| Suite count (self-run) | 726/727 green (1/727 T-FLN-6a pre-existing flake); 42/42 T-AE PASS |

---

## 9. Suggested Patch Instructions (BLOCK-1)

**File:** `test/run.sh`
**Scope:** test only — do NOT touch bin/massoh-cron or any product file.

Replace lines 5577-5587 (the md5 capture and the tautological check) with:

```bash
# Capture md5 of NOTIFICATIONS.md after first proceed tick.
md5_notif_h="$(cd "$AEh" && find . -name NOTIFICATIONS.md -exec md5sum {} \; | awk '{print $1}')"

( cd "$AEh" && MASSOH_NOW=$(( AEh_DEADLINE + 1 )) \
  MASSOH_HOME="$REPO_ROOT" MASSOH_AGENT_CMD="$FAKE_AE" MASSOH_GATE_CMD=true MASSOH_STANDUP_CMD=true \
  "$CRON_AE" once --run --no-idle-check >/dev/null 2>&1 ) || true

check "T-AE-h deadline x2: exactly 1 CLOSE block (no double-proceed)" \
  "[ \"\$(grep -cF '## NOTIF ${AEh_ID}#CLOSE' '$AEh/NOTIFICATIONS.md')\" -eq 1 ]"
check "T-AE-h deadline x2: NOTIFICATIONS.md stable (md5 identical)" \
  "[ \"\$(cd '$AEh' && find . -name NOTIFICATIONS.md -exec md5sum {} \\; | awk '{print \$1}')\" = '$md5_notif_h' ]"
```

This pattern is identical to T13g/T14g/T-DG-1 already in the suite. Suite count stays at
727; T-AE-h check count stays at 3. No product code change. No VERSION bump needed
(test-only fix; at reviewer's discretion the implementer may choose 0.28.1 for correctness
but it is not required).

---

## 10. Owner Decision Needed

None. The authority expansion was explicitly owner-authorized (sign-offs #1 and #2,
2026-06-21, recorded in NON_NEGOTIABLES.md:16 and AGENT_SYNC.md decision log). The owner
performs the final merge after this review cycle closes (NOT auto-merge, per 04:§Routing).

---

## Condition → file:line (verified)

| Condition | File:line | Status |
|---|---|---|
| Master flag guard | bin/massoh-cron:368 | VERIFIED |
| Config read: 4 new keys, same idiom as cron_idle_min | bin/massoh-cron:27-33 | VERIFIED |
| Pre-tick evaluator hook (after idle gate, before fan-out) | bin/massoh-cron:542 | VERIFIED |
| never_auto class | _dod_classify() in bin/massoh-cron:245-284 | VERIFIED |
| Plan-guard predicate | _dod_plan_guard() in bin/massoh-cron:287-319 | VERIFIED |
| Spend cap fail-closed (missing est = over-cap) | bin/massoh-cron:253-256 | VERIFIED |
| Deadline re-evaluation (never cached) | bin/massoh-cron:457-464 | VERIFIED |
| Idempotency: no double-notify | bin/massoh-cron:194 | VERIFIED |
| Idempotency: no double-proceed | bin/massoh-cron:226 | VERIFIED |
| Append-only: NOTIFICATIONS | bin/massoh-cron:210, 234 | VERIFIED |
| Append-only: DECISIONS.md | seed only (cat>, guarded:119-132,136-148) | VERIFIED |
| Append-only: decisions.queue | bin/massoh-cron:351, 511 | VERIFIED |
| NON_NEGOTIABLES §Designated safety-critical (bin/massoh-cron added) | agent-project/NON_NEGOTIABLES.md:12-16 | VERIFIED |
| Autonomy boundary 5 conditions | agent-project/NON_NEGOTIABLES.md:19-29 | VERIFIED |
| Owner sign-off #1+#2 | NON_NEGOTIABLES.md:16, AGENT_SYNC decision log | VERIFIED |
| bin/massoh diff = 0 | git diff empty | VERIFIED |
| manifest.yml diff = 0 | git diff empty | VERIFIED |
| Runtime artifacts gitignored | .gitignore:11-13 | VERIFIED |
