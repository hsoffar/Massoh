# 03 — Architecture / Safety Review
**Task:** TASK-2026-06-17-massoh-meta · **Agent:** massoh-architecture-safety · **Date:** 2026-06-17

---

## Owner sign-off verification

`00_request.md` records: "Owner authorized build + `bin/massoh*` + a new agent file (flagship
selection)." `bin/massoh` is listed as a designated safety-critical file in
`agent-project/NON_NEGOTIABLES.md`. The sign-off covers:

- Slice 1: `cmd_meta` added to `bin/massoh` — COVERED.
- Slice 2: `claude/agents/massoh-meta-engineer.md` (a new agent file) — COVERED.
- Slice 2: additive doc edits to `policies/02_AGENT_ROLES.md`, `OPERATING_SYSTEM.md`,
  `README.md` — COVERED (these are descriptive role-count updates, not guardrail changes; they
  do not alter an enforcement rule, a block marker, or the install contract).

Sign-off is on record and is sufficient for both slices. No re-confirmation required.

---

## 1. Backend / service impact

No server. Pure bash, POSIX-compatible, zero runtime services. `cmd_meta` follows the same
pattern as `cmd_learn` and `cmd_ledger`: inline function in `bin/massoh`, invoked by the existing
`case` dispatcher. No new runtime dependencies introduced.

---

## 2. Client / app impact

CLI only. `massoh meta` adds one new verb. Existing verbs are unaffected. No install-time
scaffold change (`massoh on` / `project_scaffold` are out of scope per 01 §7 Non-goals). Users
who do not run `massoh meta` see no change in behavior.

---

## 3. API impact — no contract change

The `bin/massoh` ↔ `manifest.yml` API contract seam (CHARTER.md §3) is not broken:

- `manifest.yml` does NOT change. The agent glob `massoh-*.md` already covers
  `massoh-meta-engineer.md`. The `kind: glob` entry in `manifest.yml` auto-picks up any new
  `massoh-*.md` file placed in `claude/agents/`. No manifest.yml schema change is needed or
  permitted.
- The dispatch `case` in `bin/massoh` gains one new arm (`meta`) and the usage string in `die()`
  gains one token. These are purely additive; no existing case arm is modified.
- Both sides of the `manifest.yml ↔ bin/massoh` contract are unaffected; no "both sides together"
  synchronization is required.

---

## 4. DB / migration impact

No database. `ledger.tsv` is the only data source read by `cmd_meta`; it is append-only and was
already created by `cmd_ledger`. `cmd_meta` reads it but NEVER writes it. `META.proposed.md` is
a new file created on demand (`--write-proposals` only, append-`>>`). No migration needed; no
backward-compatibility risk; no existing file is modified.

---

## 5. LLM / prompt impact

Zero LLM spend. `cmd_meta` is a pure heuristic bash/awk miner; no `claude -p` call is permitted.
This matches `cmd_learn` and `cmd_recommend`. The new role agent file
(`massoh-meta-engineer.md`) is a markdown prompt consumed by Claude Code only when the user
explicitly invokes it; it introduces no automated LLM spend and has no connection to any prompt
safety rule or calibration surface.

---

## 6. Safety / guardrail risks

### S1 — Write isolation (CRITICAL — must verify at review time)

`cmd_meta`'s ONLY write path must be `>>` append to a file bound to a single named variable
(`META_PROPOSED` or equivalent) with a `# SAFETY:` comment, and this write must be gated on
`write_meta=1` (default 0, set only by `--write-proposals`). The implementer must NOT introduce
any `>` overwrite, any second write target, or any write to: `ledger.tsv`, `AGENT_BACKLOG.md`,
`AGENT_SYNC.md`, `STANDARDS.md`, `memory/`, `docs/adr/`, `LEARNINGS.proposed.md`, or
`manifest.yml`.

The `# SAFETY:` comment pattern is established in `cmd_learn` (line 531), `cmd_recommend`
(line 692), and `cmd_ledger` (line 702). `cmd_meta` must follow the same pattern.

### S2 — grep/awk `|| true` guard (CRITICAL — recurring bug class caught 3x)

Every grep, awk, and git invocation in `cmd_meta` must terminate with `|| true`. Under
`set -euo pipefail`, any zero-match grep or awk that exits non-zero would abort the entire
function. This class of bug has appeared in 3 prior review cycles (cadence-cron rev2,
efficiency-v2 rev2, ledger). The implementer must add `|| true` even to invocations that
"obviously" have matches — the degrade path (empty ledger, no packets) is the primary failure
scenario.

### S3 — awk division-by-zero guard (CRITICAL)

