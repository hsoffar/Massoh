# 03 — Architecture / Safety Review
**Task:** TASK-2026-06-17-cadence-cron · **Date:** 2026-06-17 · **Agent:** massoh-architecture-safety

---

## Verdict

**APPROVED — with four mandatory conditions** (see §10 for the precise list). All conditions are
implementer-enforceable within the approved scope; no additional product-scope or owner sign-off is
required beyond what `00_request.md` already records.

---

## 1. Backend / service impact

No backend. This is a pure bash-in-process change to `bin/massoh-cron`. The ceremonies
(`standup`, `review`, `plan`) are read-only bash functions in `bin/massoh` that append to
markdown files — already shipped, no change to them. No network call, no API spend, no service
dependency introduced.

The only new I/O surface is the counter file `.agent_tasks/cron/cadence_state`. The parent
directory `.agent_tasks/cron/` already exists in practice (the tick result files land there), and
the cron runner already does `mkdir -p "$REPO/.agent_tasks/cron"` at line 99 of `bin/massoh-cron`
before writing result files, so the directory is guaranteed to exist by the time the cadence block
runs — provided the cadence block is placed AFTER the result-serialization block (see §6).

---

## 2. Client / app impact

CLI only. The two new flags (`--period-days N`, `--no-standup`) are additive to `cron once`.
The new flag on `cron install` (`--period-days N`) changes the generated crontab line but not the
install/uninstall contract. No user-visible behavior change on existing invocations (both flags
default to safe values: period-days=7 fires at a boundary that does not exist yet on a fresh
state file; no-standup=false means standup runs, matching the new intended default behavior).

---

## 3. API impact

No API contract change. `manifest.yml` is unchanged. The `bin/massoh` ↔ `manifest.yml` seam is
untouched. The global block markers are untouched. `bin/massoh-cron` is not listed in
`manifest.yml` (it is invoked by `bin/massoh cmd_cron` via `exec`; its interface is internal to
the cron subsystem). No "both sides together" obligation is triggered.

---

## 4. DB / migration impact

No database. The counter file `.agent_tasks/cron/cadence_state` is new, additive, and
create-if-missing. It does not appear in `manifest.yml`'s install/uninstall lists (correct — it is
ephemeral per-repo runtime state, not an installed artifact). Losing it or corrupting it resets the
period counter to 0, which is safe: the next period boundary fires at most one full period late.
No migration is needed; no backward-compat window is required.

**Counter file atomicity analysis:** Single-line integer. The increment path is
read-increment-write within a single process (the cron parent), not shared with worktree
subprocesses (those run in parallel but only write to `$RESULTS/`). Concurrent cron invocations
(clock drift / manual re-run) will cause a race on the file, but the consequence is a duplicate
increment (double standup entry in AGENT_SYNC.md, period boundary fires one tick early) — both
harmless and observable. POSIX `printf` to a named file is not atomic, but the risk is limited to
the idempotence property already accepted in `01_product_scope.md §7`. No `flock` required for v0.4.

**Corruption tolerance:** the read must default to 0 on any non-integer content. The implementer
MUST use a pattern such as:

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

This is a mandatory condition (Condition A, below).

---

## 5. LLM / prompt impact

None. The ceremonies invoke `bin/massoh standup/review/plan`, which are pure bash — no `claude`
invocation, no `$AGENT_CMD` call, no LLM spend. The cron parent does not call `$AGENT_CMD` for
ceremonies; that command is only used inside `work_item()` inside the worktree subprocesses.
No prompt layer is touched. No safety rules or disclaimers are in scope.

---

## 6. Safety / guardrail risks

### Risk 1 — set -euo pipefail abort on ceremony failure (CRITICAL)
`bin/massoh-cron` runs `set -euo pipefail`. A ceremony call that exits non-zero will abort the
entire cron tick, discarding the result-serialization block that writes AGENT_SYNC.md and result
files. This would silently drop backlog progress if a ceremony fails before the serialization loop.

**Mandatory condition B:** Every ceremony call MUST be wrapped in `|| true`. Additionally, the
cadence block MUST be placed AFTER the serialization loop (after line 118 in the current
`bin/massoh-cron`, i.e. after `printf '\n%s' "$block" >> "$REPO/AGENT_SYNC.md"`). This ordering
guarantee ensures a ceremony failure can never drop backlog progress. The `|| true` wrapping
matches the existing project pattern (lines 95, 96 of `bin/massoh-cron` already use `|| true` for
non-fatal steps).

Recommended ceremony invocation pattern (dry-run gate included — see Condition C):

```bash
# cadence block — runs AFTER backlog serialization, error-isolated
if [ "$mode" = run ] && [ "${no_standup:-0}" != 1 ]; then
  ( cd "$REPO" && "$MASSOH_HOME/bin/massoh" standup ) || true
fi
```

And for review+plan at period boundary:

```bash
if [ "$mode" = run ] && [ "$tick_count" -ge "$period_ticks" ]; then
  ( cd "$REPO" && "$MASSOH_HOME/bin/massoh" review ) || true
  ( cd "$REPO" && "$MASSOH_HOME/bin/massoh" plan )   || true
  tick_count=0
fi
```

