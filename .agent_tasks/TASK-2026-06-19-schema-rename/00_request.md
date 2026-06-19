# 00 — Request: rename manifest.yml `version:` → `schema_version:` (24h queue #11)

- **Task ID:** TASK-2026-06-19-schema-rename
- **Date:** 2026-06-19 · owner (24h queue #11). **Owner SIGNED OFF** on manifest.yml + bin/massoh
  (AGENT_SYNC decision log 2026-06-19).
- **Classification:** ARCHITECTURE_SAFETY → IMPLEMENTATION. Touches the manifest↔bin/massoh contract
  seam (safety-critical) — sign-off granted.

## Goal (AGENT_BACKLOG acceptance stub #11)
Rename `manifest.yml`'s `version:` key → `schema_version:` to disambiguate from the product `VERSION`
file. Update the `bin/massoh` reader in lockstep. **One-release backward-compat:** the reader still
accepts the old `version:` key (warn) so an old installed layout still works for one release.

## Risks for arch-safety
- Contract seam: manifest `schema_version:` ↔ `bin/massoh` reader must change together (lockstep).
- Backward-compat: read `schema_version:` first, fall back to `version:` (one release); `massoh doctor`
  + `massoh version`/status still report correctly.
- No behavior change beyond the key name; set -euo pipefail safe; additive/reversible.
- Confirm nothing else parses manifest `version:` (grep the repo).

## Routing
`massoh-architecture-safety` → `03` (conditions + backward-compat + tests) → (signed off) → `04` →
implementer → reviewer-qa → auto-merge on green. Target v0.18.0. Serial: after #7 (done), before #12.
