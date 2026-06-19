# 04 — Implementation Packet (LICENSE TO CODE): schema-rename (24h queue #11)

- **Issued after:** arch-safety APPROVED (`03`, SR1–SR7) + owner sign-off (manifest + bin/massoh). No fresh sign-off.
- **Target VERSION:** 0.18.0 · **Branch:** `feat/schema-rename`.
- **Key fact:** 0 current code readers of manifest `version:` (documentary-only) — low-risk rename.

## Scope
Rename `manifest.yml` `version:` → `schema_version:`; add a future-proof reader; update doc refs. No behavior change.

## Mandatory conditions SR1–SR7 (from `03`; cite file:line in `05`)
- **SR1** lockstep: manifest rename + bin/massoh reader in ONE atomic commit.
- **SR2** (highest) add `manifest_schema_ver()` to bin/massoh: grep `^schema_version:` first, fall back to `^version:` with a stderr deprecation note, default `unknown` — never empty/crash; grep guarded `|| true`.
- **SR3** re-grep to confirm zero other readers across lib/verbs/, test/, templates/ before merge.
- **SR4** manifest.yml comment line (`# version: 1`) → `# schema_version: 1`.
- **SR5** update the 3 doc refs to the old key: CHANGELOG.md (~line 4), CHARTER.md (~line 43), manifest comment.
- **SR6** set -euo pipefail safe (`|| true` on new grep/awk).
- **SR7** the product `VERSION` file is NOT touched by the rename logic (only bumped to 0.18.0 for the release).

## Required tests T-SR-1…11 (suite current+11; zero regressions)
schema_version present; old `version:` absent; reader returns 1 (new); fallback old-manifest returns 1 + deprecation note; neither key → `unknown` exit 0; doctor healthy; status `  version:` line still present (from VERSION); version matches semver; T-MB-a unchanged; **update the manifest-checksum baseline tests (T11i/T15l/T16r/T22b) for the new manifest content**; full suite green. Run `bash test/run.sh`.

## Acceptance
1. SR1–SR7 (file:line). 2. T-SR-* green; suite green (note pre-existing T6 network failure is unrelated); verbatim output + backward-compat fallback proof. 3. manifest↔bin lockstep. 4. VERSION 0.18.0 + CHANGELOG.

## Rollback
Revert PR; `massoh install`. No data loss (old binary has no manifest-version reader either).

## Routing
`massoh-implementer` (branch `feat/schema-rename`) → `05` → `massoh-reviewer-qa` (06) → auto-merge on green.
