# 01 — Product Scope
**Task:** TASK-2026-06-17-massoh-learn · **Date:** 2026-06-17 · **Agent:** massoh-product-scope

---

## 1. Decision: BUILD

Owner authorized. The feature is read-only, additive, and zero-LLM. The hypothesis is testable with
fixtures. The minimal version is small — a single `cmd_learn` function in `bin/massoh` modeled on
`cmd_review` and `cmd_standup` — with proposals written to a scratch file and/or stdout, never
auto-mutating any safety-critical or knowledge file.

---

## 2. Target segment

Solo owner on a Massoh-enabled repo that has accumulated at least one completed task packet
(`06_review_result.md`). Justify "all" is N/A — the wedge is the single-owner + Claude Code
installation as defined in CHARTER.md. No hard-coding: the command works on any repo that has
`.agent_tasks/` and `AGENT_SYNC.md` (the standard scaffold).

---

## 3. Target region / locale

MVP: any locale. Pure bash text-mining over markdown — no locale-sensitive string comparison, no
date parsing beyond ISO strings already in the files. No locale surface introduced. Expansion note:
the patterns grep for English markdown headings (`## Blocking`, `## Non-blocking`, `Decision:`,
`REQUEST CHANGES`) that match the task-packet spec; a future multi-language project would need a
configurable pattern set (LATER, not now — flag any regex that hard-codes English vocabulary so it
can be made configurable later).

---

## 4. Why now / why not

**Why now:** The decision log in `AGENT_SYNC.md` and the review history in `.agent_tasks/` already
contain the raw material. The cadence layer (standup / review / plan / cron) is complete and merged
(TASK-2026-06-17-cadence-cron APPROVED). The system now produces enough audit trail to mine. The
owner explicitly requested this as the next thread, classifying it PRODUCT_SCOPE entry. Without
`learn`, knowledge mined from the audit trail stays trapped in completed packets and the decision
log — never promoted into STANDARDS or memory — which is the "knowledge drift" problem Massoh exists
to prevent.

**Why not later:** The value is proportional to the size of the history. Mining starts small (few
packets now) and improves over time. There is no better moment to establish the feedback loop than
when the ceremony layer is in place and the history is fresh.

**Strategic mode alignment:** The current mode is "validate that a portable, gated agent OS reduces
build-trap / knowledge-drift." `massoh learn` is the direct answer to the knowledge-drift half of
that claim. Confirmed aligned. No contradiction found in repo evidence.

---

## 5. Metric affected

**`packet_merged`** (activation/complete) — the command strengthens the value proposition of
completing a full packet: each merge now contributes to a mine-able history. No new metric event
required. When `massoh report` exists (LATER), `learn` execution count would be a natural secondary
metric; defer that instrumentation.

Secondary: `retention` — an owner who runs `learn` after a second repo's packets accumulate has a
strong reason to remain on Massoh. Not instrumented yet (acceptable per METRICS.md note).

---

## 6. Minimal version

A single `cmd_learn` function in `bin/massoh` (same file, same pattern as `cmd_review` /
`cmd_standup` / `cmd_plan`). Read-only. Heuristic text-mining via grep/awk over markdown — no
`claude -p`, no LLM call, zero cost.

**What it mines (v1 scope):**

1. `.agent_tasks/*/06_review_result.md` — extract lines from `## Blocking` and `## Non-blocking`
   sections, plus any `REQUEST CHANGES` decision lines. Count how many times a pattern recurs
   across packets. Recurring patterns (seen in 2+ reviews) become STANDARDS Do/Don't proposal
   candidates.

2. `AGENT_SYNC.md` decision log — extract rows from the `## Decision log` table. Flag any decision
   that uses the word "irreversible" or refers to a safety-critical file (bin/massoh, manifest.yml)
   as an ADR candidate.

3. `git log` — count reverts (`grep -ci revert`) and fixup commits (`grep -ci fixup`) in the
   project git history. Surface them as "repeated-fix indicators."

**Output (v1):**

- Always: a "lessons" report printed to stdout (same style as `massoh review` output).
- With `--write-proposals`: write proposed knowledge to
  `agent-project/LEARNINGS.proposed.md` (append, never overwrite; create-if-missing). This is the
  scratch file the owner reviews and promotes manually into STANDARDS.md, memory/, or docs/adr/.
  The command NEVER writes directly to those files.

**Flags:**
- `--since DAYS` (default: all time) — limit git log and packet scan to the last N days.
- `--write-proposals` (default: off) — append proposals to
  `agent-project/LEARNINGS.proposed.md`.
- `--no-write` — explicit no-op alias for the default; useful in tests (mirrors `cmd_review`
  and `cmd_standup` convention).

**Proposal format inside `LEARNINGS.proposed.md`** (structured so the owner can grep/promote):

