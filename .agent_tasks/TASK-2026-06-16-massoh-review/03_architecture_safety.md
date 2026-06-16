# 03 — Architecture / Safety
**Agent:** massoh-architecture-safety · **Date:** 2026-06-16

## Impact
`bin/massoh`: +`cmd_review` (inline, ~40 lines) + dispatch `review)` + usage. New: none (writes into
existing `agent-project/METRICS.md`). No new install artifact → **no manifest change**.

## Safety
- Read-only except an **append** to `METRICS.md` (additive, keep-older-data; `--no-write` for none).
  Not a designated safety-critical file.
- No network, no spend, no merges, no worktrees.
- Edits `bin/massoh` (safety-critical) → owner authorized (selection). Block markers / backup /
  uninstall set / manifest untouched.
- Must tolerate a repo with no `.agent_tasks/`, no `METRICS.md`, or not-a-git-repo (degrade, exit 0).

## Required tests (T8, real)
Fixture repo with a couple of fake `.agent_tasks/TASK-*` (some with `06_`/`04_`), a backlog, a git
history → assert: report prints counts; `--no-write` changes nothing (md5 snapshot of the dir);
default appends exactly one `## Snapshot` block; second run → two blocks; runs in a non-git dir
without erroring. Prior 45 green.

## Rollback
Additive; revert branch.

## Approved? **YES** — read-only + additive, owner-authorized. Conditions: `--no-write` truly inert;
degrade gracefully on missing inputs; no manifest/marker/backup edits.
