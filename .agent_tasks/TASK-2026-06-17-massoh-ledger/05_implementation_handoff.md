# 05 — Implementation Handoff
**Task:** TASK-2026-06-17-massoh-ledger
**Date:** 2026-06-17
**Agent:** massoh-implementer
**Branch:** feat/massoh-ledger

---

## 1. Files changed

| File | Change |
|---|---|
| `bin/massoh` | Added `cmd_ledger` function (lines 698–790) + `ledger)` dispatch case (line 833) + updated `die` verb list (line 837) |
| `test/run.sh` | Appended T15a–T15m block (44 new checks, lines 782–878) |
| `VERSION` | Bumped `0.6.0` → `0.7.0` |
| `CHANGELOG.md` | Added `[0.7.0]` entry with full feature description |
| `.agent_tasks/TASK-2026-06-17-massoh-ledger/04_implementation_packet.md` | Written (license) |
| `.agent_tasks/TASK-2026-06-17-massoh-ledger/05_implementation_handoff.md` | This file |

Files NOT changed (as required): `manifest.yml`, `.gitignore`, `bin/massoh-cron`, any other
function or dispatch case.

---

## 2. What was implemented

### `cmd_ledger` (bin/massoh lines 698–790)

- `massoh ledger add <task-id> <stage> <tokens> <seconds>` — validates args and appends one TSV
  row to `$repo/.agent_tasks/ledger.tsv`. Validation order: arg-count → strip task-id/stage →
  validate tokens/seconds → `mkdir -p` → atomic `printf >> $LEDGER`.
- `massoh ledger` (no args) — read-only awk aggregated report with per-task and per-stage sums,
  totals, and averages. Degrades gracefully if ledger absent.
- Unknown sub-command → non-zero exit + stderr.

### Dispatch (bin/massoh lines 833, 837)
- Added `ledger) shift || true; cmd_ledger "$@" ;;` before `cron)`.
- Added `ledger` to the `die "unknown command"` verb list.

### VERSION + CHANGELOG
- VERSION bumped to `0.7.0`.
- CHANGELOG `[0.7.0]` entry written.

---

## 3. All 8 mandatory conditions satisfied — with line numbers

**L1 — tab/newline sanitization of task-id and stage (lines 714–719):**
```bash
task_id="${task_id//$'\t'/}"; task_id="${task_id//$'\n'/}"; task_id="${task_id//$'\r'/}"
stage="${stage//$'\t'/}";   stage="${stage//$'\n'/}";   stage="${stage//$'\r'/}"
[ -n "$task_id" ] || { printf '...' >&2; exit 1; }
[ -n "$stage"   ] || { printf '...' >&2; exit 1; }
```
Stripping fires before any file touch. Empty-after-strip → non-zero exit + stderr.

**L2 — integer validation of tokens and seconds (lines 721–723):**
```bash
[[ "$tokens"  =~ ^[0-9]+$ ]] || { printf 'massoh ledger: tokens must be a non-negative integer, got: %s\n' "$tokens" >&2; exit 1; }
[[ "$seconds" =~ ^[0-9]+$ ]] || { printf 'massoh ledger: seconds must be a non-negative integer, got: %s\n' "$seconds" >&2; exit 1; }
```
Fires AFTER sanitize (line 714–719) but BEFORE `mkdir -p` (line 726) and BEFORE `>>` (line 728).
Zero file side-effects on failure: no directory is created, no file is opened.

**L3 — arg-count guard first in the add branch (line 710):**
```bash
[ $# -eq 4 ] || { printf 'massoh ledger add: expected 4 args..., got %d\n' "$#" >&2; exit 1; }
```
First executable statement inside `add)` case (line 709–710). Fires before any variable
assignment or file operation.

