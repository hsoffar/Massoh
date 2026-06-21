# 04 — License: Fleet slice 1a-0 — `massoh fleet serve` skeleton

- **Gate:** system-architect review `00_architecture_review.md` (conditions N1–N7) = the arch-safety
  authority for read-only slices. Owner away-autonomy grant covers it. No fresh sign-off (no
  safety-critical file: scripts/ wiring exists; fleet is already dispatched).
- **Branch:** `feat/fleet-serve`. **No VERSION bump** (internal skeleton; 1a bumps to 0.20.0 when the
  dashboard is user-useful). CHANGELOG: hold until 1a.

## Scope (skeleton ONLY — prove the risky part in isolation)
Add a `serve` subcommand to `lib/verbs/fleet.sh` → execs a new `scripts/massoh-dashboard` (Python
stdlib `http.server`). The skeleton serves ONE static stub page and proves bind-scope + lifecycle.
NO repo content yet (index/KPIs/board = slice 1a). Touch `bin/massoh` ONLY if a usage-string line is
needed (additive, pre-authorized); prefer keeping it all in fleet.sh + scripts/.

## Mandatory conditions (from `00_architecture_review.md` N1–N7 — read it; key ones)
- **N1 loopback-only:** bind `127.0.0.1` **hard-coded, NOT configurable**; never `0.0.0.0`. `--port`
  (default 8787) is the only knob.
- **Route allowlist, NOT a file server:** method+path → a fixed allowlist (`/` → stub) → 404 everything
  else. No filesystem path resolution from the URL (kills path traversal). GET only in the skeleton.
- **N3 clean lifecycle:** starts, serves, and shuts down cleanly on SIGINT/SIGTERM; **no lingering
  process**; prints the URL on start.
- **stdlib-only Python** (no pip / no PyYAML); the bash CLI gains no dep (python is the opt-in for this
  verb only). Guard: if python3 absent → clear message, exit non-zero.
- set -euo pipefail in the fleet.sh path; `|| true` where apt.

## Required tests (T-FS-* in test/run.sh; additive)
- `massoh fleet serve` starts, `curl -s 127.0.0.1:<port>/` returns the stub (200); a bogus path → 404;
  the listener is bound to 127.0.0.1 ONLY (assert not reachable/declared on 0.0.0.0); the process
  stops cleanly with no orphan (check after teardown). python3-absent → graceful exit.
- Run with an ephemeral/free port to avoid CI collisions. Full suite stays green.

## Acceptance
1. N1–N7 honored (file:line in handoff). 2. T-FS-* green; suite green; paste the start→curl→404→stop
   transcript. 3. scripts/massoh-dashboard is stdlib-only, route-allowlist, loopback-only. 4. No
   safety-critical file changed (manifest/install untouched; scripts/ glob already covers the new file).

## Rollback
Remove scripts/massoh-dashboard + the fleet.sh serve subcommand. Additive; zero installed-behavior impact.

## Routing
`massoh-implementer` (branch `feat/fleet-serve`) → `05` → `massoh-reviewer-qa` → auto-merge on green.
