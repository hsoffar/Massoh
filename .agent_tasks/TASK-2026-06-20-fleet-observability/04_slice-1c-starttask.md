# 04 — License: Fleet slice 1c — start-task panel (READ-ONLY; POST parked)

- **Gate:** architect `00_architecture_review.md` §4 — build the form READ-ONLY; the live HTTP-write is
  a NEW safety-critical risk class, **PARKED for owner**. Away-grant covers the read-only part.
- **Branch:** `feat/fleet-starttask`. **VERSION → 0.22.0**; CHANGELOG [0.22.0].

## Scope (read-only affordance only)
Add a **"Start a task"** panel to the repo view (`/repo/<name>`): render the exact copy-paste commands
to start a task in that repo + a clear note that one-click submit is owner-gated (coming). **No POST
endpoint** — POST stays 404. HTML in bash (Seam A); escape the repo name/path.

Panel content (rendered, escaped):
- `cd <repo-abs-path> && massoh intake "<your idea>"`  — queue it (append-only inbox)
- `massoh work <repo>`  then  `/start-task "<your idea>"`  — build it interactively
- A muted note: "Live one-click submit from the dashboard is owner-gated — parked pending sign-off."

Optional (only if trivial + safe): a vanilla inline JS that updates a `<code>` block via **textContent**
(never innerHTML, no eval, no network, no fetch) as the user types an idea — purely client-side
convenience. If it adds any complexity, SKIP it and ship the static commands.

## Mandatory conditions
- **NO POST handler / no server-side write / no exec** — POST → 404 (the architect park). The panel is
  display-only; the user runs the commands in their own shell.
- HTML-escape the repo name + abs path via `_board_html_escape`. If the optional JS is used: insert
  user text via `textContent` only (DOM-XSS-safe); no `innerHTML`, no `eval`, no network.
- Loopback-only; GET-only; read-only against all repos (byte-snapshot still holds).
- set -euo pipefail.

## Required tests (T-FS-* additive)
- `/repo/<name>` now contains the "Start a task" panel with the `massoh intake`/`massoh work` commands
  + the parked note; repo name escaped.
- **POST to any route still → 404** (assert the park holds — no write path).
- read-only byte-snapshot unchanged; loopback + no-orphan still hold.
- (if JS added) the script uses textContent, has no `innerHTML`/`eval`/`fetch` (static grep).
Run `bash test/run.sh` green.

## Acceptance
1. Conditions (file:line). 2. Tests green; suite green; paste the panel HTML + the POST→404 proof.
3. VERSION 0.22.0 + CHANGELOG. 4. No safety-critical file; no POST/exec; bin/massoh + manifest untouched.

## PARKED (owner): the live POST→intake submit (one-click start from the browser) — separate slice,
needs owner sign-off (first HTTP-input-to-write). This slice ships the read-only affordance only.

## Routing
`massoh-implementer` (branch `feat/fleet-starttask`) → `05` → `massoh-reviewer-qa` → auto-merge on green.