```
## [learn] YYYY-MM-DDTHH:MM:SSZ (vX.Y.Z)
### Proposed STANDARDS.md Do/Don't
- Don't: <pattern> (seen in: TASK-A, TASK-B)
- Don't: <pattern> (seen in: TASK-C)
### Possible ADR candidates (from decision log)
- Decision: "<row text>" — consider formalizing (mentions irreversible / safety-critical file)
### Repeated-fix indicators (git)
- N revert commit(s) found — review for recurring root causes
- N fixup commit(s) found
```

All three sections are always emitted (even if empty — prints "(none)" like the other ceremonies).
The owner reads the file and manually copies whatever they agree with into the target location.

**Proposal targets (where the owner promotes):**

- STANDARDS.md `## Do / Don't` section — paste manually after review.
- `memory/` — owner creates a new memory file per `memory/SCHEMA.md` and adds it to
  `memory/MEMORY.md` index.
- `docs/adr/` — owner creates a new ADR file from the proposed text (directory created by the
  owner if absent; `learn` does not create directories outside `agent-project/`).

**Scope of v1 mining (explicit limits):**

- Only `06_review_result.md` and `05_implementation_handoff.md` (risks section) are scanned.
  `03_architecture_safety.md` risks are NOT scanned in v1 (added complexity; NEXT candidate).
- Pattern-matching is line-level (grep), not semantic. False positives are expected and acceptable
  — the owner filters them.
- No cross-packet similarity scoring. Simple occurrence count: how many packets mention a keyword
  in a blocking/non-blocking section.

---

## 7. Non-goals (explicit)

- Auto-writing into STANDARDS.md, memory/, or docs/adr/ — never, even with a flag. The owner
  always promotes. This is load-bearing: those files affect future agent behavior; auto-mutation
  without owner review violates the NON_NEGOTIABLES spirit (owner-gated safety-critical file
  mutations).
- LLM summarization, embedding, or semantic similarity — no `claude -p` in v1 (would introduce
  cost + testability loss).
- Scanning `03_architecture_safety.md` risks in v1.
- Deduplicating proposals across runs (LEARNINGS.proposed.md is append-only; the owner manually
  archives reviewed proposals).
- Cross-repo mining (each `massoh learn` runs in one repo).
- Versioning or archiving `LEARNINGS.proposed.md` (append-only is sufficient for v1; large file
  warning is a NEXT).

---

## 8. Required events (named)

No new instrumentation event. `packet_merged` is the upstream event that populates the mine-able
history. If `massoh report` is built later, add a `learn_run` count event at that time.

---

## 9. Safety / guardrail impact

**Guardrail A3 (keep older data):** `LEARNINGS.proposed.md` is append-only (never overwritten).
Proposals accumulate; the owner deletes or archives reviewed proposals manually. Satisfies A3.

**NON_NEGOTIABLES — prohibited overwrite:** `learn` must never write to `bin/massoh`,
`manifest.yml`, global-block markers, or `templates/`. It must never write directly to
`agent-project/STANDARDS.md`, `memory/`, or `docs/adr/` — only to
`agent-project/LEARNINGS.proposed.md` (the designated scratch file). Any path not
`agent-project/LEARNINGS.proposed.md` is out of scope for `--write-proposals`.

**Designated safety-critical files:** NOT touched. `bin/massoh` is edited (to add `cmd_learn` and
the dispatch case), which is a safety-critical file per NON_NEGOTIABLES.md — this requires owner
sign-off before implementation (as with prior tasks). The implementation packet must gate on that
sign-off. The architecture-safety agent must call this out.

**Read-only posture:** `cmd_learn` without `--write-proposals` is 100% read-only (stdout only).
With `--write-proposals` it writes only to `agent-project/LEARNINGS.proposed.md`. No other file
is touched in either mode.

**No LLM spend:** heuristic grep/awk only. Zero API cost. Testable with fake fixtures.

---

## 10. Expansion / localization impact

The command is locale-neutral. The only locale assumption is the markdown heading vocabulary
(`## Blocking`, `## Non-blocking`, `Decision:`, `REQUEST CHANGES`, `## Decision log`) — these
come from the task-packet spec and the AGENT_SYNC schema, which are English by convention.
Flag: do not hard-code these strings as constants buried in logic; extract them as named variables
or comment them with `# task-packet-spec` so a future multi-language project can override them.
No region or segment hard-coding. No timezone assumption introduced (timestamp via `date -u`
mirroring the other ceremonies).

**Expansion note (per CHARTER.md):** `LEARNINGS.proposed.md` as the scratch destination is a
single-repo convention. A future "cross-repo knowledge sync" feature would need a different
aggregation layer — do not architect v1 to support that (LATER).

---

## 11. Acceptance criteria (testable, zero LLM spend, fixture-based)

All tests added to `test/run.sh` as a new `T11` block, using the existing `mkcronrepo` / temp-dir
fixture pattern. No real `~/.claude` touched. Fixtures are fake packets with controlled content.

