# 03 — Architecture / Safety Review: auto-ledger via SubagentStop hook

**Task ID:** TASK-2026-06-19-auto-ledger
**Date:** 2026-06-19
**Agent:** massoh-architecture-safety
**Gate:** FEASIBILITY + SAFETY — must resolve before any implementation.

---

## 1. Feasibility Verdict (gates everything)

**Outcome: (C) — DEFER to owner with a precise re-entry condition.**

### Evidence and reasoning

The documented SubagentStop hook input payload (source:
`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/hook-development/SKILL.md`
lines 305–318, confirmed by
`~/.claude/plugins/marketplaces/thedotmack/docs/context/hooks-reference-2026-01-07.md`)
defines the following JSON passed to every hook via stdin:

Common fields (all events):
- `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`

SubagentStop-specific fields:
- `reason` (a stop reason string — the only event-specific field)

**Token usage is not present.** There are no fields for `input_tokens`, `output_tokens`,
`total_tokens`, `usage`, or any cost signal. This is confirmed by the absence of those terms
anywhere in the hook documentation corpus searched across `~/.claude/plugins/`.

**Duration is not present.** There is no `elapsed_ms`, `duration_seconds`, `start_time`, or
equivalent field in the SubagentStop payload. The hook fires at stop, not as a start-stop pair.
There is no documented `SubagentStart` event that would allow the hook to record a start
timestamp and compute elapsed wall-time by differencing. The only session-level start event is
`SessionStart`, which is per Claude Code session, not per subagent invocation.

**task-id and stage are not present.** The hook has no reliable, structured signal for which
Massoh task or workflow stage the subagent was executing. The `transcript_path` is the subagent's
conversation transcript, but extracting task-id/stage from unstructured transcript text is fragile,
brittle to prompt variation, and would require parsing heuristics — not a safe or maintainable
approach.

**Why not partial (B)?**
The request explicitly requires: "Do not invent token numbers." Outcome B is defined as "Only
partial (e.g. wall-time derivable, no tokens)." Wall-time is also not derivable because
SubagentStop carries no start timestamp and there is no SubagentStart event to pair it with.
A hook could record `date +%s` at SubagentStop as the stop time, but the start time is unknown.
Therefore even B is not achievable without fabrication. Outcome C is the honest verdict.

---

## 2. What the Hook Can Provide (for completeness)

The SubagentStop hook can reliably provide:
- `cwd` — the working directory at stop time (project root, usually)
- `transcript_path` — path to the subagent's conversation file
- `session_id` — the session identifier
- `reason` — the stop reason string
- Wall-clock stop timestamp (the hook can call `date +%s` itself)

It cannot provide:
- Token counts (input, output, or total) — not in payload
- Wall-clock start timestamp (no SubagentStart event; SessionStart is per-session not per-subagent)
- Elapsed duration (no start, so no diff is possible)
- Massoh task-id (not in payload; would require transcript parsing)
- Massoh stage (not in payload; would require transcript parsing)

---

## 3. Re-entry Condition (precise)

This item may re-enter as feasible IF any of the following becomes true:

**RE-ENTRY-A (preferred):** The Claude Code SubagentStop hook payload is extended to include
`token_usage` (input + output counts) and either `duration_ms` or a `start_time` / `end_time`
pair. Evidence: a documented schema change in the hooks reference or a confirmed changelog entry
showing this data is now present. This would unlock Outcome A.

**RE-ENTRY-B (reduced scope):** A `SubagentStart` event is added to Claude Code hooks,
allowing a hook script to record `date +%s` at start and compute elapsed at SubagentStop.
Combined with a reliable structured mechanism to pass task-id/stage into the hook (e.g., an
env var the orchestrator sets before spawning the subagent, readable by the hook), this would
unlock Outcome B (wall-time only, tokens placeholder or omitted).

**RE-ENTRY-C (alternative architecture):** The orchestrator agent (not a hook) is made
responsible for calling `massoh ledger add` explicitly at each stage boundary. This is the
current manual approach; making it a convention in the massoh-workflow role prompt (a simple
instruction at the end of each stage handoff) would achieve the goal without requiring hook
infrastructure. This is POSIX-safe, verifiable in tests, and avoids hook complexity entirely.
This option does not require a re-entry condition — the owner may authorize it immediately as
a PRODUCT_SCOPE task distinct from the SubagentStop hook approach.

---

## 4. Impact Assessment (for the record; implementation blocked)

**Backend/service impact:** N/A — hook is a shell command, no service.

**Client/app impact:** Would require adding a JSON block to `.claude/settings.json` (project
scope) or `~/.claude/settings.json` (global scope). Project scope is safer — blast radius is
one repo. Global scope would fire on every subagent stop in any Claude Code session for the
user, an unacceptable blast radius for a Massoh-specific action.

**API impact:** No API contract change.

**DB/migration impact:** Ledger is already append-only TSV. The hook would call
`massoh ledger add` which writes via cmd_ledger's single `printf >>` path. No schema change.

**LLM/prompt impact:** None. Hook is a shell command, not a prompt.

**Safety/guardrail risks (if this were feasible):**

- BLAST-RADIUS: If installed globally (`~/.claude/settings.json`), fires on every subagent stop
  across all repos, not just Massoh repos. Must be project-scoped to `.claude/settings.json`.
- LOOP-RISK: A hook that itself spawns a subagent or triggers Claude could create a loop.
  `massoh ledger add` is a pure shell command with no LLM calls, so loop risk is zero for that
  path. But the hook definition in settings.json must not call `claude` or any tool that
  re-enters the agent loop.
