# 00 — Request
**Task:** TASK-2026-06-17-learn-v1.1 · **Date:** 2026-06-17 · **Source:** owner ("fix learn v1 rough edges")
**Classification:** narrow bug fix → allowed shortcut Architecture/Safety → Implementer → Reviewer,
done INLINE by the orchestrator (too small to spawn the 4-agent team; recorded here).
Two defects in `cmd_learn`, both surfaced by running `massoh learn` on Massoh itself:
1. `grep -F "REQUEST CHANGES"` matched code citations (e.g. `_PAT_REQUEST_CHANGES='REQUEST CHANGES'`)
   as blocking findings → false positive.
2. "Risks seen" printed the `## Risks` heading instead of the content under it.
Owner authorized the `bin/massoh` edit (same standing sign-off as the learn feature).