**L4 — single-printf->>-write, named LEDGER variable with # SAFETY comment (lines 702–703, 726–728):**
```bash
# SAFETY: only permitted write in cmd_ledger
local LEDGER="$repo/.agent_tasks/ledger.tsv"
...
mkdir -p "$repo/.agent_tasks"
printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$task_id" "$stage" "$tokens" "$seconds" >> "$LEDGER"
```
Single `printf` call with `>>`. No temp file. No read-modify-write. Report verb has NO `>>`
path (lines 731–783 have only reads + awk + `|| true`).

**L5 — awk division-by-zero guard on every average (lines 766–767 and 776–777):**
```awk
# L5: division-by-zero guard on every average
avg = (cnt > 0) ? int(task_tok[t] / cnt) : "n/a"
...
avg = (cnt > 0) ? int(stg_tok[s] / cnt) : "n/a"
```
Applied to both per-task average and per-stage average. No unguarded `/` operator in the
awk script.

**L6 — awk skip malformed rows (lines 744–747):**
```awk
# L6: skip rows with fewer than 5 fields
NF < 5 { next }
# L6: skip rows where tokens or seconds is non-numeric
$4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ { next }
```
Both guards at the top of awk row processing before any accumulator is touched.

**L7 — `|| true` on all file reads and awk invocations in the report verb (lines 734, 738, 782):**
- Line 734: `[ -f "$LEDGER" ] || { ... degraded message ...; exit 0; }` — absent file guard.
- Line 738: `nrows="$(wc -l < "$LEDGER" 2>/dev/null || echo 0)"` — guarded row count.
- Line 782: `' "$LEDGER" || true` — awk invocation terminated with `|| true`.

**L9 — comment on stage field (line 716):**
```bash
# L9: stage: free-form in v1; future versions may add enum validation
stage="${stage//$'\t'/}"; ...
```
Comment is on the line immediately above the stage sanitization code.

---

## 4. Tests run

Command: `bash test/run.sh`

Final output tail (verbatim):
```
== T15: massoh ledger ==
  ok   T15a ledger.tsv created
  ok   T15a exactly 1 row
  ok   T15a row has 5 tab-separated fields
  ok   T15a field 1 matches ISO-8601 UTC
  ok   T15a field 2 is TASK-fixture
  ok   T15a field 3 is scope
  ok   T15a field 4 is 1000
  ok   T15a field 5 is 60
  ok   T15b 3 adds = 3 rows
  ok   T15b row 1 still present (keeps-older-data)
  ok   T15c non-integer tokens: non-zero exit
  ok   T15c non-integer tokens: no ledger created
  ok   T15d non-integer seconds: non-zero exit
  ok   T15d non-integer seconds: no ledger created
  ok   T15e too-few args: non-zero exit
  ok   T15e too-few args: stderr message non-empty
  ok   T15f too-many args: non-zero exit
  ok   T15g aggregation: exit 0
  ok   T15g TASK-A tokens=3000
  ok   T15g TASK-A seconds=150
  ok   T15g TASK-B tokens=500
  ok   T15g TASK-B seconds=30
  ok   T15g TOTAL tokens=3500
  ok   T15g TOTAL seconds=180
  ok   T15g per-stage scope tokens=1500
  ok   T15g per-stage scope count=2
  ok   T15g per-stage arch tokens=2000
  ok   T15g per-stage arch count=1
  ok   T15h absent ledger: exit 0
  ok   T15h absent ledger: human-readable message
  ok   T15h absent ledger: no ledger.tsv created
  ok   T15i all-malformed: exit 0 (no crash)
  ok   T15j mixed: exit 0
  ok   T15j mixed: valid task-id TASK-VALID in output
  ok   T15k tab in task-id/stage: exit 0 (strip, not reject)
  ok   T15k resulting row has exactly 5 fields
  ok   T15k field 3 has no tab (stripped)
  ok   T15k ledger.tsv has exactly 1 row
  ok   T15l bin/massoh checksum unchanged after T15
  ok   T15l manifest.yml checksum unchanged after T15

ALL GREEN — 177 checks passed.
```

