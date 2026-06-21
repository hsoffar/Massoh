# 04 — License: test parallel-safety (#17, P0) — test-only

- **Gate:** inbox issue #17 (P0) carries acceptance criteria → "approved issue" (Hard rule #1).
  **Test-harness-only change** (no product code, no new risk class) → ships under the away-grant.
- **Branch:** `fix/test-parallel-safety` (off current main, v0.27.0). **VERSION → 0.27.1** (patch;
  test-infra fix, no behavior change); CHANGELOG [0.27.1].

## Root cause (already diagnosed — confirm, then fix)
`test/run.sh` is already per-run isolated for tmp/HOME (`TMP="$(mktemp -d)"` line 9; throwaway
CLAUDE_CONFIG_DIR via `newcc()` line 17) and doctor is offline-deterministic (#13). The remaining
collision is **hard-coded ports**: the Plane/RMT mock-server tests bind FIXED ports —
`MOCK_PORT_18b=19901`, `18c=19902`, `18d=19903`, `19a=19904`, `20e=19905`, plus literal `19998`
(lines ~1295/1309/1316) and `19999` (lines ~1346/1716/1727). Two concurrent `bash test/run.sh`
runs both try to bind the same port → `Address already in use` → spurious FAIL (the "2/465 FAILED"
seen earlier). The dashboard tests (T-FS/T-FB) already avoid this via `_fs_free_port()` (bind :0,
read assigned port) at line ~3166 — that helper is the model.

## Scope (fix exactly this)
1. **Hoist a free-port helper to the top** of test/run.sh (near the TMP/trap setup, before ANY test
   that needs a port). Either move `_fs_free_port` up, or define a shared `free_port()` there and have
   the T-FS block reuse it (no duplicate definition — DRY).
2. **Replace every hard-coded port** with a dynamically-allocated one:
   - `MOCK_PORT_18b/18c/18d/19a/20e` → each `"$(free_port)"`.
   - The literal `19998` and `19999` occurrences (Plane base-URL mocks) → assigned to a
     `free_port`-allocated var and referenced (don't leave any hard-coded test port).
   - Sweep: after the fix, `grep -nE ':199[0-9][0-9]|=199[0-9][0-9]' test/run.sh` returns ZERO
     hard-coded test ports (the connect-refused test that needs a *closed* port may keep a fixed
     unbound port IF it's documented why — but prefer allocate-then-close).
3. Keep each mock server's teardown **PID-scoped** (no broad pkill — consistent with #21).

## Mandatory conditions
- **Test-only:** product code diff = 0 (bin/massoh, manifest.yml, lib/, scripts/, agent-os/,
  policies/, templates/, NON_NEGOTIABLES) — ONLY test/run.sh + VERSION + CHANGELOG change.
- No hard-coded `199xx` test port remains (grep-proven). All mock servers bind a free port.
- `set -euo pipefail` preserved; each spawned server torn down by its own PID.
- Suite still green single-run; AND **two concurrent runs both pass** (the actual fix).

## Required test / proof
- Add a brief comment block documenting the free-port pattern as the rule for new port-using tests.
- Acceptance proof: run `bash test/run.sh` twice CONCURRENTLY (`bash test/run.sh & bash test/run.sh &
  wait`) → BOTH exit 0 / ALL GREEN (this is the parallel-safety proof #17 asks for). Paste both results.
- Single-run `bash test/run.sh` still ALL GREEN.

## Acceptance
1. Conditions (file:line). 2. grep proof (zero hard-coded 199xx ports). 3. concurrent-run proof (two
suites pass simultaneously) + single-run green. 4. VERSION 0.27.1 + CHANGELOG. 5. Mark inbox #17
**DONE** (Status cell only, append-only). 6. Product code diff = 0.

## Routing
`massoh-implementer` (branch `fix/test-parallel-safety`) → `05_A4_handoff.md` → `massoh-reviewer-qa`
(verify product-diff=0, zero hard-coded ports, concurrent-run passes) → auto-merge on green.
