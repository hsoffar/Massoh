# 03 — Architecture & Safety: Fleet slice 3 — `massoh fleet learn`

- **Reviewer:** massoh-architecture-safety
- **Date:** 2026-06-20
- **Task:** TASK-2026-06-20-fleet-observability slice 3
- **Mode:** ARCHITECTURE_SAFETY
- **Precedents relied on:** learn.sh (ZERO-LLM + write-isolation); meta.sh (M1–M14 conditions,
  named write var + SAFETY comment); fleet.sh (FL1 read-only-across-repos); 00_architecture_review.md §4
  (CLI propose-only path endorsed; browser button PARKED).

---

## 1. Backend / service impact

Additive only. A new subcommand `massoh fleet learn` is dispatched inside `cmd_fleet` (same pattern
as `serve`). Implementation lives in `lib/verbs/fleet.sh`. No new top-level verb; no new sourced
file. No service, daemon, or background process is involved. All work is deterministic in-process
bash; exits cleanly.

## 2. Client / app impact

CLI-only. The fleet dashboard (slices 1a–1c) is unaffected. The browser-triggered learn button
remains PARKED per the architecture review ruling (POST = new risk class, owner-gated). The CLI verb
outputs to stdout and optionally writes one local file. No UI change.

## 3. API impact

None. No API contract exists for this CLI tool. The verb is additive; existing `massoh fleet`
behaviour is unchanged (the new `learn` subcommand is dispatched before the existing option parser,
same as `serve`).

## 4. DB / migration impact

The only file written is `agent-project/FLEET_LEARNINGS.proposed.md` (append / regenerate with
sentinel). Existing `LEARNINGS.proposed.md` and `META.proposed.md` files in discovered repos are
never touched. The ledger, AGENT_SYNC.md, AGENT_BACKLOG.md, and all engine policy files are
untouched. Backward-compatible: if the file does not exist it is created; if it exists it is either
appended to or regenerated (both idempotent options are acceptable — the chosen approach must be
declared in `04` and tested in T-FLN-*).

## 5. LLM / prompt impact

None. The verb is deterministic-heuristic only. Zero LLM, zero network, zero agent invocation. This
is the fundamental away-autonomy gating condition (see FLN1 below).

## 6. Safety / guardrail risks enumerated → FLN conditions

### FLN1 — Zero LLM / zero network / zero spend (CRITICAL)
**Risk:** Any `claude -p`, agent invocation, or `curl`/network call inside `cmd_fleet_learn` would
constitute paid spend under an owner-away grant, breaching the zero-spend condition of the grant and
the away-autonomy envelope.
**Condition:** The implementation MUST contain zero calls to `claude`, `massoh-meta-engineer`,
any agent harness, or any network command (`curl`, `wget`, `nc`, `fetch`). Static grep of
`lib/verbs/fleet.sh` for `/claude\b/`, `/curl\b/`, `/wget\b/`, `/agent\b/` inside the
`cmd_fleet_learn` function must return zero matches. No subprocess or eval that could invoke one.

### FLN2 — Read-only against discovered repos (FL1 extension, CRITICAL)
**Risk:** The verb reads `LEARNINGS.proposed.md` and `META.proposed.md` from each discovered repo.
Any write to a discovered repo's filesystem — including an accidental `>>`, `>`, `mv`, `cp`, or
`touch` — violates FL1 and the write-isolation guarantee.
**Condition:** Discovered-repo path variables must never appear on the left of `>`, `>>`, `tee`,
`cp`, `mv`, `mkdir`, or `touch`. The byte-snapshot test (T-FLN-3) independently verifies this at
runtime for at least 2 fake repos. All reads use `|| true` so a missing file degrades gracefully
without aborting.

### FLN3 — Single named write target + SAFETY comment (mirrors M1 / learn.sh)
**Risk:** An uncontrolled write path — even to a file in THIS repo — could overwrite non-proposal
files or write to engine directories.
**Condition:** Exactly one variable names the write target, declared at the top of
`cmd_fleet_learn`:

    local FLEET_LEARNINGS="$repo/agent-project/FLEET_LEARNINGS.proposed.md"  # SAFETY: only permitted write in cmd_fleet_learn

All `>>` or regeneration writes in the function must reference `$FLEET_LEARNINGS` (or an equivalent
named var with the SAFETY comment). No other write path is permitted. No write to
`~/.claude/agent-os/`, `lib/verbs/`, `bin/massoh`, `manifest.yml`, `templates/`, or any discovered
repo.

### FLN4 — Promotion boundary: CANDIDATE-ONLY, no auto-engine-write (THE rule, CRITICAL)
**Risk:** If the verb auto-promotes any lesson into an engine policy file
(`~/.claude/agent-os/policies/`, `agent-os/policies/`, `STANDARDS.md`, any file in `lib/verbs/`)
it bypasses the owner gate and potentially blasts the whole fleet with a bad change.
**Condition:**
- The verb writes ONLY `agent-project/FLEET_LEARNINGS.proposed.md` in THIS repo.
- Recurrence threshold: lessons seen in >= 2 discovered repos are tagged
  `[generalizable-candidate]`; lessons seen in exactly 1 repo are tagged `[project: <repo-name>]`.
