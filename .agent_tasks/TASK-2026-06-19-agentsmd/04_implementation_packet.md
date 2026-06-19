# 04 — Implementation Packet (LICENSE TO CODE): emit AGENTS.md (24h queue #10)

- **Issued after:** arch-safety APPROVED (`03`, AM1–AM10) + owner batch-auth + auto-merge-on-green. No sign-off (manifest untouched).
- **Target VERSION:** next minor after #9 (0.14.0) + #8 (0.15.0) → **0.16.0**; verify then-current main + bump.
- **Branch:** `feat/agentsmd`. Implement after #9 + #8 land (serialize; rebase for VERSION).

## Scope
New verb `massoh agents-md` → reads `$MASSOH_HOME/claude/agents/massoh-*.md` frontmatter (name,
description, tools→edits-code?) → writes a concise `AGENTS.md` at repo root (team index table +
workflow pointer). Generated-sentinel clobber-guard. No manifest change. Idempotent; opt-in.

## Mandatory conditions AM1–AM10 (from `03`; cite file:line in `05`)
AM1 `|| true` on all reads, degrade exit 0 if no role files (don't create file); AM2 write to repo
root (`git rev-parse --show-toplevel`), sentinel `<!-- massoh-generated -->` on line 1, overwrite if
present, **refuse+exit 1 if absent (hand-authored)**, idempotent byte-identical; AM3 frontmatter =
data only (name≤64, desc≤256+`...`, edits-code from tools Edit/Write; no source/eval); AM4
`_agents_md_sanitize_cell` (pipes→safe, newlines→space) for name+desc; AM5 scope: index only — 7-row
table + workflow pointer, **< 50 lines, no role bodies** ("You are the" absent); AM6 set -euo pipefail,
if/else not `A&&B||C`; AM7 exactly 2 additive bin/massoh lines; AM8 no secrets/network/LLM (static
grep); AM9 manifest.yml NOT changed (if any diff → STOP for sign-off); AM10 VERSION 0.16.0 + CHANGELOG.

## Required tests T-AM-a…j (10; suite → baseline+10)
generated w/ 7 rows + sentinel + no body; idempotent; hand-authored refused unchanged; pipe
sanitization; no-role-files degrade exit 0; static no-source/eval/network/secret; desc cap; edits-code
column; dispatch+usage; `< 50 lines` & no "You are the". Run `bash test/run.sh` green.

## Acceptance
1. AM1–AM10 (file:line). 2. T-AM-* green; suite green; verbatim + clobber-guard proof. 3. VERSION 0.16.0. 4. manifest untouched.

## Rollback
`git revert`; rm generated AGENTS.md (sentinel-marked, regenerable). No manifest/migration.

## Routing
`massoh-implementer` (branch `feat/agentsmd`, off latest main) → `05` → `massoh-reviewer-qa` (06) → auto-merge on green.
