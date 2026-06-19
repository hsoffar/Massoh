# 04 — Implementation Packet (LICENSE TO CODE): `massoh fleet` (24h queue #6)

- **Task ID:** TASK-2026-06-19-fleet-rollup
- **Issued after:** arch-safety APPROVED (`03`, FL1–FL11) + owner batch-authorization + auto-merge-on-green.
- **Target VERSION:** **0.13.0** (note: #4 intake takes 0.12.0 and merges first; this bumps to 0.13.0).
- **Branch:** `feat/fleet-rollup`. **No merge dependency**, but implement AFTER #4 merges (both touch
  the main working tree / bin/massoh dispatch — serialize) and rebase onto the post-#4 main so VERSION
  is correct.

## Scope
New READ-ONLY verb `massoh fleet [--root <dir>] [--no-cache]`: discover opted-in `.massoh` repos
(scan `--root`, default bounded; or read optional `~/.claude/massoh/fleet.tsv`) and print a per-repo
rollup — stage counts from each repo's `.agent_tasks/TASK-*/`, blocked items, last-handoff agent/mode
from each `AGENT_SYNC.md`. **Writes to NO discovered repo.** New `lib/verbs/fleet.sh` + dispatch line
+ usage. No manifest change (lib/verbs/ glob covers it — if not, STOP, do not touch manifest).

## Out of scope (Fleet epic LATER slices — do NOT build)
Cross-repo lessons pool; engine self-cure; any upload/network; writing into discovered repos.

## Mandatory conditions FL1–FL11 (from `03`; all required; cite file:line in `05`)
FL1 structural write-isolation (no `>`/`>>`/`tee`/`cp`/`mv`/`mkdir`/`touch` on a discovered-repo path;
only optional write = `~/.claude/massoh/` cache, off by default via `--no-cache`); FL2 bounded scan
(`find -maxdepth 3`, cap 200 repos, missing root → warn+exit 0, find guarded); FL3 `fleet.tsv`
sanitized (`while IFS= read -r`, never sourced, `[ -d ]` validate, skip comments/blanks/>4096-char);
FL4 untrusted content = data only (no source/eval/`bash -c`; cap 200 lines/AGENT_SYNC, 100 task dirs);
FL5 per-repo degrade (`[SKIP] <path>: <reason>`, exit 0 on partial/zero); FL6 `set -euo pipefail` +
`|| true` on all grep/find/awk/git (mirror review.sh/learn.sh); FL7 no network/credentials
(no curl/wget/nc/ssh/gh, no secret reads); FL8 privacy documented (local-only, no upload) in header +
usage; FL9 bin/massoh = 1 dispatch + 1 usage line only; FL10 manifest untouched (verify glob; else
STOP+escalate); FL11 VERSION 0.13.0 + CHANGELOG.

## Required tests T-FL-a…k (≥11; suite → target ≥312 over the then-current baseline)
Per `03`: T-FL-a/b two fake repos byte-identical before/after a fleet run (the write-isolation proof);
bounded discovery (depth-4 marker not found); degrade on unreadable `.agent_tasks/`; missing root →
exit 0; no-config → exit 0; `fleet.tsv` parse (2 valid + comment + blank + missing → 2 repos);
static no-network grep; static no-source/eval grep; rollup shows both repo paths + blocked indicator;
dispatch exits 0 + usage contains "fleet". Run `bash test/run.sh`, confirm green.

## Acceptance criteria
1. FL1–FL11 satisfied (file:line each). 2. T-FL-* green; suite green; verbatim output + the
byte-snapshot write-isolation proof. 3. Zero regressions; bin/massoh diff = 2 additive lines.
4. VERSION 0.13.0; CHANGELOG. 5. `massoh doctor` green (manifest glob covers fleet.sh).

## Rollback
`git revert` the PR; remove `lib/verbs/fleet.sh` + 2 dispatch lines; optional `~/.claude/massoh/` cache
removable by hand. Writes nothing to discovered repos → nothing to undo there.

## Routing
`massoh-implementer` (branch `feat/fleet-rollup`, off post-#4 main) → `05` → `massoh-reviewer-qa` (06)
→ auto-merge on green.
