# 00 — Request: harden T6 doctor update-check (network-flaky in CI) — inbox #13 (P0)

- **Task ID:** TASK-2026-06-19-fix-t6
- **Date:** 2026-06-19 · from `AGENT_BACKLOG.md` §Intake inbox #13 (P0, filed via `massoh intake`).
- **Classification:** bug fix → ARCHITECTURE_SAFETY → IMPLEMENTATION (workflow shortcut for bug fix).

## Problem
T6 ("doctor flags 'update available'") in `test/run.sh` depends on a live git fetch to a remote — it
**fails whenever the network/remote is unreachable**. Now that CI (#19) runs `bash test/run.sh` on
every PR + push, this flaky test will go **red in CI unpredictably**, undermining the gate's CI signal.
(Confirmed pre-existing by the #7/#11 reviews; passes locally only when network is up.)

## Goal
Make T6 **offline-deterministic**: it should validate the doctor update-check behavior WITHOUT
depending on real network reachability — e.g. point it at a local fake remote / stub the version
comparison, or skip-with-pass when no network is available. The product `doctor` update-check itself is
correct (offline-safe via `--offline`); the TEST is what's flaky.

## Constraints
- Prefer a **test-only fix** (make T6 deterministic) — no `bin/massoh` change if avoidable (keeps it
  non-safety-critical, no sign-off). If a `doctor` change IS needed, STOP and flag for owner sign-off.
- Keep T6's actual assertion meaningful (don't just delete it / make it vacuous).
- Suite stays green deterministically offline AND online.

## Routing
`massoh-architecture-safety` → `03` (the safe deterministic-fix approach + conditions) → `04` →
`massoh-implementer` → `massoh-reviewer-qa` → auto-merge on green (test-only = no sign-off; if it
touches doctor, owner sign-off first).
