# 02 — Agent roles + permissions (portable)

The core team. Each role is a `.claude/agents/massoh-*.md` file (installed globally). Project-side
"domain pack" agents (UX, design, market, etc.) feed evidence INTO these stages; they never gate or
replace them.

| Role | Decides | Edits code? | Writes |
|---|---|---|---|
| `massoh-product-scope` | build / defer / kill, scope, metric | **no** | `00/01` packet, `AGENT_SYNC.md` |
| `massoh-architecture-safety` | readiness-to-build (approve/reject), risk | no (read-only checks) | `03` packet, `AGENT_SYNC.md` |
| `massoh-implementer` | nothing (executes approved scope) | **yes, with a license** | code, tests, `05` handoff, sync |
| `massoh-reviewer-qa` | approve / request-changes / reject | no (read-only verify) | `06` review, sync |
| `massoh-system-architect` | unblock, sequence, architecture calls | small safe seams only | ADRs, backlog, packets, sync |
| `massoh-history-maintainer` | what to keep / merge / archive | no (docs only) | docs, sync, audit ledger |

## Permission spine
- Only `massoh-implementer` (and, narrowly, `massoh-system-architect`) edit product code — and only
  in `IMPLEMENTATION` mode with a license, on a non-default branch.
- All roles may write **markdown artifacts** (packets, docs, `AGENT_SYNC.md`) in any mode.
- No role changes a **designated safety-critical file/policy** (`agent-project/NON_NEGOTIABLES.md`)
  without explicit owner sign-off.
- The **owner decides** build/defer/kill and merges. Agents recommend; they don't self-authorize
  owner-gated actions (`09_GUARDRAILS.md` §B).

## Routing
`massoh-product-scope` → (UX, if user-facing) → `massoh-architecture-safety` → packet →
`massoh-implementer` → `massoh-reviewer-qa` → owner. Shortcuts are allowed but must be **explicit**
and recorded in `00_request.md` (`03_AGENT_WORKFLOW.md`).
