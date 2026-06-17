# 03 — Architecture / Safety Review
**Task:** TASK-2026-06-17-massoh-learn · **Date:** 2026-06-17 · **Agent:** massoh-architecture-safety

---

## Pre-review notes

**Guardrail B — owner sign-off on safety-critical file:** `bin/massoh` is a designated
safety-critical file per `NON_NEGOTIABLES.md`. The task packet `00_request.md` records
"Owner authorized build + bin/massoh* edits" and the owner's explicit "Build massoh learn (agents)"
selection. The AGENT_SYNC.md decision log confirms the prior pattern (2026-06-16 row: owner signed
off on `bin/massoh` edits before implementation). Sign-off is present and on record. Guardrail B
is satisfied — this review does NOT block on it; the implementer may proceed.

---

## 1. Backend / service impact

None. `cmd_learn` is a pure bash CLI function within `bin/massoh`. No external service, no daemon,
no network call. It reads local files (`$REPO/.agent_tasks/*/06_review_result.md`,
`$REPO/.agent_tasks/*/05_implementation_handoff.md`, `$REPO/AGENT_SYNC.md`) and the git log via
`git -C "$REPO" log`. Optionally appends to `$REPO/agent-project/LEARNINGS.proposed.md`.
No backend surface changed.

---

## 2. Client / app impact

The only user-facing surface is the stdout report and the optional `LEARNINGS.proposed.md` append.
Both are additive. Existing verbs are untouched. The new `learn` case in the dispatch table is
purely additive; unrecognized-command behavior for old callers is unchanged (the `*` die-case at
the bottom of the dispatch is not modified in scope).

---

## 3. API / contract impact

No API contract change. `bin/massoh` is a CLI, not a library. The dispatch table gains one new
entry (`learn`). The existing `die "unknown command '$cmd'..."` message must have `learn` added
to its list of documented verbs (low-risk, text-only, no contract implication). Both sides of any
seam (the dispatch case + the `cmd_learn` function) ship in the same commit. No contract split.

---

## 4. DB / migration impact

None. There is no database. The only persistent artifact is `agent-project/LEARNINGS.proposed.md`,
which is created on first `--write-proposals` run (create-if-missing, never overwrite). It is
append-only. This satisfies NON_NEGOTIABLES `keep older data` rule (A3). No migration needed.
No schema change to `manifest.yml` — `LEARNINGS.proposed.md` is a host artifact created at runtime,
not a file `massoh install` writes; it belongs in the repo's `agent-project/` directory, which
is already in-scope for host use. Confirmed: `manifest.yml` needs NO change.

---

## 5. LLM / prompt impact

Zero. The scope explicitly prohibits `claude -p` or any LLM call. All analysis is grep/awk
text-mining over markdown files and git log output. Zero API spend. The constraint is load-bearing
for testability and cost — the implementer must not soften it. Any future addition of LLM-based
summarization must go through a new product-scope pass.

---

## 6. Safety / guardrail risks

### 6a. Write-path containment (most important)

The entire safety model rests on one invariant: `cmd_learn` writes ONLY to
`agent-project/LEARNINGS.proposed.md`, and only when `--write-proposals` is passed. The
implementer must enforce this with absolute path discipline:

- The only `>>` or `>` redirect permitted in `cmd_learn` must target a variable resolved from
  `$repo/agent-project/LEARNINGS.proposed.md` (where `$repo` is computed the same way as in
  `cmd_review` / `cmd_standup`: `git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd`).
- No variable substitution or flag parsing must ever route the write target to any other path.
- `STANDARDS.md`, `memory/`, `docs/adr/`, `bin/massoh`, `manifest.yml`, the global-block markers:
  none of these may appear in any `>>` or `>` call within `cmd_learn`.

Implementation instruction: place a comment immediately above the write line:
`# SAFETY: the only permitted write in cmd_learn — append-only, learn proposals scratch file`
This makes it auditable in review.

### 6b. Append-only discipline

`LEARNINGS.proposed.md` must be opened with `>>` (append), never `>` (overwrite).
Create-if-missing is handled implicitly by `>>` in bash when the file does not exist.
The pre-write `mkdir -p "$repo/agent-project"` (as in `cmd_review`) must precede the append
so the directory exists. No `truncate`, `tee`, or `printf ... > file` may be used.

### 6c. `set -euo pipefail` exit safety

`bin/massoh` runs under `set -euo pipefail`. Any subshell grep/awk that produces no output and
exits non-zero (e.g. `grep` finding no matches returns 1) will abort the script.
All grep calls inside `cmd_learn` MUST be guarded with `|| true` (same pattern used in `cmd_review`
lines 221–224). A bare `grep ... "$file"` finding zero matches is a silent script abort — this is
the most common implementation pitfall in this codebase.

