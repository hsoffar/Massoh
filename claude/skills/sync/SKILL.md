---
name: sync
description: Update AGENT_SYNC.md after an agent task, preserving current state and creating a clean handoff.
---

# /sync

Input (optional context):
$ARGUMENTS

Update `AGENT_SYNC.md` — primarily §Current Task, §Last Handoff, §Decision Log,
§Active Task Packets — using this handoff structure:

```
Agent:
Mode:
Task:
Task packet:
Status:
Decision:
Files changed:
Tests run:
Risks:
Blocked by:
Next recommended agent:
Next action:
```

## Rules
- **Do not remove previous decision-log entries.** Append new decisions to the table.
- Keep §Current Strategic Mode visible and current (change it only on owner direction).
- Keep `AGENT_SYNC.md` **concise** — it is the dashboard. Detailed history goes into the task-packet
  files; ship history goes to `archive/`.
- If implementation happened: include branch and test status in the handoff.
- If a feature was deferred or killed: append it to `agent-project/NOW_NEXT_LATER.md` with reason +
  re-entry condition.
- Never delete §Frozen entries unless the owner explicitly requests it.
- **Always identify the next recommended agent** — a handoff without a recipient is a dead end.
- Update `Last updated:` at the top.
