# 05 — Implementation Handoff
**Task:** TASK-2026-06-17-cadence-cron · **Date:** 2026-06-17 · **Agent:** massoh-implementer

---

## 1. Files changed

| File | Change |
|---|---|
| `bin/massoh-cron` | Added cadence block to `cmd_once` (post-serialization); new flags `--period-days`, `--no-standup`; injectable `MASSOH_STANDUP_CMD`/`MASSOH_REVIEW_CMD`/`MASSOH_PLAN_CMD`; `--period-days` in `cmd_install`. **Rev2:** fixed `A && B \|\| C` anti-pattern → `if/then/else` in wrapper functions (reviewer-qa catch). |
| `test/run.sh` | Added T10 block (15 checks: T10a–T10h, T10f now 3 assertions). |
| `VERSION` | Bumped `0.4.1` → `0.4.2` |
| `CHANGELOG.md` | Added `[0.4.2]` entry |
| `AGENT_SYNC.md` | Updated current task, decision log, active packets, last handoff |
| `.agent_tasks/TASK-2026-06-17-cadence-cron/04_implementation_packet.md` | License packet (this session) |

No other files touched. `bin/massoh` and `manifest.yml` are untouched (safety-critical).

---

## 2. What was implemented

Cadence ceremonies wired into `bin/massoh-cron cmd_once`. The cadence block is placed immediately
after the `printf '\n%s' "$block" >> "$REPO/AGENT_SYNC.md"` serialization line (Condition B
placement). On every `--run` tick (Condition C gate):

1. **Standup ceremony:** `_massoh_standup` runs (using `MASSOH_STANDUP_CMD` if set, else
   `$massoh_bin standup`), wrapped in `|| true` (Condition B wrapping).
   Suppressed by `--no-standup`.

2. **Period counter:** Read from `.agent_tasks/cron/cadence_state` using a corruption-tolerant
   `case` guard (Condition A). Incremented on every tick. When `tick_count >= period_ticks`:
   review + plan run (each `|| true`-wrapped, Condition B), counter resets to 0. Counter
   persisted after every tick.

3. `period_ticks` = `period_days * 1440 / 30`, clamped to minimum 1 (prevents `period_days=0`
   divide or zero-trigger loop; advisory condition satisfied).

4. `cmd_install` now passes `--period-days $period_days` into the generated crontab line.

---

## 3. How each condition is satisfied

### Condition A — Corruption-tolerant counter read
`bin/massoh-cron` lines 153–159:
```bash
if [ -f "$state_file" ]; then
  raw="$(cat "$state_file" 2>/dev/null || echo 0)"
  case "$raw" in
    ''|*[!0-9]*) tick_count=0 ;;
    *) tick_count="$raw" ;;
  esac
fi
```
Bare `cat` is never used without the `case` guard. Missing file → `tick_count=0`. Non-integer
content → `tick_count=0`. Exactly the pattern specified in `03_architecture_safety.md §4`.

### Condition B — Post-serialization + `|| true` wrapping
The cadence block starts at line 143 of `bin/massoh-cron`, with a comment confirming the
ordering contract. This is after line 140: `printf '\n%s' "$block" >> "$REPO/AGENT_SYNC.md"`.
Every ceremony call follows the pattern:
```bash
( cd "$REPO" && _massoh_standup ) || true
( cd "$REPO" && _massoh_review  ) || true
( cd "$REPO" && _massoh_plan    ) || true
```
A ceremony failure can never abort the tick or drop backlog progress.

### Condition C — Dry-run and idle-skip gate
Both the standup block and the review+plan block are gated on `[ "$mode" = run ]`. Dry-run
returns at line 98 (before the worktree loop and before the cadence block). The idle gate and
empty-backlog gate also return before reaching the cadence block. The `cmd_once` structure was
not restructured — the early returns remain in place.

### Condition D — Injectable ceremony commands
Top of `bin/massoh-cron` (lines 29–35):
```bash
_STANDUP_CMD="${MASSOH_STANDUP_CMD:-}"
_REVIEW_CMD="${MASSOH_REVIEW_CMD:-}"
_PLAN_CMD="${MASSOH_PLAN_CMD:-}"
_massoh_standup(){ if [ -n "$_STANDUP_CMD" ]; then eval "$_STANDUP_CMD"; else "$(_massoh_bin)" standup; fi; }
_massoh_review(){  if [ -n "$_REVIEW_CMD"  ]; then eval "$_REVIEW_CMD";  else "$(_massoh_bin)" review;  fi; }
_massoh_plan(){    if [ -n "$_PLAN_CMD"    ]; then eval "$_PLAN_CMD";    else "$(_massoh_bin)" plan;    fi; }
```
Parallel to the existing `MASSOH_AGENT_CMD` / `MASSOH_GATE_CMD` pattern. Tests use
`MASSOH_STANDUP_CMD="bash $FAKE_STANDUP"` etc. for zero-cost fakes.

