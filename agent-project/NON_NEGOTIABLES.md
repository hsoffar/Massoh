# NON_NEGOTIABLES — Massoh

The project's hard constraints. The Massoh guardrails (`09_GUARDRAILS.md`) are portable; this file
supplies the **project-specific** content the agents enforce literally. Fill every section.

## Designated safety-critical files / policies (no change without owner sign-off)
- `bin/massoh` — the install / uninstall / backup / block logic (touches the user's `~/.claude`).
- `manifest.yml` — the boundary of record. Any change here must move with `bin/massoh` in lockstep.
- The global-block markers `<!-- massoh:start` / `<!-- massoh:end -->` and
  `templates/CLAUDE.global-block.md` — the only always-read surface in every repo.
- `templates/CLAUDE.project.template.md` — the per-repo bootloader.

## Prohibited content (the product must never produce)
- An installer that **overwrites the user's own** `~/.claude/CLAUDE.md`, agents, or skills. Massoh
  only ever touches its own `massoh-*` namespace + the delimited block.
- A scaffold (`massoh on`) that overwrites an existing project file — **create-if-missing only**.
- An `uninstall` that removes anything not listed in `manifest.yml` / not `massoh-*`-namespaced.

## Advisory / over-claim rules (if the product is advisory)
N/A (developer tool, not an advisory product).

## Localization / UX invariants
- CLI must stay POSIX-bash, `set -euo pipefail`, no non-portable deps. Idempotent verbs.
- Every destructive global write is preceded by `backup_claude` (timestamped backup).

## Data + migration policy
- Keep older data: backup-before-write globally; create-if-missing per repo; never hard-delete a
  user's files. Decision-log + Done + Frozen rows are append-only — never deleted.
- Migrations: changes to the install/uninstall contract must be backward-compatible for one release
  (old layout still uninstalls cleanly).

## Feature flags
No runtime flags (CLI tool). Equivalent discipline: **new CLI behavior must be additive + reversible**;
a new verb defaults to no-op on existing installs; nothing changes a user repo without an explicit verb.

## Frozen (do not build without an explicit unfreeze)
See `AGENT_SYNC.md` §Frozen.
