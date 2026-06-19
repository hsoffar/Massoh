# 04 — Implementation Packet (LICENSE TO CODE): harden T6 (inbox #13, P0)

- **Issued after:** arch-safety APPROVED Option A (`03`, FT1–FT6). Test-only — no safety-critical files, no sign-off.
- **VERSION:** **no bump** (test-only; zero product change). **Branch:** `feat/fix-t6`.

## Scope
Make T6 ("doctor flags 'update available'") in `test/run.sh` offline-deterministic. **test/run.sh only.**

## The fix (Option A)
Replace T6's `git clone -q --bare "$REPO_ROOT" "$B6"` setup (lines ~93–98) with a synthetic local bare
repo: `git init --bare "$B6"`, seed an initial commit directly (no REPO_ROOT clone), then advance one
commit from `$A6` and `git push` into `$B6`. Doctor's `git fetch -q origin` from `$W6` (origin=`$B6`,
a filesystem path) then succeeds with zero outbound network. Keep the `cp -rp "$REPO_ROOT/lib" "$W6/"`
overlay (line ~96) verbatim and the four offline-safe assertions (lines ~105–108) intact.

## Mandatory conditions FT1–FT6 (from `03`; cite file:line in `05`)
FT1 T6 passes with ZERO outbound network; FT2 the "update available" check stays a live grep on real
doctor output (not vacuous); FT3 the 4 existing offline-safe assertions preserved; FT4 total check
count stays **463** (no net add/remove); FT5 setup vars isolated to `$TMP`, trap cleanup covers them,
no cross-test state; FT6 CI green end-to-end.

## Acceptance
1. FT1–FT6 (file:line). 2. `bash test/run.sh` → 463 green, **run it with network blocked too** (e.g.
unset proxies / no real remote) to prove offline-determinism; paste both. 3. test/run.sh is the ONLY
file changed. 4. No VERSION/product change.

## Rollback
Revert the PR (test-only; zero product/data impact).

## Routing
`massoh-implementer` (branch `feat/fix-t6`) → `05` → `massoh-reviewer-qa` (06) → auto-merge on green.