### T11a — stdout report emitted; no files written (default mode)
Create a temp repo with two fake `06_review_result.md` files each containing a `## Blocking`
section with the same keyword. Run `massoh learn`. Assert stdout contains "Blocking findings" (or
the report header). Assert `agent-project/LEARNINGS.proposed.md` does NOT exist (default no-write).

### T11b — `--no-write` behaves identically to default (no proposals file created)
Run `massoh learn --no-write`. Assert `agent-project/LEARNINGS.proposed.md` does NOT exist.
Assert stdout report is still emitted. (Mirrors `cmd_review --no-write` pattern.)

### T11c — `--write-proposals` creates `LEARNINGS.proposed.md` with expected sections
Run `massoh learn --write-proposals`. Assert `agent-project/LEARNINGS.proposed.md` exists. Assert
it contains `## [learn]`, `### Proposed STANDARDS.md Do/Don't`, `### Possible ADR candidates`,
`### Repeated-fix indicators`. Assert it is append-only (run twice → two `## [learn]` blocks, no
overwrite).

### T11d — recurring pattern surfaces in proposals
Create two fake `06_review_result.md` with identical blocking text "A&&B||C anti-pattern". Run
`massoh learn --write-proposals`. Assert `LEARNINGS.proposed.md` contains "A&&B||C" and references
both task names (or a count of 2+).

### T11e — decision log ADR candidate extracted
Create a fake `AGENT_SYNC.md` with a decision log row containing the word "irreversible". Run
`massoh learn --write-proposals`. Assert `LEARNINGS.proposed.md` contains "ADR candidates" section
with a non-empty entry referencing the irreversible row.

### T11f — git revert count appears in report
Create a temp git repo, commit once, then `git revert HEAD`. Run `massoh learn`. Assert stdout
contains "revert" with a count of 1.

### T11g — `--since DAYS` limits packet scan
Create two fake packets: one dated today and one with an old date (simulated via filename). Run
`massoh learn --since 1`. Assert only the recent packet's findings appear. (If date-filtering is
implemented via file mtime, set mtime on old packet to >2 days ago via `touch -t`.)

### T11h — graceful degrade: no `.agent_tasks/` directory
Run `massoh learn` in a Massoh project with no `.agent_tasks/` or no completed packets. Assert exit
0, stdout contains report with "(none)" sections, no crash.

### T11i — `LEARNINGS.proposed.md` never touches safety-critical paths
After `massoh learn --write-proposals`, assert `bin/massoh` checksum unchanged (md5 snapshot),
`manifest.yml` unchanged, `agent-project/STANDARDS.md` unchanged (if it exists).

### T11j — `massoh learn` fails if not in a Massoh project (no `.massoh` and no `agent-project/`)
Assert non-zero exit and error message to stderr. (Mirrors `cmd_discover` pattern.)

---

## 12. Kill / defer criteria

**Kill this scope if:**
- The owner decides proposals should always go to stdout only (no file output) — simplify; remove
  `--write-proposals` and `LEARNINGS.proposed.md`.
- The owner decides `learn` should be an LLM-powered pass — re-scope entirely; the current
  heuristic version has no value in that world.

**Defer `massoh learn` if:**
- Fewer than 2 completed task packets exist in the repo (not enough signal to mine — `learn`
  should warn and exit 0 gracefully, not crash, but the output will be trivial).

**Defer specific sub-features:**
- `03_architecture_safety.md` risk scanning → NEXT after v1 ships.
- Cross-repo aggregation → LATER.
- ADR file auto-creation (even as proposals) → the owner creates `docs/adr/` manually; `learn`
  only proposes text, never creates new ADR files.

---

## 13. Task-packet update

This file is the packet update for stage `01_product_scope`.

---

## 14. AGENT_SYNC.md update

Append the following decision row to the Decision log:

```
| 2026-06-17 | TASK-2026-06-17-massoh-learn: product-scope BUILD — read-only heuristic miner; proposals to LEARNINGS.proposed.md; flags: --since/--write-proposals/--no-write; routes to architecture-safety | product-scope |
```

Add to Active task packets:

```
| TASK-2026-06-17-massoh-learn | 01_product_scope | IN FLIGHT — product scope done, routes to architecture-safety |
```

Update Last handoff:

```
Agent: massoh-product-scope
Mode: scope
Task: TASK-2026-06-17-massoh-learn — massoh learn command (heuristic mining loop)
Status: BUILD. 01_product_scope.md written.
Next recommended agent: massoh-architecture-safety
Next action: write 03_architecture_safety.md; review the bin/massoh edit (safety-critical file
  sign-off needed from owner before implementation); confirm write path to LEARNINGS.proposed.md
  is the only non-stdout output; confirm zero LLM spend constraint holds; specify T11 test details.
```
