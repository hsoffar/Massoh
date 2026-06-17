# 03 — Architecture & Safety Review
**Task:** TASK-2026-06-17-efficiency-v2
**Date:** 2026-06-17
**Agent:** massoh-architecture-safety
**Decision: APPROVED — all 3 slices, with mandatory per-slice conditions below**

Owner sign-off on editing `bin/massoh` and `bin/massoh-cron` is on record in `00_request.md`
("Full efficiency v2 bundle (agent-driven)" selection). Guardrail B does not block; recorded here
for the audit trail.

---

## 1. Backend / service impact

None. Pure-bash CLI. No server, no service boundary, no network call in any slice.

## 2. Client / app impact

None. Terminal stdout only for all three slices. Slice C adds one new verb (`massoh recommend`) and
one optional flag-guarded write path (`--write` to AGENT_SYNC.md). Neither affects any existing
caller.

## 3. API impact

No API contract seam touched. `manifest.yml` is not changed. `cmd_cron` dispatch in `bin/massoh`
(line 488) is unchanged — Slice A patches `massoh-cron` internals only. Slice B extends `cmd_review`
additively (new output lines appended; existing lines untouched). Slice C adds a new `cmd_recommend`
case to the `case "$cmd"` dispatch — additive, no existing case altered. No both-sides-together
concern is triggered.

## 4. DB / migration impact