Specifically at risk:
- `grep -E '## Blocking' ...` over a file with no such heading → exits 1 → script dies.
- `grep -ci revert` when there are zero reverts → exits 1 → script dies.
- `awk` parsing AGENT_SYNC.md decision log with no matching rows → safe (awk exits 0), but any
  `grep` pipe after it is not.

All grep calls inside `cmd_learn` must be written as: `grep ... || true` or assigned via
`var=$(grep ... || true)`.

### 6d. Non-Massoh-project guard

`cmd_discover` (line 169 of `bin/massoh`) sets the pattern: check for `.massoh` marker or
`agent-project/` directory; if neither, `die "not a Massoh project"`. `cmd_learn` must apply
the same guard at the top, before any read. This is required for T11j.

### 6e. No sub-process LLM invocation

No `claude`, no `claude -p`, no external AI API call anywhere in `cmd_learn`. The text-mining
heuristics must be self-contained bash. Grep/awk/sed only.

### 6f. `LEARNINGS.proposed.md` path never leaks to safety-critical locations

When computing the proposals file path, use only the pattern:
`local proposals="$repo/agent-project/LEARNINGS.proposed.md"`
Never construct it from user-supplied input or flags. The `--write-proposals` flag is a boolean
switch; it does not accept a path argument. This prevents any path-traversal foot-gun.

---

## 7. Expansion / localization risks

The grep patterns that mine packet headings are English-language strings from the task-packet spec:
`## Blocking`, `## Non-blocking`, `REQUEST CHANGES`, `## Decision log`, `irreversible`. These must
be extracted as named variables or have `# task-packet-spec` comments inline (as called out in
`01_product_scope.md §3`). They must NOT be string literals buried silently in logic.

Recommended implementation pattern:
```bash
# task-packet-spec: these heading names match the mandatory section names in 11_TASK_PACKET_SPEC.md
_BLOCKING_HDR='## Blocking'
_NONBLOCKING_HDR='## Non-blocking'
_DECISION_LOG_HDR='## Decision log'
_ADR_FLAG_WORD='irreversible'
_REQUEST_CHANGES_WORD='REQUEST CHANGES'
```

Timestamps must use `date -u` (UTC), matching all other ceremonies. No locale-specific date
parsing introduced. No region or segment hard-coding. `--since DAYS` is a numeric parameter
(integer days), locale-neutral.

---

## 8. Required tests (T11)

All tests must follow the existing pattern in `test/run.sh`: temp dirs, fixture markdown files,
real `bin/massoh` invocation, `check`/`ok`/`bad` macros, no bats dependency, no real `~/.claude`
touched. A `mklearnrepo` fixture helper is recommended (modeled on `mkcronrepo`) to reduce
repetition across T11a–T11j.

### Mandatory tests (blocking — must be green before review approves)

**T11a** — Default mode: stdout report emitted; `LEARNINGS.proposed.md` NOT created.
- Fixture: temp Massoh project + two fake `06_review_result.md` files each containing `## Blocking`
  with a shared keyword.
- Assert: stdout contains the report header; `agent-project/LEARNINGS.proposed.md` does not exist.

**T11b** — `--no-write` identical to default: no proposals file; stdout still emitted.

**T11c** — `--write-proposals` creates `LEARNINGS.proposed.md` with all four required sections
(`## [learn]`, `### Proposed STANDARDS.md Do/Don't`, `### Possible ADR candidates`,
`### Repeated-fix indicators`). Re-run appends a second `## [learn]` block — file is NOT
overwritten (two blocks present, not one).

**T11d** — Recurring pattern surfaces: two fake `06_review_result.md` files with identical
blocking text "A&&B||C anti-pattern"; after `--write-proposals`, `LEARNINGS.proposed.md` contains
that string and a count or reference indicating 2+ occurrences.

**T11e** — Decision log ADR candidate: fake `AGENT_SYNC.md` with a row containing the word
"irreversible"; after `--write-proposals`, ADR candidates section is non-empty.

**T11f** — Git revert count in report: temp git repo, one commit, then `git revert HEAD --no-edit`;
`massoh learn` stdout contains "revert" with a count of 1.

**T11g** — `--since DAYS` limits scan: two fake packets, one with recent mtime and one with
`touch -t` set to >2 days ago; `massoh learn --since 1` shows only the recent packet's findings.

**T11h** — Graceful degrade (no `.agent_tasks/`, no packets): exit 0; stdout contains "(none)"
sections; no crash.

**T11i** — Safety-critical paths untouched: md5 snapshot of `bin/massoh` and `manifest.yml`
and `agent-project/STANDARDS.md` (if present) before run; assert checksums identical after
`massoh learn --write-proposals`.

**T11j** — Non-Massoh-project refusal: run in a temp dir with no `.massoh` and no `agent-project/`;
assert non-zero exit and error message on stderr.

### Additional guard test (required for the append-only invariant)

