# 04 — Implementation Packet (License)
**Task:** TASK-2026-06-17-massoh-ledger
**Date:** 2026-06-17
**Agent:** massoh-implementer
**Status: LICENSED — approved in 03_architecture_safety.md**

---

## 1. Scope restated

Add `cmd_ledger` to `bin/massoh` implementing two sub-commands:

- `massoh ledger add <task-id> <stage> <tokens> <seconds>` — validate args and append one
  TSV row to `.agent_tasks/ledger.tsv` in the current repo.
- `massoh ledger` (no args) — read-only awk-aggregated report: tokens + seconds per task and
  per stage, totals + per-task averages. If ledger absent → human-readable degraded message,
  exit 0, no file created.

Add `ledger` to the dispatch `case "$cmd"` in `bin/massoh` and to the `die "unknown command"`
verb list.

Bump VERSION `0.6.0` → `0.7.0` and add `[0.7.0]` entry to CHANGELOG.

Add T15a–T15m to `test/run.sh` (fixture-based, zero spend).

Do NOT touch: `manifest.yml`, backup/uninstall/install/block logic, per-repo scaffold list,
any other function or dispatch case, `.gitignore` (ledger.tsv is intentionally tracked).

---

## 2. Mandatory conditions (from 03_architecture_safety.md)

**L1 — tab/newline sanitization of task-id and stage:**
Strip `\t`, `\n`, `\r` from `task-id` and `stage` via bash parameter expansion before write.
Reject (non-zero exit, stderr, no file touch) if either field is empty after stripping.

**L2 — integer validation of tokens and seconds:**
Both fields validated with `^[0-9]+$` regex before any write or arithmetic. On failure: non-zero
exit + stderr message + ZERO file side-effects. Validation fires before `mkdir -p` or any
file creation.

**L3 — arg-count guard first:**
First statement in the `add` branch: `[ $# -eq 4 ]` — exactly 4 args after `add`. Non-zero exit
+ stderr on violation. Fires before any file operation.

**L4 — single-printf->>-write, named LEDGER variable with # SAFETY comment:**
`LEDGER="$repo/.agent_tasks/ledger.tsv"  # SAFETY: only permitted write in cmd_ledger`
Row written as a single `printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$task" "$stage" "$tokens" "$seconds" >> "$LEDGER"`.
Report verb is read-only — no `>>` path.

**L5 — awk division-by-zero guard:**
All division operations in the awk report script guarded: `(count > 0) ? total/count : "n/a"`.

**L6 — awk skip malformed rows:**
`NF < 5 { next }` and `$4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ { next }` at top of awk row
processing.

**L7 — `|| true` on all file reads and awk invocations in the report verb:**
File absent → human-readable message, exit 0. All awk invocations terminated with `|| true`.

**L9 — comment on stage field:**
`# stage: free-form in v1; future versions may add enum validation` near the stage
sanitization.

---

## 3. Acceptance criteria — T15a–T15m

**T15a** — `ledger add` appends a valid 5-field TSV row; field 1 matches ISO-8601; fields 3–5
are `TASK-fixture`, `scope`, `1000`, `60`.

**T15b** — 3 calls to `ledger add` → 3 rows; row 1 unchanged (append-only, keeps-older-data).

**T15c** — non-integer tokens rejected (non-zero exit, `ledger.tsv` NOT created or unchanged).

**T15d** — non-integer seconds rejected (non-zero exit, `ledger.tsv` unchanged).

**T15e** — wrong arg count (too few) rejected (non-zero exit, stderr message).

**T15f** — wrong arg count (too many) rejected (non-zero exit).

**T15g** — aggregation correct from pre-populated fixture: TASK-A tokens=3000/seconds=150,
TASK-B tokens=500/seconds=30, TOTAL tokens=3500/seconds=180, per-stage scope tokens=1500
count=2, arch tokens=2000 count=1.

**T15h** — absent ledger: exit 0, human-readable message, no `ledger.tsv` created by report.

**T15i** — all-malformed ledger (only rows < 5 fields): exit 0, no crash.

**T15j** — mixed valid+malformed: valid row's task-id appears in output (not dropped).

**T15k** — embedded tab in task-id and stage stripped, not preserved; resulting TSV has exactly
5 fields per row; field 3 contains no tab.

**T15l** — `bin/massoh` and `manifest.yml` checksums unchanged after running T15a–T15k.

**T15m** — full `bash test/run.sh` suite exits 0 (all tests green, regression guard).

---

## 4. gitignore decision

`ledger.tsv` is intentionally tracked in git (audit history, same as METRICS.md and
AGENT_SYNC.md). No `.gitignore` change needed.

---

## 5. Validation order (from 03 architectural notes)

arg-count check → sanitize task-id/stage → validate tokens/seconds → `mkdir -p` → write.

---

## 6. Files to change

| File | Change |
|---|---|
| `bin/massoh` | Add `cmd_ledger` function + `ledger)` dispatch case; update `die` verb list |
| `test/run.sh` | Append T15a–T15m block |
| `VERSION` | Bump `0.6.0` → `0.7.0` |
| `CHANGELOG.md` | Add `[0.7.0]` entry (create if absent) |
| `.agent_tasks/TASK-2026-06-17-massoh-ledger/04_implementation_packet.md` | This file |
| `.agent_tasks/TASK-2026-06-17-massoh-ledger/05_implementation_handoff.md` | Written after implementation |