No schema. METRICS.md append is the only persistence in Slices B and C; it is strictly additive
and backward-compatible (old snapshot rows are never modified or deleted — NON_NEGOTIABLES "keep
older data" satisfied). AGENT_SYNC.md append (Slice C `--write`) follows the same append-only
pattern already established by standup/plan. Cadence_state file (Slice A) is already in use; the
fix does not alter its format.

## 5. LLM / prompt impact

Zero. No `claude -p` or equivalent in any slice. No prompt text, no spend. All three slices are
explicitly zero-LLM.

## 6. Safety / guardrail risks

### Slice A — cron tick-time fix

**Risk A1 — injection via `--every` flag value.**
The `--every` value is parsed by the same `case` pattern used in `cmd_install` (line 190:
`*m) mins="${every%m}";;  *h) mins=$(( ${every%h} * 60 ));;  *) mins=30;;`). This does NOT pass
the raw value to `eval` or to an unquoted command substitution; it extracts a numeric fragment via
bash parameter expansion only. The fallback `*) mins=30` catches any unexpected shape. No injection
vector.
MANDATORY CONDITION A1: The implementer MUST replicate exactly the same `case` pattern from
`cmd_install` line 190, including the `*) mins=30` catch-all default. Do not parse `--every`
differently or more liberally.

**Risk A2 — tick-time duration in dry-run.**
The current dry-run path returns at line 97 before any work runs (`return 0` inside `if [ "$mode" = dry ]`).
The tick_start capture and tick_duration `say` must be placed INSIDE the `[ "$mode" = run ]` block,
AFTER the early-return dry-run guard, so dry-run remains a no-state-change, no-timing-noise path.
This aligns with the existing Condition C (ceremonies suppressed in dry-run) and the task packet
requirement.
MANDATORY CONDITION A2: tick_start=$(date +%s) MUST be captured after the dry-run early-return
block (i.e., after line 98). The tick_duration `say` line MUST be placed at the end of the run
block, before or after the cadence block (both are acceptable) but NEVER in the dry-run path. A
test must assert that dry-run output does NOT contain "tick_duration" or equivalent.

**Risk A3 — `every_mins` default safety.**
With the fix, if `--every` is not passed to `cmd_once`, `every_mins` must default to 30 (matching
the existing hardcode and `cmd_install` default). The T_A2 regression test enforces this
numerically. The `*) mins=30` fallback in the case statement handles it.
MANDATORY CONDITION A3: default-30 fallback must be preserved and must appear in the case pattern,
not as a separate post-parse override. It is both a safety property (period_ticks stays defined)
and a regression guard.

**Risk A4 — cadence counter logic.**
The cadence_state counter (`tick_count`, `period_ticks`, the `>= period_ticks` comparison, the
reset to 0, and the `printf '%s\n' "$tick_count"` persist) MUST NOT be altered. Only
`every_mins=30` (line 146) and `period_ticks=$(( period_days * 1440 / every_mins ))` (line 147)
are changing — the remainder of the cadence block is frozen under this slice.
MANDATORY CONDITION A4: The implementer must make no other changes in the cadence block (lines
150–177). Changing the cadence_state read/write, the `|| true` guards on ceremonies, or the
counter reset logic is out of scope and will be rejected by reviewer-qa.

**Risk A5 — `cmd_install` crontab line.**
`cmd_install` currently generates:
  `cd $REPO && $REPO/bin/massoh cron once --run --period-days $period_days >> ...`
It does NOT pass `--every` to `cron once`. The fix must update this line to include `--every $every`
so the installed schedule and the live behavior are consistent.
MANDATORY CONDITION A5: `cmd_install`'s generated crontab line MUST be updated to pass
`--every $every` to `cron once`. The T_A4 test must verify this by capturing the `say` output of
`massoh cron install --every 15m` and asserting the generated line contains `--every 15m`.

### Slice B — review-v2 KPIs

**Risk B1 — `stat` portability (the primary risk in this slice).**
`stat -c %Y` (Linux) and `stat -f %m` (macOS) are not cross-portable. The product-scope packet
acknowledges this and mandates a mitigation. After evaluating the existing codebase:
- `bin/massoh-cron` line 51 already uses `date +%s` (portable).
- `bin/massoh` lines 348-349 and 395 already use `find -mtime -N` (portable).

MANDATORY CONDITION B1 (stat-portability decision): The implementer MUST derive packet dates from
the `Date:` field already written in `00_request.md` and `06_review_result.md` (grep the `Date:`
header line), using `git log -1 --format=%ct -- <file>` as fallback when the `Date:` field is
absent or unparseable. Do NOT use `stat -c` or `stat -f` anywhere in this slice. This is the
mandated approach. Rationale: the `Date:` field is explicitly present in every packet
(e.g., `00_request.md` line 2: `**Date:** 2026-06-17`) and is already structured text that grep
can extract reliably on all platforms. `git log --format=%ct` is also portable (used in existing
codebase at `massoh-cron` line 51). `find -mtime` is a backup option if git history is
unavailable, but it measures filesystem mtime (affected by checkout operations) — `Date:` field is
more reliable for cycle time.

The extraction pattern: `grep -m1 '^[*]*Date:' "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true`
followed by conversion to epoch via `date -d` (Linux) / `date -j -f` (macOS). Since cross-platform
`date` conversion is also fragile, the preferred fallback is `git log -1 --format=%ct -- "$f"`.
Implementer MUST choose one of:
  (a) Primary: grep `Date:` field → `git log -1 --format=%ct -- "$f"` if field absent.
  (b) Sole: `git log -1 --format=%ct -- "$f"` for both files (simpler, always portable).
Option (b) is simpler and safer. If the file is not in git history, cycle time = "n/a" for that
packet (degrade gracefully, do not crash).

**Risk B2 — `|| true` guard on all grep/awk calls.**
The recurring bug class in this repo is unguarded grep returning non-zero when no match found
under `set -euo pipefail`. ALL grep and awk calls added in Slice B MUST have `|| true` guards.
This includes: the REQUEST CHANGES grep per packet, the Date: extraction grep, and any
`wc -l`-based counting.
MANDATORY CONDITION B2: Every new grep, awk, and wc call in `cmd_review` must end with `|| true`.
Reviewer-qa will reject any unguarded grep, regardless of context.

**Risk B3 — division-by-zero.**
`rework_pct` = rework_count / total_reviewed * 100. If `total_reviewed` is 0, this is a division
by zero under bash arithmetic. The implementer must guard: if `total_reviewed -eq 0` then
`rework_pct=0` (or "n/a") rather than computing the division.
MANDATORY CONDITION B3: Guard division-by-zero for rework_pct and throughput_per_week
(throughput = packets / days; if days=0 output "n/a"). Use explicit bash integer guards before
any `$(( ... / ... ))` arithmetic.

**Risk B4 — METRICS.md append idempotency.**
The existing `cmd_review` append pattern (line 237: `>> "$repo/agent-project/METRICS.md"`) is
already append-only. Slice B must follow the identical pattern — new fields appended as additional
`- field=value` lines within the same snapshot block. NON_NEGOTIABLES "keep older data" is
satisfied as long as no existing snapshot line is modified.
MANDATORY CONDITION B4: New KPI lines must be appended within the same `## Snapshot ...` block,
not written as a separate block. The `--no-write` flag must remain inert (verified by T_B tests
matching the existing T8 pattern).

**Risk B5 — `--no-write` test parity.**
The existing T8 pattern tests `--no-write` with a filesystem checksum before/after. A T_B variant
must replicate this check for the new fields to confirm read-only behavior is preserved.
This is covered under the required tests below.

### Slice C — `massoh recommend`

**Risk C1 — `--write` default-OFF.**
The `--write` flag must be explicitly opt-in. Default behavior (no flag) MUST be stdout-only with
zero file mutations. The implementer must not default `write_recommend` to 1.
MANDATORY CONDITION C1: `write_recommend=0` must be the initial assignment inside `cmd_recommend`.
The `--write` flag toggles it to 1. Test T_C7 must verify file mtime is unchanged after a
no-flag invocation.

**Risk C2 — awk parser cannot corrupt AGENT_SYNC.md or METRICS.md.**
The METRICS.md parse is read-only (awk reads, does not write). The only write path is the
`--write` AGENT_SYNC.md append. However, a malformed awk substitution using `>` instead of `>>`
would truncate AGENT_SYNC.md. The implementer MUST use `>>` (append) exclusively for the
`--write` path.
MANDATORY CONDITION C2: The `--write` path MUST use `>>` (append, not `>`). A comment in the code
must note this is the sole permitted write. Additionally, the awk METRICS.md parse MUST be wrapped
in `|| true` so a parse failure degrades to R5 ("no snapshots") rather than a crash.

**Risk C3 — `|| true` guards on all reads.**
Same pattern required as Slice B. Every grep, awk, find, and cat call in `cmd_recommend` must
end with `|| true`.
MANDATORY CONDITION C3: Same as B2 — every new grep, awk, wc, cat call in `cmd_recommend` must
end with `|| true`.

**Risk C4 — fewer-than-2-snapshots degrade.**
If METRICS.md has 0 or 1 snapshots, rules R1 and R4 (which require 2 snapshots to compute a
trend) cannot fire. The implementer must detect this condition and degrade gracefully: output
"Not enough history (< 2 snapshots) — run `massoh review` to capture more data." Do not attempt
to apply R1/R4 with a single snapshot (comparing snapshot to zero is a false trend).
MANDATORY CONDITION C4: Explicitly count parsed snapshots. If count < 2, suppress R1 and R4.
If count == 0, fire R5 only. "Not enough history" message may also fire for count == 1.

**Risk C5 — no writes to safety-critical files.**
NON_NEGOTIABLES designates `bin/massoh` and `manifest.yml` as safety-critical. The `--write` path
writes ONLY to `AGENT_SYNC.md`. STANDARDS.md, memory/, templates/, and all files under
`agent-os/` are prohibited write targets.
MANDATORY CONDITION C5: The `--write` path must have a single, named write target:
`"$repo/AGENT_SYNC.md"`. Any write to any other file is a safety violation. A comment in the
code must name the target explicitly (mirror cmd_learn's `# SAFETY: only permitted write`
pattern at line 482).

**Risk C6 — expansion / locale.**
Rule trigger logic uses numeric field extraction from METRICS.md (numbers for cycle_avg_days,
rework_pct, throughput/wk). Rule text is English. The numeric extraction must not assume
locale-specific decimal formatting (bash arithmetic is integer; the values in METRICS.md are
written by cmd_review in integer or simple decimal form). No localization risk for MVP.
The product-scope note that "pattern-matching on structural fields (numbers, packet counts), not
prose" is the correct implementation guide.

**Risk C7 — `massoh recommend` not auto-added to cron.**
The product-scope explicitly states "Do not add recommend to the cron cadence automatically."
The implementer MUST NOT add a `_massoh_recommend` call anywhere in `bin/massoh-cron`.
MANDATORY CONDITION C6: No cron invocation of `recommend` in this slice. `cmd_cron` dispatch
in `bin/massoh` is also not to be modified.

---

## 7. Expansion / localization risks

Slice C rule-text strings are English. The numeric extraction is locale-neutral (integer
arithmetic). The CHARTER.md expansion principle ("parameter, not assumption") is satisfied:
rule thresholds are named constants in the code (not scattered literals), and the rule text
is in one location. No hard-coding of the current wedge (solo founder) that would break if a
second segment is added. This is acceptable for MVP; flagged as NEXT if non-English environments
are needed.

No slice hard-codes a region, locale, or date format that cannot be parameterized later.

---

## 8. Required tests

### T12 — Slice A: cron-fix (append to test/run.sh, section `== T12: cron tick-time fix ==`)

**T12a** — `--every 60m` resolves `every_mins=60`:
  Set up a cron repo with `cadence_state=0`, run `cron once --run --no-idle-check --period-days 7 --every 60m`
  with fake agent+gate. Read cadence_state afterward; verify it is 1, not 0 (tick ran). Then
  separately assert period_ticks would be 168 (7*1440/60) by injecting a state at 167 and
  verifying review fires (inject MASSOH_REVIEW_CMD to write a sentinel file).

**T12b** — `--every 30m` (default) is a non-regression:
  Same setup; run with `--every 30m --period-days 7`. Verify period_ticks is 336 by setting
  cadence_state=335 and asserting review fires on the next tick. Alternatively: `--period-days 0`
  sets period_ticks=1 regardless — reuse T10e pattern and confirm T10e still passes.

**T12c** — dry-run DOES NOT contain tick_duration:
  Run `cron once --no-idle-check` (dry-run, default). Capture stdout. Assert output does NOT
  contain "tick_duration" (or the chosen duration keyword). This tests Condition A2.

**T12d** — run mode output DOES contain tick_duration:
  Run `cron once --run --no-idle-check --every 30m` with `MASSOH_AGENT_CMD=fake`, `MASSOH_GATE_CMD=true`,
  `NO_IDLE=1`. Capture stdout. Assert output contains "tick_duration=" (or equivalent).

**T12e** — `cron install --every 15m` generates crontab line with `--every 15m`:
  Capture `cron install --every 15m` output. Assert the printed crontab line contains
  the string `--every 15m`.

**T12f** — regression: all existing T7 and T10 checks remain green. No explicit new test needed;
  the harness exit code enforces this. State it explicitly in the handoff.

All T12 tests: fixture-based, zero LLM spend, injectable fakes. Tests must be appended to
`test/run.sh` following the established `check()` pattern.

### T13 — Slice B: review-v2 KPIs (append to test/run.sh, section `== T13: review-v2 KPIs ==`)

**T13a** — single packet with both files: output contains `cycle_avg_days=`, `rework_pct=`, `throughput/wk=`:
  Create fixture with `00_request.md` (contains `**Date:** 2026-06-10`) and
  `06_review_result.md` (contains `**Date:** 2026-06-17` + "REQUEST CHANGES"). Run
  `massoh review --no-write`. Assert stdout contains all three field names.

**T13b** — rework_pct=100 on single packet with REQUEST CHANGES:
  Same fixture as T13a. Assert stdout contains `rework_pct=100`.

**T13c** — rework_pct=50 on two packets (one with, one without REQUEST CHANGES):
  Add second fixture packet with `06_review_result.md` containing only "APPROVE". Run review.
  Assert stdout contains `rework_pct=50`.

**T13d** — packet missing `06_review_result.md` excluded from cycle time and rework (no crash):
  Add a third fixture with only `00_request.md`. Run `massoh review --no-write`. Assert exit 0.
  Assert packet count for cycle time does not include this packet (rework_pct and cycle_avg_days
  reflect only complete packets).

**T13e** — division-by-zero guard (0 reviewed packets):
  Create a repo with only incomplete packets (no `06_review_result.md` files). Run review. Assert
  exit 0, output contains `rework_pct=0` or `rework_pct=n/a`.

**T13f** — METRICS.md snapshot gains new fields (write mode):
  Create fixture repo. Run `massoh review` (default write). Assert METRICS.md snapshot block
  contains `cycle_avg_days=`, `rework_pct=`, `throughput/wk=`. Run again; assert 2 snapshots
  (append-only, no overwrite — mirrors T8 pattern).

**T13g** — `--no-write` leaves files unchanged:
  Checksum before/after run with `--no-write` (mirror T8 checksum pattern). Assert md5 unchanged.

**T13h** — all existing T8 review tests remain green (regression guard; enforced by harness exit code).

### T14 — Slice C: massoh recommend (append to test/run.sh, section `== T14: massoh recommend ==`)

**T14a** — R1 fires when cycle_avg_days rises across 2 snapshots:
  Create fixture METRICS.md with two snapshot blocks: first has `cycle_avg_days=2`, second has
  `cycle_avg_days=5`. Run `massoh recommend`. Assert output contains R1 text ("Cycle time climbing").

**T14b** — R2 fires when rework_pct > 25:
  Fixture with one snapshot containing `rework_pct=50`. Run recommend. Assert R2 text
  ("High rework rate").

**T14c** — R3 fires on revert > 0:
  Fixture snapshot with `reverts=2` (or the field name used by review-v2). Assert R3 text.

**T14d** — R4 fires when TODO grows and throughput/wk is flat or falling:
  Fixture with two snapshots: first TODO=5 throughput/wk=2, second TODO=8 throughput/wk=2.
  Assert R4 text ("Throughput bottleneck").

**T14e** — R5 fires (and only R5) when METRICS.md is empty or missing:
  Run `massoh recommend` in a repo with no METRICS.md. Assert R5 text ("No METRICS.md snapshots").

**T14f** — "No issues detected" when no rules fire:
  Fixture with two snapshots where cycle_avg_days is flat or falling, rework_pct=0, reverts=0,
  TODO flat, throughput/wk flat or rising. Assert output contains "No issues detected".

**T14g** — `--write` appends `[recommend]` block to AGENT_SYNC.md; default (no flag) does NOT write:
  In a repo with AGENT_SYNC.md, capture file mtime before. Run `massoh recommend` (no flags).
  Assert AGENT_SYNC.md mtime unchanged. Run again with `--write`. Assert AGENT_SYNC.md now
  contains `[recommend]` block.

**T14h** — awk parse failure on malformed METRICS.md degrades to R5, not crash:
  Write a METRICS.md with no parseable snapshot structure. Run recommend. Assert exit 0 and
  R5 text (or "No issues detected" — not a crash, not a corrupt AGENT_SYNC.md).

**T14i** — all existing tests remain green (regression guard).

---

## 9. Rollback plan

All three slices are additive changes to `bin/massoh` and `bin/massoh-cron` in a feature branch
(`feat/efficiency-v2`). Rollback = do not merge the PR, or revert the merge commit on main.

Slice A: reverting returns `every_mins` to the hardcoded 30 (the prior incorrect-but-safe
behavior). No state is corrupted — cadence_state file format is unchanged.

Slice B: reverting removes the new KPI lines from `cmd_review` output. Existing METRICS.md
snapshot rows are untouched (append-only). Any snapshots already written with the new fields
are harmless legacy rows (review just won't emit them).

Slice C: reverting removes `cmd_recommend` and its case-dispatch entry. AGENT_SYNC.md entries
written with `--write` remain as harmless appended blocks.

No schema migration. No install/uninstall contract change. No manifest.yml change.
Rollback cost: a `git revert` of the merge commit, followed by `massoh install`.

---

## 10. Per-slice approval

### Slice A — APPROVED
Conditions: A1, A2, A3, A4, A5 (all mandatory, see §6 above).
Build order: Slice A first. Do not begin Slice B until T12a–T12f are all green.

### Slice B — APPROVED
Conditions: B1 (stat-portability — use git log %ct or Date: field, NOT stat), B2 (every grep
`|| true` guarded), B3 (division-by-zero guard), B4 (append-only within same snapshot block),
B5 (--no-write checksum test).
Build order: Slice B after Slice A green. Do not begin Slice C until T13a–T13h are all green.

### Slice C — APPROVED
Conditions: C1 (write_recommend=0 default), C2 (>> append only, awk parse `|| true`), C3
(every grep/awk/cat `|| true`), C4 (< 2 snapshots degrades, R1/R4 suppressed), C5 (sole write
target is AGENT_SYNC.md with explicit comment), C6 (no cron auto-addition).
Build order: Slice C after Slice B green. T14a–T14i must all be green before handoff.

---

## 11. Answers to product-scope §11 questions

- Slice A `--every` parsing in cmd_once: safe from injection (case pattern with numeric extraction
  only, same as cmd_install; default-30 fallback holds; dry-run suppression enforced).
- Slice B stat/find portability: MANDATED — use `git log -1 --format=%ct -- <file>` (portable,
  already used in codebase); `|| true` on all greps confirmed required.
- Slice C `--write` default-OFF: enforced via `write_recommend=0` initial assignment; awk parser
  cannot corrupt AGENT_SYNC.md (reads only; sole write is `>>`-guarded append path).
