# 04 — Implementation Packet (License)
**Task:** TASK-2026-06-17-cadence-cron · **Date:** 2026-06-17 · **Agent:** massoh-implementer

---

## Status: LICENSED FOR IMPLEMENTATION

This packet restates the approved scope, the four mandatory conditions from
`03_architecture_safety.md`, and the T10 test list as the acceptance gate. Implementation may
proceed within these exact bounds.

---

## Approved scope (verbatim from 01 + 03)

Wire cadence ceremonies into the cron runner (`bin/massoh-cron` only):
- On every `--run` tick: run `massoh standup` (appends `## [standup]` to `AGENT_SYNC.md`).
- On every Nth tick (where N = `period_ticks` derived from `--period-days`, default 7): run
  `massoh review` + `massoh plan`, then reset the period counter to 0.
- Counter stored in `.agent_tasks/cron/cadence_state` (create-if-missing, single integer line).
- New flags on `cron once`: `--period-days N` (default 7), `--no-standup`.
- New flag on `cron install`: `--period-days N` (passed through to generated crontab line).

**Change surface:** `bin/massoh-cron` (one file) + `test/run.sh` (T10 block) + `VERSION` +
`CHANGELOG.md`. Nothing else.

**Explicit non-goals (must not be built):**
- No changes to `bin/massoh`, `manifest.yml`, the block markers, the backup logic, or the
  uninstall set.
- No changes to `cmd_review`, `cmd_standup`, or `cmd_plan`.
- No telemetry, no UI, no new named metrics events.
- No per-project cadence overrides.
- No `massoh review --run-tests` from cron.

---

## Four mandatory conditions (from 03_architecture_safety.md §10)

**Condition A — Corruption-tolerant counter read (mandatory).**
Default `tick_count=0` on any non-integer or missing state file content, using an explicit integer
guard (case/pattern match). Do not use bare `$(cat ...)` without validation. The required pattern:

```bash
tick_count=0
if [ -f "$state_file" ]; then
  raw="$(cat "$state_file" 2>/dev/null || echo 0)"
  case "$raw" in
    ''|*[!0-9]*) tick_count=0 ;;
    *) tick_count="$raw" ;;
  esac
fi
```

**Condition B — Post-serialization placement + `|| true` wrapping (mandatory, safety-critical).**
The cadence block MUST be placed after the AGENT_SYNC.md serialization write (after
`printf '\n%s' "$block" >> "$REPO/AGENT_SYNC.md"`). Every ceremony call MUST be wrapped in
`|| true`. This ordering is load-bearing: a ceremony failure must never drop backlog progress.

**Condition C — Dry-run and idle-skip gate (mandatory).**
Ceremonies MUST be gated on `[ "$mode" = run ]`. No ceremony file write on dry-run. No ceremony
call when the idle gate or empty-backlog gate fires (those early-return before the cadence block
anyway — the implementer must not restructure `cmd_once` in a way that bypasses this).

**Condition D — Injectable ceremony commands for testing (mandatory).**
Expose `MASSOH_STANDUP_CMD`, `MASSOH_REVIEW_CMD`, and `MASSOH_PLAN_CMD` injectable env vars
(defaulting to the massoh binary's standup/review/plan sub-commands), matching the
`MASSOH_AGENT_CMD` / `MASSOH_GATE_CMD` pattern already in the codebase. This is the only way to
write a reliable T10f test for ceremony failure isolation.

---

## T10 test list (acceptance gate — all 8 must pass)

### T10a — standup runs on a --run tick
Invoke `cron once --run --no-idle-check` in a mkcronrepo repo (using fake agent + gate).
Assert `AGENT_SYNC.md` contains a `## [standup]` line.

### T10b — standup does NOT run on dry-run
Invoke `cron once --no-idle-check` (default dry-run).
Assert `AGENT_SYNC.md` does NOT contain `## [standup]`.

### T10c — --no-standup suppresses standup
Invoke `cron once --run --no-idle-check --no-standup`.
Assert `AGENT_SYNC.md` does NOT contain `## [standup]`.

### T10d — cadence_state created and increments
After two `--run` ticks, assert `.agent_tasks/cron/cadence_state` exists and contains `2`.

### T10e — review+plan fire at period boundary, counter resets
Pre-seed `.agent_tasks/cron/cadence_state` with `period_ticks - 1` (using `--period-days 1
--every 1440m` giving period_ticks=1, so seed with `0`). Invoke once. Assert
`agent-project/METRICS.md` contains `## Snapshot` and `AGENT_SYNC.md` contains `## [plan]`.
Assert `.agent_tasks/cron/cadence_state` contains `0` (reset after boundary).

### T10f — ceremony failure does NOT abort the tick
Set `MASSOH_STANDUP_CMD=false` and `MASSOH_REVIEW_CMD=false` and `MASSOH_PLAN_CMD=false`.
Assert the cron tick still exits 0 and `AGENT_BACKLOG.md` still has `| DONE |`.

### T10g — cron install --period-days passes through to crontab line
Assert `cron install --every 30m --period-days 7` output contains `--period-days 7` in the
printed crontab line.

### T10h — existing T7 still passes (regression)
All T7 sub-tests must continue to pass unmodified.

---

## VERSION + CHANGELOG

- Bump `VERSION`: `0.4.1` → `0.4.2`
- Add `CHANGELOG.md` entry `[0.4.2]` with the cadence wiring description.

---

## Branch
`feat/massoh-cadence-cron` (already checked out by orchestrator — do NOT switch).

## Co-Authored-By trailer
`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
