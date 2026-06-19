# 00 — Request: `massoh board --local` renderer (24h queue #8)

- **Task ID:** TASK-2026-06-19-board-renderer
- **Date:** 2026-06-19 · owner (24h queue #8) · batch-authorized + auto-merge-on-green.
- **Classification:** ARCHITECTURE_SAFETY → IMPLEMENTATION.

## Goal (AGENT_BACKLOG acceptance stub #8)
`massoh board --local` emits a self-contained **HTML kanban** + an **Obsidian-Kanban `BOARD.md`**
from the same internal task model the Plane push already builds (`.agent_tasks/TASK-*/` stage =
highest packet file). **No network, no token, no jq required for the local path.** The offline
counterpart to the deferred local renderer (re-entry condition now met by owner request).

## Reuse, don't duplicate
The Plane adapter (`lib/verbs/board.sh`, merged v0.10.0) already builds the task model
(`_board_build_model`). The local renderer should reuse that model builder and add two emitters
(HTML, BOARD.md). Add a `--local` mode (and/or `--out <dir>`); the existing `--push plane` path is
unchanged.

## Risks for arch-safety
- **Write location safety:** where do `board.html` / `BOARD.md` go (default path vs `--out`)?
  create/overwrite policy — overwriting a GENERATED artifact is fine, but never clobber a
  hand-authored file; default to a clearly-generated path (e.g. `agent-project/board.html`) or require
  `--out`. Decide + condition.
- **HTML safety:** task titles/handoff text are interpolated into HTML → must be **HTML-escaped**
  (no injection / broken markup); BOARD.md cells sanitized (pipes/newlines) like the Plane path.
- **No jq for --local** (jq stays confined to the Plane push path); pure-bash/printf HTML+MD.
- Additive; `--push plane` behavior byte-identical; set -euo pipefail discipline.

## Routing
`massoh-architecture-safety` → `03` → (batch-auth) → `04` → implementer → reviewer-qa → auto-merge.
No merge dependency, but implement after #6/#9 land (all touch lib/verbs/board.sh or bin tree —
serialize; rebase for correct VERSION).