The outlier computation (stage token vs. cross-task-stage mean) divides by the mean. If a stage
appears in only one row, the mean equals that row's value; the division is safe but still must be
guarded. The implementer must add a `cnt > 0` / `mean > 0` check before every division in
awk, matching the established pattern from `cmd_ledger` lines 766–777.

### S4 — Non-Massoh-project guard

`cmd_meta` must check `[ -e "$repo/.massoh" ] || [ -d "$repo/agent-project" ]` before any work
(same guard as `cmd_learn` / `cmd_discover`). Running outside a Massoh project must exit non-zero
with an informative message and create no files.

### S5 — massoh-meta-engineer.md safety designation

The new agent file `claude/agents/massoh-meta-engineer.md` is NOT a designated safety-critical
file under `NON_NEGOTIABLES.md`. It is a role-prompt markdown file, not an installer, not a block
marker, not a manifest, not a template. No new safety-critical designation is needed.

However, the agent prompt must explicitly state:

- PROPOSES only; never auto-merges engine changes.
- Never directly edits `STANDARDS.md`, `memory/`, `docs/adr/`, `bin/massoh`, or any safety file.
- All proposals route through the gate (product-scope → arch/safety → implementer → reviewer).
- The agent's only write targets are `agent-project/META.proposed.md` (via proposal appends)
  and `AGENT_BACKLOG.md` (via append-only labeled `[meta]` items when the owner/gate has
  promoted a finding).

These constraints must be explicit in the prompt body, not just implied.

### S6 — `massoh-intake` / `massoh-meta` write-path separation (RESOLVED)

The product-scope packet (01 §15) flagged potential collision between `massoh-intake` and
`massoh-meta` on `META.proposed.md`. The resolution is confirmed adequate:

