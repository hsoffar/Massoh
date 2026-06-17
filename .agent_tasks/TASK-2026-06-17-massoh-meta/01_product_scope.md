# 01 — Product Scope
**Task:** TASK-2026-06-17-massoh-meta · **Agent:** massoh-product-scope · **Date:** 2026-06-17

---

## 1. Decision: BUILD

Owner authorized. Flagship item #1 in AGENT_BACKLOG.md (DOING). Directly serves the north-star
differentiator: governance + self-measurement + autonomy coupled. The ledger is now live (v0.7.0);
`cmd_learn` and `cmd_recommend` are proven read-only miners. `massoh meta` is the natural next
capability in the measurement→diagnose→learn→improve loop. No frozen items in scope. No Defer
trigger applies.

---

## 2. Target segment

Solo owner + Claude Code (current wedge). The output of `massoh meta` is engine-internal — it reads
Massoh's own operational data and proposes changes to Massoh's own engine. This makes it
wedge-correct by definition (the only user is the system itself and its owner). Expansion note: the
heuristic mining patterns (cost per stage, rework rate, repeated findings) are locale-neutral and
task-type-neutral. No wedge hard-coding introduced.

---

## 3. Target region/locale

MVP: English text output, numeric extraction locale-neutral (awk with `-F'\t'`, no locale-sensitive
collation). Expansion ready: same note as `cmd_learn` and `cmd_recommend` — rule text is English;
numeric logic is portable. No hard locale constraint introduced.

---

## 4. Why now / why not

Why now:
- The ledger (v0.7.0) gives `massoh meta` its primary data source. Without ledger, this was
  impossible. Now it is actionable.
- Seed findings from this session are already concrete: ~285k tokens/task via full 4-agent gate
  (over-process signal), 3 rework cycles (rev2s) catching the same `cmd||true`/one-line-`local`
  bash anti-pattern — a class of bug that shellcheck would have caught at lint time. These are
  exactly the recurring findings `massoh meta` is designed to surface and encode as enforced checks.
- `massoh-meta` is DOING in the backlog. The ledger unblocked it. Building now closes the loop.

Why not later:
- Deferring leaves the seed findings as tribal knowledge in packet files rather than surfaced and
  promoted into the engine. Every task that runs between now and promotion risks re-triggering the
  same rework cycle.

---

## 5. Metric affected

Named event from METRICS.md: `packet_merged` (each massoh-meta upgrade ships as a PR → packet
`00→06` → merge, incrementing the activation/retention signal for the dogfood instance).

Secondary (learning metric, not yet in METRICS.md but flagged for addition): `rework_rate` —
the fraction of packets that required a REQUEST-CHANGES round before APPROVE. Meta's job is to
drive this toward zero by promoting recurring findings into enforced checks. Recommend the owner
add `rework_rate` and `mean_stage_tokens` as tracked metrics in METRICS.md.

---

## 6. Minimal version (two cohesive slices, one PR)

### Slice 1 — `massoh meta` CLI verb (read-only report + optional write)

Scope: add `cmd_meta` to `bin/massoh`. Read-only by default. Sources:

1. **Ledger cost analysis** — read `.agent_tasks/ledger.tsv`; compute per-stage mean tokens;
   surface stages where a task's token count exceeds 2x the cross-task stage mean (the "outlier
   threshold"). Report ranked findings: "stage X costs Nk tokens vs Mk mean."

2. **Rework rate** — count packets where `06_review_result.md` contains a `Decision.*REQUEST
   CHANGES` line before the final APPROVE. Report: total packets, rework count, rework rate %.
   Flag if rework rate > 25%.

3. **Backlog drift** — cross-reference AGENT_BACKLOG.md TODO items against AGENT_SYNC.md decision
   log + active packets: surface items marked TODO whose description matches a decision-log entry
   flagging it as shipped (heuristic: `massoh.*APPROVE` or `DONE` in the log for that item's
   keyword). Report drifted items by name.

