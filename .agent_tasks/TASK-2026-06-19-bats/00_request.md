# 00 — Request: test/run.sh → bats (24h queue #12)

- **Task ID:** TASK-2026-06-19-bats
- **Date:** 2026-06-19 · owner (24h queue #12, P3). Owner authorized "do #12 bats."
- **Classification:** ARCHITECTURE_SAFETY (approach + feasibility) → IMPLEMENTATION.

## Goal (AGENT_BACKLOG acceptance stub #12)
Port `test/run.sh` checks to the bats framework (nicer test UX), with identical coverage; CI runs bats.

## Material facts (arch-safety must weigh)
- **bats is NOT installed** (locally or in the GitHub runner) — adds a dependency + a CI install step.
- The suite is **483 `check()` calls** — a full big-bang port is large + error-prone.
- **CI (#19) runs `bash test/run.sh`** — any port must keep CI green (install bats + run it, or keep run.sh).
- Value is **P3** ("nicer UX") — weigh ROI vs the rewrite risk.

## What arch-safety must decide (don't rubber-stamp)
Recommend ONE: (A) **scoped/incremental** — add bats infra + a `*.bats` harness that REUSES the existing
checks (or port a small pilot), keep `test/run.sh` as the source of truth + CI, migrate over time;
(B) **full big-bang port** with conditions (coverage parity proof, CI install bats, run.sh removed);
(C) **DEFER** — value doesn't justify the risk/dependency now (like #5), with a re-entry condition.
Be honest about coverage-parity risk (483 checks) and the CI dependency.

## Routing
`massoh-architecture-safety` → `03` (recommended approach + conditions OR defer) → if build:
`04` → implementer → reviewer-qa → auto-merge on green. If defer: route back to owner with reason.