Note: `$MASSOH_HOME` is already set at the top of `bin/massoh-cron` via
`REPO="$(git rev-parse --show-toplevel)"`. The implementer must also ensure `MASSOH_HOME` is
resolvable; the safest path is `"$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."` mirroring the
pattern in `bin/massoh`. Alternatively, since `bin/massoh-cron` is invoked via
`exec "$MASSOH_HOME/bin/massoh-cron" "$@"` in `bin/massoh`, the environment already has
`MASSOH_HOME` set. The implementer should verify this at the top of `cmd_once` rather than
re-deriving it.

### Risk 2 — ceremony invoked during dry-run or after idle-skip
The idle gate (`owner_active`) returns early at line 67. The empty-backlog check returns early at
line 70. The dry-run branch returns at line 75. All three of these early returns happen BEFORE the
ceremony block, so ceremonies will naturally not run in those cases — provided the cadence block is
placed at the correct position (after the dry-run early-return, in the real-tick path only).

**Mandatory condition C:** Ceremonies MUST be gated on `[ "$mode" = run ]`. Dry-run MUST NOT
invoke any ceremony. The implementer must verify that the dry-run path either prints a note
("would run standup") or is silent — either is acceptable, but no ceremony file must be appended.

### Risk 3 — `bin/massoh` and `manifest.yml` not touched
Confirmed: `bin/massoh` is a designated safety-critical file under `NON_NEGOTIABLES.md`. The
ceremonies are called by invoking `bin/massoh standup` etc. from the cron parent; this is a
read-only invocation, not a modification. No edit to `bin/massoh` is required.

`manifest.yml` lists per-repo scaffold paths but not per-repo runtime state. The counter file is
runtime state (like the `.result` files already written by cron). No change to `manifest.yml` is
required. Confirmed safe.

### Risk 4 — EXIT trap interaction
The existing EXIT trap (line 80) prunes worktrees and removes temp dirs. The cadence block runs
after the worktree cleanup loop and the serialization block (lines 96–118), so if a ceremony call
triggers `|| true`, it does not interfere with the EXIT trap. If a ceremony call raises a signal
that bypasses `|| true` (not possible in standard bash), the EXIT trap would still fire and clean
up temp dirs correctly. No interaction risk.

### Risk 5 — standup appends to AGENT_SYNC.md; cron tick block also appends to AGENT_SYNC.md
Both the `[cron] tick` block (line 118) and `massoh standup` append to `AGENT_SYNC.md`. If the
cadence block runs after the tick block, AGENT_SYNC.md will have the tick entry first and the
standup entry after — correct ordering, no conflict. The file is append-only (guardrail A3
satisfied). No concurrent writer: worktree agents do not write to the parent's AGENT_SYNC.md.

---

## 7. Expansion / localization risks

