# 04 — Implementation Packet (License)
**Task:** TASK-2026-06-17-efficiency-v2
**Date:** 2026-06-17
**Agent:** massoh-implementer
**Decision: LICENSED — implement all 3 slices in order A → B → C**

Owner sign-off on editing `bin/massoh` and `bin/massoh-cron` is on record in `00_request.md`
("Full efficiency v2 bundle (agent-driven)" selection). Architecture-safety APPROVED all 3
slices in `03_architecture_safety.md` with mandatory per-slice conditions. This packet restates
those conditions and acceptance tests as the implementation license.

---

## Slices + mandatory conditions

### Slice A — cron tick-time fix (bin/massoh-cron)

**What to build:**
1. Add `--every <DUR>` flag to `cmd_once` using the SAME case-pattern as `cmd_install` line 190.
2. Derive `every_mins` from the parsed `--every` value (not hardcoded 30).
3. Capture `tick_start=$(date +%s)` AFTER the dry-run early-return guard.
4. Print `tick_duration=<N>s` via `say` at end of the run block (NEVER in dry-run path).
5. Update `cmd_install`'s generated crontab line to include `--every $every`.

**Mandatory conditions (from 03_architecture_safety.md §6):**
- **A1:** `--every` parsing MUST replicate exactly the `cmd_install` case pattern:
  `*m) mins="${every%m}";; *h) mins=$(( ${every%h} * 60 ));; *) mins=30;;` — numeric extraction
  only via bash parameter expansion; `*) mins=30` catch-all default preserved.
- **A2:** `tick_start=$(date +%s)` MUST be captured AFTER the dry-run early-return block.
  `tick_duration` say MUST NOT appear in the dry-run path. A test asserts dry-run output does
  NOT contain "tick_duration".
- **A3:** Default-30 fallback MUST appear in the case catch-all (`*) mins=30`), not as a
  separate post-parse override.
- **A4:** The cadence counter block (lines 150–177 of bin/massoh-cron at time of writing) MUST
  NOT be altered. Only `every_mins=30` and the `period_ticks` derivation line change.
- **A5:** `cmd_install`'s generated crontab line MUST include `--every $every` in the
  `cron once` call. T12e verifies this.

**Acceptance tests (T12):**
- T12a: `--every 60m` resolves period_ticks=168 for 7-day period (not 336).
- T12b: `--every 30m` (default) resolves period_ticks=336 — regression guard.
- T12c: dry-run output does NOT contain "tick_duration".
- T12d: run-mode output DOES contain "tick_duration=".
- T12e: `cron install --every 15m` generated crontab line contains "--every 15m".

---

### Slice B — review-v2 KPIs (bin/massoh cmd_review)

**What to build:**
1. During the existing packet walk, use `git log -1 --format=%ct -- "$f"` for 00_request.md
   and 06_review_result.md timestamps. If a file is not in git history → cycle time = "n/a"
   for that packet (degrade gracefully).
2. Compute: `cycle_avg_days` (avg 00→06 span), `rework_pct` (packets with REQUEST CHANGES /
   total reviewed * 100), `throughput/wk` (packets with 06 in last 7 days / (since/7)).
3. Append three new KPI lines to the same METRICS.md `## Snapshot` block (not a new block).
4. Print three new KPI lines in the `say` output.

**Mandatory conditions:**
- **B1:** MUST use `git log -1 --format=%ct -- "$f"` for dates. `stat -c` / `stat -f` BANNED.
  If file not in git history → cycle time "n/a" for that packet.
- **B2:** Every new grep, awk, wc call MUST end with `|| true`.
- **B3:** Division-by-zero guard: if `total_reviewed -eq 0` → `rework_pct=0`; if `since_days=0`
  → `throughput/wk=n/a`.
- **B4:** New KPI lines appended WITHIN the same `## Snapshot` block. `--no-write` remains inert.
- **B5:** `--no-write` checksum test (T13g) mirrors T8 pattern.