- The document is explicitly a CANDIDATE pool. Its header must contain a prominent note:
  "CANDIDATES ONLY — engine adoption is a separate owner/gated step."
- Static grep: the function body must contain zero writes to any engine file or any discovered repo.
  Test T-FLN-4 must confirm no engine file is modified after running the verb.

### FLN5 — Leak / secrets in the consolidated doc
**Risk:** Raw `LEARNINGS.proposed.md` content from a client repo may contain project names,
API endpoints, issue numbers, or other identifiers. Consolidating them into one doc on the owner's
machine risks accidental disclosure if the file is ever shared.
**Condition (light — consistent with 00_slice3_request.md §"real guard is candidates-only"):**
- The verb copies only structured fields (lesson text, source-repo basename, recurrence count) —
  NOT raw file dumps. It does not `cat` the entire proposals file into FLEET_LEARNINGS.proposed.md.
- Line lengths for individual lesson entries written to the doc are capped at 500 characters
  (truncate with `head -c 500` or equivalent) to bound accidental bulk-copy of a secret block.
- Source attribution uses the repo **basename** only (not the full absolute path), so the home
  directory layout is not exposed.
- The file is local-only: no network upload, no `massoh board --push`, no curl. (Enforced by FLN1.)

### FLN6 — `set -euo pipefail` + `|| true` on all fallible reads
**Risk:** Under `set -euo pipefail`, a missing `*.proposed.md` in a discovered repo would abort the
whole verb, silently skipping remaining repos. An unguarded `grep` on a file that does not exist
exits 1 and kills the function.
**Condition:**
- Every read of a discovered repo's file is guarded: `[ -f "$file" ] || continue` or
  `grep ... 2>/dev/null || true`, never a bare `grep`/`awk`/`cat`.
- The function degrades per-repo: if a repo has no `LEARNINGS.proposed.md` or `META.proposed.md`,
  it is skipped (contributes 0 lessons) and a `[skip]` line is appended to the report; the verb
  exits 0 overall.
- All `awk`, `sort`, `uniq`, `wc` invocations append `|| true`.
- `mkdir -p` before the write (same as learn.sh and meta.sh).

### FLN7 — Idempotent regeneration
**Risk:** Running `massoh fleet learn` twice must not duplicate entries endlessly in
`FLEET_LEARNINGS.proposed.md`.
**Condition (two acceptable patterns — implementer chooses one, declares it in 04):**
- Pattern A (sentinel + regenerate): write the entire doc fresh each run using a sentinel header
  (`<!-- massoh-generated -->`), clobber-guard as in `_board_write_safe`, regenerate atomically.
  Idempotent by construction.
- Pattern B (append with timestamp): append a timestamped block each run (same as learn.sh /
  meta.sh). File grows monotonically; no deduplication needed because each run is a snapshot in
  time. Idempotent in the append-only sense.
  Test T-FLN-6 must verify that two consecutive runs produce a deterministic result consistent with
  the chosen pattern (no corruption, no partial write).

### FLN8 — Sanitize fields written to the markdown table
**Risk:** A lesson text containing pipe characters `|` or backticks could break the markdown table
or be interpreted as shell.
**Condition:** Fields written into markdown table cells or bullet lists must have `|` characters
replaced (e.g. `\|` or ` `) and must never be passed through `eval`. The lesson text is data, not
code. Use `printf '%s'` with named variables only; no unquoted `$()` substitution in the write
block.

---

## 7. Expansion / localization risks

None. The verb uses repo basenames as source labels (already locale-neutral). File paths handled via
`$()` and `printf '%s'` (no eval, no locale-dependent sorting assumptions beyond `|| true` fallback).
The recurrence threshold is a named constant (FLN-THRESHOLD, similar to OUTLIER_FACTOR in meta.sh)
— it should be a named variable, not a magic number, for future configurability.

## 8. Required tests

