# CHARTER — Massoh (constant context)

The unchanging facts every agent needs. Keep it short; details go in `docs/`.

## 1. Mission
Massoh is a **portable agent operating system for Claude Code**: install once globally, and any
repo you opt in gets a small gated software team (product-scope, architecture/safety, implementer,
reviewer/QA, system-architect, history-maintainer) plus guardrails, task packets, and an optional
idle-time autonomous mode. For solo owners shipping a real product with AI agents.

**North-star:** point Massoh at a product goal → a governed team ships it autonomously, efficiently,
**time/token/cost-aware**, learning from history, **reusing the harness** (never re-measuring what it
already reports). The moat = **governance + self-measurement + autonomy** coupled.
See `PRODUCT_STRATEGY.md` §North-star.

## 2. Current wedge (focus, NOT a permanent constraint)
Solo owner + **Claude Code** as the host harness, on a maintained product repo.
**Expansion principle:** today's wedge is selectable, not hard-coded
(`~/.claude/agent-os/policies/12_EXPANSION_READY_ARCHITECTURE.md`). Single-valued-for-now:
host harness = Claude Code (`.claude/agents`, `.claude/skills`). Multi-harness (`AGENTS.md`) is a NEXT.

## 3. Architecture (one paragraph + the seams)
Pure-bash CLI (`bin/massoh`) + a machine-readable boundary (`manifest.yml`). No runtime service.
`install` wires three planes: SOURCE repo → GLOBAL (`~/.claude`: namespaced `massoh-*` agents,
owned skills, `agent-os/` engine, a marker-gated block in `~/.claude/CLAUDE.md`) → HOST repo
(`massoh on` scaffolds `agent-project/`, `AGENT_SYNC.md`, `AGENT_BACKLOG.md`, `memory/`, `.massoh`).
The system itself is markdown convention executed by the model.
- **Swap seams** (small safe change points): `wire()` copy/symlink in `bin/massoh`; the per-repo
  scaffold list; the install/uninstall verb handlers.
- **API contract seam** (change both sides together): `manifest.yml` ↔ `bin/massoh` (install +
  uninstall + status must stay in sync with the manifest); the global block markers
  `<!-- massoh:start … <!-- massoh:end -->` ↔ `add_block`/`remove_block`.

## 4. Environment / how to run
- Run: `bin/massoh <install|update|on|off|enable|disable|status|work|uninstall> [--link]`.
- Test: **none yet** (gap — `bats` suite is a backlog item; until then, manual + `massoh status`).
- Deploy: `git push` to `github.com/hsoffar/Massoh`; users `massoh update`. No server. (Publishing a
  release / breaking the manifest contract is owner-gated.)

## 5. Conventions
- Commits: Conventional Commits; trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Branching: branch + PR per feature; default branch is `main`.
- Versioning: engine carries `manifest.yml version:`; product is `v0.1`. Bump on any change to the
  install/uninstall contract.
- Never commit: `.env*`, local config, build outputs, secrets, user `~/.claude` backups.
