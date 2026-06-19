# NOW / NEXT / LATER — Massoh

## NOW (in flight)
None. Shipped v0.1→v0.8: discover/doctor (v0.1), version+update-check (v0.2), cron (v0.3),
cadence ceremonies standup/review/plan (v0.4, PR #8), `massoh learn` (v0.5, PR #9/#10),
efficiency-v2 cycle-time/rework/recommend (v0.6, PR #12), `massoh ledger` (v0.7, PR #14),
`massoh meta` + 7th PROPOSE-ONLY role (v0.8, PR #15).

## NEXT (queued, agreed)
- Enforce the license-to-code gate mechanically (pre-commit / pre-push + CI check). *In flight —
  `feat/license-gate`, implemented (236/236 green), awaiting reviewer-qa.*
- **`massoh board` — task visualization → Plane** (self-hosted OSS kanban): generate a board from
  the packet folders + git; push via Plane's REST API. *Scoped — BUILD decision; BLOCKED on license-gate merge; routed to massoh-architecture-safety.*
- **Requirements Management & Traceability (RMT)** — opt-in engine capability: addressable
  `requirements/registry.yml` + per-project config + `req-check` CI validator; forward code/test/PR
  traceability; append-only + safety guard; no background automation. PROPOSE-ONLY. First adopter:
  elard. Full spec → `agent-project/briefs/RMT-requirements-traceability.md`.

## LATER (someday / maybe)
- **Fleet layer (EPIC / north-star)** — multi-repo dashboard + cross-repo lessons pool + self-curing
  engine. Sequenced: per-repo board (NEXT) → fleet registry + read-only rollup → cross-repo lessons
  pool → engine self-cure feed. Hard rule: only generalizable/de-identified lessons promote to the
  engine (PROPOSE-ONLY + versioned). Full brief → `agent-project/briefs/fleet-multi-repo-self-curing.md`.
- Emit `AGENTS.md` → multi-harness (Cursor / Codex / Antigravity).
- Profiles (global default + project override) + a single `config.yml`.
- Package as a Claude Code plugin / marketplace entry.
- Live per-agent event feed via SubagentStop hooks → real-time Plane card activity log. Re-entry: harness adds SubagentStop hook support AND owner requests live feed view.

## FROZEN (do not build without an explicit owner unfreeze)
None yet. Mirror the authoritative list in `AGENT_SYNC.md` §Frozen.

## DEFERRED / KILLED (kept — never deleted)
| Item | Decision | Reason | Re-entry condition | Date |
|---|---|---|---|---|
| Multi-harness (`AGENTS.md`) | Defer | Prove Claude-Code flow first | ≥2 repos through gates | 2026-06-16 |
| `massoh board --local` (HTML/Obsidian renderer) | Defer | No visual surface without push; Plane satisfies MVP need | Owner reports Plane unavailable or requests offline renderer | 2026-06-19 |
| Two-way Plane sync (Plane → Massoh) | Defer | Split-brain risk; no daemon to poll; destructive local writes | Explicit owner request + arch-safety-approved conflict protocol + daemon/webhook surface | 2026-06-19 |
