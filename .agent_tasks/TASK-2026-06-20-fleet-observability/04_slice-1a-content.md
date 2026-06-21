# 04 — License: Fleet slice 1a — dashboard content (index + repo KPI views + nav)

- **Gate:** architect `00_architecture_review.md` (N1–N7, Seam A/B) = arch authority; owner away-grant. Read-only GET slice → PROCEED. No safety-critical file.
- **Branch:** `feat/fleet-dashboard`. **VERSION → 0.20.0** (fleet serve now user-useful); CHANGELOG [0.20.0].

## Scope
Make `massoh fleet serve` render real content. Two GET pages, **HTML rendered + escaped IN BASH**
(Seam A — reuse `_board_html_escape` from lib/verbs/board.sh); the python server is a transport that
routes + streams bash stdout (Seam B). Read-only against all repos (FL1).

- **`/` Fleet index:** discover repos (reuse `massoh fleet` discovery) → a table/cards, one row per
  repo with KPIs: open/blocked task counts (from `.agent_tasks/` stages), throughput/wk + rework% +
  cycle-days (from `massoh review`/METRICS if present), tokens + cost (from `ledger.tsv`), last-handoff
  agent/mode (AGENT_SYNC), version. Each repo links to its repo page.
- **`/repo/<name>` Repo view:** KPI panel on top + the repo's kanban (reuse `massoh board --local`
  rendering) + task list (stage · last-handoff) + recent commits (git log). Breadcrumb → `/` + quick
  links to sibling repos (A↔B nav).

## Mandatory conditions (extend N1–N7)
- **Route allowlist (critical):** routes = `/` and `/repo/<name>`. `<name>` is **validated against the
  discovered-repo set** — if not a known repo, 404. **Never** use `<name>` as a filesystem path
  (no join/translate); no `..`/encoded traversal can escape (the set-membership check is the guard).
- **HTML escaping in bash:** every interpolated value (repo names, titles, handoff text, commit msgs)
  through `_board_html_escape`. No raw interpolation. (Seam A — escaping in bash, not python.)
- **Loopback-only** (N1, unchanged); **GET-only** (no POST — start-task form is slice 1c, parked).
- **Read-only on repos** (FL1): no write to any discovered repo; only reads (find/grep/git/cat guarded).
- **Reuse, don't recompute:** KPIs come from the existing verbs/files (review/METRICS/ledger/fleet);
  the server/renderer aggregates, doesn't reimplement metric logic.
- set -euo pipefail; degrade gracefully per repo (a repo missing METRICS/ledger → show "—", never crash).

## Required tests (T-FS-* additive; suite 476 → target ~488)
- index renders ≥2 fake repos with their KPI cells; each links to `/repo/<name>`.
- `/repo/<known>` renders KPI panel + board + task list; `/repo/<unknown>` → 404; `/repo/..%2f..` → 404.
- HTML-escape: a fake task title with `<script>`/`&`/`"` → escaped in output (no raw `<script>`).
- read-only: byte-snapshot 2 fake repos before/after a full index+repo render → unchanged.
- loopback-only still holds; clean lifecycle (no orphan); python3 guard.
Run `bash test/run.sh` green.

## Acceptance
1. N1–N7 + the above (file:line). 2. Tests green; suite green; paste a rendered-index sample + the
escape proof + the read-only byte-snapshot. 3. VERSION 0.20.0 + CHANGELOG. 4. No safety-critical file
changed; bin/massoh untouched (fleet dispatch covers it); manifest untouched (scripts/ glob).

## Rollback
Revert PR; the serve skeleton remains. Additive.

## Routing
`massoh-implementer` (branch `feat/fleet-dashboard`) → `05` → `massoh-reviewer-qa` → auto-merge on green.
