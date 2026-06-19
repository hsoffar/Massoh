# 00 — Request: massoh board (task visualization) → Plane

- **Task ID:** TASK-2026-06-19-massoh-board
- **Date:** 2026-06-19
- **Raised by:** owner
- **Source:** owner question — "visualize tasks (kanban), see what each agent is doing, monitor
  backlogs, interface via an open-source project." Owner chose **self-hosted OSS → Plane**.

## Verbatim request
> is there a way that i can visualize tasks maybe through kanbans or some way to understand what each
> agent is doing right now, monitor backlogs, visually see what really happens — can i use open source
> projects to interface with and maintain such structure

## Decisions already taken (owner)
1. Surface class = **self-hosted OSS tool** (not local-only HTML/Obsidian, not GitHub Projects).
2. Tool = **Plane** (`makeplane/plane`) — REST API, Docker-compose stack (Postgres/Redis/web/api/worker).

## Context / why this is natural for Massoh
Massoh state is already board-shaped. The **column = the highest-numbered packet file present** in
`.agent_tasks/TASK-*/`:
`00 backlog → 01 scoping → 03 arch/safety → 04 licensed → 05 implementing → 06 review → merged (git)`.
Card metadata is derivable: title/desc from `00_request.md`/`01_product_scope.md`; priority +
status from `AGENT_BACKLOG.md`; "which agent / what mode" from `AGENT_SYNC.md` §Last handoff;
cost from `.agent_tasks/ledger.tsv`. **Source of truth = file existence + git, not the hand-kept
backlog table** (which is provably drifted today — e.g. backlog lists meta=DOING and license-gate=TODO
though both are done/in-review). A generated board cannot drift.

## MVP hypothesis (for product-scope to confirm / cut)
A read-only `massoh board` verb (same family as `review`/`plan`/`standup`) that:
(a) scans packet folders + git → an internal task model (id, title, stage, pri, last-agent, blocked?),
(b) `--push plane` upserts that model into a Plane project (states = the 7 stages; one issue per
task-id; idempotent by a stored id-map), reading the Plane base URL + API token from config/env.

## Scoping questions product-scope MUST resolve
1. **MVP cut:** is the local generator (internal model + a text/JSON dump) shipped first and Plane
   push second, or is `--push plane` the whole MVP? (Recommend: model + push together, one slice;
   local HTML/Obsidian deferred.)
2. **Sync direction:** push-only (Massoh → Plane, Plane is a read-only mirror) for MVP? Two-way
   (drag a card in Plane → reflected back) is much harder — defer with a re-entry condition.
3. **Identity / idempotency:** how is a packet matched to its Plane issue across runs (a local
   `.agent_tasks/.board-map.tsv`? a Plane field? the task-id in the issue title)? Append-only.
4. **Live "what's each agent doing now":** in/out of MVP? Agents are ephemeral subagents — true
   per-agent telemetry needs harness hooks (SubagentStop). Recommend: MVP shows *task-level* state
   (stage + last-handoff agent/mode + `git worktree list`); real-time hook-fed events = a later phase.
5. **Config surface:** where do `PLANE_BASE_URL`, `PLANE_API_TOKEN`, workspace/project slug live?
   (env vars? `agent-project/` config? Secrets must never enter git — guardrail.)
6. **Cost/safety posture:** confirm read-only against Massoh's own files (only writes are the
   id-map + outbound API calls); zero LLM; the push must degrade gracefully when Plane is unreachable
   (exit 0, no crash) — matches the `|| true` / degrade pattern of existing verbs.

## Routing
1. `massoh-product-scope` → `01_product_scope.md` (build/defer/kill + minimal cut + acceptance criteria).
2. If Build → `massoh-architecture-safety` (new verb touches `bin/massoh` + `manifest.yml` =
   safety-critical → owner sign-off required; plus an outbound-network + secrets-handling surface
   that is new for Massoh and needs explicit risk treatment) → `04` → implementer → reviewer.

## Implementation note (for later stages, not for product-scope)
The implementer MUST fetch **current Plane REST API docs** (via the context7 MCP / Plane docs) before
coding — Plane's API evolves (API-key header, workspace/project/issue + state endpoints). Do not code
the adapter from memory.

## Shortcuts taken
None. Full gated flow (touches safety-critical files + introduces an outbound-network/secrets surface).
