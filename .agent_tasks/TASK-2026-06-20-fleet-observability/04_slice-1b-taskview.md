# 04 — License: Fleet slice 1b — task drill-down view

- **Gate:** architect `00_architecture_review.md` (N1–N7, Seam A/B) + away-grant. Read-only GET → PROCEED. No safety-critical file.
- **Branch:** `feat/fleet-taskview`. **VERSION → 0.21.0**; CHANGELOG [0.21.0].

## Scope
Add a third GET page: **`/repo/<name>/task/<task-id>`** — a task's packet trail + cost. HTML rendered +
escaped IN BASH (Seam A); server routes + streams (Seam B). Read-only.
- Render the packet stages present (`00_request` → `06_review_result`, plus any `0N_*`/handoff/proposal
  files): for each, show which stage + a short who/what (derive from the file's role + first line/title;
  do NOT dump full file bodies — link/label only, keep it an index).
- Show that task's **ledger cost** (rows in `.agent_tasks/ledger.tsv` for the task-id → per-stage
  tokens/seconds + totals).
- Breadcrumb: `/` → `/repo/<name>` → task. Link back to the repo board.

## Mandatory conditions
- **Route allowlist + double set-membership (critical):** `<name>` validated against discovered repos
  (as 1a); `<task-id>` validated against THAT repo's discovered task set (`.agent_tasks/TASK-*/`
  basenames) — membership check, **never used as a filesystem path**; unknown name OR task → 404;
  traversal/encoded → 404.
- **HTML-escape every interpolated value** (`_board_html_escape`): task-id, stage names, titles/first-lines,
  ledger numbers, commit refs. No raw interpolation. Stage "who/what" text is repo content → treat as data, escape it.
- **No full-body dump:** show stage presence + a one-line label only (avoid leaking large/sensitive file
  contents into the page); keep it an index (scope guard).
- Loopback-only; GET-only (no POST); read-only against all repos (byte-snapshot); set -euo pipefail +
  per-task graceful degrade (no ledger rows → "no cost recorded"; missing stage → omit, never crash).

## Required tests (T-FS-* additive; suite 504 → ~514)
- `/repo/<known>/task/<known>` → 200 with the stage list + cost; `/repo/<known>/task/<unknown>` → 404;
  `/repo/<known>/task/..%2f..` → 404; `/repo/<unknown>/task/x` → 404.
- escape: a task whose `00_request` first line contains `<script>` → escaped in the drill-down (no raw `<script>`).
- read-only byte-snapshot of fake repos across a full index+repo+task render → identical.
- no-full-body: a large/multi-line packet file is NOT dumped verbatim (assert only the label/first-line appears).
- loopback + no-orphan still hold. Run `bash test/run.sh` green.

## Acceptance
1. Conditions (file:line). 2. Tests green; suite green; paste a drill-down sample + escape proof +
read-only snapshot + the double-404 (unknown name / unknown task). 3. VERSION 0.21.0 + CHANGELOG.
4. No safety-critical file; bin/massoh + manifest untouched.

## Rollback
Revert PR; index + repo views remain. Additive.

## Routing
`massoh-implementer` (branch `feat/fleet-taskview`) → `05` → `massoh-reviewer-qa` → auto-merge on green.
