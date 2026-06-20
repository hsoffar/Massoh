# 00 — Request: Fleet slice 3 — `massoh fleet learn` (cross-repo lessons → engine proposals)

- **Task:** Fleet slice 3 (24h-vision part 3). Architect platform review already endorsed the CLI
  propose-only path (`00_architecture_review.md` §4); the browser button is PARKED (inherits 1c).
- **Owner away-grant** covers it IF zero-spend + propose-only + read-only on repos.

## Goal
`massoh fleet learn` — aggregate every discovered repo's existing learning proposals
(`agent-project/LEARNINGS.proposed.md`, `META.proposed.md`) into a consolidated, de-identified,
recurrence-ranked pool written to THIS repo's `agent-project/FLEET_LEARNINGS.proposed.md`. The owner
(or a later gated meta-engineer task) promotes generalizable ones into the engine. **Never mutates the
engine; never writes to other repos.**

## Must be (mirror learn/meta)
- **Zero LLM, zero network, zero spend** — deterministic heuristic ONLY (like `massoh learn`/`meta`).
  No `claude -p`, no agent invocation. (Invoking the meta-engineer agent = paid spend = PARKED.)
- **Read-only against discovered repos** — only reads their `*.proposed.md`; writes NOTHING to them (FL1).
- **Write target = exactly one file here:** `agent-project/FLEET_LEARNINGS.proposed.md` (propose-only;
  regenerate-with-sentinel or append; never the engine policies/bin/manifest).

## The promotion boundary (THE safety rule — arch-safety must nail this)
- Do NOT auto-de-identify-and-promote into the engine. Instead: cluster lessons by recurrence; flag
  ones seen across **≥2 repos** as "generalizable candidates" for owner review; keep project-specific
  ones **tagged by source repo**, NOT promoted. The actual generalization + engine adoption is a
  separate gated step (owner / meta-engineer), never this verb.
- Strip/avoid leaking secrets + obvious project-identifiers into the consolidated doc where feasible;
  but the real guard is "candidates only, owner promotes," not heuristic auto-de-identification.

## Routing
`massoh-architecture-safety` (focused: promotion boundary, write surface, zero-LLM/zero-spend, read-only)
→ `04` → `massoh-implementer` → `massoh-reviewer-qa` → auto-merge on green. The browser button + any
engine adoption remain PARKED for owner.
