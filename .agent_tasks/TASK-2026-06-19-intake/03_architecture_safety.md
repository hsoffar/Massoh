# 03 — Architecture / Safety Assessment: `massoh intake` (TASK-2026-06-19-intake)

**Agent:** massoh-architecture-safety  
**Date:** 2026-06-19  
**Verdict:** APPROVED (batch-authorized; no separate owner sign-off needed)  
**Condition count:** 11 (IK1–IK11)  
**Test target:** 301 + 11 = 312 checks (T-IK-a through T-IK-k)  
**Highest risk:** Append-only discipline — intake WRITES to `AGENT_BACKLOG.md`, a NON_NEGOTIABLES append-only file with an active violation history this session (board agent deleted Done rows; reviewer caught it).  
**Safe append mechanism chosen:** single `awk`-based in-place rewrite of AGENT_BACKLOG.md is PROHIBITED. Instead: use a `printf '...' >> "$BACKLOG"` single-append to a dedicated `## Intake inbox` section that is separated from the Queue/Done/Frozen tables. The Queue table itself is never rewritten. The implementer may alternatively anchor to `## Queue` via `awk` that only adds one line after the last `|` row and exits immediately, but the dedicated-section approach is safer and simpler to audit. See IK1 for the exact spec.

---

## 1. Backend / service impact

No backend. This is a standalone bash verb sourced by `bin/massoh`. The only persistent effect is one `printf >> "$BACKLOG"` append and one `printf >> "$MEMORY"` append. No network, no subprocess that escapes the local repo.

## 2. Client / app impact

CLI only. `massoh intake "<idea>"` is a new case in `bin/massoh`'s dispatch block and a usage line update. No other verb behavior changes. Existing CLI output is byte-identical.

## 3. API impact

No API contract. The CLI verb set gains one new entry (`intake`). The `die` path for unknown commands (line 215 of `bin/massoh`) must add `intake` to the help string — additive only, no behavioral change to other paths.

## 4. DB / migration impact

`AGENT_BACKLOG.md` acts as the human-readable append-only store. The verb adds rows; it never rewrites, deletes, or reorders existing content. `memory/MEMORY.md` gets a one-line pointer appended. Both are already tracked in git, giving full audit history. No schema migration required.

## 5. LLM / prompt impact

Zero. No `claude -p`, no API call, no token spend. Priority assignment is a deterministic heuristic (IK5). No confidence levels, disclaimers, or calibration rules apply to this verb.

## 6. Safety / guardrail risks and mandatory conditions

The central risk is write safety to `AGENT_BACKLOG.md`. The Done and Frozen sections are protected by NON_NEGOTIABLES §Data+migration ("Decision-log + Done + Frozen rows are append-only — never deleted"). The Queue table rows, while not individually frozen, must not be modified or deleted either — only new rows added. The board agent this session accidentally deleted Done rows (AGENT_SYNC decision log 2026-06-19), demonstrating the risk is real.

### Mandatory conditions (IK1–IK11)

**IK1 — Append-only write mechanism (HIGHEST RISK)**  
The verb MUST NOT use `sed -i`, any `> file` redirect, `mv tmp file`, or any awk pattern that rewrites the whole file. The ONLY permitted write to `AGENT_BACKLOG.md` is a single `printf '...' >> "$BACKLOG"` that appends to a dedicated `## Intake inbox` section at the end of the file (after Done/Frozen). If the section header is absent, `printf '\n## Intake inbox\n| # | Pri | Item | Status |\n|---|---|---|---|\n'` is appended first (one-time bootstrap, also via `>>`). The Queue/Done/Frozen tables are never touched. The named variable MUST be:  
```bash
local BACKLOG="$repo/AGENT_BACKLOG.md"  # SAFETY: only permitted write in cmd_intake
```  
A `# SAFETY: only permitted write in cmd_intake` comment MUST appear on the append line itself, mirroring `ledger.sh` L4 and `learn.sh`/`meta.sh` patterns.

**IK2 — Input sanitization**  
The idea string is free-form user input going into a markdown table cell. Before any file touch:  
- Strip all literal pipe characters `|` (replace with a space or `—`).  
- Strip all newlines `\n`, carriage returns `\r`, and tab characters `\t`.  
- Truncate to at most 200 characters (prevents runaway rows).  
- After stripping, reject the empty string with a usage message to stderr and exit non-zero; write nothing.  
These transforms happen on a named local variable (`local idea_clean`) before any `>>` is executed.

**IK3 — Arg guard (first statement)**  
`[ $# -ge 1 ]` MUST be the first executable statement in `cmd_intake`. An empty or missing argument exits non-zero and writes nothing to any file. Mirror ledger.sh's L3 pattern: check before any local file or directory access.

