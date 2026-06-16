# 03 — Architecture / Safety

**Agent:** massoh-architecture-safety · **Date:** 2026-06-16
Owner overrode product-scope (full fleet now). Approved **with mandatory safe-default conditions** —
building the capability must NOT make unattended spend or auto-merge happen by default.

## Design
New script `bin/massoh-cron` (the subsystem); `bin/massoh` gains `cmd_cron` that forwards to it.
Subcommands: `once` (the tick), `install`/`off` (scheduler artifact), `status`.

- **Injectable agent:** `MASSOH_AGENT_CMD` (default `claude -p`). Tests/dry-run use a fake → real
  loop tested at zero cost.
- **Injectable gate:** `MASSOH_GATE_CMD` (default: run `test/run.sh` if present, else `true`).
- **Race-free parallel sync:** each agent writes its result to `.agent_tasks/cron/<ts>-<slug>.md`;
  the orchestrator (single parent process, after `wait`) collects + appends to `AGENT_SYNC.md`
  **once, serialized.** No concurrent writers to `AGENT_SYNC.md`. (Solves the write-race.)
- **Isolation:** each agent runs in its own `git worktree` on branch `cron/<slug>`; the owner's
  working tree is never touched; worktrees are removed after.

## Mandatory safe defaults (NON-NEGOTIABLE — these are the gate)
1. `once` defaults to **`--dry-run`** (no agent call, no edits). Real work needs explicit `--run`.
2. **Auto-merge defaults OFF.** `--auto-merge` only merges when the gate is green; even then it is
   the owner's opt-in acceptance of the AUTONOMOUS_CRON additive/flag-dark contract. Never on by default.
3. **Idleness gate ON** by default (`--no-idle-check` only for tests).
4. `install` (a recurring spender) **generates** the schedule artifact (crontab line / systemd unit)
   and only applies it with explicit `--apply` + `--yes-spend`. Otherwise it prints. No silent spend.
5. Paid `claude -p` spend + production auto-merge remain **Guardrail B owner-gated** — the flags are
   the owner's switch; defaults keep them off.

## Required tests (real, fakes — Guardrail A5)
Fixture repo with its own `AGENT_BACKLOG.md`/`AGENT_SYNC.md`/git + a fake `MASSOH_AGENT_CMD`:
- idleness gate: recent commit → `once` exits 0, no work.
- dry-run default: prints chosen TODO, fake agent **not** invoked (sentinel absent).
- `--run`: worktree made, fake invoked once, item → DONE, one `[cron]` AGENT_SYNC entry, worktree cleaned.
- `--run --parallel 2`: fake invoked twice, both DONE, **2** sync entries, file intact (no race corruption).
- auto-merge OFF by default: green gate, no `--auto-merge` → main unchanged.
- empty/all-BLOCKED backlog → exit 0.
- all prior 28 tests green.

## Risks + mitigations
- Unattended spend → dry-run default + explicit `--run`/`--yes-spend`. ✓
- AGENT_SYNC race → serialized single-writer collect. ✓
- Worktree leakage → `git worktree remove` in a trap. ✓
- Auto-merge of bad code → gate must be green AND flag explicit; default off. ✓
- Edits `bin/massoh` (safety-critical) → owner sign-off (granted via override). ✓

## Rollback
Additive (new script + new verb). Revert branch. No state. Scheduler `off` removes any artifact.

## Approved for implementation? **YES — conditional on all "mandatory safe defaults" above.**