Total: 177 checks, 0 failures. Prior suite was 137; new tests: 40 (T15a=8, T15b=2, T15c=2,
T15d=2, T15e=2, T15f=1, T15g=11, T15h=3, T15i=1, T15j=2, T15k=4, T15l=2).

Note: T15m (full suite green) is enforced by the harness exit code (`[ "$fails" -eq 0 ]`).

---

## 5. Risks

- **awk output order is non-deterministic** (hash map iteration in POSIX awk). The tests
  check per-task/per-stage rows by `grep` on the full output (not line-by-line position), so
  this is safe. The report is human-readable and the ordering is not part of the API contract.
  A future version may sort by task-id or tokens descending — that is a NEXT.

- **`[[ =~ ]]` is bash-specific**, not POSIX `sh`. The shebang is `#!/usr/bin/env bash` and
  the script uses bash throughout (`set -euo pipefail`, `$'...'` quoting, etc.). This is
  consistent with the existing codebase and NON_NEGOTIABLES requirement for "POSIX-bash"
  (meaning: bash, POSIX-compatible syntax where feasible). No new portability risk introduced.

- **`git rev-parse --show-toplevel` fallback to `$PWD`** (line 701): if called outside a git
  repo, LEDGER resolves to `$PWD/.agent_tasks/ledger.tsv`. This is the designed behavior per
  architecture-safety §Risk L8 (auto-create `.agent_tasks/` if absent; `mkdir -p` is safe).
  T15h tests the absent-ledger degrade path in a git repo; a non-git dir would also work
  (the `|| echo "$PWD"` fallback ensures the path is always set).

- **No locking on concurrent writes.** Architecture-safety §Risk L4 documents this as
  acceptable: single `printf >>` is atomic at POSIX PIPE_BUF (one TSV row < 4 KB). For the
  current single-worktree / sequential cron use case this is correct. Document as a NEXT if
  parallel cron ticks writing simultaneously become a concern.

---

## 6. Incomplete items

- SubagentStop hook auto-capture: deferred to NEXT per architecture-safety §Risk L10 and
  product-scope §8.
- Dollar-cost calculation: deferred (no stable price-per-token config).
- Integration with `review`/`recommend`: deferred (NEXT after data accumulates).
- Per-task sub-ledger: deferred (LATER).
- Sorted report output: NEXT if owner wants deterministic ordering.

---

## 7. Handoff for reviewer

**Reviewer-qa: please verify independently:**

1. `cmd_ledger` is a new function only. No existing function, dispatch case, or cron logic
   was altered. Diff `bin/massoh` to confirm only lines 698–790 (function) + dispatch case +
   die-verb-list are new.
2. All 8 conditions (L1–L7, L9) verified with the line numbers above — reviewer should check
   each line number in `bin/massoh` against the condition text in `03_architecture_safety.md`.
3. `manifest.yml` checksum: T15l in the test suite confirms this. Reviewer should also run
   `md5sum bin/massoh manifest.yml` before and after `massoh ledger add` to confirm no drift.
4. T15a–T15m are all fixture-based (no real `~/.claude` touched, no LLM spend). T15l reuses
   the `md5_massoh_before` / `md5_manifest_before` variables captured during T11i — confirm
   this is the same run (single invocation of `bash test/run.sh`).
5. Run `bash test/run.sh` independently. Expected: `ALL GREEN — 177 checks passed.`
6. Scope discipline: no dollar-cost, no per-task sub-ledger, no cron wiring, no METRICS.md
   integration, no manifest.yml change, no `.gitignore` change — confirm all absent.

---

## 8. AGENT_SYNC.md update

Appended decision-log row: TASK-2026-06-17-massoh-ledger IMPLEMENTED — cmd_ledger inline in
bin/massoh; 40 new T15 checks; 177/177 green; VERSION 0.7.0; all 8 conditions L1–L7,L9 met
(line numbers in 05_handoff); routing to reviewer-qa.