- `cmd_meta` writes proposals labeled `## [meta] <timestamp>` to `agent-project/META.proposed.md`.
- `massoh-intake` (backlog item #2, not yet built) will write proposals labeled `## [intake] <timestamp>` to the same file (or its own file — that is for intake's arch/safety review to decide).
- The `[meta]` and `[intake]` labels are mutually exclusive namespaces within the file.
- `massoh-meta` NEVER writes to `AGENT_BACKLOG.md` directly; intake WILL write to
  `AGENT_BACKLOG.md` directly (its core function). These are different write targets today.
- Future risk: if meta is later upgraded to auto-file backlog items directly, the arch/safety
  review for that upgrade must mandate a `[meta]` label prefix on those rows too. Record this
  as a forward constraint in the task packet.

The `[meta]` / `[intake]` label namespacing is sufficient for this slice. No collision for Slice 2.

### S7 — No cmd_learn / cmd_recommend / cmd_ledger internal calls

`cmd_meta` must be a standalone miner that reads raw files directly. It must NOT call `cmd_learn`,
`cmd_recommend`, or `cmd_ledger` as internal functions. This prevents hidden coupling and
double-counting. The implementer must replicate the needed pattern (grep patterns, awk field
access) rather than delegating.

---

## 7. Expansion / localization risks

No expansion risk introduced. Numeric logic uses awk with `-F'\t'` and integer arithmetic; no
locale-sensitive collation. Text output is English, matching `cmd_learn` / `cmd_recommend`
pattern. The `OUTLIER_FACTOR` constant (condition M7) must be a named variable, not a hard-coded
literal `2`, so future tuning requires a one-line patch rather than a regex hunt. No wedge
hard-coding detected. The agent prompt for `massoh-meta-engineer` must not reference any
product domain.

---

## 8. Required tests

### Slice 1 — cmd_meta (fixture-based, zero spend, zero network)

All tests run against synthetic fixtures in `test/` or a temp dir. No ledger writes, no LLM.

| ID | Description | Pass condition |
|---|---|---|
| T-meta-A | Ledger with 3 rows same task; implementer tokens = 10x mean of other 2 stages | stdout contains "implementer" and "outlier" (or ranking equivalent) |
| T-meta-B | 3 of 5 `06_review_result.md` contain `Decision.*REQUEST CHANGES` | stdout reports rework rate >= 60% |
| T-meta-C | `AGENT_BACKLOG.md` item "foo-feature" TODO; `AGENT_SYNC.md` decision log "foo-feature: DONE" | stdout mentions "foo-feature" in a drift finding |
| T-meta-D | `06_review_result.md` in 3+ packets each contain "shellcheck" in Blocking section | stdout surfaces "shellcheck" as repeated finding candidate |
| T-meta-E | No `ledger.tsv` present | exit 0; stdout contains "(no ledger data)"; no file created |
| T-meta-F | `.massoh` present, `.agent_tasks/` empty | exit 0; all 4 finding sections degrade gracefully with "(no X data)" messages |
| T-meta-G | Run `massoh meta` without `--write-proposals`; snapshot `agent-project/` before and after | `META.proposed.md` NOT created or modified (use `cd "$RV" && find . -name META.proposed.md \| md5sum` pattern, same as T13g/T8 — NOT single-quoted paths) |
| T-meta-H | Run `massoh meta --write-proposals` | `META.proposed.md` exists and contains `## [meta]` header with timestamp; second run appends (line count increases, original content intact) |
| T-meta-I | `massoh meta` dispatched from main `case` | verb recognized; degrade path or usage hint returned with expected exit code |
| T-meta-J | Run `massoh meta` outside a Massoh project (no `.massoh`, no `agent-project/`) | non-zero exit; "not a Massoh project" message; no file created |

Note on T-meta-G: the implementer MUST use a directory-snapshot approach (find-based, same as
T8/T13g) rather than `md5sum '$RV/...'` with a single-quoted path. The vacuous-checksum bug
from efficiency-v2 (rev2 issue) must not recur.

Note on T-meta-D: the repeated-finding threshold for "promote to enforced check" was specified
as 3+ packets in `01_product_scope.md` §4 (and 2+ in §2); the threshold exposed to the CLI must
match the named constant `REPEAT_THRESHOLD` (see M7-equivalent below). The test must use a
fixture with exactly 3 qualifying packets so the boundary condition is tested, not just >3.

### Slice 2 — agent file + doc updates

| ID | Description | Pass condition |
|---|---|---|
| T-meta-K | `massoh install` in a test env wires `massoh-meta-engineer.md` | file present at `~/.claude/agents/massoh-meta-engineer.md` post-install; `massoh doctor` exits 0 with 7 "ok agent" lines |
| T-meta-L | `policies/02_AGENT_ROLES.md` role table | exactly 7 data rows (was 6) |
| T-meta-M | `OPERATING_SYSTEM.md` §3 or §4 | references "meta" or "massoh-meta-engineer" |

---

## 9. Rollback plan

`cmd_meta` is a standalone function. Rollback = revert the `feat/massoh-meta` branch (or remove
the `cmd_meta` function block + the `meta)` dispatch arm + update the usage string). No data
migrations were made; `META.proposed.md` may exist post-run but is append-only and its removal
is safe (it is a proposals staging file, not a history record). `massoh-meta-engineer.md` is
removed by reverting the branch; it is not in `manifest.yml` as an explicit entry (covered by
the glob), so uninstall automatically skips it if missing. All other files are untouched.

---

## 10. Mandatory conditions (implementer checklist)

### Slice 1 — cmd_meta in bin/massoh

**M1 — Write isolation.**
The only write is `>> "$META_PROPOSALS"` (or equivalent named variable) inside a
`if [ "$write_meta" = 1 ]` block. Named variable must have a `# SAFETY:` comment. No other
file write anywhere in `cmd_meta`. Exact pattern to follow: `cmd_learn` line 531.

**M2 — grep/awk `|| true` on every invocation.**
Every `grep`, `awk`, `git log`, `git rev-parse`, `wc`, and `find` call in `cmd_meta` terminates
with `|| true`. No exceptions, even where zero-match "can't happen." Reviewer must verify by
grepping the function body for bare `grep`/`awk` without `|| true`.

**M3 — Degrade gracefully on absent inputs.**
- No `ledger.tsv`: print "(no ledger data)" for finding #1; exit 0; no file created.
- No `.agent_tasks/TASK-*/` directories or no qualifying `06` files: print "(no packet data)"
  for findings #2 and #4; continue to findings #3 and finish; exit 0.
- No `AGENT_BACKLOG.md`: print "(no backlog file)" for finding #3; continue; exit 0.
- All four degrade messages must be covered in T-meta-E and T-meta-F.

**M4 — `--write-proposals` flag default OFF.**
`local write_meta=0` at function start. Only `--write-proposals` sets `write_meta=1`. Unknown
flags die with a usage message (same pattern as `cmd_learn`'s `*) die ...` arm).

**M5 — No internal calls to cmd_learn / cmd_recommend / cmd_ledger.**
`cmd_meta` reads raw files directly. No `cmd_learn "$@"` or similar delegation.

**M6 — `massoh-meta-engineer.md` not designated safety-critical.**
The implementer must NOT add the new agent file to `NON_NEGOTIABLES.md`. (Confirmed: no new
safety-critical designation required.)

**M7 — Named heuristic constants.**
Two constants must be named variables at the top of `cmd_meta` (or as local vars before first use):
- `local OUTLIER_FACTOR=2` — the multiplier for stage-token outlier detection.
- `local REPEAT_THRESHOLD=3` — the count at which a repeated finding is flagged as "promote
  to enforced check" (the product-scope packet uses 3+ in the "enforced check" path and 2+ for
  general surfacing; the more conservative threshold 3 is the correct default for the enforce
  candidate).

Both names must appear as named locals; numeric literals `2` and `3` must NOT be scattered in
the awk/arithmetic body.

**M8 — `[meta]` label prefix in write block.**
When `--write-proposals` is ON, the appended block must begin with `## [meta] <timestamp>`.
This reserves the namespace and separates `massoh-meta` output from the future `[intake]` entries
in the same `META.proposed.md` file.

**M9 — Verb registration and usage string.**
`meta)` dispatch arm added after `ledger)` in the `case` block. The `die` usage string updated
to include `meta`. Version bump to 0.8.0 (new user-facing verb).

**M10 — No double-counting with cmd_review's rework_pct.**
`cmd_meta` computes rework rate from raw `06_review_result.md` files, not from a cached METRICS
snapshot. This is by design (direct heuristic, not review-ceremony aggregate). The implementer
must NOT read `METRICS.md` for the rework finding — it reads packet files directly. (This avoids
the stale-snapshot issue if `massoh review` has not been run recently.)

### Slice 2 — massoh-meta-engineer.md + doc updates

**M11 — Agent prompt is PROPOSE-ONLY.**
The `massoh-meta-engineer.md` prompt must explicitly state all of the following:
- PROPOSES only; never auto-merges engine changes.
- Never directly edits `STANDARDS.md`, `memory/`, `docs/adr/`, `bin/massoh`, `manifest.yml`,
  or any file in `NON_NEGOTIABLES.md`.
- Routes all engine-upgrade proposals through the normal gate.
- Only write targets: `agent-project/META.proposed.md` (append, labeled `[meta]`) and
  `AGENT_BACKLOG.md` (append-only, labeled `[meta]`, only for backlog items the gate has
  approved — not autonomous).

**M12 — Manifest glob covers the new file without manifest.yml change.**
The `kind: glob` entry (`pattern: massoh-*.md`, `source: claude/agents/`) in `manifest.yml`
covers `massoh-meta-engineer.md` automatically. The implementer must NOT modify `manifest.yml`.
(Verified: the glob is in place; no change required.)

**M13 — Doctor auto-adapts to 7 agents.**
`cmd_doctor` enumerates `"$MASSOH_HOME"/claude/agents/massoh-*.md` dynamically (lines 141–143
of `bin/massoh`). Adding `massoh-meta-engineer.md` to `claude/agents/` automatically makes
`cmd_doctor` expect and check for 7 agents. No change to `cmd_doctor` is needed. T-meta-K
verifies this: `massoh doctor` must exit 0 with an "ok agent massoh-meta-engineer.md" line.

**M14 — Doc edits are additive only.**
The three doc updates (`02_AGENT_ROLES.md` role count, `OPERATING_SYSTEM.md` workflow references,
`README.md` role table) must be pure additive row/reference additions. No guardrail rule, block
marker, install procedure, or enforcement language may be modified. The reviewer must verify that
only description text changes.

---

## 11. Rollback plan (explicit)

1. `git revert` the `feat/massoh-meta` PR (or delete the branch before merge).
2. `massoh install` re-installs the previous 6-agent set (the glob picks up whatever is in
   `claude/agents/`; the reverted branch has no `massoh-meta-engineer.md`).
3. `META.proposed.md`, if created, can be deleted or left in place — it is not a history record
   and is not referenced by any other verb.
4. No data was mutated; no migration to undo.

---

## Approved for implementation?

**Slice 1 (cmd_meta in bin/massoh): YES — conditional on M1–M10.**
**Slice 2 (massoh-meta-engineer.md + doc updates): YES — conditional on M11–M14.**

Both slices approved as a single PR on `feat/massoh-meta`.

Conditions M1 (write isolation), M2 (grep/awk `|| true`), and M3 (degrade) are BLOCKING: if any
is absent at review, the reviewer-qa agent must issue REQUEST CHANGES.

The owner sign-off on record in `00_request.md` is the authorization of record for both slices.

---

## 12. Recommended next agent

**massoh-implementer** — consume this packet (`03_architecture_safety.md`) as the license
to implement. Build Slice 1 first (cmd_meta + T-meta-A through T-meta-J), then Slice 2 (agent
file + doc updates + T-meta-K through T-meta-M). One PR on `feat/massoh-meta`. VERSION → 0.8.0.
