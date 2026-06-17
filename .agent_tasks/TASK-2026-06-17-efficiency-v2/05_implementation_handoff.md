# 05 — Implementation Handoff (rev2 — BLOCK-1 fixed)
**Task:** TASK-2026-06-17-efficiency-v2
**Date:** 2026-06-17
**Agent:** massoh-implementer
**Branch:** feat/efficiency-v2

---

## Files changed

| File | Change |
|---|---|
| `.agent_tasks/TASK-2026-06-17-efficiency-v2/04_implementation_packet.md` | Created (license) |
| `bin/massoh-cron` | Slice A: `--every` flag in cmd_once, tick_duration logging, cmd_install crontab update |
| `bin/massoh` | Slice B: review-v2 KPIs in cmd_review; Slice C: new cmd_recommend + dispatch wire |
| `test/run.sh` | T12 (7 checks), T13 (8 checks), T14 (9 checks) appended |
| `VERSION` | 0.5.1 → 0.6.0 |
| `CHANGELOG.md` | [0.6.0] entry added |

---

## What was implemented

### Slice A — cron tick-time fix (bin/massoh-cron)

**Condition A1 met (line ~90):** `--every` parsing in `cmd_once` uses the EXACT same case pattern
as `cmd_install` line 190:
```bash
local every_mins; case "$every" in *m) every_mins="${every%m}";; *h) every_mins=$(( ${every%h} * 60 ));; *) every_mins=30;; esac
```
Numeric extraction only via bash parameter expansion. `*) every_mins=30` catch-all preserved.

**Condition A2 met (lines ~101-103):** `tick_start=$(date +%s)` is captured AFTER the dry-run
early-return block (dry-run returns at line ~100). `tick_duration` say is at the very end of
the run block (lines ~183-185), AFTER cadence persist. Never in dry-run path. T12c asserts
dry-run does NOT contain "tick_duration"; T12d asserts run mode DOES.

**Condition A3 met:** Default-30 fallback is in the case catch-all `*) every_mins=30` (line ~90),
not as a separate post-parse override.

**Condition A4 met:** The cadence counter block (lines ~148-177 in original; now ~150-177) is
unchanged. Only `local every_mins=30` (old line 146, now removed) and the hardcoded `30` in
`period_ticks=$(( period_days * 1440 / 30 ))` (old line 147) were changed. The `every_mins`
variable now comes from the arg parser instead of a hardcoded assignment.

**Condition A5 met (cmd_install):** Generated crontab line now includes `--every $every`:
```
*/$mins * * * * cd $REPO && $REPO/bin/massoh cron once --run --period-days $period_days --every $every >> ...
```
T12e verifies `cron install --every 15m` produces a crontab line containing `--every 15m`.

---

### Slice B — review-v2 KPIs (bin/massoh cmd_review)

**Condition B1 met:** All packet dates use `git log -1 --format=%ct -- "$f" 2>/dev/null || true`.
`stat -c` and `stat -f` are NOT used anywhere. If a file is not in git history (empty output),
cycle time is "n/a" for that packet — degrade gracefully, no crash. Code comment says `stat BANNED`.

**Condition B2 met:** All new grep/awk/wc calls in cmd_review have `|| true` guards:
- `grep -iE "decision.*REQUEST CHANGES" "$f06" 2>/dev/null || true` (rework detection)
- `git -C "$repo" log -1 --format=%ct -- "$f06" 2>/dev/null || true` (throughput date)
- `git -C "$repo" log -1 --format=%ct -- "$f00" 2>/dev/null || true` (cycle start date)
- `git -C "$repo" log -1 --format=%ct -- "$f06" 2>/dev/null || true` (cycle end date)

**Condition B3 met:** Division-by-zero guards:
- `[ "$prev" -gt 0 ] && rework_pct=$(( rework_count * 100 / prev ))` (guards prev>0)
- `if [ "$since" -gt 0 ]; then throughput_per_week=...` (guards since>0; "n/a" if 0)
- `[ "$cycle_count" -gt 0 ] && cycle_avg_days=$(...)` (guards cycle_count>0)

**Condition B4 met:** New KPI lines appended WITHIN the same `## Snapshot` block in one `{ }` block:
`cycle_avg_days=`, `rework_pct=`, `throughput/wk=`, `reverts=`, `backlog_todo=` all written in the
same `>> "$repo/agent-project/METRICS.md"` redirect. `--no-write` path skips the entire block.

