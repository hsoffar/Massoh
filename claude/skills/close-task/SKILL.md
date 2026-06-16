---
name: close-task
description: Close a task packet after approval, rejection, deferral, or completion.
---

# /close-task

Input:
$ARGUMENTS

## Steps
1. Read `AGENT_SYNC.md`.
2. Read the relevant task-packet folder (`.agent_tasks/TASK-*/`).
3. Verify the task's terminal state:
   - **Completed** (implemented + reviewed + owner accepted)
   - **Deferred** (Product Scope or owner; re-entry condition recorded)
   - **Killed** (Product Scope or owner; reason recorded)
   - **Rejected** (reviewer or owner; reason recorded)
   - **Waiting owner decision** (→ do NOT close; record the open question in `AGENT_SYNC.md`
     §Open Questions instead)
4. Update the task packet with the final status (append a `## Closed` section: status, date,
   decider, reason).
5. Update `AGENT_SYNC.md`: §Current Task cleared (or next task) · §Decision Log appended ·
   §Active Task Packets row → terminal status · §Last Handoff updated.
6. **Do not delete the task packet.** If the active list is noisy, move the folder to
   `.agent_tasks/archive/` — contents intact.
7. If code was implemented: verify `06_review_result.md` exists. If it doesn't, the task is **not
   closable** — route to `massoh-reviewer-qa` first.
8. If the task was Deferred/Killed and is feature-shaped: ensure `agent-project/NOW_NEXT_LATER.md`
   reflects it.
