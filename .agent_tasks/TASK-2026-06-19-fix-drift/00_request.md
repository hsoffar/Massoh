# 00 — Request: bats/test inline-copy drift guard — inbox #15 (P1)

- **Task ID:** TASK-2026-06-19-fix-drift
- **Date:** 2026-06-19 · from `AGENT_BACKLOG.md` §Intake inbox #15 (P1, filed via `massoh intake`).
- **Classification:** hardening → ARCHITECTURE_SAFETY → IMPLEMENTATION.

## Problem
`test/run.sh` contains `SR_HELPER` — an INLINE COPY of `bin/massoh`'s `manifest_schema_ver()` (used by
the T-SR tests because sourcing bin/massoh auto-dispatches). The #11 reviewer confirmed it is
byte-identical today, but flagged it could **silently drift** if the real function changes later, leaving
the T-SR tests validating a stale copy.

## Goal
Prevent silent drift with the **lowest-risk** fix.

## Approach (arch-safety to pick; prefer test-only)
- (A, preferred) **Drift guard:** add a test that extracts `manifest_schema_ver()`'s body from
  `bin/massoh` and asserts it matches the `SR_HELPER` copy in `test/run.sh` — fails loudly on drift.
  Test-only; no bin/massoh change; no sign-off.
- (B) **Extract to a sourceable helper** both bin/massoh and the test load — cleaner long-term but
  touches bin/massoh (safety-critical, sourcing-without-dispatch concern) → owner sign-off. Heavier.
Recommend A unless there's a strong reason for B.

## Routing
`massoh-architecture-safety` → `03` → `04` → implementer → reviewer-qa → auto-merge on green
(if A = test-only, no sign-off; if B, flag owner sign-off for bin/massoh).
