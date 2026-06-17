# 01 — Product Scope
**Task:** TASK-2026-06-17-massoh-ledger · **Date:** 2026-06-17 · **Agent:** massoh-product-scope
**Decision: BUILD**

---

## 1. Why build this now

The north-star locked in `PRODUCT_STRATEGY.md` is: governed, self-measuring, autonomous. The
system is governed (gate enforced). It is beginning to be autonomous (cron, ceremonies). The
missing pillar is **self-measuring at the agent level** — the system cannot yet tell the owner
"this task consumed N tokens and M minutes." Without that primitive, autonomy has no cost
accountability, and the cron cannot be trusted to run unsupervised at scale.

The key insight from `00_request.md` applies directly: the Claude Code harness already reports
`subagent_tokens` and `duration_ms` on every agent result visible to the orchestrator. Massoh must
capture + persist + analyze that data, not re-measure it. This is a pure collection and reporting
problem.

The ledger is also the prerequisite for two future capabilities called out in `00_request.md`:
`review`/`recommend` reading cost-per-task ("a gated feature costs N tokens, ~M min") and durable
token budgets stored in memory. Neither is in scope now. But if the ledger does not exist, both
remain impossible.

**Strategic mode alignment:** the current mode is "validate that a portable, gated agent OS
reduces build-trap for solo+Claude shipping — enough to install it in a second real repo." A
self-measuring OS is directly persuasive to that claim. No contradiction found in repo evidence.

