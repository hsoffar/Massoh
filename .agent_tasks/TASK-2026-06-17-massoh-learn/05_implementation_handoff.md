# 05 — Implementation Handoff
**Task:** TASK-2026-06-17-massoh-learn · **Date:** 2026-06-17 · **Agent:** massoh-implementer

---

## Status: IMPLEMENTED — ready for reviewer-qa

Branch: `feat/massoh-learn` (no commit yet per task instructions; do NOT push / do NOT open PR).

---

## 1. Files changed

| File | Change |
|---|---|
| `bin/massoh` | Added `cmd_learn()` function (lines 308–480); added `learn` to dispatch case (line 514); added `learn` to die-verb list (line 519) |
| `test/run.sh` | Added T11 block (T11a–T11j, 26 new checks) + `mklearnrepo` + `mklearnpacket` fixture helpers |
| `VERSION` | Bumped `0.4.2` → `0.5.0` |
| `CHANGELOG.md` | Added `[0.5.0]` entry |
| `.agent_tasks/TASK-2026-06-17-massoh-learn/04_implementation_packet.md` | Created (the license) |
| `.agent_tasks/TASK-2026-06-17-massoh-learn/05_implementation_handoff.md` | This file |

Files NOT touched (as required):
- `manifest.yml` — no change (LEARNINGS.proposed.md is a runtime host artifact)
- `bin/massoh-cron` — no change
- Any agent `.md` files, skills, templates, `memory/`, `docs/adr/`
- `agent-project/STANDARDS.md` — not created or modified (by cmd_learn or this implementation)

---

## 2. What was implemented

`cmd_learn` is a read-only heuristic miner inline in `bin/massoh`, following the same pattern as
`cmd_review` / `cmd_standup` / `cmd_plan`. It:

1. Resolves repo via `git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd`.
2. Guards at top: requires `.massoh` marker or `agent-project/` directory; otherwise `die`.
3. Defines all English pattern strings as named local variables with `# task-packet-spec` comment
   (`_PAT_BLOCKING`, `_PAT_NONBLOCKING`, `_PAT_REQUEST_CHANGES`, `_PAT_DECISION_LOG`, `_PAT_ADR_FLAG`).
4. Scans `.agent_tasks/TASK-*/06_review_result.md` for blocking/non-blocking sections and
   `REQUEST CHANGES` lines; `.agent_tasks/TASK-*/05_implementation_handoff.md` for risk lines.
5. Counts recurring keywords from blocking sections (seen in 2+ reviews).
6. Scans `AGENT_SYNC.md` decision log for rows containing "irreversible" → ADR candidates.
7. Counts git reverts and fixup commits from `git log`.
8. Always prints a lessons report to stdout (7 sections).
9. With `--write-proposals`: appends a structured `## [learn] <ts>` block to
   `$repo/agent-project/LEARNINGS.proposed.md` using `>>` only (append-only, create-if-missing).
   The `>>` redirect line has the comment `# SAFETY: only permitted write in cmd_learn`.
10. `--since DAYS` limits packet scan via `find -mtime`.
11. `--no-write` is the default (stdout only; no files written).

---

## 3. How each mandatory condition is satisfied (with line numbers)

### Condition 1 — All grep calls guarded with `|| true`

Every `grep` inside `cmd_learn` is captured via `$(... || true)` or piped with `|| true`:

| Line (bin/massoh) | Pattern |
|---|---|
| 348 | `find ... | grep -c . || true` (recent06 mtime check) |
| 349 | `find ... | grep -c . || true` (recent05 mtime check) |
| 371 | `rc=$(grep -F "$_PAT_REQUEST_CHANGES" "$f06" || true)` |
| 373 | `rk=$(grep -iE ... "$f05" || true)` |
| 381 | `find ... | grep -c . || true` (recurring scan mtime check) |
| 389 | `... | grep -oE '[A-Za-z_|&]{5,}' || true` |
| 426 | `revert_count=$(git ... | grep -ci revert || true)` |
| 428 | `fixup_count=$(git ... | grep -ci fixup || true)` |

Verified: `awk '/^cmd_learn\(\)/,/^}/' bin/massoh | grep 'grep' | grep -v '|| true' | grep -v '#'` produces ZERO output.

### Condition 2 — Write target locked to named variable; SAFETY comment on redirect line

- Line 459: `local proposals="$repo/agent-project/LEARNINGS.proposed.md"` — single named variable.
- Line 478: `} >> "$proposals" # SAFETY: only permitted write in cmd_learn` — SAFETY comment present.
- No `>` (overwrite), no `tee`, no other write path exists in `cmd_learn`.
- Only one `>>` redirect in the entire function, targeting `$proposals`.

### Condition 3 — Pattern strings as named variables with `# task-packet-spec` comment

