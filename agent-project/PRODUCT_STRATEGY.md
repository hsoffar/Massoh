# PRODUCT_STRATEGY — Massoh

## North-star / global goal (decided 2026-06-17)
**Point Massoh at a product goal → a governed team of agents ships it** — autonomously, efficiently,
**aware of time, task-duration, and tokens/cost**, **learning from its own history**, and **without
reinventing the wheel** (reuse the harness + existing tools; build only the differentiator).

**Differentiator (the moat):** the only system that couples **governance + self-measurement +
autonomy**. Others ship a team (subagent collections) *or* a runtime (OpenClaw) — Massoh ships a
*governed, self-measuring, autonomous* team. Precision = the gate; efficiency = the
review→recommend→learn loop; autonomy = cron.

**Reuse, don't rebuild:** the Claude Code harness already reports **tokens + duration per agent run**
— Massoh *captures + persists + analyzes* it, never re-measures. Reuse subagents / Tasks / Hooks /
cron. Do **not** rebuild OpenClaw (a runtime/daemon) — Massoh is the governance method that runs
inside one.

**Roadmap to the goal:** measure (`review`-v2) · diagnose (`recommend`) · learn (`learn`) — done →
**time/token/cost ledger** (understand cost per task type) → **`decide`/`promote`** (ledger + lessons
become durable memory + ADRs) → **goal-decomposed, budget-aware autonomy** (cron drains a backlog
derived from a stated product goal).

## Positioning — "post-agile for agents" (decided 2026-06-16)
Keep agile's **empirical core** (iterate, small increments, test against reality, inspect-and-adapt,
retrospective learning) — those fight *uncertainty in software*, which agents face too. **Drop the
human-coordination ceremony** (sprints, standups, story points, velocity) — agents sync instantly via
files + run in parallel, so those are pure overhead. **Add what agile under-specifies: hard gates**
(license-to-code, owner-gated safety, auditable packets) — agents move fast and can do irreversible
damage cheaply. Pitch: *"agile's discipline without agile's meetings — enforced, auditable, for AI
agents."* **Focus software now; keep the engine domain-neutral** (wedge is selectable per CHARTER —
do not generalize before it's proven).

## Current strategic mode (v0.3 shipped)
Validate: does a **portable, gated** agent OS actually reduce build-trap / scope-creep / knowledge
drift for a solo owner shipping with Claude Code — enough to install it in a second real repo?
(v0.1→v0.3 shipped on itself: discover/doctor/version/cron, all through the gate.)

## Activation metric
A repo runs `massoh on` **and** takes one task through the full gate (packet `00 → 06`) to a merge.
Within ~7 days of install. (Dogfood instance: this repo, as of 2026-06-16.)

## Bets + non-bets
- Betting on: opt-in marker model (inert elsewhere), one hard license-to-code gate, auditable
  packets, clean install/uninstall. Governance is the differentiator.
- Explicitly NOT now (re-entry condition): multi-harness output (`AGENTS.md`) — re-enter once the
  Claude-Code flow is proven on ≥2 repos. A hosted/SaaS layer — not while it's a local tool.

## Segments
- Primary (now): solo founder / single maintainer using Claude Code on one product.
- Long-term (moat, not current focus): small teams wanting auditable AI-agent governance + the
  borrowed "standards discovery" input layer feeding the gates.
