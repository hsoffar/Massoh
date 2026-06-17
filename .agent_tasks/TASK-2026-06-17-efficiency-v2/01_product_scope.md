# 01 — Product Scope
**Task:** TASK-2026-06-17-efficiency-v2
**Date:** 2026-06-17
**Agent:** massoh-product-scope
**Decision: BUILD (all 3 slices, sequenced)**

---

## 1. Why build this now

Strategic mode is "validate that a portable, gated agent OS reduces build-trap for solo+Claude
shipping." The efficiency v2 bundle is the first instrumentation pass that makes the validation
measurable rather than felt. Without cycle time, rework rate, and throughput in METRICS.md the
owner cannot observe whether the gate is helping or hurting. The cron-fix is a confirmed
correctness bug (period_ticks hardcoded to 30m regardless of --every) that makes the period
boundary ceremony (review + plan) fire at the wrong cadence — fixing it is not elective.
`massoh recommend` closes the feedback loop: data in → signal out → owner acts. All three are
read-only / heuristic / zero LLM spend; the cost of not shipping them is continued blindness on
the core validation metric.

Both `bin/massoh` and `bin/massoh-cron` are safety-critical per NON_NEGOTIABLES.md. Owner sign-off
is on record in `00_request.md` ("Full efficiency v2 bundle (agent-driven)" selection, branch
feat/efficiency-v2). No additional sign-off gate is required; record it here and proceed.

---

## 2. Target segment and region

Segment: solo founder / single maintainer using Claude Code on one product (the primary wedge).
Region: no locale constraint — pure CLI, English output only. Expansion note: output strings for
`recommend` must not be hard-coded to English idioms that would break if a non-English METRICS.md
snapshot is fed in; keep pattern-matching on structural fields (numbers, packet counts), not prose.

---

## 3. Metrics affected

All three slices feed the same named event chain:

| Named event (METRICS.md) | How each slice connects |
|---|---|
| `packet_merged` (activation complete) | review-v2 measures cycle time and throughput per packet — directly instruments this event |
| `packet_merged` (rework signal) | rework rate counts REQUEST-CHANGES-before-APPROVE on 06 files — quality signal on the same event |
| (new snapshot data) | cron-fix ensures the period boundary review/plan fires at the correct cadence, so METRICS.md snapshots are trustworthy |
| (new recommend output) | `recommend` converts METRICS.md trend into actionable owner guidance — closing the inspect-and-adapt loop |

METRICS.md does not yet define cycle_time, rework_rate, or throughput as named events. This scope
authorizes adding them as sub-fields within the existing `packet_merged` snapshot row. No new
top-level event rows are required for MVP; a comment noting the new fields is sufficient.

---

## 4. Slices and build order

Recommended order: **Slice A (cron-fix) → Slice B (review-v2) → Slice C (recommend)**.
Rationale from 00_request: cron-fix is a correctness bug (fixes data reliability before review
captures it); review-v2 generates the data that recommend consumes. Each slice is independently
deployable and testable.

---

### Slice A — cron-fix: correctness bug in period_ticks

**What:** In `bin/massoh-cron` lines 144–148, `every_mins` is hardcoded to 30 regardless of the
`--every` argument passed to `cmd_once`. Fix: parse `--every` in `cmd_once` (the same way
`cmd_install` parses it at line 190) and pass the resolved minutes value into the period_ticks
calculation. Also: log per-tick duration (seconds) to cron output as a single `say` line at tick
end.

