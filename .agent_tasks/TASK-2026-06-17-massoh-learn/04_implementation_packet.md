# 04 — Implementation Packet (License)
**Task:** TASK-2026-06-17-massoh-learn · **Date:** 2026-06-17 · **Agent:** massoh-implementer

---

## Status: APPROVED — license to implement

Source approvals on record:
- `00_request.md`: owner authorized build + `bin/massoh*` edits.
- `01_product_scope.md`: product-scope decision = BUILD.
- `03_architecture_safety.md`: architecture-safety decision = APPROVED with 4 mandatory conditions.
- `AGENT_SYNC.md` decision log row (2026-06-17): arch/safety APPROVED, 4 conditions, routes to implementer.

---

## 1. Approved scope (exact; no additions)

Add `cmd_learn` as an inline function in `bin/massoh` (same file, same pattern as `cmd_review` /
`cmd_standup` / `cmd_plan`). The function:

1. **Resolves the repo root** via `git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd`
   (identical to the other ceremonies).

2. **Guards with a Massoh-project check** at the top (same as `cmd_discover`): requires `.massoh`
   marker or `agent-project/` directory; otherwise calls `die`.

3. **Mines (read-only; grep/awk only — NO LLM, NO `claude -p`)**:
   - `.agent_tasks/*/06_review_result.md` — blocking and non-blocking findings, `REQUEST CHANGES`
     lines. Counts recurring patterns (keyword seen in 2+ files).
   - `.agent_tasks/*/05_implementation_handoff.md` — risk lines.
   - `AGENT_SYNC.md` decision log — rows from `## Decision log` table containing the word
     "irreversible" → ADR candidates.
   - `git log` — count of revert commits and fixup commits.

4. **Flags**:
   - `--since DAYS` (default: all time) — limit packet scan by file mtime via `find -mtime`.
   - `--write-proposals` (default: OFF) — when set, append proposals to
     `$repo/agent-project/LEARNINGS.proposed.md`.
   - `--no-write` — explicit no-op alias for the default; stdout only.

5. **Always prints** a "lessons" report to stdout with sections:
   - Recurring review findings (with counts)
   - Risks seen (from `05_implementation_handoff.md`)
   - ADR candidates (irreversible/repeated decisions from decision log)
   - Revert count (from git log)

6. **When `--write-proposals` is set**: appends a `## [learn] <ts>` block to
   `agent-project/LEARNINGS.proposed.md`. NEVER writes to `STANDARDS.md`, `memory/`, `docs/adr/`,
   `bin/massoh`, `manifest.yml`, or any other file.

7. **Added to dispatch table**: `learn) shift || true; cmd_learn "$@" ;;`
   and `learn` added to the `die "unknown command"` verb list.

8. **VERSION**: bumped `0.4.2` → `0.5.0` (new capability + Agent-OS-learning milestone).
   **CHANGELOG**: new `[0.5.0]` entry added.

---

## 2. The 4 mandatory conditions (reviewer will block if any unmet)

### Condition 1 — All grep calls guarded with `|| true`

EVERY `grep` inside `cmd_learn` must be written as `grep ... || true` or captured via
`$(grep ... || true)`. A bare `grep` returning exit 1 on zero matches kills the script under
`set -euo pipefail`. This is the most frequent failure class in this codebase
(confirmed: A&&B||C anti-pattern was the same class of bug, caught twice in review history).
No bare `grep` permitted inside `cmd_learn`. Implementation must use:
```bash
var=$(grep ... || true)
```
or append `|| true` at the end of any grep that is not captured into a variable.

### Condition 2 — Write target locked to a single named variable; SAFETY comment required

The ONLY `>>` redirect in `cmd_learn` must target a local variable `$proposals` computed as:
```bash
local proposals="$repo/agent-project/LEARNINGS.proposed.md"
```
The redirect line must carry a comment:
```bash
# SAFETY: only permitted write in cmd_learn
```
No `>` (overwrite), no `tee`, no other file path may appear in any write operation within
`cmd_learn`. The reviewer will grep-confirm this.