**IK4 — Idempotency**  
If the sanitized idea text already appears as a cell value in `$BACKLOG` (a simple `grep -qF "$idea_clean"` is sufficient), the verb prints a one-line notice to stdout and exits 0 without writing anything. This prevents duplicate rows from re-runs or copy-paste accidents. The check uses `|| true` so a missing file does not abort.

**IK5 — Priority heuristic (deterministic, zero LLM)**  
When no priority flag is supplied, assign using this documented rule (simple keyword scan, no NLP):  
- P0: idea string (lowercased) contains any of: `bug`, `broken`, `crash`, `fail`, `urgent`, `security`, `block`.  
- P1: contains any of: `add`, `implement`, `ship`, `feature`, `new verb`, `enable`, `integrate`.  
- P2: contains any of: `improve`, `optimize`, `refactor`, `update`, `enhance`.  
- P3: everything else.  
The heuristic is applied via a simple `case`/`if` chain on `echo "$idea_lower"` with `grep -qiE`. No subprocess that could fail opaquely; every branch produces a result. The heuristic and its keywords MUST be documented in a comment block inside `lib/verbs/intake.sh`.

**IK6 — Memory pointer write**  
The one-line memory pointer is appended to `memory/MEMORY.md` (the index file) via a single `printf '...' >> "$MEMORY"` — never overwritten, never clobbered. The line format mirrors the existing index entries (e.g. `- [intake: <first 60 chars of idea>](<ts>)\n`). Named variable:  
```bash
local MEMORY="$repo/memory/MEMORY.md"
```  
If `memory/MEMORY.md` does not exist, `mkdir -p "$repo/memory"` is run first (create-if-missing, consistent with `cmd_on`). The write is guarded with `|| true` — a MEMORY.md write failure must not abort backlog append if backlog already succeeded (degrade gracefully).

**IK7 — Degrade + guards**  
- `set -euo pipefail` context: the sourced file inherits it. Every read-side operation (`grep`, `wc`, `awk`) that can fail on missing files MUST use `|| true`.  
- If `AGENT_BACKLOG.md` does not exist: `mkdir -p` + bootstrap the file with the `## Intake inbox` section header, then append. Never hard-fail silently.  
- All reads of `$BACKLOG` (for idempotency check, for row-count) use `|| true` so an absent file degrades to "not found / proceed."  
- Exit 0 on successful append; exit non-zero on arg/sanitization failure only.

**IK8 — Massoh-project guard**  
Mirror `cmd_learn`/`cmd_meta`: check `[ -e "$repo/.massoh" ] || [ -d "$repo/agent-project" ]` before any write; die with `"not a Massoh project (run: massoh on)."` if not in a project. This prevents accidental writes to non-Massoh repos.

**IK9 — Read-only isolation**  
`cmd_intake` MUST NOT call `cmd_ledger`, `cmd_learn`, `cmd_meta`, `cmd_board`, or any other `cmd_*`. Its only reads are: `git rev-parse --show-toplevel`, `grep` on `$BACKLOG` (idempotency), and `wc -l` for row numbering. No subshell that can invoke another verb.

**IK10 — Dispatch registration**  
Add exactly one case line in `bin/massoh`:  
```
intake)    shift || true; cmd_intake "$@" ;;
```  
Add `intake` to the usage die string at line 215. No other changes to `bin/massoh`. `lib/verbs/intake.sh` is auto-sourced by the existing glob loop (`for _verb_file in "$MASSOH_HOME/lib/verbs/"*.sh`) — no manifest change, no additional wiring required.

**IK11 — VERSION bump**  
Bump `VERSION` to `0.12.0` (next minor after 0.11.0). Update `CHANGELOG.md` with a `[0.12.0]` entry. The installed layout (`~/.claude/agent-os/lib/verbs/intake.sh`) is auto-wired by `cmd_install`'s existing glob: `wire "$MASSOH_HOME/lib/verbs" "$CLAUDE_DIR/agent-os/lib/verbs"`.

---

## 7. Expansion / localization risks

The priority heuristic keywords are English-only. This is acceptable for v1 given the CLI is already English-only and NON_NEGOTIABLES §Localization requires POSIX-bash portability, not multi-language support. The heuristic keywords MUST live in named constants or a comment block (not magic strings scattered across the function) so future localization or replacement is straightforward. No region/locale hard-coding beyond what is already present in other verbs.

## 8. Files touched

| File | Change | Write type |
|---|---|---|
| `lib/verbs/intake.sh` | New file — `cmd_intake` implementation | Create |
| `bin/massoh` | +1 dispatch case line; +`intake` in usage string | Additive edit (batch-authorized) |
| `AGENT_BACKLOG.md` | Append-only: `## Intake inbox` section + rows | `>>` only, never rewrite |
| `memory/MEMORY.md` | Append-only: one-line memory pointer per intake | `>>` only |
| `VERSION` | Bump to `0.12.0` | Overwrite (standard release process) |
| `CHANGELOG.md` | Prepend/append `[0.12.0]` entry | Additive |

