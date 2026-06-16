# 00 — Request

**Task ID:** TASK-2026-06-16-massoh-version-notify · **Date:** 2026-06-16 · **Source:** owner (this session)

## Request
Close the "older installs don't know they're stale" gap. Add: (1) a **version stamp** + `massoh
version`; (2) `massoh doctor` **update-check** (compare clone vs `origin/main`, say "update
available"); (3) a **CHANGELOG.md**. So an old install can tell it's behind and how to update.

## Classification
**PRODUCT_SCOPE** (entry) → BUILD expected → arch/safety → packet → implement → review.

## Code edits allowed?
No (until `04`). Touches `bin/massoh` + `manifest.yml` (safety-critical). **Owner authorized** the
build incl. the `bin/massoh` edit via the deploy-question selection ("Also build version/notify").

## Shortcut
UX skipped (not user-facing). Recorded.
