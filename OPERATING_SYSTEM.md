# OPERATING_SYSTEM.md — how the agent system works (portable)

Audience: the founder/owner and every AI agent working in a repo that uses agent-os.
Bootstrap: the host repo's `CLAUDE.md` (read it first — it is the session bootloader).
State: `AGENT_SYNC.md`. Policies: `agent-os/policies/`. Project specifics: `agent-project/`.
Task history: `.agent_tasks/`.

> **Portable file.** This is owned by agent-os (Massoh). Project-specific facts live in
> `agent-project/` (charter, non-negotiables, strategy) and in `AGENT_SYNC.md` — never inline here.

## 1. Purpose

One owner + AI agents ship a product without build-trap, scope creep, quality/safety regressions,
or knowledge drift. The system guarantees:

1. Every session loads the correct context (`CLAUDE.md` boot sequence).
2. Every task routes to the correct agent (mode classification).
3. Nothing is coded before product/architecture approval (gates).
4. Every meaningful task leaves artifacts (`.agent_tasks/` packets).
5. Agents stay synchronized (`AGENT_SYNC.md` dashboard + handoffs).
6. Old/duplicated history gets cleaned, not hoarded (History Maintainer).

## 2. Starting a session

1. Claude reads `CLAUDE.md` automatically → follows the boot sequence.
2. Claude outputs the preflight block (Mode / Agent / Reason / files / will-edit-code / artifacts / packet path).
3. Work proceeds per the workflow below.
4. Session ends with `/sync` (and `/close-task` if a packet completed).

## 3. The workflow

```
Owner idea
  → Product Scope Agent          (build / defer / kill + minimal version)
  → UX Agent                     (flow, copy — when user-facing; optional domain pack)
  → Architecture / Safety Agent  (impact, risks, approval — when technical/AI)
  → Implementation Packet        (.agent_tasks/TASK-*/04_implementation_packet.md)
  → Implementer                  (code, tests, handoff)
  → Reviewer / QA Agent          (approve / request changes / reject)
  → Owner merge/reject decision
```

Not every task needs every stage — but **every shortcut must be explicit**. Allowed shortcuts:

| Task type | Path |
|---|---|
| Narrow bug fix | Architecture/Safety → Implementer → Reviewer |
| Copy-only | UX → Implementer → Reviewer |
| Strategy-only | Product Scope only |
| Review-only | Reviewer only |
| Sync-only | Update `AGENT_SYNC.md` only |

Full detail: `agent-os/policies/03_AGENT_WORKFLOW.md`.

## 4. Routing tasks

Use `/start-task`. `evaluate …` → decision artifacts (00/01 packet files), **never code**.
`implement …` → consumes an existing approved `04_implementation_packet.md`. Or invoke agents
explicitly (`@product-scope`, `@architecture-safety`, `@implementer`, `@reviewer-qa`,
`@system-architect`, `@history-maintainer`, `@meta-engineer`). Roles/permissions:
`agent-os/policies/02_AGENT_ROLES.md`.

The **massoh-meta-engineer** (7th role) reads `massoh meta` output + the ledger + completed
packets to surface bottlenecks, rework patterns, and repeated review findings. It proposes engine
upgrades to `agent-project/META.proposed.md` (labeled `[meta]`), then routes them through the
normal gate. It never auto-merges engine changes and never edits safety-critical files directly.

## 5. Task packets (`.agent_tasks/`)

Every meaningful task gets `.agent_tasks/TASK-YYYY-MM-DD-short-slug/`:

| File | Created by | Content |
|---|---|---|
| `00_request.md` | /start-task | original request, classification, code-edit allowance |
| `01_product_scope.md` | Product Scope | build/defer/kill, minimal version, acceptance criteria |
| `02_ux_review.md` | UX | flow, copy (when user-facing) |
| `03_architecture_safety.md` | Architecture/Safety | impact, risks, tests, **approved yes/no** |
| `04_implementation_packet.md` | after approvals | the only license to code |
| `05_implementation_handoff.md` | Implementer | files changed, tests, risks, reviewer handoff |
| `06_review_result.md` | Reviewer | approve/request-changes/reject |

Full spec: `agent-os/policies/11_TASK_PACKET_SPEC.md`. Packets = detailed history.
`AGENT_SYNC.md` = dashboard only.

## 6. AGENT_SYNC.md

The single shared status file: strategic mode, key metric, frozen list, current task, decision log,
open questions, active packets, last handoff. Every agent reads it at boot and appends after
meaningful work (`/sync`). Never delete decision-log entries or frozen items.

## 7. When may Claude edit code?

Only in `IMPLEMENTATION` mode, with an approved issue **or** `04_implementation_packet.md`, with
acceptance criteria, on a non-default branch. Markdown artifacts (packets, docs, sync) are editable
in any mode. Explicit owner request can override — say so in the preflight block.
Rules: `agent-os/policies/04_CLAUDE_CODE_RULES.md`.

## 8. Frozen list

Features the owner has explicitly deferred. The authoritative list lives in the **project**:
`AGENT_SYNC.md` §Frozen and `agent-project/NOW_NEXT_LATER.md`. Never build a frozen item without
an explicit unfreeze.

## 9. History maintenance

Old coordination docs are never silently deleted. The History Maintainer (`/history-cleanup`)
audits, merges, deprecates (with headers), or archives. Ledger: `agent-os/policies/10_AGENT_HISTORY_AUDIT.md`
(template; the project keeps its own ledger). ADRs are never rewritten.

## 10. Source-of-truth map

| Question | File |
|---|---|
| How do I boot? | `CLAUDE.md` |
| How does the system work? | this file |
| What is the current state? | `AGENT_SYNC.md` |
| What's the autonomous work queue? | `AGENT_BACKLOG.md` |
| What are the (portable) policies? | `agent-os/policies/` |
| What is *this* product / its rules? | `agent-project/` (CHARTER, NON_NEGOTIABLES, …) |
| How do agents behave? | `.claude/agents/` (wired from `agent-os/claude/agents/`) |
| What happened in task X? | `.agent_tasks/TASK-*/` |
| Why was decision Y made? | `docs/adr/` |

## 11. Autonomous backlog + idle cron (optional)

`AGENT_BACKLOG.md` is the prioritized work queue. An optional **idle cron** drains it: when the
owner is away, it takes the **top unblocked TODO**, works it to completion under all rules in
§3/§7 (flag-gate new features, never touch designated safety/prompt files, keep-older-data, write a
real test, run the local gate before any PR). Flag-dark + additive + all-green ⇒ may auto-merge;
otherwise leave the PR open + a note.

**Escalation:** if the previous item is unfinished or a decision is pending, hand the stalled item
to the **`system-architect`** agent. **When a decision is needed, go with the recommended (safe,
reversible, flag-dark) option and proceed** — block only for owner-gated calls: designated
safety/prompt changes, irreversible/destructive ops, or significant cost. **Re-rank the backlog
whenever an item is added.** Done items are kept (never deleted).
