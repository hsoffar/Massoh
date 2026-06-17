# 01 — Product Scope
**Task:** TASK-2026-06-17-cadence-cron · **Date:** 2026-06-17 · **Agent:** massoh-product-scope

---

## Decision: BUILD

---

## 1. Why now / why this decision

Backlog item #1 (top of queue). The ceremonies are already shipped and read-only (pure bash, no
LLM call, no API spend). The cron runner (`bin/massoh-cron`) fires today but only works the
agent backlog; it has zero cadence awareness. The gap is narrow: cron ticks do not produce a
standup entry, and period boundaries (e.g. weekly) do not trigger review + plan. Closing this gap
completes v0.4 as documented in `NOW_NEXT_LATER.md` and `AGENT_BACKLOG.md`. The "post-agile for
agents" positioning (`PRODUCT_STRATEGY.md`) names this directly: "cron = do work; cadence =
review + decide." The integration is the payoff of that architectural bet.

The strategic mode is "validate that a portable, gated agent OS reduces build-trap." Automated
cadence ceremonies are the mechanism that surfaces drift and forces inspect-and-adapt — they are
the primary retention/learning driver this cycle. Deferring weakens the validation.

---

## 2. Target segment

Solo owner + Claude Code on one maintained repo (primary wedge). No change to expansion
readiness — the cron and ceremony commands already work per-repo; nothing here hard-codes a
single repo, schedule value, or user identity.

---

## 3. Target region / locale

POSIX-bash CLI, no locale-specific content. No change needed. Expansion note: nothing in this
change introduces hard-coded locale assumptions.

---

## 4. Metric affected

`packet_merged` (activation complete) — this is a direct continuation of the v0.4 activation
arc. The secondary signal is cadence log density in `AGENT_SYNC.md` and `agent-project/METRICS.md`
(observable by hand; no new telemetry required under the current instrumentation policy).

There is no named event for "retention via cadence" in `METRICS.md` yet. That is acceptable: the
metric file notes that events are counted by hand from git + `.agent_tasks/` until `massoh report`
exists. This task does not block on a new named event.

---

## 5. Minimal version (smallest slice that tests the hypothesis)

One change to `bin/massoh-cron`, specifically inside `cmd_once`:

**On every tick** (after the idle gate passes and before the worktree loop):
- Run `massoh standup` (in the repo, no worktree needed — it is read-only + appends to
  `AGENT_SYNC.md`).

**On every Nth tick** (where N = period boundary, default = 7 days' worth of ticks, computed as
`period_ticks = period_days * minutes_in_day / tick_interval_minutes`, stored as a counter in
`.agent_tasks/cron/cadence_state`):
- Run `massoh review` (appends snapshot to `agent-project/METRICS.md`).
- Run `massoh plan` (appends queue snapshot to `AGENT_SYNC.md`).

**Counter mechanics (simple, file-based, portable):**
- A single-line file `.agent_tasks/cron/cadence_state` stores the integer tick count since last
  period reset.
- On every tick: increment counter. If `counter >= period_ticks`: run review+plan, reset counter to 0.
- `period_ticks` is derived from `--every` and `--period-days` (new flag, default 7).
- The counter file is created on first tick if absent (no migration needed — additive).

**New flags on `cron once`:**
- `--period-days N` (default `7`) — how many days constitute a "period" for review+plan.
- `--no-standup` — skip standup on this tick (escape hatch for testing/debugging).

**New flag on `cron install`:**
- `--period-days N` — passed through to the generated crontab line.

That is the entire change surface. No new files beyond the state counter. No LLM call. No API
spend. No changes to the ceremony commands themselves. No changes to `manifest.yml`, install/
uninstall, or the safety-critical file list.

---

## 6. Non-goals (explicit)

