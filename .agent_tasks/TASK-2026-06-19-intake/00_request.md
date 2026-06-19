# 00 — Request: `massoh intake` (idea triage) — 24h queue #4

- **Task ID:** TASK-2026-06-19-intake
- **Date:** 2026-06-19
- **Raised by:** owner (24h queue #4); vision [[massoh-idea-intake]]
- **Classification:** ARCHITECTURE_SAFETY → IMPLEMENTATION. New verb; owner **batch-authorized**
  `bin/massoh` edits + **auto-merge-on-green** (AGENT_SYNC decision log 2026-06-19).

## Goal (from AGENT_BACKLOG acceptance stub #4)
`massoh intake "<idea>"` — appends a ranked TODO row to `AGENT_BACKLOG.md` (value×safety priority if
unstated) + a one-line memory pointer; idempotent; **never edits existing rows**; read-only elsewhere.
Absorb a fast-firing owner without dropping or mis-ordering ideas.

## Why this matters for safety (note for arch-safety)
This verb WRITES to `AGENT_BACKLOG.md` — a file with an **append-only** Done/Frozen rule
(NON_NEGOTIABLES §Data+migration). The orchestrator already tripped this rule once this session
(deleting Done rows), so the write discipline here is the central risk. Mirror the write-safety
precedent of `cmd_ledger`/`cmd_learn`/`cmd_meta` (named target var, sanitized fields, single append,
`|| true` on reads, degrade exit 0).

## Implementation shape (modularization win)
New `lib/verbs/intake.sh` (verb logic) + one dispatch line in `bin/massoh` + `intake` in usage. The
manifest already lists `lib/verbs/` as a dir, so **no manifest change needed**.

## Routing
`massoh-architecture-safety` → `03_architecture_safety.md` (write-safety conditions + tests) →
(batch-authorized, no fresh sign-off) → `04` → `massoh-implementer` → `massoh-reviewer-qa` →
auto-merge on green.