No changes to: `manifest.yml`, `templates/`, `agent-os/policies/`, `NON_NEGOTIABLES.md`, `agent-project/`, any other verb file, install/uninstall/backup/block logic.

## 9. Required tests (T-IK-a through T-IK-k)

Test suite baseline: 301 checks. Target after this task: 312 checks (11 new).

**T-IK-a — Append-only: existing rows preserved**  
Setup: create a temp Massoh project with a real `AGENT_BACKLOG.md` containing a Done row and a Queue row. Run `massoh intake "add integration tests"`. Assert: (1) the Done row is still present verbatim, (2) the Queue row is still present verbatim, (3) the file has more lines than before. Assert no `sed -i` invocation (structural, not runtime: `grep -c 'sed -i' lib/verbs/intake.sh` equals 0).

**T-IK-b — Pipe sanitization**  
Run `massoh intake "idea with | pipe | chars"`. Assert the appended row in BACKLOG contains no literal `|` inside the idea cell (pipes are cell delimiters — the idea field must be sanitized).

**T-IK-c — Newline sanitization**  
Run `massoh intake $'multi\nline\nidea'`. Assert BACKLOG has exactly one new row (not multiple lines from the injected newlines); the idea field is on a single line.

**T-IK-d — Length truncation**  
Run `massoh intake` with a 300-character string. Assert the idea cell in the appended row is no longer than 200 characters.

**T-IK-e — Empty arg dies writing nothing**  
Run `massoh intake ""` (empty string). Assert: exit non-zero; BACKLOG unchanged (byte-for-byte); MEMORY.md unchanged.

**T-IK-f — Missing arg dies writing nothing**  
Run `massoh intake` (no argument). Assert: exit non-zero; BACKLOG unchanged; MEMORY.md unchanged.

**T-IK-g — Idempotent re-run no duplicate**  
Run `massoh intake "same idea twice"` twice. Assert BACKLOG contains exactly one row whose idea cell matches "same idea twice" (grep -c). Second run exits 0.

**T-IK-h — Priority assignment**  
Three runs:  
(1) `massoh intake "fix critical bug"` → assert row contains `P0`.  
(2) `massoh intake "add new feature"` → assert row contains `P1`.  
(3) `massoh intake "someday maybe"` → assert row contains `P3`.

**T-IK-i — Degrade on missing BACKLOG**  
Delete BACKLOG from a temp project. Run `massoh intake "fresh idea"`. Assert: exit 0; BACKLOG now exists with the idea row; no crash.

**T-IK-j — Memory pointer written**  
Run `massoh intake "test memory pointer"`. Assert `memory/MEMORY.md` contains a line referencing "test memory pointer" (grep -q).

**T-IK-k — Smoke dispatch (added to T-MB-g family)**  
`( cd "$TMB_PROJ" && "$MASSOH" intake "smoke test idea" >/dev/null 2>&1 )` exits 0.  
This integrates with the existing T-MB-g smoke-dispatch block pattern.

## 10. Rollback plan

`massoh intake` is a net-additive change:

1. `lib/verbs/intake.sh` is a new file — delete it to remove the verb entirely.  
2. `bin/massoh` gets one new dispatch case line and one usage string update — revert with `git revert` or `git checkout HEAD -- bin/massoh`.  
3. `AGENT_BACKLOG.md` will have a `## Intake inbox` section and any queued rows appended. These are append-only additions; they can be left in place (they do not affect Queue/Done/Frozen) or removed by hand. They are never in the Queue table proper, so no ordering or priority logic is disturbed.  
4. `VERSION` and `CHANGELOG.md` revert normally via git.  
5. No schema migration required; no other file is touched. Rollback is a single-PR revert.

## 11. Verdict

**APPROVED for immediate implementation.**

Authorization basis: owner batch-authorization dated 2026-06-19 (AGENT_SYNC decision log) covering `bin/massoh` edits for the 24h queue, which includes item #4 `massoh-intake`. No separate per-change sign-off required.

`bin/massoh` is already modular (v0.11.0, PR #18 merged). `lib/verbs/intake.sh` is auto-sourced by the existing glob. There is no merge dependency — implementation may proceed immediately on a fresh branch (`feat/massoh-intake`).

Conditions IK1–IK11 are mandatory. The implementer must cite each condition by ID in `05_implementation_handoff.md` with the line number(s) that satisfy it. The reviewer must independently verify each condition before approving.

**Highest risk reiterated:** IK1 — append-only write to `AGENT_BACKLOG.md`. The implementer must confirm zero `sed -i`, zero `> file` redirect, zero `mv tmp file` patterns in `lib/verbs/intake.sh`. T-IK-a asserts this at both the structural level (grep on the source file) and the runtime level (row preservation after intake runs).
