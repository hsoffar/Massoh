# 00 — Request: emit AGENTS.md from the roles (24h queue #10)

- **Task ID:** TASK-2026-06-19-agentsmd
- **Date:** 2026-06-19 · owner (24h queue #10) · batch-authorized + auto-merge-on-green.
- **Classification:** ARCHITECTURE_SAFETY → IMPLEMENTATION.
- **Note:** the LATER re-entry condition ("≥2 repos through gates") is waived — owner placed it in the
  24h queue. This is the generator only (a first multi-harness step), not full multi-harness support.

## Goal (AGENT_BACKLOG acceptance stub #10)
A verb that generates an `AGENTS.md` from the installed role files (`claude/agents/massoh-*.md`) — the
emerging cross-harness convention (Cursor/Codex/Antigravity read `AGENTS.md`). Idempotent; opt-in verb.

## Scope intent
New verb (e.g. `massoh agents-md` / `massoh emit-agents`) reading the 7 role files' frontmatter
(name + description + "edits code?") → write a single `AGENTS.md` summarizing the team + the gated
workflow pointer. Generated artifact (sentinel-marked); overwrite only if generated; refuse if
hand-authored. No network, no LLM.

## Risks for arch-safety
- Write location + clobber policy (generated-sentinel like #8's `<!-- massoh-generated -->`; refuse on
  hand-authored AGENTS.md).
- Read role frontmatter safely (data only; cap; sanitize into markdown — pipes/newlines).
- Additive; no manifest change (new verb in lib/verbs/); set -euo pipefail; degrade if no role files.
- Scope guard: emit a SUMMARY index, do NOT dump full role bodies (keep it a pointer doc).

## Routing
`massoh-architecture-safety` → `03` → (batch-auth) → `04` → implementer → reviewer-qa → auto-merge.
Implement after #9/#8 land (serialize on main tree; rebase for VERSION). Likely v0.16.0.