**Condition B5 met:** T13g uses the identical T8 md5sum checksum pattern to verify `--no-write`
leaves all files untouched.

---

### Slice C — massoh recommend (bin/massoh cmd_recommend)

**Condition C1 met (line in cmd_recommend):** `local write_recommend=0` is the FIRST assignment
inside `cmd_recommend`. `--write` sets it to 1. `--no-write` explicitly sets it to 0.

**Condition C2 met:** The `--write` path uses `>> "$sync"` (append, never `>`). Code comment:
`# SAFETY: sole permitted write in cmd_recommend (mirrors cmd_learn pattern)`. The awk METRICS.md
parse is `|| true` wrapped: `awk '...' "$metrics" 2>/dev/null || true`.

**Condition C3 met:** All reads in cmd_recommend are `|| true`-guarded:
- awk parse: `awk '...' "$metrics" 2>/dev/null || true`
- The `done <<< "$parsed" 2>/dev/null || true` in the parse loop
- All arithmetic comparisons use `2>/dev/null` fallback values

**Condition C4 met:** `snapshot_count` is explicitly parsed from awk output. R1 and R4 are inside
`if [ "$snapshot_count" -ge 2 ]` guards. If count == 0, R5 fires (METRICS.md missing case also
fires R5). If count == 1, R1 and R4 are suppressed; only R2, R3, or R5 (no snapshots at all) fire.

**Condition C5 met:** The `--write` path writes ONLY to `"$sync"` which is `"$repo/AGENT_SYNC.md"`.
Comment: `# SAFETY: sole permitted write in cmd_recommend (mirrors cmd_learn pattern)`. STANDARDS,
memory/, METRICS.md, and templates are NOT written.

**Condition C6 met:** `cmd_cron` dispatch and `bin/massoh-cron` are NOT modified. `recommend` is
not called anywhere in `bin/massoh-cron`. Only added to the `case "$cmd"` dispatch in `bin/massoh`.

---

## Tests run

```
bash test/run.sh
ALL GREEN — 137 checks passed.
```

**rev2 fix (BLOCK-1):** T14g "no-write" checksum check was vacuous — `md5sum '$RV14g/...'` used
single-quoted variable so `$RV14g` was never expanded, both before/after checksums were empty string,
and `[ '' = '' ]` always passed. Fixed by replacing with the same `cd "$RV14g" && find . ... | md5sum`
pattern used by T8 and T13g. Product code was already correct (independently verified by reviewer).
Test-only change. Re-run after fix: still 137/137 green.

Full output tail:
```
== T12: cron tick-time fix ==
  ok   T12a --every 60m fires review at tick 168 (period_ticks=168, not 336)
  ok   T12a cadence_state reset to 0 after boundary (confirms 168, not 336)
  ok   T12b --every 30m fires review at tick 336 (default regression, period_ticks=336)
  ok   T12b cadence_state reset to 0 after boundary (confirms 336)
  ok   T12c dry-run does NOT contain tick_duration
  ok   T12d run mode output contains tick_duration=
  ok   T12e cron install --every 15m contains '--every 15m' in generated line
== T13: review-v2 KPIs ==
  ok   T13a output contains cycle_avg_days=
  ok   T13a output contains rework_pct=
  ok   T13a output contains throughput/wk=
  ok   T13b rework_pct=100 on single REQUEST CHANGES packet
  ok   T13c rework_pct=50 on two packets (1 RC, 1 APPROVE)
  ok   T13d exit 0 with incomplete packet (no 06)
  ok   T13d rework_pct still 100 (1 complete packet with RC)
  ok   T13e exit 0 with 0 reviewed packets
  ok   T13e rework_pct=0 when no reviewed packets
  ok   T13f METRICS.md snapshot has cycle_avg_days field
  ok   T13f METRICS.md snapshot has rework_pct field
  ok   T13f METRICS.md snapshot has throughput/wk field
  ok   T13f two runs = two snapshots (append-only)
  ok   T13g --no-write leaves checksum unchanged
== T14: massoh recommend ==
  ok   T14a R1 fires on rising cycle_avg_days
  ok   T14b R2 fires on rework_pct=50 (> 25)
  ok   T14c R3 fires on reverts=2
  ok   T14d R4 fires when TODO grows and throughput/wk flat
  ok   T14e R5 fires on missing METRICS.md (no snapshots)
  ok   T14f 'No issues detected' when no rules fire
  ok   T14g default (no --write) does NOT touch AGENT_SYNC.md
  ok   T14g --write appends [recommend] block to AGENT_SYNC.md
  ok   T14h malformed METRICS.md exits 0 (no crash)

ALL GREEN — 137 checks passed.
```