4. **Repeated review findings** — mine all `06_review_result.md` Blocking sections (same pattern
   as `cmd_learn`); count finding classes (keyword seen in 2+ blocking sections); surface any class
   seen in 3+ packets as a "promote to enforced check" candidate.

Output: ranked bottleneck findings list, printed to stdout. Degrades gracefully: no ledger → print
"(no ledger data)" for finding #1; no packets → "(no packet data)" for findings #2/#4; no backlog
→ "(no backlog file)" for finding #3. Exit 0 in all degrade cases.

`--write-proposals` flag: appends ranked findings + suggested backlog items to
`agent-project/META.proposed.md` (append-only, `>>`, never overwrites). This is the ONLY write
path in `cmd_meta`. NEVER writes to STANDARDS.md, memory/, docs/adr/, AGENT_BACKLOG.md, or
AGENT_SYNC.md directly.

Verb registration: add `meta` to the `case` dispatch in `bin/massoh` (after `ledger`). Update
the `die` usage string.

### Slice 2 — `massoh-meta-engineer` role agent + doc updates

Scope: one new file `claude/agents/massoh-meta-engineer.md`. Auto-installs via `massoh install`
(picked up by the `massoh-*.md` glob in `cmd_install` and in `manifest.yml`). No manifest.yml
change required — the existing `kind: glob` entry covers it.

The agent is a process/efficiency engineer prompt. Its workflow:

1. Reads `massoh meta` output (or runs it) + the ledger + recent packets.
2. For each bottleneck finding: files a concrete AGENT_BACKLOG.md item (append-only, labeled
   `[meta]`) **or** proposes an ENFORCED check in `agent-project/META.proposed.md`.