**Minimal version:**
1. Add `--every` flag parsing to `cmd_once` (mirroring cmd_install's case statement).
2. Derive `every_mins` from the parsed value instead of the hardcoded 30.
3. Capture `tick_start=$(date +%s)` before the work block; print `tick_duration` in seconds with
   `say` at the end of `cmd_once`.
4. Update `cmd_install`'s generated crontab line to pass `--every $every` to `cron once` so the
   installed schedule stays consistent.

**Non-goals:**
- Do not add tick-time persistence or trend analysis (that is Slice B/C territory).
- Do not change cron output format beyond the single duration `say` line.
- Do not change any other flag behavior.

**Safety / guardrail impact:**
- `bin/massoh-cron` is safety-critical (NON_NEGOTIABLES.md). Owner sign-off on record.
- The fix is additive: existing installs with no `--every` flag will still default to 30m (same
  behavior). The default must be preserved.
- POSIX-bash, `set -euo pipefail` must remain intact.
- No new external deps.

**Acceptance criteria (fixture-based, zero LLM spend):**
- T_A1: `massoh cron once --dry-run --every 60m` prints a dry-run block and does NOT compute
  period_ticks using 30 (i.e., for `--every 60m --period-days 7` the resolved period_ticks is
  7*1440/60=168, not 7*1440/30=336). Verify via a test helper that injects a fake cadence_state
  and checks the counter threshold.
- T_A2: `massoh cron once --dry-run --every 30m` (default) behaves identically to the current
  behavior (period_ticks = 336 for 7-day period). Regression guard.
- T_A3: cron once output in run mode contains "tick_duration=" (or equivalent "tick:" line with
  seconds) after the tick completes. Test with `NO_IDLE=1 MASSOH_AGENT_CMD=... --run` in the
  existing test harness pattern.
- T_A4: `massoh cron install --every 15m` generates a crontab line containing `--every 15m` in
  the `cron once` call. Verify by capturing the `say` output.
- All existing cron tests (test/run.sh) remain green (no regression).

**Kill / defer criteria:**
- If parsing --every in cmd_once requires structural refactoring beyond 15 lines of bash, scope
  down to only the period_ticks derivation from an env var (MASSOH_EVERY_MINS) as a zero-risk
  intermediate.

---

### Slice B — review-v2: cycle time, rework rate, throughput

**What:** Extend `cmd_review` in `bin/massoh` to compute and output three new KPIs, then include
them in the METRICS.md snapshot line.

- **Cycle time** (per packet): `00_request.md` mtime → `06_review_result.md` mtime in days
  (or hours for sub-day). Report min/max/avg across all packets that have both files. If git
  history is available, fall back to branch-first-commit → merge-commit date (but file mtime is
  simpler and sufficient for MVP).
- **Rework rate**: count of packets where `06_review_result.md` contains "REQUEST CHANGES" (any
  case). `rework_count / total_reviewed * 100`%. One grep pass per file.
- **Throughput**: packets with `06_review_result.md` present within the `--since` window (already
  partially present as `prev` but not reported as a rate). Express as `N done / since_days`.

All three are heuristic / read-only. No LLM. Uses the same file-walk the current `cmd_review`
already does (the `for d in "$repo"/.agent_tasks/TASK-*/` loop).

**Minimal version:**
1. During the existing packet walk, capture: request_mtime, review_mtime, has_request_changes flag
   per packet. Use `stat -c %Y` (Linux) with `stat -f %m` (macOS) fallback or `find -newer` trick
   for portability.
2. After the walk: compute avg_cycle_days, rework_pct, throughput_per_week.
3. Append to the existing `report` string (same `say` + METRICS.md write path).
4. METRICS.md snapshot gains three new fields: `cycle_avg_days=`, `rework_pct=`, `throughput/wk=`.

**Non-goals:**
- Do not compute per-packet cycle time breakdowns in the snapshot (only aggregate).
- Do not change the existing `review` output lines — append new lines only.
- Do not add git-log-based cycle time in this slice (file mtime is sufficient for MVP).
- Do not add visualization or charting.

**Safety / guardrail impact:**
- `bin/massoh` is safety-critical. Owner sign-off on record.
- Pure read + append-only (METRICS.md append). NON_NEGOTIABLES "keep older data" satisfied.
- `stat` portability: must work on Linux and macOS (POSIX requirement). Use `find -newer` or store
  mtime via `awk`/`ls -t` if `stat` format differs. Document the portability choice in comments.
- `set -euo pipefail`: all new subshells must use `|| true` guards on optional reads (same pattern
  as existing cmd_review grep calls).

**Acceptance criteria (fixture-based, zero LLM spend):**
- T_B1: Create fixture `.agent_tasks/TASK-fixture-a/` with `00_request.md` (older) and
  `06_review_result.md` (newer, contains "REQUEST CHANGES"). `massoh review --no-write` output
  contains `cycle_avg_days=`, `rework_pct=100`, `throughput/wk=`.
- T_B2: With two fixture packets — one with REQUEST CHANGES, one with APPROVE only —
  `rework_pct` is 50 (1 of 2). Verify string match in output.
- T_B3: METRICS.md snapshot (--write mode on fixture repo) gains the three new field lines.
  Verify by grepping the appended block.
- T_B4: Packets missing `06_review_result.md` are excluded from cycle time avg and rework rate
  (no division-by-zero, no crash). Test with a packet that has only `00_request.md`.
- T_B5: All existing `review` tests remain green.

**Kill / defer criteria:**
- If `stat` portability across Linux/macOS proves fragile in test harness, fall back to using
  `ls -t` ordering or `find`-based comparison. Do not ship if cycle time is always 0 or always
  wrong on either platform.

---

### Slice C — massoh recommend: forward heuristic suggestions

**What:** New verb `massoh recommend` in `bin/massoh`. Read-only. Reads the last N snapshot
blocks from `agent-project/METRICS.md` plus the current `review` output (or a fresh `--live`
capture). Applies heuristic rules to produce a ranked list of suggestions, printed to stdout.
Optionally appends to `AGENT_SYNC.md` as a `[recommend]` block (same pattern as `[standup]`
and `[plan]`).

**Heuristic rules (MVP — all additive, no LLM):**

| Rule ID | Trigger | Suggestion |
|---|---|---|
| R1 | cycle_avg_days rising across last 2 snapshots | "Cycle time climbing — consider tightening product scope (smaller slices) in next planning pass." |
| R2 | rework_pct > 25% | "High rework rate — arch/safety review may be too shallow; consider deepening 03 conditions." |
| R3 | revert commits > 0 in last snapshot | "Revert spike detected — consider adding regression test coverage before next feature." |
| R4 | TODO backlog grows while done/wk flat or falling across 2 snapshots | "Throughput bottleneck — backlog growing faster than delivery; re-rank or reduce parallel work." |
| R5 | No snapshots found | "No METRICS.md snapshots yet — run `massoh review` to capture a baseline." |

Rules fire independently. Output is a numbered ranked list (most severe first, by simple ordering:
R2 > R1 > R4 > R3 > R5). "No issues detected" if no rules fire.

**Minimal version:**
1. `cmd_recommend` function in `bin/massoh`.
2. Parse last 2 `## Snapshot` blocks from `agent-project/METRICS.md` using `awk`.
3. Extract: cycle_avg_days, rework_pct, throughput/wk, revert count, TODO count, DONE count per
   block.
4. Apply rules R1–R5; collect fired rules.
5. Print ranked list to stdout.
6. `--write` flag: append `[recommend]` block to AGENT_SYNC.md (default OFF — explicit opt-in
   only, to avoid noisy autonomous appends; cron can pass --write).
7. Wire into `case` dispatch at end of `bin/massoh`.

**Non-goals:**
- No LLM calls. No `claude -p`. Zero spend.
- No config for rule thresholds in this slice (hardcoded MVP values only).
- No trend analysis beyond 2 snapshots.
- Do not add recommend to the cron cadence automatically — leave that for the owner to opt in.
- Do not parse prose descriptions; only parse structured field lines from METRICS.md snapshots.

**Safety / guardrail impact:**
- `bin/massoh` is safety-critical. Owner sign-off on record.
- Read-only by default; `--write` only touches `AGENT_SYNC.md` (not a safety-critical file).
- All reads are `|| true` guarded (no crash on missing/malformed METRICS.md).
- No destructive action possible — the verb is advisory only.
- Expansion note: rule text strings are English; extracted numeric fields are locale-neutral. If
  METRICS.md snapshot format ever changes, the awk parser breaks silently (returns R5). That is
  acceptable failure-mode for MVP; document in comments.

**Acceptance criteria (fixture-based, zero LLM spend):**
- T_C1: Fixture METRICS.md with 2 snapshots where cycle_avg_days increases. `massoh recommend`
  output contains R1 suggestion text. No crash.
- T_C2: Fixture with rework_pct=50 triggers R2 suggestion.
- T_C3: Fixture with revert=2 triggers R3 suggestion.
- T_C4: Fixture with TODO growing and throughput/wk flat triggers R4.
- T_C5: Empty/missing METRICS.md triggers R5 ("No METRICS.md snapshots").
- T_C6: Fixture with no rule triggers prints "No issues detected."
- T_C7: `--write` appends a `[recommend]` block to AGENT_SYNC.md; `--no-write` (default) does
  not touch any file. Verify by checking file mtime before/after in test harness.
- T_C8: All existing tests remain green.

**Kill / defer criteria:**
- If awk parsing of the current METRICS.md snapshot format proves unreliable (format is prose
  with variable spacing), replace with a simpler grep-based field extraction. Defer if no reliable
  extraction is possible without changing the METRICS.md format — do not change the format in
  this slice.

---

## 5. Non-goals (bundle-level)

- No LLM calls anywhere in this bundle.
- No new external dependencies.
- No changes to the packet format (`00`–`06` spine), `manifest.yml`, install/uninstall contract,
  or `templates/`.
- No telemetry wiring or remote reporting.
- No charting, dashboards, or non-CLI output formats.
- Do not generalize to multi-harness or multi-owner in this pass.
- Do not add `recommend` to the cron cadence automatically (owner-opt-in only).

---

## 6. Required events (named)

From `agent-project/METRICS.md` (existing):
- `packet_merged` — review-v2 instruments cycle time and rework rate against this event.

New sub-fields authorized for METRICS.md snapshot rows (not new top-level events):
- `cycle_avg_days` — average 00→06 span across reviewed packets
- `rework_pct` — % packets with REQUEST CHANGES before APPROVE
- `throughput/wk` — reviewed packets per week in the --since window

New output:
- `tick_duration_secs` — per-tick wall-clock duration in cron output (not persisted to METRICS.md)

---

## 7. Safety and guardrail summary

| File touched | Safety-critical? | Sign-off | Notes |
|---|---|---|---|
| `bin/massoh-cron` | Yes | On record (00_request.md) | Slice A only; additive flag + default preserved |
| `bin/massoh` | Yes | On record (00_request.md) | Slices B + C; no install/uninstall/block logic touched |
| `agent-project/METRICS.md` | No | N/A | Append-only; NON_NEGOTIABLES "keep older data" satisfied |
| `AGENT_SYNC.md` | No | N/A | Append-only; only with --write flag in Slice C |
| `test/run.sh` | No | N/A | New test cases appended; existing cases must remain green |

Guardrail A5 (real tests): each slice requires fixture-based tests before implementation is
considered done. Stub-only tests are rejected.
Guardrail A9 (scope discipline): implementer must not add observability, config, or new verbs
beyond the three slices described here.

---

## 8. Expansion and localization impact

No hard-coding of the wedge. Slice C rule-text is English; the numeric extraction is
locale-neutral. If the project later runs in a non-English environment, the rule trigger logic
(numbers and counts) remains valid; only the output strings need localization. Flag that as a
NEXT item, not a blocker.

---

## 9. Acceptance criteria (bundle-level testable)

1. `massoh cron once --dry-run --every 60m` resolves period_ticks as 168 for a 7-day period, not
   336. (Slice A correctness.)
2. `massoh cron once --dry-run --every 30m` resolves period_ticks as 336. (Slice A non-regression.)
3. After a real cron tick (run mode, with NO_IDLE=1 and fake agent), output contains a
   `tick_duration` line with a non-negative integer. (Slice A observability.)
4. `massoh review` on a repo with fixture packets outputs cycle_avg_days, rework_pct, and
   throughput/wk. (Slice B.)
5. `massoh review` never crashes on packets missing `06_review_result.md`. (Slice B robustness.)
6. `massoh recommend` fires R1–R5 rules correctly against fixture METRICS.md data. (Slice C.)
7. `massoh recommend` without --write leaves all files untouched. (Slice C safety.)
8. All existing tests in `test/run.sh` remain green after each slice lands. (Non-regression,
   enforced per slice, not only at bundle end.)

---

## 10. Kill / defer criteria (bundle-level)

- If Slice A cannot cleanly parse --every in cmd_once without touching the cmd_install flow,
  scope to env-var injection (MASSOH_EVERY_MINS) and defer the cmd_once flag.
- If Slice B's `stat` portability cannot be solved cleanly in bash for both Linux and macOS,
  defer cycle time; ship rework rate + throughput only (those use grep/count, no mtime).
- If Slice C's awk parsing of METRICS.md is consistently unreliable due to snapshot format
  variability, defer Slice C until review-v2 stabilizes the snapshot format (Slice B first).
- Do not defer the cron-fix (Slice A) — it is a correctness bug with a confirmed deviation noted
  in the cadence-cron handoff. Defer criteria for the tick-time logging portion only.

---

## 11. Routing

Build order: Slice A → Slice B → Slice C.
Each slice routes independently: **architecture-safety** (all three touch safety-critical files or
produce new CLI output requiring a safety review). UX review is not required (internal CLI tool,
no user-facing UI).

Architecture-safety conditions to evaluate per slice:
- Slice A: is the --every parsing in cmd_once safe from injection? Does the default-30 fallback
  hold? Is tick-time logging suppressed in dry-run mode?
- Slice B: is stat/find portability handled? Are all grep/awk calls || true guarded? Does METRICS.md
  append remain idempotent?
- Slice C: is --write default-OFF enforced? Are all file reads || true guarded? Can the awk
  parser corrupt AGENT_SYNC.md on malformed input?

Next agent: **massoh-architecture-safety** (Slice A first; return for B, then C after each
implementation handoff).