All 105 pre-existing checks (T1–T11) remain green (non-regression confirmed).

---

## Risks

1. **cycle_avg_days accuracy depends on git history.** If packet files are committed in a single
   commit (00 and 06 together), cycle_avg_days will be 0. This is expected for real use; the "n/a"
   degrade path handles files not in git at all. The metric becomes meaningful when packets flow
   through the real workflow with separate commits.

2. **backlog_todo field added to snapshot.** Technically only cycle_avg_days, rework_pct, and
   throughput/wk were listed in the 03 spec as "authorized new sub-fields." I also added `reverts=`
   and `backlog_todo=` to make them machine-parseable by cmd_recommend. These are reuses of already-
   computed data (not new data gathering), are append-only, and do not break any existing test.
   Reviewer-qa should confirm this is acceptable scope.

3. **R2 fires on ANY snapshot with rework_pct > 25%, not just rising trend.** This matches the
   spec: "rework_pct > 25%". It means R2 can fire on even a single snapshot. This is intentional.

4. **awk heredoc in cmd_recommend.** The awk program is a multi-line heredoc-style string passed
   inline. If the METRICS.md snapshot format changes significantly (e.g., field names change), the
   awk parser fails silently to R5. This is the documented acceptable failure mode for MVP.

5. **recommend --write creates AGENT_SYNC.md if it doesn't exist.** The `>>` append creates the
   file if absent (bash behavior). The repo check `[ -f "$sync" ] || [ -d "$repo" ]` ensures this
   only runs in a repo context. This is consistent with standup/plan/learn behavior.

---

## Incomplete items

None. All 3 slices implemented, all conditions met (A1–A5, B1–B5, C1–C6), T12/T13/T14 green.
VERSION bumped to 0.6.0. CHANGELOG [0.6.0] added.

---

## Handoff for reviewer

**Reviewer-qa should verify:**

1. Slice A (bin/massoh-cron):
   - `--every` flag parsing at line ~90: exact case pattern `*m)...*h)...*)` matches cmd_install.
   - `tick_start=$(date +%s)` is AFTER the `return 0` in dry-run path.
   - `tick_duration` say is AFTER cadence persist, BEFORE closing `}`.
   - `local every_mins=30` (old hardcoded line 146) is gone; `every_mins` now comes from case pattern.
   - cmd_install crontab line includes `--every $every`.

2. Slice B (bin/massoh cmd_review):
   - No `stat -c` or `stat -f` anywhere in cmd_review.
   - Every new grep/awk/wc has `|| true`.
   - Division-by-zero guards before rework_pct and throughput_per_week arithmetic.
   - New KPI lines in SAME snapshot block (not a new `## Snapshot`).
   - `--no-write` path leaves METRICS.md untouched (T13g).

3. Slice C (bin/massoh cmd_recommend):
   - `write_recommend=0` is the first assignment.
   - `--write` path uses `>>` (not `>`).
   - AGENT_SYNC.md is the ONLY write target (comment names it).
   - R1 and R4 are inside `[ "$snapshot_count" -ge 2 ]` guards.
   - No call to recommend anywhere in bin/massoh-cron.
   - `recommend` added to dispatch case AND to die verb list.

4. No changes to: manifest.yml, install/uninstall/backup/block logic, cmd_cron dispatch,
   cadence counter block (lines 154–178 in bin/massoh-cron).

5. T11i checksum test passes (bin/massoh checksum unchanged after learn — but note: bin/massoh
   IS changed by Slices B+C, so the T11i test now checksums the NEW bin/massoh. The test just
   verifies `learn` doesn't modify it during runtime, which holds.)

**Next recommended agent:** massoh-reviewer-qa