### Condition 3 — English pattern strings as named variables with `# task-packet-spec` comments

The following strings must be extracted as named bash variables with `# task-packet-spec`
comments, NOT buried as literals in grep/awk logic:
```bash
# task-packet-spec: heading names match mandatory sections in 11_TASK_PACKET_SPEC.md
_PAT_BLOCKING='## Blocking'
_PAT_NONBLOCKING='## Non-blocking'
_PAT_DECISION_LOG='## Decision log'
_PAT_ADR_FLAG='irreversible'
_PAT_REQUEST_CHANGES='REQUEST CHANGES'
```
This makes them findable and overridable for future multi-language projects.

### Condition 4 — T11a–T11j all green (10 checks minimum, zero LLM spend, real paths)

All 10 tests added to `test/run.sh` as a `T11` block. Uses temp dirs + fixture markdown.
Exercises the real `bin/massoh learn` invocation (not a stub). Requirements:
- **T11a**: stdout report emitted; `LEARNINGS.proposed.md` NOT created in default mode.
- **T11b**: `--no-write` identical to default; no proposals file; stdout still emitted.
- **T11c**: `--write-proposals` creates file with 4 required sections; three-run
  three-blocks append-only assertion (no overwrite).
- **T11d**: recurring pattern ("A&&B||C anti-pattern" in 2 fixtures) surfaces in proposals.
- **T11e**: decision log row containing "irreversible" → ADR candidates section non-empty.
- **T11f**: git repo with one `git revert` → stdout contains "revert" with count 1.
- **T11g**: `--since 1` with `touch -t` old packet → only recent packet's findings appear.
- **T11h**: no `.agent_tasks/` → exit 0, stdout "(none)" sections, no crash.
- **T11i**: md5 of `bin/massoh` + `manifest.yml` + `STANDARDS.md` unchanged after
  `--write-proposals`.
- **T11j**: non-Massoh-project (no `.massoh`, no `agent-project/`) → non-zero exit + stderr.

---

## 3. Out of scope (do not implement)

- Changes to `manifest.yml` — `LEARNINGS.proposed.md` is a runtime host artifact.
- Changes to any agent `.md` files, skills, or templates.
- `massoh uninstall` cleanup of `LEARNINGS.proposed.md` (not in manifest; left to owner).
- `docs/adr/` directory creation — owner creates manually.
- Auto-promotion to `STANDARDS.md`, `memory/`, or `docs/adr/`.
- LLM calls, `claude -p`, or any API spend.
- Scanning `03_architecture_safety.md` (deferred to v2).
- Cross-repo mining, cross-run deduplication.
- Changes to `backup_claude`, `cmd_uninstall`, `cmd_on`, marker files, `manifest.yml`.

---

## 4. T11 acceptance criteria (restated for clarity)

| Test | What | Assert |
|---|---|---|
| T11a | default mode | stdout has report; no `LEARNINGS.proposed.md` |
| T11b | `--no-write` | identical to default |
| T11c | `--write-proposals` x3 | file has 4 sections; exactly 3 `## [learn]` blocks after 3 runs |
| T11d | recurring pattern | `A&&B||C` appears in proposals; count ≥ 2 |
| T11e | ADR candidate | `irreversible` row → non-empty ADR section |
| T11f | git revert count | stdout contains "revert" with count of 1 |
| T11g | `--since 1` | old packet (touch -t >2d) excluded from scan |
| T11h | no packets | exit 0; stdout "(none)" sections |
| T11i | safety-critical unchanged | md5 of bin/massoh + manifest.yml + STANDARDS.md same before/after |
| T11j | non-Massoh project | non-zero exit; error on stderr |

---

## 5. Branch / commit discipline

- Branch: `feat/massoh-learn` (already checked out).
- Small Conventional Commits; trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- No commit of `.env*`, backups, secrets, datasets.
- Do NOT push; do NOT open PR (per task instructions).