- NON-BLOCKING: Hook must exit 0 regardless; any failure silently degrades. `|| true` required
  throughout. A hook that exits 2 feeds stderr to Claude as a blocking error — unacceptable.
- IDEMPOTENCY: SubagentStop may fire more than once (e.g., retry scenarios). Without a
  start/stop timestamp pair we cannot detect duplicates. A file-based mutex keyed on `session_id`
  could mitigate but adds complexity.
- TASK-ID INJECTION: If task-id/stage were passed via env var set by the orchestrator, those
  vars must be sanitized through cmd_ledger's existing L1/L2 before the ledger write. This is
  already designed into cmd_ledger but the env-var injection path needs validation.
- NO SECRETS: Hook must not log session_id or transcript_path to ledger; only task telemetry.
- SETTINGS.JSON NOT SAFETY-CRITICAL: `settings.json` is not in NON_NEGOTIABLES.md's designated
  files list. However it is global infrastructure. If added to project `.claude/settings.json`,
  it is additive and reversible (remove the JSON block to disable). Owner batch-auth covers
  `bin/massoh`; `settings.json` edits need no additional sign-off per NON_NEGOTIABLES.

**Expansion/localization risks:** None — no hard-coded locale, region, or segment.

---

## 5. Required Tests (if re-entry is authorized)

These tests are defined now so they are ready at re-entry. They are NOT a license to implement.

| ID | Test | Assert |
|---|---|---|
| T-AL-a | Hook degrades when `massoh` binary absent | Hook script exits 0, no file created, no stderr to Claude |
| T-AL-b | Hook degrades when ledger verb returns non-zero | `|| true` swallows; SubagentStop not blocked |
| T-AL-c | Sanitized task-id: tab/newline/CR stripped | L1 in cmd_ledger fires; malformed row not written |
| T-AL-d | Sanitized stage: tab/newline/CR stripped | L1 in cmd_ledger fires; malformed row not written |
| T-AL-e | Token integer validation: non-integer rejected | L2 in cmd_ledger fires; no write |
| T-AL-f | Seconds integer validation: non-integer rejected | L2 in cmd_ledger fires; no write |
| T-AL-g | Opt-in default-off: fresh repo has no hook entry | Grep project `.claude/settings.json` for SubagentStop yields no match before `massoh hook-ledger on` |
| T-AL-h | Enable step: after enable, settings.json has hook entry | `massoh hook-ledger on` inserts SubagentStop block; idempotent on second run |
| T-AL-i | Disable step: after disable, hook entry removed | `massoh hook-ledger off` removes the block; no other settings.json content changed |
| T-AL-j | Non-blocking: hook exits 0 even when ledger missing | Simulate absent ledger directory; hook still exits 0 |
| T-AL-k | No double-count (if idempotency mechanism exists): second SubagentStop call for same session_id skips write | Ledger row count unchanged on second call |
| T-AL-l | Project-scope only: hook command must reference `$CLAUDE_PROJECT_DIR`, not `~/` or absolute path | Static analysis of hook command string in settings.json |
| T-AL-m | No secrets in ledger row: session_id and transcript_path absent from written TSV | `grep session_id .agent_tasks/ledger.tsv` returns empty |

Test target: existing suite + 13 new T-AL-* checks. Target total depends on suite count at
re-entry.

---

## 6. Rollback Plan (if re-entry is authorized)

1. Remove the SubagentStop block from `.claude/settings.json` (project scope only).
2. Existing ledger rows are append-only and remain valid; no migration needed.
3. The `massoh hook-ledger off` verb (if implemented) must be the documented removal path.
4. Revert the PR that added `hook-ledger` on/off to `lib/verbs/` and any `.claude/settings.json`
   changes.

---

## 7. Verdict

**DEFER to owner.**

The SubagentStop hook payload does not carry token usage or duration. Neither is derivable
from any documented hook event. Task-id and stage are also absent from the payload. Implementing
a hook against this surface would require fabricating token numbers (explicitly prohibited by the
00_request) or accepting zeros/placeholders for all three required fields, rendering the ledger
entry meaningless.

**What must change before this can proceed:**

Either RE-ENTRY-A or RE-ENTRY-B must be confirmed (hook payload extended by Claude Code), or
the owner may authorize RE-ENTRY-C (orchestrator-side explicit ledger calls, a different and
simpler approach that does not use SubagentStop at all).

**Single biggest risk (if forced through):** fabricated token numbers silently polluting the
ledger, making `massoh ledger` and `massoh meta` cost-outlier analysis misleading while appearing
authoritative. This is the exact "over-claim" pattern that NON_NEGOTIABLES.md and the Massoh
safety spine prohibit.

**This item is NOT approved for implementation.** Route to owner with this document and the
three re-entry conditions above.

---

## 8. Owner Action Required

Recommended owner response: choose one of the following.

1. **Wait for RE-ENTRY-A/B:** Monitor Claude Code changelog for hook payload extension. Re-route
   to arch-safety when confirmed.

2. **Authorize RE-ENTRY-C immediately:** Instruct the orchestrator (Massoh agent workflow) to
   call `massoh ledger add` explicitly at stage completion, passing task-id, stage name, token
   count (from the API response the orchestrator has access to), and elapsed seconds (computable
   from the orchestrator's own clock). This does not require a hook and is implementable today.
   The product-scope agent would need a PRODUCT_SCOPE task for this.

3. **Defer indefinitely:** Move item #5 from TODO to DEFERRED in AGENT_BACKLOG.md with a note
   "blocked on hook payload carrying token/duration — re-enter on RE-ENTRY-A/B/C."
