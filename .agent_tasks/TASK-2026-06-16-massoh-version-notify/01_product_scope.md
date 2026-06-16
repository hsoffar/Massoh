# 01 — Product Scope

**Agent:** massoh-product-scope · **Date:** 2026-06-16

## Decision: **BUILD**
Directly serves the v0.1 validation goal (install trust → `second_repo` retention). A pull-only
updater with no staleness signal rots silently; this is the smallest fix that makes "am I current?"
answerable on any machine.

## Minimal version
1. **VERSION** file at repo root (`0.2.0`). `massoh version` (+ `--version`/`-v`) prints
   `massoh <VERSION> (<clone short SHA>)`. `massoh status` shows the version line.
2. **doctor update-check**: best-effort `git fetch` then compare local `HEAD` vs `origin/main`;
   if behind → print `update available → massoh update` (informational; does **not** change exit
   code — staleness is not install drift). **Offline-safe** (fetch fail → skip silently).
   Opt-out: `MASSOH_NO_FETCH=1` or `doctor --offline`.
3. **CHANGELOG.md** (Keep-a-Changelog style); `0.2.0` entry for both CLI tasks today.

## Non-goals
No auto-update, no telemetry, no network calls in any verb except `update` and the optional
`doctor` fetch (which is opt-out). No breaking-migration runner yet (separate item if/when a
breaking layout change happens).

## Metric / events
`doctor_update_available` (counted by hand). Affects install trust → retention.

## Safety/guardrail impact
Edits `bin/massoh` + `manifest.yml` (both safety-critical) + adds VERSION to the install payload.
Owner authorized. `doctor` must stay read-only to the filesystem (network fetch only, no writes).

## Acceptance criteria
- `massoh version` prints a semver line; `status` includes it.
- `doctor` on an up-to-date clone → exit 0, no "update available".
- `doctor` on a clone behind `origin/main` → prints "update available", **still exit 0**.
- `doctor --offline` / `MASSOH_NO_FETCH=1` → no network, no error, works.
- VERSION is installed to `~/.claude/agent-os/VERSION`; `doctor` reports it present.
- All prior tests still green (regression).

## Routing
BUILD → `massoh-architecture-safety` (touches safety-critical files).