**Acceptance tests (T13):**
- T13a: single packet with both files: output contains `cycle_avg_days=`, `rework_pct=`, `throughput/wk=`.
- T13b: rework_pct=100 on single packet with REQUEST CHANGES.
- T13c: rework_pct=50 on two packets (one with, one without REQUEST CHANGES).
- T13d: packet missing 06 excluded from cycle time + rework; no crash.
- T13e: 0 reviewed packets → exit 0, rework_pct=0 or n/a.
- T13f: METRICS.md snapshot gains new fields; append-only (two runs = two snapshots).
- T13g: `--no-write` leaves checksum unchanged.
- T13h: all existing T8 tests remain green.

---

### Slice C — massoh recommend (new verb in bin/massoh)

**What to build:**
1. `cmd_recommend` function in `bin/massoh`, following `cmd_learn` pattern.
2. Parse last 2 `## Snapshot` blocks from `agent-project/METRICS.md` using `awk || true`.
3. Apply rules R1–R5; collect fired rules; print ranked list to stdout.
4. `--write` flag (default OFF): append `## [recommend] <ts>` block to AGENT_SYNC.md via `>>`.
5. Wire into `case` dispatch + update `die "unknown command"` verb list.

**Heuristic rules:**
- R1: cycle_avg_days rising across 2 snapshots → "Cycle time climbing — consider tightening product scope..."
- R2: rework_pct > 25 → "High rework rate — arch/safety review may be too shallow..."
- R3: reverts > 0 → "Revert spike detected — consider adding regression test coverage..."
- R4: TODO growing while throughput/wk flat or falling across 2 snapshots → "Throughput bottleneck..."
- R5: No snapshots found → "No METRICS.md snapshots yet — run `massoh review` to capture a baseline."
- Default (no rules fire): "No issues detected."

**Mandatory conditions:**
- **C1:** `write_recommend=0` MUST be the initial assignment. `--write` toggles to 1.
- **C2:** `--write` path MUST use `>>` (append, not `>`). Code comment names it as the sole
  permitted write. awk METRICS.md parse MUST be `|| true` wrapped.
- **C3:** Every grep, awk, wc, cat call in `cmd_recommend` MUST end with `|| true`.
- **C4:** Count parsed snapshots. If count < 2, suppress R1 and R4. If count == 0, fire R5 only.
- **C5:** `--write` path writes ONLY to `"$repo/AGENT_SYNC.md"`. Comment mirrors cmd_learn's
  `# SAFETY: only permitted write` pattern.
- **C6:** NO cron invocation of `recommend` anywhere — `cmd_cron` dispatch unchanged.

**Acceptance tests (T14):**
- T14a: R1 fires on rising cycle_avg_days across 2 snapshots.
- T14b: R2 fires on rework_pct=50 (> 25 threshold).
- T14c: R3 fires on reverts=2.
- T14d: R4 fires on TODO growing + throughput/wk flat across 2 snapshots.
- T14e: R5 fires on empty/missing METRICS.md.
- T14f: "No issues detected" when no rules fire.
- T14g: `--write` appends `[recommend]` to AGENT_SYNC.md; no-flag default does NOT write.
- T14h: malformed METRICS.md → exit 0, R5 or "No issues detected" (no crash).
- T14i: all existing tests remain green.

---

## Version bump
- VERSION: 0.5.1 → 0.6.0
- CHANGELOG.md: add [0.6.0] entry

## Do NOT touch
- `manifest.yml`
- install/uninstall/backup/block logic in bin/massoh
- `cmd_cron` dispatch in bin/massoh
- cadence counter block in bin/massoh-cron (lines ~150–177 at time of writing)
- Any verb not in the 3 slices above

## Build order
1. Implement Slice A → run `bash test/run.sh` → must be GREEN before Slice B.
2. Implement Slice B → run `bash test/run.sh` → must be GREEN before Slice C.
3. Implement Slice C → run `bash test/run.sh` → final GREEN.
4. Write 05_implementation_handoff.md.
