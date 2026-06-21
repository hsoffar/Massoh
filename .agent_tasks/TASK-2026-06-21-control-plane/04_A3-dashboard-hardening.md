# 04 — License: Control plane track A, slice A3 — dashboard hardening (3 filed bugs)

- **Gate:** the three inbox issues below already carry acceptance criteria (filed by the gate during
  earlier slices) → qualifies as "approved issue with acceptance criteria" (Hard rule #1). Read-only
  fixes to existing fleet routes; same read-only GET-over-loopback risk class as 1a/1b/A1/A2 →
  **ships under the 8h away-grant; no fresh owner sign-off.**
- **Branch:** `feat/fleet-hardening` (off current main, v0.26.0 — serialize after A2; touches
  fleet.sh/dashboard). **VERSION → 0.27.0**; CHANGELOG [0.27.0].

## Scope — fix exactly these three (AGENT_BACKLOG intake inbox #20/#19/#21)
1. **#20 (P1) — task list not clickable.** On `/repo/<name>`, the in-flight/known task list shows
   task ids as plain text. Make each an `<a href="/repo/<name>/task/<id>">` to the existing drill-down.
   Escape the id in BOTH the href and the text. No new route — link to the route that already exists.
2. **#19 (P3) — routes 404 until restart.** The `repo_name_map` (and any per-repo file/task maps) are
   built once at server startup, but the index re-discovers repos per request → a repo added to
   `fleet.tsv` after launch 404s until restart. Fix: **rediscover per request** (rebuild the
   name→path map on each request, same source the index uses), OR if per-request rebuild is too costly,
   document the restart requirement AND make it consistent (index must not show a repo the routes 404).
   Prefer per-request rebuild for correctness; keep it O(repos) cheap.
3. **#21 (P3) — broad pkill in test teardown.** Any test that stops a dashboard via
   `pkill -f massoh-dashboard` (or similar broad match) must instead kill ONLY the test server's own
   PID/port. A broad pkill kills the owner's live dashboard. Sweep test/run.sh for broad-match
   teardown and scope every one to the spawned PID.

## Mandatory conditions
- Read-only / GET-only preserved (POST still → 404); loopback-only unchanged; no new write/exec.
- #20: escape id in href + text via `_board_html_escape`; only link to the **existing**
  `/repo/<name>/task/<id>` route; unknown/again-404 behavior unchanged.
- #19: per-request rebuild must use the SAME discovery source as the index (no drift: if the index
  lists a repo, its routes must resolve in the same request). No path-from-URL introduced.
- #21: every test-spawned server torn down by its own PID (capture `$!` / the printed PID); ZERO
  `pkill`/`killall` broad-match against massoh-dashboard anywhere in test/run.sh. The live 8787
  dashboard must survive a full `bash test/run.sh`.
- `set -euo pipefail`; degrade safe; bin/massoh + manifest.yml + safety-critical files diff = 0.

## Required tests (additive; live-HTTP style)
- #20: `/repo/<name>` contains `href="/repo/<name>/task/<id>"` for a known task; clicking that href
  (GET) → 200 (the drill-down); id escaped.
- #19: start server, add a repo to a temp fleet registry AFTER launch, request it → resolves in the
  same run WITHOUT restart (or, if documented-restart path chosen, index and routes agree — no
  index-shows-but-route-404 split). Pick one and test it.
- #21: a test asserting no broad `pkill`/`killall massoh-dashboard` token exists in test/run.sh
  (static grep guard), plus the existing live 8787 server (or a sentinel server on another port)
  survives the suite.
- `bash test/run.sh` green.

## Acceptance
1. Conditions (file:line). 2. Tests green; suite green; paste: the task-list href sample + a 200 on
that href; the per-request-rediscovery proof (repo added post-launch resolves, no restart); the
no-broad-pkill grep guard + a survived-sentinel proof. 3. VERSION 0.27.0 + CHANGELOG. 4. Mark inbox
#19/#20/#21 **DONE** in AGENT_BACKLOG (append-only: edit the Status cell, do not delete rows).
5. No safety-critical file; GET-only; bin/massoh + manifest untouched.

## Routing
`massoh-implementer` (branch `feat/fleet-hardening`, off current main) → `05_A3_handoff.md` →
`massoh-reviewer-qa` (verify read-only preserved + escaped links + per-request rediscovery + zero
broad-pkill + live server survives suite) → auto-merge on green.
