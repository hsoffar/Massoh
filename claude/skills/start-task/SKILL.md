---
name: start-task
description: Start a task by loading context, creating/updating a task packet, classifying task mode, selecting the right agent, and preparing a safe execution plan.
---

# /start-task

Input:
$ARGUMENTS

## Steps

1. Read the host `CLAUDE.md`.
2. Read `agent-os/OPERATING_SYSTEM.md`.
3. Read `AGENT_SYNC.md`.
4. Read `agent-project/NON_NEGOTIABLES.md`.
5. Read `agent-os/policies/03_AGENT_WORKFLOW.md`.
6. Read `agent-project/NOW_NEXT_LATER.md`.
7. Read `agent-os/policies/11_TASK_PACKET_SPEC.md`.
8. Classify the task as exactly one of:
   - `PRODUCT_SCOPE`
   - `UX_REVIEW`            (user-facing copy/flow — uses the project's UX/domain pack if present)
   - `ARCHITECTURE_SAFETY`
   - `IMPLEMENTATION`
   - `REVIEW_QA`
   - `SYNC_ONLY`
   - `HISTORY_MAINTENANCE`
9. Create or identify the task-packet folder `.agent_tasks/TASK-YYYY-MM-DD-short-slug/`
   (reuse the existing folder if the task continues a known Task ID).
10. Create/update `00_request.md` (verbatim request, date, classification, requested mode,
    code edits allowed?, source context).
11. Select the correct agent (`massoh-product-scope`, `massoh-architecture-safety`,
    `massoh-implementer`, `massoh-reviewer-qa`, `massoh-system-architect`,
    `massoh-history-maintainer`, or a project UX/domain agent).
12. Determine whether code edits are allowed (only `IMPLEMENTATION`, or explicit owner override).
13. If implementation is requested: **verify** `04_implementation_packet.md` exists, or an
    approved issue/card with acceptance criteria exists. If not → reclassify as `PRODUCT_SCOPE`
    and say why.
14. Print: Mode · Agent · Reason · Files to inspect · Will edit code? · Will create/update
    artifacts? · Task-packet path · Required handoff output.
15. Update `AGENT_SYNC.md` §Current Task.
16. Do **not** implement until mode, agent, and task packet are clear.

## Rules
- `/start-task evaluate …` creates **decision artifacts, not code** (`00_request.md` + routes to
  `massoh-product-scope` for `01_product_scope.md`).
- `/start-task implement …` **consumes** an approved implementation packet — it never creates one.
- If Product Scope says **Defer or Kill** → do not create an implementation packet.
- If **Build** → route to UX and/or Architecture/Safety before implementation (shortcuts only per
  `agent-os/policies/03_AGENT_WORKFLOW.md`, recorded in `00_request.md`).
