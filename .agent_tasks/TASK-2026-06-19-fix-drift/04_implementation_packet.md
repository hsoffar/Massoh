# 04 — Implementation Packet (LICENSE TO CODE): drift guard — inbox #15 (P1)

- **Issued after:** arch-safety APPROVED Approach A (`03`, DG1–DG4). Test-only — no safety-critical files, no sign-off.
- **VERSION:** no bump (test-only). **Branch:** `feat/fix-drift`.

## Scope
Add a drift-guard to `test/run.sh` that fails if the `SR_HELPER` inline copy diverges from
`bin/massoh`'s real `manifest_schema_ver()`. **test/run.sh ONLY.**

## Mechanism (DG1–DG4)
- **DG1** extract `manifest_schema_ver()` body from bin/massoh anchored to the function SIGNATURE (awk: start after the signature line, stop before the closing `}`) — NOT line numbers.
- **DG2** extract the `SR_HELPER` body from test/run.sh anchored to the heredoc delimiters (`cat > "$SR_HELPER"` … `SR_HELPER_EOF`) + the same awk body-extraction — NOT line numbers.
- **DG3** normalize both (strip leading/trailing whitespace per line) then `diff <(...) <(...)` — false-green-proof on indentation, red on any logic change (grep key / awk / printf / fallback).
- **DG4** the guard is non-vacuous: T-DG-2 injects a known divergence into one side and asserts `diff` exits non-zero.

## Required tests T-DG-1, T-DG-2 (2 new; suite 463 → 465)
- T-DG-1: extracted bodies identical today → `diff` exit 0.
- T-DG-2: meta-check — inject a divergence (e.g. substitute a key in one extracted copy) → `diff` exit non-zero (proves the guard catches drift).
Run `bash test/run.sh` → 465 green.

## Acceptance
1. DG1–DG4 (file:line). 2. T-DG-1 + T-DG-2 green; suite 465 green; paste output. 3. test/run.sh ONLY changed. 4. No product/VERSION change.

## Rollback
Revert the test/run.sh addition (zero installed-behavior impact).

## Routing
`massoh-implementer` (branch `feat/fix-drift`) → `05` → `massoh-reviewer-qa` (06) → auto-merge on green.
