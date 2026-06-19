# CLAUDE.md — {{PROJECT}} session bootloader

> This repo uses **Massoh** (the agent operating system), installed globally in `~/.claude/`.
> This file is the project's bootloader. The portable engine lives in `~/.claude/agent-os/`.

## Boot sequence — read before any task
1. `~/.claude/agent-os/OPERATING_SYSTEM.md` — how the agent system works.
2. `AGENT_SYNC.md` — current strategic mode, current task, blockers, last handoff.
3. `agent-project/NON_NEGOTIABLES.md` — this project's hard constraints + safety-critical files.
4. `~/.claude/agent-os/policies/03_AGENT_WORKFLOW.md` — the gated workflow.
5. `agent-project/NOW_NEXT_LATER.md` — backlog + frozen list.

Constant context: `agent-project/CHARTER.md` (mission, architecture, env facts).
Guardrails: `~/.claude/agent-os/policies/09_GUARDRAILS.md`. Decisions: `docs/adr/`.

## Required preflight output (before any work)
```
Mode:
Agent:
Reason:
Files I will read first:
Will I edit code? yes/no
Will I create/update task artifacts? yes/no
Task packet path, if any:
```

## Task classification
Classify every task as exactly one: `PRODUCT_SCOPE` · `UX_REVIEW` · `ARCHITECTURE_SAFETY` ·
`IMPLEMENTATION` · `REVIEW_QA` · `SYNC_ONLY` · `HISTORY_MAINTENANCE`
(`~/.claude/agent-os/policies/03_AGENT_WORKFLOW.md`).

## Hard rules (full list: `~/.claude/agent-os/policies/09_GUARDRAILS.md`)
1. **No implementation without a license** (an approved `04_implementation_packet.md` or an issue
   with acceptance criteria). Else route to `massoh-product-scope`.
2. **No code edits** outside `IMPLEMENTATION` (markdown artifacts always allowed) unless the owner
   explicitly requests it.
3. Never change a **designated safety-critical file/policy** (see `agent-project/NON_NEGOTIABLES.md`)
   without explicit owner sign-off.
4. **Flag-gate** new features (default OFF), if this project uses flags.
5. **Keep older data** — append-only / soft-delete; never hard-delete or overwrite history.
6. **Branch + PR per feature.** Bump the client version on shipped client changes.
7. No frozen feature (`AGENT_SYNC.md` §Frozen) without an explicit unfreeze.
8. Update `AGENT_SYNC.md` after meaningful work (`/sync`).
9. No broad refactors unless requested.

<!-- ====================== PROJECT BLOCK (owned by this repo; Massoh never overwrites) ====================== -->
## Project facts (quick reference)
- {{ fill in: how to run, test, deploy; the API contract seam; commit trailer; env quirks }}
<!-- ====================== END PROJECT BLOCK ====================== -->

## Skills
`/start-task <request>` · `/sync` · `/close-task <id>` · `/history-cleanup`.

## Optional capabilities
- **RMT** (requirements registry + CI validator): see
  `~/.claude/agent-os/policies/14_REQUIREMENTS_TRACEABILITY.md` to opt in.
