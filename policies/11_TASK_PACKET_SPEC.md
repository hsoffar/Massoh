# 11 — Task-packet spec (portable)

Every meaningful task gets a folder `.agent_tasks/TASK-YYYY-MM-DD-short-slug/`. Packets are the
**detailed history**; `AGENT_SYNC.md` is only the dashboard.

| File | Created by | Content |
|---|---|---|
| `00_request.md` | `/start-task` | verbatim request, date, classification, mode, code-edit allowance, source |
| `01_product_scope.md` | product-scope | build/defer/kill, minimal version, metric, acceptance criteria |
| `02_ux_review.md` | UX (if user-facing) | flow, copy, UX invariants |
| `03_architecture_safety.md` | architecture-safety | impact, risks, tests, **approved yes/no** |
| `04_implementation_packet.md` | after approvals | the **license to code** — scope, criteria, flag, tests, rollback |
| `req:` | optional | REQ-ID this task satisfies, e.g. `REQ-SAFE-001` (RMT: policy 14) |
| `05_implementation_handoff.md` | implementer | files changed, tests run (verbatim), risks, reviewer handoff |
| `06_review_result.md` | reviewer | approve / request-changes / reject + specific findings |

## Rules
- Reuse the existing folder when a task continues (same Task ID).
- Decision/design tasks may use extra numbered files (`02_decision.md`, etc.) — keep the 00→06
  spine for the standard build flow.
- **Never delete a packet.** Noisy active list → move the folder to `.agent_tasks/archive/`,
  contents intact (keep-older-data).
- A code task is **not closable** without `06_review_result.md`.
