# 04 — License: Control plane track A, slice A1 — ops read panels

- **Gate:** architect `TASK-2026-06-20-fleet-observability/00_architecture_review.md` (N1–N7, read slices) + away-grant. Read-only GET → PROCEED. No safety-critical file.
- **Branch:** `feat/fleet-ops`. **VERSION → 0.24.0**; CHANGELOG [0.24.0].

## Scope (read-only panels on the existing repo view `/repo/<name>`)
Extend `_fleet_render_repo` (lib/verbs/fleet.sh) with three READ panels, HTML in bash (Seam A), escaped:
1. **Queue / tickets:** the repo's `AGENT_BACKLOG.md` — open TODO + BLOCKED rows (the "tickets"/queue)
   + the `## Intake inbox` rows. Show pri + item + status.
2. **Cron:** read-only `massoh cron status`-equivalent for the repo (is cron configured? schedule line?
   last tick if recorded) — READ ONLY, never run/modify cron.
3. **Workflow:** the active tasks' current stage (highest packet file per in-flight TASK-*) as a
   compact gated-workflow view (00→06 where each in-flight task sits).

## Mandatory conditions (read-only; same model as 1a/1b)
- Loopback-only; **GET-only** (no POST/write/exec — control actions are track B, owner-gated, separate).
- Read-only against all repos (byte-snapshot proven); cron panel must NOT invoke a cron-mutating path
  (read status only).
- HTML-escape every interpolated value via `_board_html_escape` (backlog text, cron lines, task ids).
- set -euo pipefail; degrade per panel (missing AGENT_BACKLOG/cron → "—", never crash).
- No new routes needed (panels render inside `/repo/<name>`); no path-from-URL.

## Required tests (T-FS-* additive)
- `/repo/<name>` now contains Queue (TODO/BLOCKED + inbox), Cron, Workflow panels with escaped content.
- read-only byte-snapshot of fake repos across render unchanged; loopback + no-orphan hold; POST still 404.
- a backlog row with `<script>`/`|` → escaped.
Run `bash test/run.sh` green.

## Acceptance
1. Conditions (file:line). 2. Tests green; suite green; paste a repo-view sample showing the 3 panels +
escape proof + read-only snapshot. 3. VERSION 0.24.0 + CHANGELOG. 4. No safety-critical file; POST=404;
bin/massoh + manifest untouched.

## Routing
`massoh-implementer` (branch `feat/fleet-ops`) → `05` → `massoh-reviewer-qa` → auto-merge on green.