- Do NOT change `cmd_review`, `cmd_standup`, or `cmd_plan` — they are already correct.
- Do NOT add telemetry or a new named metrics event (out of scope for this task).
- Do NOT add a UI or web surface.
- Do NOT add persistence beyond the single counter file.
- Do NOT wire cadence into the worktree agents (they work the backlog; cadence is the parent
  process's concern).
- Do NOT support per-project cadence overrides (LATER — profiles/config.yml backlog item #4).
- Do NOT change `manifest.yml` or the install/uninstall contract (no schema bump needed).
- Do NOT auto-run `massoh review --run-tests` from cron (test invocation remains an explicit
  opt-in flag; cron should not run the test suite unattended without explicit owner enablement).

---

## 7. Safety / guardrail impact

**Designated safety-critical files:** `bin/massoh` and `manifest.yml` are listed in
`NON_NEGOTIABLES.md`. `bin/massoh` is NOT touched — the change is confined to `bin/massoh-cron`.
`manifest.yml` is NOT touched. Owner sign-off is therefore NOT required by the designated file
rule, but the `00_request.md` records that the owner authorized `bin/massoh*` edits explicitly.
`bin/massoh-cron` is in the `massoh*` namespace — this is a safe change point under CHARTER §3
("swap seams").

**Read-only ceremonies:** `standup`, `review`, and `plan` are read-only (no code changes, no
worktree, no git ops). They append to markdown files inside the repo, which is exactly what they
do today when called manually. No new destructive surface.

**Counter file:** `.agent_tasks/cron/cadence_state` is a new append-or-overwrite file in an
already-owned directory. It is not in the user's `~/.claude`. It is ephemeral state — losing it
resets the period counter (safe: the next period boundary will just fire slightly early or late
by at most one tick interval). No data is lost.

**POSIX-bash invariant:** The counter logic must use POSIX arithmetic (`$(( ))`) and basic file
ops (`cat`, `printf`, `mkdir -p`). No `bc`, no `python`, no non-portable deps.

**Idempotence:** if `cmd_once` is called twice in rapid succession (e.g. by clock drift), the
counter will increment twice. This is acceptable — a double standup in AGENT_SYNC.md is harmless
and observable. A period boundary firing one tick early is harmless.

**`set -euo pipefail`:** The standup/review/plan commands must be guarded so that a failure does
not abort the entire cron tick. Wrap each ceremony call in `|| true` (matching the existing
pattern in `massoh-cron` for non-fatal steps) and log the outcome to the cron log.

**Guardrail E (autonomous cron):** ceremonies are not deployments, not merges, not paid spend —
they do not require the `--auto-merge` or `--yes-spend` guards. They are ambient telemetry, safe
to run unattended.

---

## 8. Expansion / localization impact

None. The counter file path is relative to `$REPO`, which is already per-repo. If a second repo
opts in and runs cron, it gets its own counter. No shared state. No locale-specific content.

---

## 9. Required events (named)

No new named events required under the current instrumentation policy. The output artifacts
(standup entries in `AGENT_SYNC.md`, review snapshots in `agent-project/METRICS.md`, plan entries
in `AGENT_SYNC.md`) are the observable signal — countable by hand from git log.

If/when `massoh report` is built (LATER), the event to name would be `cadence_tick` (standup run)
and `cadence_period` (review+plan run). These names are reserved here for future instrumentation.

---

## 10. Acceptance criteria (testable)

All of the following must be verifiable by the existing `test/run.sh` suite plus new tests:

1. `massoh cron once --run --no-idle-check --dry-run` prints a standup line in dry-run output
   (or the implementer documents why dry-run cannot show ceremony output — acceptable if noted).

2. After `massoh cron once --run --no-idle-check`, `AGENT_SYNC.md` in the repo contains a new
   `## [standup]` section with a timestamp from the current run.

3. After `massoh cron once --run --no-idle-check` repeated N times (where N = `period_ticks`
   derived from `--period-days 0` or equivalent test shortcut), `agent-project/METRICS.md`
   contains a new `## Snapshot` entry and `AGENT_SYNC.md` contains a new `## [plan]` entry.

4. `.agent_tasks/cron/cadence_state` exists after a run, contains a non-negative integer, and
   increments on each subsequent tick.

5. `.agent_tasks/cron/cadence_state` resets to `0` after a period boundary fires.

6. `massoh cron once --run --no-idle-check --no-standup` does NOT append a standup entry.

7. A ceremony failure (simulated by `MASSOH_STANDUP_CMD=false`) does NOT abort the cron tick —
   the backlog work loop still runs and the exit code of `cron once` is still 0.

8. All existing `test/run.sh` checks continue to pass (no regression).

9. `massoh cron install --every 30m --period-days 7` output includes `--period-days 7` in the
   printed crontab line.

---

## 11. Kill / defer criteria

**Kill this task if:**
- The ceremony commands are discovered to have side effects beyond appending to markdown files
  (e.g. network calls, secret reads) — re-evaluate safety before proceeding.

**Defer this task if:**
- A higher-priority P0 bug surfaces before `03_architecture_safety.md` is written.
- The owner decides to refactor cadence state into `config.yml` first (backlog item #4) — merge
  the two tasks rather than layering.

**Re-entry condition (if deferred):** when the blocking item is resolved, pick this task back up
from `01` (this file) — no re-scoping needed unless the ceremonies changed.

---

## 12. Routing

**Next agent: `massoh-architecture-safety`**

This is a technical/bash change (new flag, counter file, ceremony invocation in `cmd_once`). UX
review is not required (no user-facing UI surface — CLI flags are an implementation detail,
governed by the POSIX-bash invariant already in place). Route directly to architecture-safety for
the `03_architecture_safety.md` review.

Architecture-safety should specifically evaluate:
- The counter file: path, atomicity, failure mode (missing file, corrupt contents, concurrent cron runs).
- The `|| true` wrapping pattern for ceremony calls — confirm it matches the project's error-
  handling convention in `massoh-cron`.
- Confirm `--period-days` flag does not conflict with any existing flag namespace.
- Confirm no change is needed to `manifest.yml` (install/uninstall contract unaffected).