**T11c-idempotent** (can be part of T11c): run `massoh learn --write-proposals` three times;
assert the file has exactly three `## [learn]` section headers (no deduplication, no overwrite,
pure append). This is the md5-inert check for repeated `--no-write` / default runs (T11b).

---

## 9. Rollback plan

`cmd_learn` is a pure additive function. Rollback = revert the `bin/massoh` commit on the feature
branch. No data is changed on existing installs (the only new file is `LEARNINGS.proposed.md`
in the host repo, which the owner must explicitly trigger with `--write-proposals`). That file
is not owned by `manifest.yml` and is not touched by `massoh uninstall`. If the owner wants to
discard it: `rm agent-project/LEARNINGS.proposed.md`. No other rollback artifact exists.

Installed instances (`~/.claude`) are unaffected by `cmd_learn` additions to `bin/massoh` until
the owner runs `massoh install` or `massoh update` after the merge. This is the same rollout
model as all prior verbs.

---

## 10. Decision: APPROVED — with 4 mandatory conditions

The proposed `cmd_learn` is architecturally sound and safety-appropriate. The scope is minimal
(one function, one optional scratch file, zero LLM spend), the write boundary is tightly defined,
and the proposal-only / never-auto-promote model correctly gates knowledge promotion behind the
owner. Owner sign-off on `bin/massoh` is on record. No ADR conflict detected.

**The 4 mandatory conditions the implementer must satisfy before the reviewer approves:**

**Condition 1 — All grep calls guarded with `|| true`.**
Every `grep` inside `cmd_learn` (packet scan, decision log scan, git log scan) must be written
as `grep ... || true` or captured via `$(grep ... || true)`. A bare grep returning exit 1 on
zero matches will kill the script under `set -euo pipefail`. This is the most common failure mode
in this codebase (confirmed by review history: A&&B||C anti-pattern was a prior guard failure
of the same class). No bare grep permitted.

**Condition 2 — Write target locked to `$repo/agent-project/LEARNINGS.proposed.md`.**
The `>>` redirect in `cmd_learn` must target a single named local variable holding that exact
computed path. A comment `# SAFETY: only permitted write in cmd_learn` must appear on that line.
The implementer must grep-confirm no other write (`>>`, `>`, `tee`, `printf ... >`) exists in
`cmd_learn` pointing to any other path. The reviewer will diff-confirm this.

**Condition 3 — English pattern strings extracted as named variables with `# task-packet-spec` comments.**
The heading and keyword patterns (`## Blocking`, `## Non-blocking`, `REQUEST CHANGES`,
`## Decision log`, `irreversible`) must not be string literals buried in awk/grep logic. They
must appear as named bash variables with a `# task-packet-spec` comment, making them findable
and overridable by a future multi-language project.

**Condition 4 — T11a through T11j all green (10 checks minimum, zero LLM spend, real paths).**
The reviewer will run `bash test/run.sh` and verify ALL GREEN before approving. T11 tests must
exercise the real `bin/massoh learn` invocation (not a stub). The append-only re-run check
(three runs = three `## [learn]` blocks) must be present inside T11c.

---

## 11. Task-packet update

This file is the packet update for stage `03_architecture_safety`.

---

## 12. AGENT_SYNC.md update

Append the following decision row to the Decision log:

```
| 2026-06-17 | TASK-2026-06-17-massoh-learn: arch/safety APPROVED — 4 conditions: grep-guard || true, write-lock to LEARNINGS.proposed.md, pattern strings as named vars, T11a-j all green | architecture-safety |
```

Update Active task packets row for TASK-2026-06-17-massoh-learn:

```
| TASK-2026-06-17-massoh-learn | 03_architecture_safety | APPROVED — 4 conditions; routes to implementer for 04_implementation_packet |
```

Update Last handoff:

```
Agent: massoh-architecture-safety
Mode: architecture_safety
Task: TASK-2026-06-17-massoh-learn — massoh learn command (heuristic mining loop)
Status: APPROVED with 4 conditions.
Branch: feat/massoh-learn
Key decisions:
  - Guardrail B satisfied: owner sign-off on bin/massoh edits is on record in 00_request.md
  - Write path strictly locked to agent-project/LEARNINGS.proposed.md (append-only, --write-proposals only)
  - manifest.yml needs no change (LEARNINGS.proposed.md is a runtime host artifact, not installed)
  - All grep calls must be || true guarded (set -euo pipefail kills bare grep on zero matches)
  - English pattern strings (## Blocking, ## Non-blocking, REQUEST CHANGES, irreversible) must be
    named variables with # task-packet-spec comments for future localizability
  - T11a-j: 10 required tests, fixture-based, zero LLM spend, real bin/massoh invocations
  - Graceful degrade: no packets / no decision log / non-git / non-Massoh-project → exit 0 or die gracefully
Next recommended agent: massoh-implementer
Next action: write 04_implementation_packet.md; implement cmd_learn satisfying all 4 conditions
```