| Test ID | What it verifies |
|---|---|
| T-FLN-1 | Two fake repos each have `LEARNINGS.proposed.md` with overlapping lesson text; running `massoh fleet learn --write-proposals` produces `FLEET_LEARNINGS.proposed.md` containing both lessons; the lesson present in both repos is tagged `[generalizable-candidate]`; the lesson present in only one repo is tagged `[project: <basename>]`. |
| T-FLN-2 | Same setup: the two fake repos' `LEARNINGS.proposed.md` files are byte-snapshot before the run; after the run their md5sums are identical (ZERO writes to discovered repos). |
| T-FLN-3 | A discovered repo has no `*.proposed.md` file at all; verb exits 0 and FLEET_LEARNINGS.proposed.md contains a `[skip]` or `(no proposals)` line for that repo; the missing-file repo's directory is byte-snapshot-identical before/after (no file created in it). |
| T-FLN-4 | After running the verb, assert zero engine files modified: `git diff --name-only` on `agent-os/`, `lib/verbs/`, `bin/massoh`, `manifest.yml`, `templates/` all return empty. Also assert no file is written to either discovered fake repo. |
| T-FLN-5 | Static grep of `lib/verbs/fleet.sh` for `\bclaude\b`, `\bcurl\b`, `\bwget\b`, `\bagent\b` inside the `cmd_fleet_learn` function returns zero matches (zero-LLM/zero-network assertion). |
| T-FLN-6 | Run `massoh fleet learn --write-proposals` twice consecutively against the same fake fleet; verify the output file is consistent with the declared idempotency pattern (Pattern A: md5 identical; Pattern B: second block appended, first block intact, no corruption). |
| T-FLN-7 | Run with `--no-write` (or no flags); verify `FLEET_LEARNINGS.proposed.md` is NOT created or modified; stdout contains the candidate summary. |
| T-FLN-8 | A fake repo's `LEARNINGS.proposed.md` contains a lesson with a pipe character `|` and backticks; verify the output file is valid markdown (no broken table row, no shell injection; the `|` is escaped or replaced). |

**Test target (current suite):** 544 green (slice 1c merged). Target after slice 3: 544 + 8 (T-FLN-1 through T-FLN-8) = **552 or higher**. The implementer must confirm the exact count in the handoff.

---

## 9. Rollback plan

The verb is additive (`cmd_fleet_learn` is a new subcommand; existing `cmd_fleet` dispatch is a one-line `learn)` case). Rollback = remove the `learn)` dispatch case from `cmd_fleet` and the `cmd_fleet_learn` function from `lib/verbs/fleet.sh`. The only output artifact (`agent-project/FLEET_LEARNINGS.proposed.md`) is a non-tracked proposal file in this repo — it can be deleted without affecting any other verb, test, or user data.

If Pattern A (sentinel + regenerate) is used, the file is always fresh and rollback leaves no stale data. If Pattern B (append), the file is append-only and removal is the rollback.

No safety-critical files are touched. No discovered repo is touched. Rollback is always clean.

---

## 10. Verdict

**APPROVED for implementation — with 8 mandatory conditions (FLN1–FLN8).**

No owner sign-off gate is required beyond what is already granted (2026-06-20 8h away-autonomy grant; `bin/massoh` edits for new fleet verbs pre-authorized). The verb is:
- zero-spend (FLN1 enforced + tested)
- propose-only (FLN3 + FLN4: one named write target, no engine write)
- read-only against discovered repos (FLN2 tested by byte-snapshot)
- within the away-autonomy envelope (no new safety-critical risk class introduced)

**The browser-triggered learn button (POST path) remains PARKED** per 00_architecture_review.md §4 and the 00_slice3_request.md ruling. It is not part of this implementation. The implementer must not wire a POST handler to `cmd_fleet_learn` in `scripts/massoh-dashboard`. Engine adoption of any FLEET_LEARNINGS.proposed.md candidate remains PARKED for owner.

---

## 11. Task-packet update (written above — this IS the 03 document)

Path: `/home/hossam/dev/Massoh/.agent_tasks/TASK-2026-06-20-fleet-observability/03_slice3_architecture_safety.md`

---

## 12. AGENT_SYNC.md update

Per instruction: **do NOT edit AGENT_SYNC.md** in this review pass (read-only assessment role).
The orchestrator or implementer should append the approval row to AGENT_SYNC.md decision log after
this document is written.

---

## Summary for orchestrator

| Item | Value |
|---|---|
| **APPROVED** | YES |
| **Condition count** | 8 (FLN1–FLN8) |
| **Zero-spend confirmed** | YES — deterministic bash heuristic only; FLN1 requires static grep + zero matches for claude/curl/wget/agent |
| **Write target** | Exactly one: `agent-project/FLEET_LEARNINGS.proposed.md` in THIS repo (named var `FLEET_LEARNINGS` + SAFETY comment) |
| **Promotion-boundary mechanism** | Recurrence counter per lesson text across repos; threshold >= 2 = `[generalizable-candidate]`; else `[project: <basename>]`; doc header says "CANDIDATES ONLY — engine adoption is a separate owner/gated step"; no write to any engine file (FLN4 + T-FLN-4) |
| **Browser-button POST** | PARKED — not built in this slice |
| **Biggest risk** | FLN4 (promotion boundary): if the implementer accidentally writes to `agent-os/policies/` or any engine file, the whole fleet's engine is mutated unattended. Mitigated by T-FLN-4 (`git diff` assertion on engine paths) and the single named write variable (FLN3). |
| **Test target** | 552+ (8 new T-FLN-* on top of 544 baseline) |
| **VERSION** | 0.23.0 (next after 0.22.0 slice 1c) |
