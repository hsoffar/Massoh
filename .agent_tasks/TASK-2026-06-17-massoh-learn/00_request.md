# 00 — Request
**Task:** TASK-2026-06-17-massoh-learn · **Date:** 2026-06-17 · **Source:** owner
("implement most of buildermethods Agent OS ideas; focus on **learning from previous things**")

Build `massoh learn` — the **learning-from-previous loop**. Massoh's edge over Agent OS: Agent OS
mines the *codebase* for standards; Massoh has its own **work history** (packets, reviews, reverts,
decision log) — a richer source of "patterns refined over time."

`massoh learn` (read-only) **mines** completed task packets + git + the decision log and **proposes**
durable knowledge (drafts the owner promotes — never auto-writes into safety files):
- `.agent_tasks/*/06_review_result.md` (request-changes / reject findings) + `05` risks
  → recurring failure patterns → **STANDARDS.md Do/Don't** additions
- `git log` (reverts, `fixup`, repeated bug fixes) → lessons
- `AGENT_SYNC.md` decision log → repeated/irreversible decisions → **ADR drafts** (`docs/adr/`)
- durable facts → **memory** entry drafts (per `memory/SCHEMA.md` types: user|feedback|project|reference)

Seed example (from THIS project's history): the review gate twice caught bash-scope bugs
(parallel `local x=$1 y=$x` leak; `cmd || true` masking an injected-ceremony failure) → `learn`
should surface a STANDARDS Do/Don't: *"avoid one-line `local a=$1 b=$a`; don't let `|| true` mask a
real failure path."*

**Driven by the massoh-* agent team.** Classification: PRODUCT_SCOPE (entry). Owner authorized build
+ `bin/massoh*` edits. Branch: `feat/massoh-learn`. After this: explore how memory + decisions get
*created/promoted* (next conversation thread).