**Bin/massoh safety-critical file:** owner has authorized `bin/massoh` edits for this task on
the north-star track, as recorded in `00_request.md` ("Owner authorized build + `bin/massoh*`
edits"). No additional unfreeze is required; record it here and do not block.

---

## 2. Target segment

Solo founder / single maintainer using Claude Code on one product (the primary wedge per
`CHARTER.md` §2 and `PRODUCT_STRATEGY.md` §Segments). No "all users" generalization; this is
the same wedge every prior task has targeted.

No hard-coding of the wedge. The ledger path (`.agent_tasks/ledger.tsv`) uses the standard
per-repo `.agent_tasks/` scaffold that `massoh on` already creates. A future expansion to
multi-repo or multi-harness requires no structural change to the ledger format — TSV rows are
harness-neutral.

---

## 3. Target region / locale

MVP: any locale. Pure bash CLI writing tab-separated values and reading them with `awk`. No
locale-sensitive date parsing beyond ISO-8601 timestamps via `date -u`. No locale surface
introduced. Expansion note: output labels ("tokens", "seconds", "total", "avg") are English;
the numeric extraction in `awk` is locale-neutral. Flag as a NEXT if multi-language output is
ever required — do not parameterize now.

---

## 4. Why now / why not

**Why now:** The cadence ceremonies (standup / review / plan / cron) are shipped. The learning
layer (learn / recommend) is shipped. The natural next primitive is cost visibility — the system
cannot answer "how much did that task cost?" The data already exists in the harness; capturing it
is one new verb and one append to a TSV file.

**Why not wait:** The ledger's value compounds over time (more rows = better averages). The
sooner it is introduced, the richer the data when the owner wants to set budgets or tune cron
autonomy. Waiting means retroactively missing data that cannot be recovered.

---

## 5. Metric affected

**`packet_merged`** (activation complete) — the ledger enriches every merged packet with cost
data. A packet that has been through the full gate `00→06` now also contributes a ledger row,
making the activation event more observable and the cost-per-packet trend visible over time.

No new top-level metric event is required for MVP. The ledger is the raw data source; future
reporting verbs (e.g. `massoh report`) would aggregate it into a named event. If `massoh report`
is built later, add a `ledger_read` event at that time.

---

## 6. Minimal version

Two verbs added to `bin/massoh`. Both are pure bash, zero LLM spend, no new external
dependencies.

### Verb 1 — `massoh ledger add <task-id> <stage> <tokens> <seconds>`

Appends one row to the central ledger at `.agent_tasks/ledger.tsv` in the current repo.

**Row format (TSV, 5 fields, no header):**

```
<ISO-8601-UTC-timestamp>\t<task-id>\t<stage>\t<tokens>\t<seconds>
```

Example:
```
2026-06-17T14:23:00Z\tTASK-2026-06-17-massoh-ledger\tproduct-scope\t4200\t83
```

Rationale for central ledger (not per-task):
- A single `.agent_tasks/ledger.tsv` is trivially grep-able, awk-aggregatable, and portable. A
  per-task ledger would require a join to produce cross-task totals — unnecessary complexity for
  MVP.
- `.agent_tasks/` already exists (created by `massoh on`). No new directory needed.
- Append-only (never overwrites). Satisfies NON_NEGOTIABLES "keep older data."

**Validation (v1):**
- Exactly 4 positional args required after `add`; any other count → error + non-zero exit.
- `<tokens>` must be a non-negative integer (`[0-9]+`); reject otherwise.
- `<seconds>` must be a non-negative integer (`[0-9]+`); reject otherwise.
- `<stage>` is free-form (no enum enforcement in v1 — keeps it flexible and harness-neutral).
- `<task-id>` is free-form.

**POSIX compliance:** `printf '\t'` for tab separator; `date -u +%Y-%m-%dT%H:%M:%SZ` for
timestamp; `>>` append; `set -euo pipefail` preserved throughout.

### Verb 2 — `massoh ledger` (no args, read-only report)

Reads `.agent_tasks/ledger.tsv` and prints an aggregated report to stdout. No file writes.

**Report structure:**

```
massoh ledger — <timestamp>  (v<ver>)
  ledger: <N> rows  (.agent_tasks/ledger.tsv)

  Per-task summary:
    <task-id>   tokens=<sum>  seconds=<sum>  avg_tokens/stage=<avg>  stages=<count>
    ...
    TOTAL       tokens=<sum>  seconds=<sum>

  Per-stage summary:
    <stage>     tokens=<sum>  seconds=<sum>  count=<N>  avg_tokens=<avg>
    ...
```

All arithmetic done in `awk`. Division-by-zero guarded (if count=0, print "n/a"). If
`.agent_tasks/ledger.tsv` is absent or empty, print a single-line degraded message:
`  (no ledger data — run: massoh ledger add <task-id> <stage> <tokens> <seconds>)` and exit 0.

**Dispatch:** `massoh ledger` with no additional args prints the report. `massoh ledger add ...`
appends a row. Any other sub-command → error. The dispatch is a sub-command case inside
`cmd_ledger`.

---

## 7. Capture mechanism recommendation: verb over SubagentStop hook

**Recommended v1 mechanism: the orchestrator-called verb `massoh ledger add ...`.**

Rationale:

1. **Testable without harness.** A fixture-based test can call `massoh ledger add TASK-X scope
   1000 60` directly and verify the TSV row — no Claude Code instance, no SubagentStop lifecycle
   needed. This satisfies guardrail A5 (real tests, zero spend).

2. **No harness coupling.** `settings.json` SubagentStop hooks are Claude Code-specific. The
   CHARTER §2 expansion principle names "host harness = Claude Code (single-valued for now)" as
   a wedge, not a permanent constraint. A verb-based capture keeps the ledger harness-neutral: any
   orchestrator (a future harness, a cron script, a CI step) can call `massoh ledger add`. A hook
   hard-codes Claude Code.

3. **Owner visibility.** When the orchestrator calls `massoh ledger add` explicitly, the call
   appears in the agent handoff notes and the commit history. A SubagentStop hook fires silently —
   harder to audit.

4. **Additive / reversible.** A new verb is flag-dark: existing installs see no behavior change
   until the orchestrator is wired to call it. A SubagentStop hook fires on every agent stop
   immediately after installation.

**SubagentStop hook as a NEXT:** note for `NOW_NEXT_LATER.md`. Once the verb is proven and the
ledger format is stable, a SubagentStop hook in `settings.json` can auto-call `massoh ledger add`
on every agent return, removing the need for the orchestrator to wire it explicitly. That hook
adds zero new logic (it calls the verb); it is purely an ergonomic improvement and can be
proposed to architecture-safety in a follow-up task.

---

## 8. Non-goals (explicit)

- No SubagentStop hook in v1. The hook is a NEXT; do not implement it here.
- No LLM calls. No `claude -p`. Zero API spend.
- No per-task sub-file ledger (e.g. `.agent_tasks/TASK-X/ledger.tsv`). Central file only.
- No cost in dollars (tokens only; dollar conversion requires model pricing which changes and
  varies by model — defer to a NEXT where a configurable price-per-token can be introduced).
- No integration with `review` or `recommend` in v1 (those read METRICS.md; ledger integration
  is a NEXT).
- No auto-wiring into cron. The cron can call `massoh ledger add` after each agent tick, but
  wiring that is the orchestrator's responsibility, not this task's.
- No charting, visualization, or non-CLI output.
- No changes to packet format, `manifest.yml`, or install/uninstall contract.
- No migration of past tasks (data starts accumulating from when the verb is first called).

---

## 9. Required events (named)

No new top-level metric event required for MVP. The `packet_merged` event is enriched indirectly
(each merged packet can now have a corresponding ledger row). If `massoh report` is built later,
define `ledger_row_added` as a new event at that time.

---

## 10. Safety / guardrail impact

| File touched | Safety-critical? | Sign-off required | Notes |
|---|---|---|---|
| `bin/massoh` | Yes | On record in `00_request.md` | New `cmd_ledger` function + dispatch case; no install/uninstall/backup/block logic touched |
| `.agent_tasks/ledger.tsv` | No | N/A | Append-only; created on first `ledger add`; satisfies NON_NEGOTIABLES "keep older data" |
| `test/run.sh` | No | N/A | New T15 block appended; existing tests must remain green |

**Guardrail A1 (no code without a license):** this `01_product_scope.md` feeds `03_architecture_safety.md`
before any implementation.

**Guardrail A3 (keep older data):** `ledger.tsv` is append-only. `cmd_ledger add` never truncates
or rewrites; it only appends. If the file is absent, it is created. If it is present, rows
accumulate.

**Guardrail A5 (real tests):** fixture-based tests in `test/run.sh` (T15 block). No stubs. The
tests call the real `massoh ledger add` and `massoh ledger` verbs against a temp repo.

**Guardrail A9 (scope discipline):** implementer must not add dollar-cost calculation, per-task
sub-ledgers, cron wiring, or METRICS.md integration — all are explicit non-goals.

**POSIX-bash / `set -euo pipefail`:** must remain intact. All subshell reads `|| true` guarded
(awk on missing file). No non-portable deps.

**NON_NEGOTIABLES "feature flags" clause:** this project has no runtime flags (CLI tool), per
NON_NEGOTIABLES §Feature flags. The ledger verb is additive (no behavior change on existing
installs until explicitly called). No flag registry entry needed; record this.

---

## 11. Expansion / localization impact

The ledger TSV format is harness-neutral: `timestamp`, `task-id`, `stage`, `tokens`, `seconds` —
no Claude Code-specific fields, no locale-sensitive content. A future multi-harness expansion
(AGENTS.md) can populate the same ledger from any orchestrator by calling the same verb.

The `stage` field is free-form in v1. If a future expansion defines a controlled vocabulary of
stage names (e.g. for cross-harness normalization), the TSV format does not change — only the
validation logic gains an enum check. Design note for the implementer: do not add an enum today;
leave `stage` as a free string with a comment `# stage: free-form; future versions may enumerate`.

Output labels are English; numeric fields are locale-neutral. No hard-coded region or segment
assumption introduced.

---

## 12. Acceptance criteria (testable, fixture-based, zero LLM spend)

All tests added to `test/run.sh` as a new `T15` block. Each test uses a temp repo with a
`.agent_tasks/` directory (same fixture pattern as prior tests). No real `~/.claude` touched.

### T15a — `ledger add` appends a valid row
Call `massoh ledger add TASK-fixture scope 1000 60` in a temp repo. Assert `.agent_tasks/ledger.tsv`
exists. Assert it contains exactly one line. Assert the line has 5 tab-separated fields. Assert
field 3 is `TASK-fixture`, field 4 is `scope`, field 5 is `1000`, field 6 is `60`. Assert field 1
is a valid ISO-8601 UTC timestamp (matches `^[0-9]{4}-`).

### T15b — `ledger add` is append-only (two calls → two rows)
Call `massoh ledger add TASK-fixture scope 1000 60` twice. Assert `.agent_tasks/ledger.tsv` has
exactly 2 lines. Assert neither call overwrote the other row. (Keep-older-data.)

### T15c — bad input rejected (tokens not an integer)
Call `massoh ledger add TASK-fixture scope notanumber 60`. Assert non-zero exit. Assert
`ledger.tsv` was not created (or, if it existed beforehand, assert it is unchanged — file is
never partially written on validation failure).

### T15d — bad input rejected (seconds not an integer)
Call `massoh ledger add TASK-fixture scope 1000 notanumber`. Assert non-zero exit.

### T15e — wrong arg count rejected
Call `massoh ledger add TASK-fixture scope 1000` (missing seconds). Assert non-zero exit and error
message to stderr.

### T15f — `massoh ledger` aggregates correctly
Pre-populate a fixture `ledger.tsv` with 3 rows:
```
2026-06-17T00:00:00Z\tTASK-A\tscope\t1000\t60
2026-06-17T00:01:00Z\tTASK-A\tarch\t2000\t90
2026-06-17T00:02:00Z\tTASK-B\tscope\t500\t30
```
Run `massoh ledger`. Assert output contains:
- `TASK-A` with `tokens=3000` and `seconds=150`.
- `TASK-B` with `tokens=500` and `seconds=30`.
- TOTAL `tokens=3500` and `seconds=180`.
- Per-stage: `scope` with `tokens=1500`, `count=2`; `arch` with `tokens=2000`, `count=1`.

### T15g — graceful degrade when no ledger exists
Run `massoh ledger` in a temp repo with no `ledger.tsv`. Assert exit 0. Assert stdout contains
a degraded message (no crash, no empty output — a human-readable hint).

### T15h — `massoh ledger add` in a non-Massoh-project (no `.agent_tasks/`)
Run `massoh ledger add TASK-X scope 100 10` in a temp dir with no `.agent_tasks/` directory.
Assert the command either creates `.agent_tasks/ledger.tsv` (auto-create acceptable since
`.agent_tasks/` may not exist yet) or exits non-zero with an error. Document which behavior is
implemented. (Recommended: auto-create `.agent_tasks/` if absent, matching `cmd_on` behavior;
do not require `massoh on` to have been run first, since ledger add may be called by the
orchestrator in CI before the repo is fully initialized.)

### T15i — safety-critical files unchanged
After all T15 tests, assert `bin/massoh` checksum is unchanged (same as before the test run) and
`manifest.yml` checksum is unchanged.

### T15j — all existing tests remain green
Run the full `test/run.sh` suite. Assert 0 failures. (Non-regression.)

---

## 13. Kill / defer criteria

**Kill this scope if:**
- The owner decides token tracking is not needed before a second repo opts in (activation metric
  takes priority). Re-entry condition: owner explicitly re-queues.

**Defer `massoh ledger` if:**
- Wiring the orchestrator to actually call `massoh ledger add` proves harder than the verb itself —
  in that case, ship the verb anyway (it is independently useful), and the orchestrator wiring
  becomes a separate follow-up.

**Defer specific sub-features (not in scope for v1, explicit re-entry conditions):**
- Dollar-cost calculation → NEXT after token data accumulates and a stable price-per-token
  config is defined.
- `review`/`recommend` reading ledger data → NEXT after the ledger has at least one full cycle
  of data (one packet `00→06` instrumented).
- SubagentStop hook auto-capture → NEXT after the verb is proven stable and the format is
  confirmed.
- Per-task sub-ledger → LATER if cross-task query performance becomes an issue (it will not for
  hundreds of tasks in a TSV).
- Ledger pruning / archiving → LATER; append-only is the policy until the file becomes unwieldy.

---

## 14. Task-packet update

This file is the packet update for stage `01_product_scope`. The task packet
`.agent_tasks/TASK-2026-06-17-massoh-ledger/` continues with `03_architecture_safety.md` next.

No UX review is required (internal CLI tool, no user-facing UI, no copy to review).

---

## 15. AGENT_SYNC.md update

See the decision log row and active packet entry appended separately to `AGENT_SYNC.md`.
