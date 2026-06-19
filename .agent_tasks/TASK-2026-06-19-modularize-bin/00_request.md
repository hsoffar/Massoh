# 00 — Request: modularize bin/massoh → sourced verb files (24h queue #3)

- **Task ID:** TASK-2026-06-19-modularize-bin
- **Date:** 2026-06-19
- **Raised by:** owner (24h queue item #3)
- **Classification:** ARCHITECTURE_SAFETY → IMPLEMENTATION (pure refactor of the safety-critical file).

## Goal
Extract each `cmd_*` from the monolithic `bin/massoh` into sourced files under `lib/verbs/<verb>.sh`,
loaded by `bin/massoh` at startup. **Pure extraction — zero behavior change.** This is the leverage
move that lets future verb tasks run in parallel worktrees without colliding on one giant file.

## Why now
`bin/massoh` is the serialization bottleneck for the whole 24h queue — 8 of 12 items touch it, so
they can't parallelize. Modularizing first removes that bottleneck.

## Authorization
Owner **batch-authorized** `bin/massoh` edits for queue items #3–#11 (recorded in `AGENT_SYNC.md`
decision log, 2026-06-19). No fresh per-item sign-off needed for this item; arch-safety + reviewer-qa
+ green tests still gate it; PR left open for owner merge.

## Hard constraints (this is THE safety-critical file)
- **Byte-identical CLI behavior.** Every existing verb produces the same output + exit codes.
- **Full test suite stays green** (currently 280 after board; this task adds no features).
- `manifest.yml` updated in lockstep to list the new `lib/verbs/` files (install must wire them).
- `install`/`uninstall`/`backup_claude`/`add_block`/`remove_block` logic unchanged in behavior.
- POSIX-bash, `set -euo pipefail`, no new deps. Sourcing must be robust (absolute path resolution
  from the script's own location, not cwd).
- Pure extraction only — **no logic rewrites, no opportunistic cleanup** (Guardrail: no broad refactor
  beyond the agreed scope).

## Shortcuts taken (recorded)
Product-scope skipped — agreed infrastructure refactor, not a build/defer/kill decision; owner
batch-authorized. Straight to `massoh-architecture-safety` to define safe-extraction conditions +
tests, then implementer, then reviewer-qa.

## Routing
`massoh-architecture-safety` → `03_architecture_safety.md` → (no fresh sign-off; batch-authorized) →
`04_implementation_packet.md` → `massoh-implementer` (after board #1 merges, to avoid conflicting on
`bin/massoh`) → `massoh-reviewer-qa` → owner merge.

## Dependency
**Implementation must start after board (#1) merges to main** — both touch `bin/massoh`; modularizing
must operate on the post-board `bin/massoh` (which includes `cmd_board`). Arch-safety (read-only) may
proceed now.
