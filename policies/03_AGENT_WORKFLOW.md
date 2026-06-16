# 03 — The gated workflow (portable)

```
Owner idea
  → Product Scope        (build / defer / kill + minimal version)
  → UX                   (flow, copy — when user-facing; project domain pack)
  → Architecture/Safety  (impact, risks, approval — when technical/AI)
  → Implementation Packet (.agent_tasks/TASK-*/04_implementation_packet.md  = the license to code)
  → Implementer          (code, tests, handoff)
  → Reviewer / QA        (approve / request-changes / reject)
  → Owner merge/reject
```

Not every task needs every stage — but **every shortcut must be explicit** and recorded in
`00_request.md`. Allowed shortcuts:

| Task type | Path |
|---|---|
| Narrow bug fix | Architecture/Safety → Implementer → Reviewer |
| Copy-only | UX → Implementer → Reviewer |
| Strategy-only | Product Scope only |
| Review-only | Reviewer only |
| Sync-only | update `AGENT_SYNC.md` only |
| History maintenance | History Maintainer only |

## Mode classification (required before any work)
Classify each task as exactly one: `PRODUCT_SCOPE` · `UX_REVIEW` · `ARCHITECTURE_SAFETY` ·
`IMPLEMENTATION` · `REVIEW_QA` · `SYNC_ONLY` · `HISTORY_MAINTENANCE`. Output the preflight block
(Mode / Agent / Reason / files / will-edit-code / artifacts / packet path) before acting.

## The one hard gate
**No implementation without a license** (an approved `04_implementation_packet.md` or an approved
issue with acceptance criteria). If neither exists, the task is not `IMPLEMENTATION` → route to
`massoh-product-scope` first. See `04_CLAUDE_CODE_RULES.md` and `09_GUARDRAILS.md`.
