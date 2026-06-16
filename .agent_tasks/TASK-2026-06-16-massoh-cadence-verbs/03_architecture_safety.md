# 03 — Architecture / Safety
**Agent:** massoh-architecture-safety · **Date:** 2026-06-16

## Impact
`bin/massoh`: +`cmd_standup` +`cmd_plan` (inline, ~25 lines each) + dispatch + usage. Writes only
append to existing `AGENT_SYNC.md`. **No manifest change**, no new install artifact.

## Safety
- Read-only except additive `AGENT_SYNC.md` append (keep-older-data; `--no-write` = inert).
- No network except optional best-effort `gh pr list` (skip silently if absent).
- Edits `bin/massoh` (safety-critical) → owner authorized. Markers / backup / uninstall set /
  manifest untouched.
- Must tolerate missing `AGENT_BACKLOG.md` / `AGENT_SYNC.md` / non-git (degrade, exit 0).

## Required tests (T9, real)
Fixture with backlog (TODO/DOING/BLOCKED), `AGENT_SYNC.md` with an Open-questions row, git history,
an in-flight packet (04 no 06): assert standup lists commits + DOING/BLOCKED + in-flight; plan lists
TODO + surfaces the question; `--no-write` md5-inert for both; write appends one block each; non-git
dir degrades. Prior 53 green.

## Rollback
Additive; revert branch.

## Approved? **YES** — read-only + additive, owner-authorized. Conditions: `--no-write` inert;
degrade gracefully; no manifest/marker/backup edits.
