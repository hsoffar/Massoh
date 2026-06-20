# 04 — License: Fleet slice 3 — `massoh fleet learn` (cross-repo lessons → candidates)

- **Gate:** arch-safety `03_slice3_architecture_safety.md` (FLN1–FLN8) + owner 8h away-grant (zero-spend + propose-only + read-only → no fresh sign-off).
- **Branch:** `feat/fleet-learn`. **VERSION → 0.23.0**; CHANGELOG [0.23.0].

## Scope
New `massoh fleet learn` subcommand in lib/verbs/fleet.sh — aggregate every discovered repo's
`agent-project/LEARNINGS.proposed.md` + `META.proposed.md`, cluster by recurrence, write a consolidated
candidates doc `agent-project/FLEET_LEARNINGS.proposed.md` in THIS repo. CLI only. **Zero LLM, zero
spend, read-only on discovered repos.** Browser button = NOT built (parked).

## Mandatory conditions FLN1–FLN8 (from `03_slice3...`; cite file:line in `05`)
- **FLN1** zero LLM/network/spend — no `claude`/`curl`/`wget`/agent call in `cmd_fleet_learn`.
- **FLN2** read-only against discovered repos — their paths never on the LHS of a write; byte-snapshot proof.
- **FLN3** single named write var `FLEET_LEARNINGS` + `# SAFETY` comment (mirror META_PROPOSALS in meta.sh); sole write target.
- **FLN4** (highest) promotion boundary: recurrence ≥2 repos → `[generalizable-candidate]`; 1 repo → `[project: <basename>]`; doc header "CANDIDATES ONLY — engine adoption is a separate owner/gated step"; **zero writes to any engine file** (`agent-os/`, `lib/verbs/`, `bin/massoh`, `manifest.yml`, `templates/`, `policies/`) — T-FLN-4 git-diff asserts.
- **FLN5** leak guard: structured fields only (no raw file dump); source = basename not abs-path; cap line ≤500; local-only (no upload).
- **FLN6** set -euo pipefail + `|| true` on all reads; per-repo degrade exit 0 on missing proposals (`[skip]`).
- **FLN7** idempotent — declare Pattern A (sentinel/regenerate) or B (append+timestamp); default-off write unless run (a no-op/`--no-write`-style guard like meta: writing only when the subcommand is invoked is fine, but two runs must be consistent).
- **FLN8** sanitize `|` + backticks in lesson text → valid markdown, no eval. Recurrence threshold = a NAMED constant (no magic number).

## Required tests T-FLN-1…8 (8 new; suite 544 → target 552+)
overlap→generalizable-candidate + single→project-tagged (T-FLN-1); discovered-repo byte-snapshot identical (T-FLN-2); no-proposals repo → exit 0 + `[skip]`, no file in that repo (T-FLN-3); `git diff --name-only` on engine paths empty after run (T-FLN-4); static grep no claude/curl/wget/agent (T-FLN-5); idempotent two runs (T-FLN-6); no-write/no-flag leaves the doc untouched (T-FLN-7); `|`/backtick lesson → valid markdown no injection (T-FLN-8). Run `bash test/run.sh` green.

## Acceptance
1. FLN1–FLN8 (file:line). 2. T-FLN-* green; suite green; paste a FLEET_LEARNINGS.proposed.md sample + the engine-untouched git-diff + the discovered-repo byte-snapshot. 3. VERSION 0.23.0 + CHANGELOG. 4. scripts/massoh-dashboard NOT modified (no POST/button); bin/massoh + manifest untouched.

## PARKED (owner): the browser learn-button (POST) + engine ADOPTION of any candidate — separate gated steps.

## Routing
`massoh-implementer` (branch `feat/fleet-learn`) → `05` → `massoh-reviewer-qa` → auto-merge on green.
