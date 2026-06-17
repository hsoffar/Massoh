# 00 — Request
**Task:** TASK-2026-06-17-massoh-meta · **Date:** 2026-06-17 · **Source:** owner (flagship)

Build **`massoh-meta`** — the self-improvement engineer: a capability + role that watches Massoh's
OWN operation, finds bottlenecks/inefficiency/excess-comms/over-process, learns from repeated
mistakes, and turns findings into **gated engine upgrades shipped as new versions**. Memory:
[[massoh-meta-improvement]]; serves [[massoh-north-star]].

Two parts (product-scope to slice):
1. **`massoh meta` CLI verb** (read-only report) — mine the **ledger** (`.agent_tasks/ledger.tsv`:
   per-stage / per-task cost, stages far above mean), **rework** (packets with REQUEST-CHANGES before
   APPROVE), **backlog drift** (shipped items still TODO), and **repeated review findings** (a finding
   class seen in 2+ packets). Output ranked **bottleneck findings**. `--write-proposals` appends
   suggested backlog items to a proposals file (e.g. `agent-project/META.proposed.md`). Read-only;
   never mutates STANDARDS/memory/adr/AGENT_BACKLOG directly — proposes; the owner/gate promotes.
2. **A new role agent** `claude/agents/massoh-meta-*.md` — the process/efficiency engineer prompt
   (auto-installs via the manifest `massoh-*.md` glob): reads the ledger + packets + `massoh meta`
   output → files engine-upgrade backlog items, and **promotes recurring findings into ENFORCED
   checks** (e.g. add shellcheck to the gate so a class of bug is never hand-caught again).

Docs to update: `policies/02_AGENT_ROLES.md` + `OPERATING_SYSTEM.md` ("6 roles" → "7"), README role table.

**The self-improvement→version pipeline (already exists):** meta finds issue → backlog item → gate
(product-scope→arch/safety→implementer→reviewer) → PR → merge → VERSION bump → `massoh update`.
**Guardrail:** meta PROPOSES; engine self-changes stay gated + owner-approved; NEVER auto-merge engine
changes. Read-only, zero LLM spend (heuristic, like `learn`/`recommend`).

**Driven by the massoh-* agent team.** Classification: PRODUCT_SCOPE. Owner authorized build +
`bin/massoh*` + a new agent file (flagship selection). Branch: `feat/massoh-meta`.

Seed findings (this session's own data, what meta should surface): ~285k tokens/task via the full
4-agent gate (over-process for small fixes); 3 rev2s (arch/safety conditions → implementer checklist);
the bash `cmd||true`/one-line-`local` bug caught 3× (→ shellcheck lint); agents start cold + re-read
the repo ~50k tokens each (excess "communication" → context-pack); backlog drift.