3. "Promote to enforced check" path: if a finding class appears in 3+ blocking reviews, the agent
   writes a proposal to META.proposed.md (e.g., "Add shellcheck to the gate pre-implementation so
   bash anti-patterns are caught at lint time, not review time"). The proposal goes to the owner/
   gate for promotion into STANDARDS.md or a CI check — the agent does NOT edit STANDARDS.md itself.
4. Routes the resulting engine-upgrade backlog items through the normal gate (product-scope →
   arch/safety → implementer → reviewer).

The agent prompt explicitly states: PROPOSES only; never auto-merges engine changes; never edits
STANDARDS.md, memory/, docs/adr/, or bin/massoh directly; routes all proposals through the gate.

Doc updates (also in Slice 2):
- `policies/02_AGENT_ROLES.md`: add row for `massoh-meta-engineer` → "6 roles" table becomes 7.
- `OPERATING_SYSTEM.md`: update §3 workflow diagram + §4 routing note to mention the meta role.
- `README.md` (if it exists and has a roles table): update to 7 roles.

No manifest.yml change for the agent glob (already covered). No manifest.yml schema change.

---

## 7. Non-goals (explicit)

- No LLM spend. Zero `claude -p` calls in `cmd_meta`. Pure heuristic bash + awk.
- No auto-merge of engine changes. Meta proposes; the gate + owner ship.
- No direct writes to STANDARDS.md, memory/, docs/adr/, AGENT_BACKLOG.md (only via proposals).
- No `massoh-intake` scope here. Intake (idea-queue auto-triage, [[massoh-idea-intake]]) is
  backlog item #2 and shares the backlog-automation seam. Overlap: both will write to
  AGENT_BACKLOG.md via proposals. Resolution: meta's proposals are labeled `[meta]`; intake's are
  labeled `[intake]`. Mutually exclusive write targets for now (both use META.proposed.md as the
  intermediate). Flag for architecture-safety: confirm the two proposals files don't collide.
- No new subcommands beyond `meta`. The `massoh meta --write-proposals` flag is the full surface.
- No new scaffold files added to `massoh on` / `project_scaffold` in manifest.yml.
- No instrumentation wiring (telemetry). Events counted by hand from git + packets per METRICS.md.

---

## 8. Required events (named)

- `packet_merged` — already in METRICS.md. Each engine-upgrade item that meta surfaces and the gate
  ships will register as a packet_merged event.
- `rework_rate` — not yet in METRICS.md. Meta surfaces it; recommend owner add it. Named event:
  `rework_pct_per_window` (mirrors the `review-v2` KPI name from efficiency-v2 task).
- `meta_bottleneck_surfaced` — a new named event: `massoh meta` run that produced at least one
  ranked finding. Not yet in METRICS.md; recommend owner add it to track whether the diagnostic
  loop is being used.

---

## 9. Safety/guardrail impact

bin/massoh is a designated safety-critical file per NON_NEGOTIABLES.md. Owner sign-off is required
before the implementer touches it. Record: 00_request.md §"Owner authorized build + bin/massoh*
+ a new agent file (flagship selection)" — this is the authorization of record for Slice 1
(cmd_meta in bin/massoh) and Slice 2 (massoh-meta-engineer.md). Architecture-safety must confirm
this sign-off is sufficient or request explicit re-confirmation before issuing the license.

Additional guardrail checks for architecture-safety:
- M1: `cmd_meta` write path is ONLY `>>` append to `META.proposed.md`. No other file write.
  Verify: named `META_PROPOSED` var + SAFETY comment (mirrors L4/cmd_ledger pattern).
- M2: All grep/awk invocations in `cmd_meta` terminate with `|| true` (mirrors L7/cmd_learn).
- M3: Ledger-absent degrade: if `.agent_tasks/ledger.tsv` missing, print message + exit 0 (no
  file created).
- M4: `--write-proposals` flag: default OFF (write_meta=0); only `--write-proposals` sets to 1.
- M5: `cmd_meta` must NOT call `cmd_learn`, `cmd_recommend`, or `cmd_ledger` internally — it is
  a standalone miner that reads raw files directly. (Avoids hidden coupling + double-counting.)
- M6: The new agent file `massoh-meta-engineer.md` is NOT in the safety-critical list in
  NON_NEGOTIABLES.md. It is a role-prompt file, not an installer. Architecture-safety should
  confirm no new safety-critical designation is needed.
- M7: The outlier threshold (2x mean) is a heuristic constant. It must be defined as a named
  variable (e.g., `OUTLIER_FACTOR=2`) to make it auditable and patchable without a re-read.

---

## 10. Expansion/localization impact

No expansion or localization impact. Numeric logic is locale-neutral (awk tab-delimited, integer
arithmetic only). Text output is English; the pattern is identical to `cmd_learn`/`cmd_recommend`.
No wedge hard-coding. The agent prompt for `massoh-meta-engineer` should not reference any specific
product domain — it operates on Massoh's own operational files, which are domain-neutral.

---

## 11. Acceptance criteria (testable)

### Slice 1 — `massoh meta` verb

T-meta-A: Given a `ledger.tsv` with 3 rows for the same task (`product-scope`, `arch-safety`,
`implementer`) where `implementer` has tokens = 10x the mean of the other two, `massoh meta`
stdout contains "implementer" and "outlier" (or equivalent ranking word).

T-meta-B: Given packets where 3 of 5 `06_review_result.md` files contain `Decision.*REQUEST
CHANGES`, `massoh meta` stdout reports rework rate >= 60%.

T-meta-C: Given `AGENT_BACKLOG.md` with item "foo-feature" status TODO and `AGENT_SYNC.md`
decision log with "foo-feature: DONE", `massoh meta` stdout mentions "foo-feature" in a drift
finding.

T-meta-D: Given `06_review_result.md` files in 3+ packets each containing "shellcheck" in a
Blocking section, `massoh meta` stdout surfaces "shellcheck" as a repeated finding candidate.

T-meta-E (degrade — no ledger): run `massoh meta` in a repo where `.agent_tasks/ledger.tsv` is
absent. Exit code = 0. Stdout contains "(no ledger data)" (or equivalent). No file created.

T-meta-F (degrade — empty repo): run `massoh meta` in a repo with `.massoh` but no `.agent_tasks/`
subdirectory contents. Exit code = 0. All four finding sections degrade gracefully.

T-meta-G (write flag off by default): run `massoh meta` without `--write-proposals`. Verify
`agent-project/META.proposed.md` is NOT created or modified (checksum before == checksum after;
use `find`-based approach as in T13g/T14g patterns).

T-meta-H (write flag on): run `massoh meta --write-proposals`. Verify `META.proposed.md` exists
and contains a `## [meta]` header with timestamp. Run again; verify it APPENDED (line count
increased, original content intact).

T-meta-I: `massoh meta` is dispatched correctly from the main `case` in `bin/massoh` — run
`massoh meta --help` (or any unknown flag) and get a non-zero exit with usage hint (or the degrade
path if no `--help` is implemented).

T-meta-J (non-Massoh-project guard): run `massoh meta` outside a Massoh project (no `.massoh`,
no `agent-project/`). Exit non-zero with "not a Massoh project" message. No file created.

### Slice 2 — agent file + doc updates

T-meta-K: `massoh install` run in a test env wires `massoh-meta-engineer.md` to
`~/.claude/agents/`. Verify via `massoh status` (or direct file check) that the file is present
post-install.

T-meta-L: `policies/02_AGENT_ROLES.md` contains exactly 7 rows in the roles table (was 6).

T-meta-M: `OPERATING_SYSTEM.md` references "meta" or "massoh-meta-engineer" in the workflow
section (§3 or §4).

---

## 12. Kill/defer criteria

Kill Slice 1 if: `cmd_meta` requires LLM spend (zero-LLM is a hard constraint per 00_request.md).
Kill Slice 1 if: the only write path is not strictly `>> META.proposed.md` (safety regression).
Defer Slice 2 (agent file) if: the arch/safety agent flags a collision with `massoh-intake` on the
`META.proposed.md` write path that cannot be resolved with simple label namespacing.
Defer both slices if: owner rescinds the `bin/massoh` sign-off on record in 00_request.md.

Re-entry condition for any defer: owner explicit unfreeze + new sign-off entry in AGENT_SYNC.md.

---

## 13. Recommended build order (one PR)

1. Slice 1 first (cmd_meta in bin/massoh + tests T-meta-A through T-meta-J).
2. Slice 2 second (agent file + doc updates, tests T-meta-K through T-meta-M).
3. One PR on branch `feat/massoh-meta`. VERSION bump (likely 0.8.0).

Rationale: Slice 2 (agent file) reads the `massoh meta` output — it must be implemented after
Slice 1 exists and is testable.

---

## 14. Routing

BUILD decision → route to `massoh-architecture-safety` (bin/massoh is safety-critical; new agent
file touches the global install path via manifest glob; mandatory conditions M1–M7 above).
No UX pass needed (no user-facing UI; CLI output only, consistent with existing `learn`/`recommend`
style).

Safety-critical sign-off on record: 00_request.md "Owner authorized build + bin/massoh* + a new
agent file (flagship selection)" is the authorization of record. Architecture-safety to confirm
scope of that sign-off covers both slices.

---

## 15. `massoh-intake` overlap note (flag for architecture-safety)

`massoh-intake` (backlog item #2) will also write to `AGENT_BACKLOG.md` (its core function is
auto-queuing ideas). `massoh-meta` proposes to `META.proposed.md` only and never writes to
`AGENT_BACKLOG.md` directly. The seam is: meta surfaces findings → owner/gate promotes them into
AGENT_BACKLOG.md. Intake auto-queues new ideas → AGENT_BACKLOG.md. These are different write
targets today. Architecture-safety should confirm the separation holds and note any future
collision risk (e.g., if meta is later upgraded to auto-file backlog items directly).
