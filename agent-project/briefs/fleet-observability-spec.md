# Spec — Massoh Fleet: agent observability + self-learning platform

- **Date:** 2026-06-20 · owner-approved design (brainstormed). Extends `[[massoh-fleet-vision]]`
  (`agent-project/briefs/fleet-multi-repo-self-curing.md`).
- **Status:** APPROVED design; building under an **8-hour owner-away autonomy grant** (proceed on
  recommended defaults; consult `massoh-system-architect`; steer by the vision; auto-merge-on-green).

## Vision
A local **observability + control plane** over many Massoh repos: select a project, monitor its
agents/tasks/KPIs, navigate project→project, and accumulate cross-repo learning that is proposed
(gated) back into the master engine — which then self-updates and propagates via `massoh update`.
"The ultimate self-learning system," kept safe by: read-only on repos, PROPOSE-ONLY on the engine,
127.0.0.1-only, zero browser-side spend.

## Decomposition (each sub-project = its own spec → Massoh gate)
1. **Observability dashboard** (`massoh fleet serve`) — verbose, KPI-first; index → repo → task drill-down; A↔B nav.
2. **Engine-as-separate-repo** — **DEFERRED** (owner: this repo stays the engine for now).
3. **Self-learning loop** — `massoh fleet learn`: aggregate cross-repo lessons → meta-engineer PROPOSE-ONLY → engine proposals → owner adopt → `massoh update` propagates.

## Architecture (sub-project 1 + 3)
- **Thin server:** `massoh fleet serve [--port 8787]` → Python-stdlib `http.server` bound to
  **127.0.0.1 only**. Opt-in Python dep (bash CLI stays dep-free). The server is thin — each request
  shells the existing verbs and serves their output; **bash remains the source of truth**, the server
  holds no business logic. File: `scripts/massoh-dashboard`.
- **Reuse:** `massoh fleet` (discovery + rollup), `massoh board --local` (per-repo kanban HTML),
  `massoh review`/`METRICS.md` (KPIs), `ledger.tsv` (tokens/cost), `AGENT_SYNC.md` (last-handoff),
  packet folders (task stages), git log (commits).
- **Self-contained HTML** like `board --local` (sentinel-marked), meta-refresh 30s.

## Views (sub-project 1)
- **Fleet index:** every opted-in repo (`.massoh` scan / `~/.claude/massoh/fleet.tsv`) + KPI summary
  row: open/blocked tasks · throughput/wk · rework% · tokens/cost · last-handoff agent/mode · version.
- **Repo view:** KPI panel (cycle-days, rework%, throughput, cost) on top + kanban + task list
  (stage · last-handoff) + recent commits. Breadcrumb to fleet + sibling-repo links (A↔B nav).
- **Task drill-down:** a task's packet trail (00→06, who/what per stage) + that task's ledger cost.

## Actions (the only side effects; later slices)
- **Start task** (1c): form (repo + idea) → POST → `massoh intake "<idea>"` in that repo
  (append-only) → returns the launch command. **No server-side exec, no token spend.**
- **Update master learning** (3): button → `massoh fleet learn` → meta-engineer PROPOSE-ONLY drafts
  de-identified/generalized engine proposals → master proposals doc → owner adopts via the gate.

## Build order (each its own gate)
`0 ledger-capture` → `1a index + repo KPI views + A↔B nav` → `1b task drill-down` → `1c start-task`
→ `3 fleet learn + button`.

### Slice 0 — ledger capture (prereq; KPIs are empty without it)
Orchestrator-called `massoh ledger add <task-id> <stage> <tokens> <seconds>` per stage (RE-ENTRY-C
from the deferred auto-ledger #5 — feasible today; the orchestrator has token+time per subagent).
Deliver: backfill this session's real per-stage costs into `ledger.tsv` (append-only) + document the
convention. Small; non-safety-critical (append-only TSV write the ledger verb already guards).

## Safety (whole platform)
- 127.0.0.1 bind only (no remote). **Read-only against every discovered repo** (the FL1 write-isolation
  rule, proven in `massoh fleet`). Only writes: `intake` (append-only inbox) + `fleet learn` proposals
  (propose-only, gated). No secrets. **Zero token spend from the browser.** Engine never auto-mutated.
- Promotion boundary (self-learning): only generalizable, de-identified lessons reach the master;
  project-specific facts/secrets never cross repos or enter the engine.

## Honest limits
- Agent monitoring is **task/stage/cost-level, refreshed** — not keystroke-live (no SubagentStop
  telemetry; deferred). KPI richness == ledger capture coverage.

## Autonomy envelope (8h owner-away)
- Proceed on **recommended defaults** (table in the session handoff); consult `massoh-system-architect`
  for architecture calls; steer by this spec + the vision.
- Each slice: arch-safety → implementer → reviewer-qa → **auto-merge on green**. bin/massoh edits for
  the new verbs are **pre-authorized** under this grant (same model as the 24h-queue batch-auth) —
  arch-safety + reviewer + green still required per item; PRs reviewable post-hoc.
- **PARK for owner return (do NOT do unattended):** anything irreversible; real paid-API spend;
  engine **adoption** of self-learning proposals (drafts only); engine-extraction (#2); any NEW
  safety-critical risk class the architect says needs human eyes. Park with a clear queued decision;
  continue other independent slices meanwhile.

## Testing
Fake-repo fixtures (2+ `.massoh` temp repos): index renders both; repo view renders KPIs+board; task
drill-down renders a packet trail; POST intake appends to the right repo + writes nothing elsewhere
(byte-snapshot); server binds 127.0.0.1 only; server starts/stops cleanly in tests (no lingering proc).