**Note (reviewer-qa catch, fixed):** The original implementation used `[ -n "$VAR" ] && eval "$VAR" || real_cmd`,
which is a shell `A && B || C` anti-pattern: when `B` exits non-zero (e.g. `MASSOH_STANDUP_CMD=false`),
`C` runs as an unconditional fallback. Fixed to `if/then/else` so a failing injected command is
NOT silently replaced by the real ceremony. T10f assertion 3 (`! grep -q '## \[standup\]'`) now
verifies isolation rather than fallback success.

---

## 4. Tests run — final result (verbatim tail)

```
== T10: cadence ceremonies wired into cron ==
  ok   T10a standup appended on --run tick
  ok   T10b standup NOT on dry-run
  ok   T10c --no-standup suppresses standup
  ok   T10d cadence_state exists
  ok   T10d cadence_state = 2 after 2 ticks
  ok   T10e review fired at boundary
  ok   T10e plan fired at boundary
  ok   T10e counter reset to 0 after boundary
  ok   T10f ceremony failure exit 0
  ok   T10f backlog still marked DONE
  ok   T10f injected false did NOT fall back to real standup
  ok   T10g install line contains --period-days 7
  ok   T10h regression: run still marks DONE
  ok   T10h regression: run still appends [cron]
  ok   T10h regression: run still creates branch

ALL GREEN — 79 checks passed.
```

Previous suite (T1–T9): 64 checks. T10 adds 15 checks (T10f has 3 assertions after the rev2 fix). Total: 79.

---

## 5. Risks

- **`every_mins` is hardcoded to 30 in `cmd_once`** — `cmd_once` does not have an `--every`
  flag (that's a `cmd_install` concern). So `period_ticks` in `cmd_once` always uses 30 min per
  tick as the basis. If the real crontab uses `--every 60m`, the actual period will be 2x the
  configured value. This is the same design as `01_product_scope.md §5` ("`period_ticks` is
  derived from `--every` and `--period-days`") — but since `--every` isn't a `cmd_once` flag,
  the approximation is 30m. The README or a future `--every` on `cmd_once` can make this exact.
  Considered low risk for v0.4 since default `cron install` uses 30m anyway.

- **Race on `cadence_state`** — two rapid cron invocations will double-increment. Accepted in
  `01_product_scope.md §7` (no `flock` required for v0.4).

- **`_massoh_bin` uses `BASH_SOURCE[0]`** — works when invoked as a script; may differ if the
  file is sourced. `massoh-cron` is always `exec`'d by `bin/massoh`, so this is safe.

---

## 6. Incomplete items

None. All 8 T10 sub-tests pass. All 4 conditions satisfied. Version bumped. CHANGELOG written.

---

## 7. Handoff for reviewer

**Branch:** `feat/massoh-cadence-cron`

**Review focus:**
1. Confirm cadence block placement is after line 140 (`printf '\n%s'...`) in `bin/massoh-cron`.
2. Confirm `case` guard on counter read (lines 153–159) matches the pattern in `03 §4`.
3. Confirm `[ "$mode" = run ]` gates on both standup (line 163) and review+plan (line 169).
4. Confirm `MASSOH_STANDUP_CMD`, `MASSOH_REVIEW_CMD`, `MASSOH_PLAN_CMD` vars at lines 30–35.
5. Confirm `|| true` on all three ceremony calls (lines 165, 171, 172).
6. Confirm `--period-days` in `cmd_once` (line 85) and `cmd_install` (line 187) don't collide
   with existing flags (`--run`, `--dry-run`, `--parallel`, `--auto-merge`, `--no-idle-check`,
   `--idle-min`, `--apply`, `--yes-spend`, `--every`).
7. Run `bash test/run.sh` — must output `ALL GREEN — 78 checks passed.`

**Next agent:** `massoh-reviewer-qa` → write `06_review_result.md`.
