# 04 — Implementation Packet
**Task:** TASK-2026-06-17-massoh-meta · **Agent:** massoh-implementer · **Date:** 2026-06-17

---

## License

Both slices are APPROVED for implementation per `03_architecture_safety.md` (dated 2026-06-17).

Owner sign-off on record: `00_request.md` — "Owner authorized build + `bin/massoh*` + a new agent
file (flagship selection)."

Architecture-safety confirmed sign-off covers:
- Slice 1: `cmd_meta` added to `bin/massoh`
- Slice 2: `claude/agents/massoh-meta-engineer.md` + additive doc updates

---

## Scope: Both slices, one PR on `feat/massoh-meta`

### Slice 1 — `cmd_meta` in `bin/massoh`

Add a read-only heuristic miner `cmd_meta` to `bin/massoh`. Zero LLM spend. Four findings:

1. **Ledger cost analysis** — per-stage token outlier detection (`OUTLIER_FACTOR=2` × mean).
2. **Rework rate** — count `06_review_result.md` files with `Decision.*REQUEST CHANGES`.
3. **Backlog drift** — AGENT_BACKLOG TODO items whose keyword appears DONE in AGENT_SYNC.md.
4. **Repeated review findings** — finding class seen in >= `REPEAT_THRESHOLD=3` blocking sections.

Flags: `--write-proposals` (default OFF). Writes ONLY to `$META_PROPOSALS` (`>>` append) with
`# SAFETY:` comment when `--write-proposals` is set. Write block begins with `## [meta] <ts>`.

### Slice 2 — `massoh-meta-engineer.md` + doc updates

- `claude/agents/massoh-meta-engineer.md` — PROPOSE-ONLY role agent (auto-installs via glob).
- `policies/02_AGENT_ROLES.md` — 6 rows → 7 (add massoh-meta-engineer).
- `OPERATING_SYSTEM.md` — §3 or §4 updated to reference meta role.
- `README.md` — role table updated to 7 roles.
- `VERSION` — 0.7.0 → 0.8.0.
- `CHANGELOG.md` — [0.8.0] entry added.

---

## Acceptance criteria (all must pass)

### Slice 1 mandatory conditions

**M1 (BLOCKING) — Write isolation.**
Only write is `>> "$META_PROPOSALS"` inside `if [ "$write_meta" = 1 ]`. Named var with
`# SAFETY:` comment. No other write in `cmd_meta`. Pattern: `cmd_learn` line 531.

**M2 (BLOCKING) — grep/awk `|| true` on every invocation.**
Every `grep`, `awk`, `git`, `wc`, `find` in `cmd_meta` terminates with `|| true`. No exceptions.

**M3 — Degrade gracefully on absent inputs.**
- No `ledger.tsv` → print `(no ledger data)`, exit 0, no file created.
- No packets → print `(no packet data)`, exit 0.
- No `AGENT_BACKLOG.md` → print `(no backlog file)`, exit 0.

**M4 — `--write-proposals` default OFF.**
`local write_meta=0` at start. Only `--write-proposals` sets to 1. Unknown flags → die with usage.

**M5 — No internal calls to cmd_learn / cmd_recommend / cmd_ledger.**
Reads raw files directly.

**M6 — massoh-meta-engineer.md NOT designated safety-critical.**
Do NOT add to `NON_NEGOTIABLES.md`.

**M7 — Named heuristic constants.**
`local OUTLIER_FACTOR=2` and `local REPEAT_THRESHOLD=3` as named locals.

**M8 — `[meta]` label prefix in write block.**
Appended block begins with `## [meta] <timestamp>`.

**M9 — Verb registration + usage string.**
`meta)` arm added after `ledger)`. Usage string in `die()` includes `meta`. VERSION → 0.8.0.

**M10 — No double-counting with cmd_review's rework_pct.**
Reads raw `06_review_result.md` files directly, NOT `METRICS.md`.

### Slice 2 mandatory conditions

**M11 — Agent prompt is PROPOSE-ONLY.**
Explicit statements: proposes only; never auto-merges; never edits safety files; routes through gate.

**M12 — Manifest glob covers the new file without manifest.yml change.**
Do NOT modify `manifest.yml`.

**M13 — Doctor auto-adapts to 7 agents.**
No `cmd_doctor` change needed. Adding `massoh-meta-engineer.md` to `claude/agents/` is sufficient.

**M14 — Doc edits are additive only.**
No guardrail rules, block markers, or install procedures modified.

---

## Tests (T-meta-A through T-meta-M)

### Slice 1

| ID | Pass condition |
|---|---|
| T-meta-A | stdout contains "implementer" and "outlier" with 10x outlier fixture |
| T-meta-B | stdout reports rework rate >= 60% (3 of 5 packets with REQUEST CHANGES) |
| T-meta-C | stdout mentions "foo-feature" in drift finding |
| T-meta-D | stdout surfaces "shellcheck" as repeated finding (exactly 3 qualifying packets) |
| T-meta-E | exit 0; stdout contains "(no ledger data)"; no file created |
| T-meta-F | exit 0; all 4 finding sections degrade with "(no X data)" messages |
| T-meta-G | META.proposed.md NOT created or modified (find-based snapshot, NOT `md5sum '$var'`) |
| T-meta-H | META.proposed.md created with `## [meta]` header; second run appends (line count increases) |
| T-meta-I | `massoh meta` dispatched from main case; returns expected exit code |
| T-meta-J | non-zero exit + "not a Massoh project" message outside a Massoh project |

### Slice 2

| ID | Pass condition |
|---|---|
| T-meta-K | massoh install wires massoh-meta-engineer.md; massoh doctor exits 0 with 7 "ok agent" lines |
| T-meta-L | `policies/02_AGENT_ROLES.md` has exactly 7 data rows |
| T-meta-M | `OPERATING_SYSTEM.md` references "meta" or "massoh-meta-engineer" in §3 or §4 |

---

## Files likely touched

- `bin/massoh` — add `cmd_meta`, add `meta)` dispatch, update usage string
- `claude/agents/massoh-meta-engineer.md` — new file
- `policies/02_AGENT_ROLES.md` — add 7th row
- `OPERATING_SYSTEM.md` — update §3 workflow + §4 routing
- `README.md` — update role table
- `VERSION` — 0.7.0 → 0.8.0
- `CHANGELOG.md` — [0.8.0] entry
- `test/run.sh` — add T-meta-A through T-meta-M

---

## Safety / guardrail impact

- `bin/massoh` is safety-critical. Owner sign-off on record.
- Changes are strictly additive: new function + new case arm + usage string update.
- No existing function modified.
- `META_PROPOSALS` var + `# SAFETY:` comment mirrors `cmd_learn` pattern.
- `manifest.yml` must NOT be modified.
- `NON_NEGOTIABLES.md` must NOT be modified.

---

## Branch

`feat/massoh-meta` (already set by operator).
