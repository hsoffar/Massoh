# 04 — Implementation Packet (LICENSE TO CODE): bats infra (scoped) — 24h queue #12

- **Issued after:** arch-safety APPROVED Option A (`03`, BA1–BA7). Test-only/CI — no safety-critical files, no sign-off.
- **Target VERSION:** 0.19.0 · **Branch:** `feat/bats`.
- **Approach: SCOPED (A)** — additive bats infra + a native T1 pilot; `test/run.sh` stays the source of truth (NOT replaced). Big-bang (B) rejected: cross-test checksum sharing (T11i→T15l→T16r→T22b) is incompatible with bats `@test` isolation.

## Scope
1. `.github/workflows/ci.yml`: add `sudo apt-get install -y bats` step (mirror the jq step) BEFORE a new bats step; KEEP the existing `bash test/run.sh` step.
2. New additive `test/massoh.bats`: a **native T1 pilot** — port the 6 T1 (install/doctor) checks as real bats `@test` blocks that invoke `$MASSOH` and assert real output (BA6). No copy-paste shell one-liners; no shared global state with run.sh (BA7).
3. CI runs both: `bash test/run.sh` AND `bats test/massoh.bats`.
4. VERSION → 0.19.0; CHANGELOG [0.19.0] (bats infra proven + migration template).

## Out of scope
Porting the other ~451 checks; touching/removing `test/run.sh`; the safety-checksum cross-section tests (the structural blocker — future work post test-modularization).

## Mandatory conditions BA1–BA7 (from `03`; cite file:line in `05`)
BA1 `bash test/run.sh` still green (457 checks); BA2 `bats test/massoh.bats` exits 0; BA3 run.sh CI step preserved (bats additive); BA4 `apt-get install -y bats` in CI; BA5 ZERO changes to bin/massoh, manifest.yml, templates/, policies/, NON_NEGOTIABLES.md; BA6 bats assertions invoke `$MASSOH` + assert real output; BA7 `.bats` shares no global state with run.sh.

## Required tests / verification
- `bats test/massoh.bats` green locally (install bats first: `sudo apt-get install -y bats`, or note if unavailable in this env and verify syntax via `bats --version`/dry-parse).
- `bash test/run.sh` still green (457; note pre-existing T6 network).
- CI yaml valid (both steps present, bats installed before its step).

## Acceptance
1. BA1–BA7 (file:line). 2. Both suites green (or, if bats can't install in this env, the .bats file is syntactically valid + a clear note). 3. run.sh untouched. 4. CI has both steps. 5. VERSION 0.19.0.

## Rollback
Delete `test/massoh.bats` + revert the CI bats step. run.sh untouched → zero risk.

## Routing
`massoh-implementer` (branch `feat/bats`) → `05` → `massoh-reviewer-qa` (06) → auto-merge on green.