Lines 327–333 of `bin/massoh`:
```
# task-packet-spec: these heading/keyword names match mandatory sections in 11_TASK_PACKET_SPEC.md
# and the AGENT_SYNC schema. Extracted as named variables for future multi-language projects.
local _PAT_BLOCKING='## Blocking'
local _PAT_NONBLOCKING='## Non-blocking'
local _PAT_REQUEST_CHANGES='REQUEST CHANGES'
local _PAT_DECISION_LOG='## Decision log'
local _PAT_ADR_FLAG='irreversible'
```
All 5 pattern strings named. All awk/grep calls reference these variables via `-v` flags or
`"$_PAT_..."` expansion — no pattern strings buried as literals in logic.

### Condition 4 — T11a–T11j all green (26 checks, zero LLM spend, real bin/massoh invocations)

Final test run result:
```
== T11: massoh learn (heuristic miner) ==
  ok   T11a stdout contains report header
  ok   T11a Blocking findings section in stdout
  ok   T11a LEARNINGS.proposed.md NOT created
  ok   T11b --no-write stdout still emitted
  ok   T11b --no-write LEARNINGS.proposed.md absent
  ok   T11c LEARNINGS.proposed.md created
  ok   T11c contains ## [learn] header
  ok   T11c contains Proposed STANDARDS section
  ok   T11c contains Possible ADR candidates
  ok   T11c contains Repeated-fix indicators
  ok   T11c three runs = three [learn] blocks (append-only)
  ok   T11d recurring pattern in proposals
  ok   T11d stdout shows both tasks mentioned
  ok   T11e ADR candidates section non-empty
[main ...] Revert "chore: extra commit"
  ok   T11f stdout contains revert count 1
  ok   T11f revert count is at least 1
  ok   T11g --since 1 includes recent packet findings
  ok   T11g --since 1 excludes old packet findings
  ok   T11h no packets exit 0
  ok   T11h no packets stdout has report header
  ok   T11h no packets stdout has (none) section
  ok   T11i bin/massoh checksum unchanged
  ok   T11i manifest.yml checksum unchanged
  ok   T11i STANDARDS.md checksum unchanged
  ok   T11j non-Massoh-project non-zero exit
  ok   T11j non-Massoh-project error on stderr

ALL GREEN — 105 checks passed.
```

T11c includes the three-runs-three-blocks append-only assertion. T11i verifies md5 of
`bin/massoh`, `manifest.yml`, and `STANDARDS.md` unchanged after `--write-proposals`. T11j
verifies non-zero exit on non-Massoh-project. All 10 mandatory tests pass.

---

## 4. Tests run

Command: `bash test/run.sh`

Result (verbatim last line): `ALL GREEN — 105 checks passed.`

Previous passing count before this task: 79 checks (T1–T10).
New checks added by T11: 26.
Total: 105 checks, 0 failures.

---

## 5. Risks

- **Low**: The recurring-keyword heuristic uses a simple word-frequency count from blocking
  sections. It will produce false-positive "recurring" signals for common words (e.g., "found",
  "pattern") that appear in multiple reviews but carry no unique lesson. The owner filters
  these manually when reviewing `LEARNINGS.proposed.md`. Acceptable per the 01 scope ("false
  positives are expected and acceptable — the owner filters them").

- **Low**: `git revert --no-edit HEAD -q` in the T11f fixture emits a git info line to stdout in
  some git versions (seen in test output: `[main ...] Revert "chore: extra commit"`). This is
  test fixture output, not `cmd_learn` output, and does not affect the check result. No risk to
  the implementation.

- **None**: No LLM API calls. No network calls. No global `~/.claude` writes. No safety-critical
  file modifications. `--write-proposals` is append-only to a single explicitly named path.

---

## 6. Incomplete items

None. All 4 conditions are met, all 10 T11 tests are green, scope is exactly as approved.

Deferred (explicitly out of scope per 01 and 04 packets):
- `03_architecture_safety.md` risk scanning — NEXT after v1 ships.
- Cross-repo aggregation — LATER.
- ADR file auto-creation — owner creates `docs/adr/` manually.
- `LEARNINGS.proposed.md` size warning — NEXT.

---

## 7. Handoff for reviewer

Reviewer: `massoh-reviewer-qa`

To verify:
1. `bash test/run.sh` → must show `ALL GREEN — 105 checks passed.`
2. `grep 'grep' bin/massoh | grep -A0 'cmd_learn' ...` or the awk block check above → zero bare greps.
3. `grep -n 'SAFETY' bin/massoh` → line 478 shows the SAFETY comment on the `>>` redirect.
4. `grep -n '_PAT_\|task-packet-spec' bin/massoh` → lines 327–333 show named variables with comment.
5. `grep 'learn' bin/massoh` → `learn)` in dispatch (line 514) + `learn` in die-verb list (line 519).
6. `cat VERSION` → `0.5.0`
7. `grep '\[0.5.0\]' CHANGELOG.md` → present.
8. `bin/massoh learn` in this repo → prints lessons report, no write.
9. `bin/massoh learn --write-proposals` in this repo → appends to `agent-project/LEARNINGS.proposed.md`.
10. The only `>>` in `cmd_learn` targets `$proposals` = `$repo/agent-project/LEARNINGS.proposed.md`.

Blocking concerns for reviewer: None anticipated. All 4 conditions are satisfied with verifiable
line numbers. The implementation is strictly within scope.
