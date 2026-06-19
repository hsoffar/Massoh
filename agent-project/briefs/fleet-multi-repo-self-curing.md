# Vision brief — the Fleet layer: multi-repo dashboard + cross-repo learning + self-curing engine

- **Status:** VISION / EPIC (captured, not started). Subsumes and sequences `massoh board`,
  `massoh learn`, and `massoh meta` into one north-star arc.
- **Captured:** 2026-06-19
- **Raised by:** owner
- **Relation to prior art:** the `massoh-autonomous-fleet` packet (shipped, single-repo) explicitly
  named *"No cross-repo fleet"* as its deferred non-goal. This brief is that deferred layer.
- **Memory:** see `[[massoh-fleet-vision]]`, `[[massoh-north-star]]`, `[[massoh-meta-improvement]]`.

## The ask (owner, paraphrased)
One dashboard to: **select the repos I'm working on**, **monitor what's actually being done per
repo** (tasks + interactions), keep a **centralized lessons-learned pool aggregated from agents
across repos**, and feed that back to **self-cure the master engine repo** so Massoh improves over
time. Each project stays separate; the engine gets better from all of them.

## Why it's sound (not scope creep)
It is the natural top of Massoh's existing architecture, not a new system:
- The engine is **already singular + global** (`~/.claude/agent-os`) = the "master agent repo."
- Every opted-in repo **already emits the exact telemetry** a fleet view rolls up:
  `AGENT_SYNC.md` (state) · `.agent_tasks/` (interactions) · `ledger.tsv` (cost) · `METRICS.md`
  (KPIs) · the board · `LEARNINGS.proposed.md` / `META.proposed.md` (lessons).
- `massoh work <repo>` is already the **repo selector** primitive; `massoh learn` / `massoh meta`
  already do per-repo learning + propose-only self-improvement.
The Fleet layer is a **read-only rollup + a gated promotion path**, not a rewrite.

## Architecture — three layers on top of what exists
```
   [ Fleet dashboard ]          ← selector + rollup across N repos
          ▲ reads (read-only)
   repoA   repoB   repoC        ← each already emits AGENT_SYNC · ledger · board · learn/meta
          │ promote  (GATED, de-identified, generalizable-only)
          ▼
   [ master engine ~/.claude/agent-os ]  ← self-cures → version bump → `massoh update` → whole fleet
```

1. **Fleet registry + selector.** Discover opted-in repos by scanning a root for `.massoh` markers,
   or a `~/.claude/massoh/fleet.tsv` registry. Answers "select / list the repos I work on."
2. **Fleet dashboard (read-only aggregator).** Roll each repo's existing state into one view —
   generalizes the `massoh board` → Plane work (one Plane workspace, **project-per-repo**). Answers
   "monitor per repo + tasks + interactions." Live granularity = **task-level** (stage, last-handoff
   agent/mode, `git worktree list`, blocked flag), refreshed; not keystroke-level.
3. **Cross-repo lessons → engine self-cure.** Pool every repo's `learn`/`meta` output into a global
   lessons set; `massoh-meta-engineer` proposes engine upgrades (policies, standards, role tweaks);
   gated adoption → VERSION bump → `massoh update` propagates to the whole fleet.

## THE one rule that makes this safe (the whole game): the promotion boundary
Only **generalizable, de-identified** lessons climb into the engine. **Project-specific facts and
secrets NEVER cross repos or enter the engine.** This extends Massoh's existing Portable / Project /
Memory split with an explicit *promotion gate*.
- promote ✓ — "reviewers repeatedly catch unguarded `grep` under `set -euo pipefail`" → engine standard.
- never ✗ — "client X's payment flow needs Y" → stays in repo X's project/memory.
Corollaries:
- **Self-cure stays PROPOSE-ONLY + gated + versioned.** The engine lives in *every* repo, so an
  auto-bad-change blasts the whole fleet. Never auto-mutate the engine. (The `massoh-meta-engineer`
  is already propose-only — the spine exists.)
- **Multi-tenant / privacy.** If repos are different clients, aggregation stays **local to the
  owner's machine**; each repo opts in to what (if anything) it contributes upward.

## Sequencing (slice by independent risk — the autonomous-fleet packet's own lesson)
1. **Per-repo board** — IN FLIGHT (`TASK-2026-06-19-massoh-board`, scoped BUILD, blocked on
   license-gate merge). Proves the single-repo visual surface.
2. **Fleet registry + read-only rollup** — list repos, aggregate their existing files into one
   dashboard. No engine writes. Pure read.
3. **Cross-repo lessons pool** — aggregate `learn`/`meta` outputs; tag each candidate lesson
   project-specific vs generalizable; hold them in a local pool. No promotion yet.
4. **Engine self-cure feed** — the meta-engineer consumes the pool → proposals → existing gate →
   version. The only step that touches the engine, and it stays propose-only.

## Honest caveats
- **"What each agent is doing right now"** across repos = same ephemeral-subagent limit: live state
  is task-level, not per-keystroke, unless SubagentStop harness hooks are added (already parked as a
  LATER item: live per-agent event feed).
- **Do not build the mega-dashboard at once.** Each slice above must be provable alone.

## Next step when picked
`/start-task` slice 2 (fleet registry + rollup) only after the per-repo board has merged — the board
is the reusable rendering/adapter substrate the fleet view builds on.