None. `period_days` is a CLI parameter (not hard-coded). The counter file is relative to `$REPO`
(per-repo state). No locale content. No timezone assumption beyond what the ceremonies themselves
already use (`date -u` in UTC). Expansion note: if a future multi-period cadence is needed
(different ceremonies on different schedules), the counter file name should be made configurable
or namespaced — but that is LATER (backlog item #4). For v0.4 the single counter is acceptable.

---

## 8. Required tests

All tests MUST use the `mkcronrepo` helper pattern from T7 in `test/run.sh` (throwaway git repos,
fake agent via `MASSOH_AGENT_CMD`, fake gate via `MASSOH_GATE_CMD=true`, temp sentinel files).
No real `~/.claude` is ever touched. Tests must be added to `test/run.sh` as a new `T10` block.

### T10a — standup runs on a --run tick
Invoke `cron once --run --no-idle-check` in a mkcronrepo repo. Assert `AGENT_SYNC.md` contains
a `## [standup]` line. (No worktree needed for this — the fake agent still runs, but the key
signal is the standup append.)

### T10b — standup does NOT run on dry-run
Invoke `cron once --no-idle-check` (default dry-run). Assert `AGENT_SYNC.md` does NOT contain
`## [standup]`.

### T10c — --no-standup suppresses standup
Invoke `cron once --run --no-idle-check --no-standup`. Assert `AGENT_SYNC.md` does NOT contain
`## [standup]`.

### T10d — cadence_state created and increments
After two `--run` ticks (two separate invocations), assert `.agent_tasks/cron/cadence_state`
exists and contains the integer `2` (or `0` if a period boundary fired — but with default
period_days=7 and default --every=30m, period_ticks would be 7*1440/30=336, so no boundary fires
in 2 ticks).

### T10e — review+plan fire at period boundary, counter resets
Pre-seed `.agent_tasks/cron/cadence_state` with a value equal to `period_ticks - 1` (computed
for `--period-days 1 --every 1440m`, giving period_ticks=1, so seed with `0`). Invoke
`cron once --run --no-idle-check --period-days 1`. Assert `agent-project/METRICS.md` contains
`## Snapshot` and `AGENT_SYNC.md` contains a `## [plan]` section. Assert
`.agent_tasks/cron/cadence_state` contains `0` (reset).

Alternatively: with `--period-days 0` (if the implementer allows it as a test shortcut mapping to
period_ticks=1), assert boundary fires on the first tick.

### T10f — ceremony failure does NOT abort the tick
Introduce a fake standup command that exits 1:
`MASSOH_STANDUP_CMD=false` (or patch via a wrapper) and assert the cron tick still exits 0 and
`AGENT_BACKLOG.md` still has `| DONE |`. This directly tests the `|| true` wrapping.

The recommended injection mechanism: add `MASSOH_STANDUP_CMD` / `MASSOH_REVIEW_CMD` /
`MASSOH_PLAN_CMD` injectable env vars (parallel to `MASSOH_AGENT_CMD` / `MASSOH_GATE_CMD`)
defaulting to `"$MASSOH_HOME/bin/massoh standup"` etc. This is the cleanest way to test ceremony
failure isolation without modifying `bin/massoh`.

### T10g -- cron install --period-days passes through to crontab line
Assert `cron install --every 30m --period-days 7` output contains `--period-days 7` in the
printed crontab line string.

### T10h -- existing T7 tests all still pass (regression)
The new flags must not break any existing `once` behavior. Run all T7 sub-tests unmodified.

---

## 9. Rollback plan

`bin/massoh-cron` is a single file. If the cadence block introduces a regression:
1. `git revert` the commit on the feature branch; re-open the PR with the revert.
2. The counter file `.agent_tasks/cron/cadence_state` can be deleted safely (it will be
   re-created on the next tick). No data is lost.
3. Ceremonies write append-only entries to `AGENT_SYNC.md` and `agent-project/METRICS.md` — these
   are not rolled back, but they are harmless historical entries.

The change is confined to one file plus one new state file. There is no install-contract change,
so no user re-install is required to roll back.

---

## 10. Approved for implementation? YES — with four mandatory conditions

**Condition A — Corruption-tolerant counter read (mandatory).**
The implementer MUST default `tick_count=0` on any non-integer or missing state file content,
using an explicit guard (case/pattern match as shown in §4). Do not use bare `$(cat ...)` without
validation.

**Condition B — Post-serialization placement + `|| true` wrapping (mandatory, safety-critical).**
The cadence block MUST be placed after the AGENT_SYNC.md serialization write (after the
`printf '\n%s' "$block" >> "$REPO/AGENT_SYNC.md"` line). Every ceremony call MUST be wrapped in
`|| true`. This ordering is load-bearing: a ceremony failure must never drop backlog progress.

**Condition C — Dry-run and idle-skip gate (mandatory).**
Ceremonies MUST be gated on `[ "$mode" = run ]`. No ceremony file write on dry-run. No ceremony
call when the idle gate or empty-backlog gate fires (those early-return before the cadence block
anyway — the implementer must not restructure `cmd_once` in a way that bypasses this).

**Condition D — Injectable ceremony commands for testing (mandatory).**
The implementer MUST expose `MASSOH_STANDUP_CMD`, `MASSOH_REVIEW_CMD`, and `MASSOH_PLAN_CMD`
injectable env vars (defaulting to `"$MASSOH_HOME/bin/massoh standup"` etc.), matching the
`MASSOH_AGENT_CMD` / `MASSOH_GATE_CMD` pattern. This is the only way to write a reliable T10f
test for ceremony failure isolation without patching `bin/massoh`.

**Advisory (not blocking):**
- `period_ticks` arithmetic should guard against `period_days=0` producing division by zero or
  period_ticks=0 (infinite trigger loop). Minimum clamp: `period_ticks=$(( period_ticks < 1 ? 1 : period_ticks ))`.
  This is worth a T10e test with `--period-days 0` if the implementer chooses to allow it.
- Log the ceremony outcome to cron.log or stdout so the owner can observe cadence activity from
  the cron log (`>> $REPO/.agent_tasks/cron/cron.log 2>&1` in the installed crontab line already
  captures this if `say` is used).

---

## 11. Task-packet update

This file (`03_architecture_safety.md`) is the packet update for this stage.

---

## 12. AGENT_SYNC.md update

The `AGENT_SYNC.md` must be updated with the following decision row and handoff block after this
review is accepted. The implementer agent should append this when it picks up the task:

Decision row to append to the Decision log table:
```
| 2026-06-17 | TASK-2026-06-17-cadence-cron: arch/safety APPROVED — 4 conditions: counter corruption-tolerance, post-serialization placement + || true, dry-run gate, injectable ceremony cmds | architecture-safety |
```

Active task packets row to update (change stage from `01_product_scope` to `03_architecture_safety`):
```
| TASK-2026-06-17-cadence-cron | 03_architecture_safety | IN FLIGHT — arch/safety approved, ready for implementer |
```

Last handoff block:
```
Agent: massoh-architecture-safety
Mode: review
Task: TASK-2026-06-17-cadence-cron — wire cadence ceremonies into cron
Status: 03_architecture_safety.md written — APPROVED with 4 conditions
Next recommended agent: massoh-implementer
Next action: write 04_implementation_packet.md; implement in bin/massoh-cron only;
  enforce all 4 conditions; add T10 tests to test/run.sh; run full suite before PR.
```
