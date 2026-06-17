# 03 — Architecture & Safety Review
**Task:** TASK-2026-06-17-massoh-ledger
**Date:** 2026-06-17
**Agent:** massoh-architecture-safety
**Decision: APPROVED — with mandatory conditions below**

Owner sign-off on editing `bin/massoh` is on record in `00_request.md` ("Owner authorized build +
`bin/massoh*` edits"). Guardrail B (owner-gated safety-critical file) does not block; recorded
here for the audit trail.

---

## 1. Backend / service impact

None. Pure-bash CLI. No server, no service boundary, no network call. The only write target is
`.agent_tasks/ledger.tsv` (append, never truncate).

## 2. Client / app impact

None. Terminal stdout for the report verb. Append to a single local file for the add verb.
The two new sub-commands are entirely additive; no existing caller is altered.

## 3. API impact

No API contract seam touched. `manifest.yml` is NOT changed (ledger.tsv is a runtime host
artifact, not part of the install/uninstall contract). The dispatch `case "$cmd"` in `bin/massoh`
gains one new `ledger` entry — additive, no existing case altered. No both-sides-together
concern is triggered.

## 4. DB / migration impact

No schema. `.agent_tasks/ledger.tsv` is the only artifact. It is append-only (create on first
call; never truncated or overwritten). This satisfies NON_NEGOTIABLES "keep older data." No
migration is needed because the file did not previously exist. The 5-field TSV format
(timestamp, task-id, stage, tokens, seconds) is simple enough that any future column addition
would be a new format version with a comment-header — defer to that NEXT.

No changes to `manifest.yml`, install/uninstall contract, or per-repo scaffold.

## 5. LLM / prompt impact

Zero. No `claude -p` or equivalent. No prompt text. No API spend. Both verbs are pure bash + awk.

## 6. Safety / guardrail risks

### Risk L1 — Injection via task-id or stage containing tabs or newlines

`ledger.tsv` is tab-separated. If `task-id` or `stage` contain a literal tab or newline, they
corrupt every downstream `awk` read (field count becomes wrong; a newline silently creates a
phantom row). The `printf` append is the write path; bash does not strip these characters
automatically under `set -euo pipefail`.

**MANDATORY CONDITION L1:** Before writing the row, sanitize `task-id` and `stage` by stripping
tabs (`\t`) and newlines (`\n`, `\r`). Use bash parameter expansion:

```bash
task_id="${1//$'\t'/}"; task_id="${task_id//$'\n'/}"; task_id="${task_id//$'\r'/}"
stage="${2//$'\t'/}";   stage="${stage//$'\n'/}";   stage="${stage//$'\r'/}"
```

No validation error is required for these (stripping is sufficient for tab/newline). However, an
empty `task-id` or empty `stage` after stripping MUST be rejected with a non-zero exit and a
message to stderr (an empty field renders the TSV unreadable). Place this check immediately after
the sanitization.

### Risk L2 — Non-integer tokens or seconds (primary injection risk)

Under `set -euo pipefail`, passing a non-integer into `$(( expr ))` is a fatal arithmetic error
that exits non-zero — but it also potentially exposes an arithmetic injection vector if the value
contains characters that bash arithmetic evaluates (e.g., `$(cmd)`, `0x1f`, `1+1`). The safest
guard is a strict regex match before any arithmetic.

**MANDATORY CONDITION L2:** Both `tokens` and `seconds` MUST be validated as non-negative
integers using a regex guard before they are written or used arithmetically. Reject (non-zero
exit, message to stderr, NO row written) if validation fails:

```bash
[[ "$tokens"  =~ ^[0-9]+$ ]] || { printf 'massoh ledger: tokens must be a non-negative integer, got: %s\n' "$tokens" >&2; exit 1; }
[[ "$seconds" =~ ^[0-9]+$ ]] || { printf 'massoh ledger: seconds must be a non-negative integer, got: %s\n' "$seconds" >&2; exit 1; }
```

Validation MUST fire before any `mkdir -p` or file creation so that a rejected call leaves no
side-effects (no partial file, no empty directory that didn't exist before). Exception: if
`.agent_tasks/` already exists, the `mkdir -p` is a no-op and can precede validation — but the
file open/write MUST NOT happen until after validation passes. The safest order is: arg-count
check → sanitize task-id/stage → validate tokens/seconds → mkdir -p → write.

### Risk L3 — Arg-count check

Exactly 4 positional args are required after `add`. Any other count must reject immediately (no
file touch, message to stderr, non-zero exit). This is the first guard in `cmd_ledger add`.

**MANDATORY CONDITION L3:** Arg-count guard is the first statement in the `add` branch:

```bash
[ $# -eq 4 ] || { printf 'massoh ledger add: expected 4 args (task-id stage tokens seconds), got %d\n' "$#" >&2; exit 1; }
```

### Risk L4 — TSV append atomicity (concurrent cron ticks)

A single `printf '...\n' >> file` on POSIX is atomic for writes smaller than PIPE_BUF (4 KB on
Linux, 512 bytes on POSIX minimum) when the file is opened with `O_APPEND`. One TSV row with
five fields is well under any PIPE_BUF limit. Concurrent `>>` appends from parallel worktrees or
cron ticks therefore cannot interleave mid-row: each write either appears fully or not at all.
There is NO read-modify-write in the `add` path — the write is purely an append, so no file lock
is needed for correctness at this scale.

**MANDATORY CONDITION L4:** The `add` verb MUST write the row as a single `printf` call with
`>>` (not in multiple steps, not with a temp file). Name the ledger path in a variable at the
top of `cmd_ledger` with a `# SAFETY` comment identifying it as the only write target:

```bash
LEDGER="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")/.agent_tasks/ledger.tsv"  # SAFETY: sole write target in cmd_ledger
```

The `report` verb (no args) is read-only; it must never open the file for writing.

### Risk L5 — awk division-by-zero in the report

The per-task average (`avg_tokens/stage = total_tokens / stage_count`) and any per-stage
average (`avg_tokens = total_tokens / count`) are divisions. If a task or stage has count = 0
(which cannot happen in a well-formed ledger, but may occur if a malformed row is skipped and
leaves a stale accumulator) the division must be guarded.

**MANDATORY CONDITION L5:** In the awk report script, ALL division operations MUST be guarded:

```awk
avg = (count > 0) ? total / count : "n/a"
```

Apply this pattern for every computed average. Do not assume count is always positive.

### Risk L6 — awk tolerance of malformed or short rows

Rows with fewer than 5 tab-separated fields must be silently skipped (not cause NF-array
errors or corrupt sums). Rows where field 4 (tokens) or field 5 (seconds) is not numeric must
also be skipped.

**MANDATORY CONDITION L6:** The awk report script MUST begin each row's processing with:

```awk
NF < 5 { next }
$4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ { next }
```

This makes the report tolerant of a manually edited or partially-written ledger.

### Risk L7 — File read `|| true` guards in the report verb

Under `set -euo pipefail`, `awk file` returns non-zero if the file does not exist on some
systems. The report verb must degrade gracefully when `ledger.tsv` is absent or empty.

**MANDATORY CONDITION L7:** The report verb MUST guard all file reads:

```bash
[ -f "$LEDGER" ] || { printf '  (no ledger data — run: massoh ledger add <task-id> <stage> <tokens> <seconds>)\n'; exit 0; }
```

The awk invocation that reads the file MUST also be terminated with `|| true` to prevent a
non-zero awk exit from propagating under `set -euo pipefail`.

### Risk L8 — `mkdir -p .agent_tasks` clobber check

NON_NEGOTIABLES §Prohibited content: "A scaffold (`massoh on`) that overwrites an existing
project file — create-if-missing only." `mkdir -p` is create-if-missing by definition; it does
not overwrite anything if the directory exists. This is safe and consistent with `cmd_on` behavior.

The `ledger add` verb MAY call `mkdir -p .agent_tasks` (or the resolved absolute path) to
support being called in CI before `massoh on` has run. This matches the spirit of `cmd_on` and
does NOT violate NON_NEGOTIABLES because it creates a directory, not a file, and only if absent.

**No blocking condition here.** Record: `mkdir -p .agent_tasks` is permitted and recommended
so that `massoh ledger add` is usable from any orchestrator without requiring `massoh on` first.

### Risk L9 — `stage` free-form with a comment for future enumeration

Product-scope §11 and the expansion principle both note that `stage` is free-form in v1.
Constraining it to an enum now would break harness-neutral usage. The implementer MUST add a
comment in the code: `# stage: free-form; future versions may enumerate`. This is not a safety
risk, but its absence would be a guardrail 12 (expansion-ready) miss.

**MANDATORY CONDITION L9 (non-blocking, architectural note):** The implementer MUST add a
comment on the `stage` variable/sanitization line reading:
`# stage: free-form in v1; future versions may add enum validation`

### Risk L10 — `bin/massoh` is a designated safety-critical file

NON_NEGOTIABLES §Designated safety-critical files lists `bin/massoh`. Editing it requires owner
sign-off. Sign-off is on record in `00_request.md`. This does NOT block; it is recorded for the
audit trail only.

The change is **additive**: a new `cmd_ledger` function and a new `ledger)` case in the dispatch.
No install/uninstall/backup/block logic is touched. The existing case-dispatch structure (line
716–736) is the correct insertion point. The implementer must not alter any other part of the
dispatch or any other function.

---

## 7. Expansion / localization risks

The TSV format is harness-neutral: `timestamp`, `task-id`, `stage`, `tokens`, `seconds` — no
Claude Code-specific fields, no locale-sensitive content. The `stage` field is free-form, making
the ledger compatible with any future orchestrator calling the same verb.

Output labels for the report verb ("tokens", "seconds", "total", "avg") are English. Numeric
extraction in awk is locale-neutral (integer arithmetic). The CHARTER expansion principle is
satisfied: no region, locale, or segment assumption is introduced. If multi-language output is
ever required, it is a NEXT parameterization — do not build it now.

The ISO-8601 UTC timestamp (`date -u +%Y-%m-%dT%H:%M:%SZ`) is POSIX-portable and locale-neutral.

---

## 8. Required tests

All tests appended to `test/run.sh` as a new `T15` block, following the established `check()`
pattern. Fixture-based (temp repo with `.agent_tasks/`). No `~/.claude` touched. Zero LLM spend.

**T15a — `ledger add` appends a valid 5-field row.**
Call `massoh ledger add TASK-fixture scope 1000 60` in a temp repo. Assert `ledger.tsv` exists.
Assert it has exactly 1 line. Assert line has 5 tab-separated fields (`awk -F'\t' 'NF==5'`).
Assert field 1 matches `^[0-9]{4}-` (ISO-8601). Assert fields 3–5 are `TASK-fixture`, `scope`,
`1000`, `60`.

**T15b — append-only (3 adds = 3 rows, no overwrite).**
Call `ledger add` three times with different token counts. Assert `ledger.tsv` has exactly 3
lines. Assert row 1 is unchanged (keeps-older-data).

**T15c — non-integer tokens rejected (non-zero exit, no row written).**
Call `massoh ledger add TASK-fixture scope notanumber 60`. Assert non-zero exit. Assert
`ledger.tsv` was NOT created (or if it pre-existed, assert its line count is unchanged).

**T15d — non-integer seconds rejected (non-zero exit, no row written).**
Call `massoh ledger add TASK-fixture scope 1000 notanumber`. Assert non-zero exit. Assert
`ledger.tsv` unchanged.

**T15e — wrong arg count rejected (too few args).**
Call `massoh ledger add TASK-fixture scope 1000` (3 args, missing seconds). Assert non-zero exit
and a message on stderr.

**T15f — wrong arg count rejected (too many args).**
Call `massoh ledger add TASK-fixture scope 1000 60 extra`. Assert non-zero exit.

**T15g — aggregation correctness.**
Pre-populate a fixture `ledger.tsv` (write raw bytes, not via `massoh ledger add`) with:
```
2026-06-17T00:00:00Z\tTASK-A\tscope\t1000\t60
2026-06-17T00:01:00Z\tTASK-A\tarch\t2000\t90
2026-06-17T00:02:00Z\tTASK-B\tscope\t500\t30
```
Run `massoh ledger`. Assert exit 0. Assert stdout contains:
- TASK-A with tokens=3000 and seconds=150
- TASK-B with tokens=500 and seconds=30
- TOTAL tokens=3500 and seconds=180
- Per-stage: scope tokens=1500, count=2; arch tokens=2000, count=1

**T15h — graceful degrade when ledger absent.**
Run `massoh ledger` in a temp repo with no `ledger.tsv`. Assert exit 0. Assert stdout contains
a human-readable message (not empty; not a crash). Assert no `ledger.tsv` is created by the
report verb (read-only).

**T15i — division-by-zero / empty-ledger degrade.**
Write a `ledger.tsv` containing only a malformed row (fewer than 5 fields). Run `massoh ledger`.
Assert exit 0 (no crash). Output may report 0 rows or the degraded message — either is
acceptable. This tests Condition L5 + L6.

**T15j — malformed row tolerated (skipped, not crash).**
Pre-populate `ledger.tsv` with one valid row followed by one malformed row (3 fields only).
Run `massoh ledger`. Assert exit 0. Assert the valid row's task-id appears in the output (it
was not silently dropped because of the bad row). Assert no arithmetic error.

**T15k — task-id and stage with tab characters sanitized.**
Call `massoh ledger add $'TASK\tX' $'sc\tope' 100 10`. Assert exit 0 (strip, not reject).
Assert `ledger.tsv` has exactly 1 line. Assert the line has exactly 5 fields (the embedded tabs
were stripped, not preserved). Assert field 3 does not contain a tab.

**T15l — safety-critical files unchanged after all T15 tests.**
After all T15 checks, assert `bin/massoh` and `manifest.yml` checksums match their pre-run
values. Mirrors the T_i pattern established in prior review cycles.

**T15m — all existing tests remain green (regression guard).**
The full `test/run.sh` suite must exit 0 after adding the T15 block.

---

## 9. Rollback plan

`cmd_ledger` and its dispatch case are additive changes to `bin/massoh` on branch
`feat/massoh-ledger`. Rollback = do not merge the PR, or `git revert` the merge commit on main,
followed by `massoh install`.

`.agent_tasks/ledger.tsv` is a local runtime artifact. Rollback of the code does not remove it;
it is kept as inert data (consistent with NON_NEGOTIABLES "keep older data"). No schema
migration. No manifest.yml change. No install/uninstall contract change. The only observable
effect of rollback is that `massoh ledger` becomes an unknown command again (`die` path in the
dispatch).

---

## 10. Approved for implementation?

**YES — APPROVED**, subject to the mandatory conditions below.

### Mandatory conditions

**L1 — tab/newline sanitization of task-id and stage** (before write): strip `\t`, `\n`, `\r`
from both fields via bash parameter expansion; reject with non-zero exit if either field is
empty after stripping.

**L2 — integer validation of tokens and seconds** (regex `^[0-9]+$` before any write or
arithmetic; non-zero exit + stderr message + zero file side-effects on failure).

**L3 — arg-count guard first** (exactly 4 args after `add`; non-zero exit + stderr message on
violation; checked before any file operation).

**L4 — single-`printf`-`>>`-write, named LEDGER variable with `# SAFETY` comment** (atomic
append; no temp file; no read-modify-write; `report` verb is read-only with no `>>` path).

**L5 — awk division-by-zero guard** (`count > 0` check before every `/` in the awk report
script; "n/a" output on zero-count).

**L6 — awk skip malformed rows** (`NF < 5 { next }` and non-numeric field 4/5 guard at the
top of awk row processing).

**L7 — `|| true` on all file reads and awk invocations in the report verb** (file-absent
graceful degrade with human-readable message, exit 0).

**L9 — comment on stage field** (`# stage: free-form in v1; future versions may add enum
validation`) in the code near the sanitization of `stage`.

Non-blocking architectural notes (no block, record in handoff):
- `mkdir -p .agent_tasks` is permitted and recommended (create-if-missing, matches `cmd_on`).
- Validation order: arg-count → sanitize → validate integers → mkdir -p → write.
- The implementer MUST NOT alter any existing function, dispatch case, or cron logic; only
  `cmd_ledger` (new function) and the `ledger)` dispatch case (new entry) are in scope.

---

## 11. gitignore decision for ledger.tsv

**Recommendation: keep `ledger.tsv` tracked in git (do NOT gitignore it).**

Rationale:
- The file is audit history, not a build artifact. Per NON_NEGOTIABLES "keep older data," the
  decision log and all append-only records are retained, not discarded.
- Tracking it in git gives the owner a free audit trail: `git log -- .agent_tasks/ledger.tsv`
  shows when rows were added; `git diff` shows exactly what data each agent run appended.
- The file will grow slowly (one row per agent stage per task; at Massoh's current cadence of
  ~6-10 agent stages per task, even 100 tasks produce fewer than 1,000 rows — well under 100 KB).
- Parallel worktrees may produce merge conflicts on the same TSV only if two branches produce
  rows and both are merged; this is a minor inconvenience, not a correctness hazard (the merge
  conflict is trivially resolved by accepting both sets of rows). This does not justify gitignore.

Action for implementer: no `.gitignore` change needed. Add a note to the `04_implementation_packet.md`
that `ledger.tsv` is intentionally tracked (same as METRICS.md and AGENT_SYNC.md).

---

## 12. Task-packet update

This file is the packet update for stage `03_architecture_safety`. The task packet
`.agent_tasks/TASK-2026-06-17-massoh-ledger/` continues with `04_implementation_packet.md` next.

No UX review is required (internal CLI tool, no user-facing UI, no copy to review).
