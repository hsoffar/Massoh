# AGENT_SYNC.md — {{PROJECT}}

**The shared dashboard for all agents — current state, latest handoff, decisions.**
Read at every session boot; update after every meaningful task (`/sync`). Dashboard, not a history
dump — task detail lives in `.agent_tasks/`, decisions of record in `docs/adr/`.

Last updated: {{ date }} ( {{ short note }} )

## Current strategic mode
{{ from agent-project/PRODUCT_STRATEGY.md }}

## Current task
{{ what's in flight; or "none" }}

## Open questions (owner decision needed)
| Question | Raised | Context |
|---|---|---|

## Decision log (append-only — never delete a row)
| Date | Decision | By |
|---|---|---|

## Frozen (never delete without an explicit owner unfreeze)
{{ list }}

## Active task packets
| Task ID | Stage | Status |
|---|---|---|

## Last handoff
```
Agent:
Mode:
Task:
Status:
Next recommended agent:
Next action:
```
