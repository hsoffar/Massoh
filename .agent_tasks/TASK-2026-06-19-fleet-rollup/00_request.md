# 00 — Request: `massoh fleet` — repo registry + read-only multi-repo rollup (24h queue #6)

- **Task ID:** TASK-2026-06-19-fleet-rollup
- **Date:** 2026-06-19
- **Raised by:** owner (24h queue #6); slice 2 of the Fleet epic [[massoh-fleet-vision]]
  (full brief: `agent-project/briefs/fleet-multi-repo-self-curing.md`).
- **Classification:** ARCHITECTURE_SAFETY → IMPLEMENTATION. New verb; owner **batch-authorized** +
  **auto-merge-on-green**.

## Goal (AGENT_BACKLOG acceptance stub #6)
`massoh fleet` lists opted-in `.massoh` repos under a root (or `~/.claude/massoh/fleet.tsv`) and
prints a per-repo rollup (stage counts from `.agent_tasks/TASK-*/`, blocked items, last-handoff
agent/mode from each repo's `AGENT_SYNC.md`). **READ-ONLY — writes to NO repo.** This is the first
multi-repo surface.

## Why this is the careful slice
The dangerous parts of the Fleet vision (cross-repo lessons promotion, engine self-cure) are NOT in
scope — this is purely a read-only aggregator/dashboard. The safety rule: it must never write into any
discovered repo, and must degrade gracefully on repos it can't read.

## Implementation shape
New `lib/verbs/fleet.sh` + dispatch line + usage. Discovery: scan a configurable root for `.massoh`
markers, or read an optional `~/.claude/massoh/fleet.tsv` registry. No manifest change (lib/verbs/ is a dir).

## Routing
`massoh-architecture-safety` → `03` (read-only-across-repos conditions + tests) → (batch-auth, no
fresh sign-off) → `04` → implementer → reviewer-qa → auto-merge on green. No merge dependency.
