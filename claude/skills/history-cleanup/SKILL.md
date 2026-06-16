---
name: history-cleanup
description: Audit and optimize old agent/sync files, merge useful knowledge, mark obsolete files, and keep the agent system clean.
---

# /history-cleanup

Input (optional scope):
$ARGUMENTS

Run as / route to the `massoh-history-maintainer` agent.

## Steps
1. Read `agent-os/policies/10_AGENT_HISTORY_AUDIT.md` (the ledger of prior passes; the project keeps
   its own copy).
2. Search for old agent/process/sync files: root `*.md`, `docs/`, `agent-project/`, `docs/adr/`
   (read-only!), `.claude/agents/`, `.claude/skills/`, `.agent_tasks/`, `.github/`.
3. Classify each file:
   - **Keep** — current and correct.
   - **Merge** — useful content moves into the current source of truth; pointer left behind. If the
     content is reusable workflow (not project-specific), note it belongs **upstream in Massoh**.
   - **Deprecate** — replaced; gets a deprecation header, content preserved.
   - **Archive** — historical value only; moves/summarizes into `archive/`.
4. **Do not rewrite ADR history.** "Superseded by" notes only.
5. **Do not delete useful content** — preserve before pruning (keep-older-data).
6. If a file is replaced, add a deprecation header at the top:
   > **Deprecated: replaced by [new file]. Preserved for history.**
7. Move/summarize useful old info into: `AGENT_SYNC.md` (active state only) · `agent-project/`
   (project policy) · `.agent_tasks/` (task detail) · `archive/` (history).
8. Update the history-audit ledger + `AGENT_SYNC.md` handoff.

## Output
Files audited · Keep/Merge/Deprecate/Archive decisions · Information preserved ·
Information compressed/removed · New source of truth · Risks · `AGENT_SYNC.md` update.
