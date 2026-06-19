# AGENT_SYNC.md — Massoh

**The shared dashboard for all agents — current state, latest handoff, decisions.**
Read at every session boot; update after every meaningful task (`/sync`). Dashboard, not a history
dump — task detail lives in `.agent_tasks/`, decisions of record in `docs/adr/`.

Last updated: 2026-06-19 (TASK-2026-06-19-modularize-bin — **MERGED** PR #18 → main `fa83bcf`, VERSION 0.11.0. Owner set **auto-merge-on-green** for the 24h queue. bin/massoh now modular (12 lib/verbs); fan-out unlocked.)

## Current strategic mode
v0.1 post-extraction — validate that a portable, gated agent OS reduces build-trap for solo+Claude
shipping. Activation = a repo opts in and lands one packet `00→06` to merge. (see PRODUCT_STRATEGY.md)

## Current task
**24h queue fan-out (auto-merge-on-green).** bin/massoh modularized (#3 merged) → verb items now
parallelize via worktrees. Driving the remaining queue: #2 dogfood gate+CI, #4 intake, #5 auto-ledger
hook, #6 fleet rollup, #7 RMT slice 1, #8 board renderer, #9 profiles, #10 AGENTS.md, #11 schema_version,
#12 bats. Each: arch-safety (batch-authorized for bin/massoh) → implementer → reviewer-qa → auto-merge
on green; PRs reviewable post-hoc. See `AGENT_BACKLOG.md` §24h-plan.

**Last shipped:** TASK-2026-06-19-modularize-bin — bin/massoh → lib/verbs (pure extraction).
**Merged PR #18 → `fa83bcf`, VERSION 0.11.0**, 301/301 green, MB1–MB8 verified, byte-identical proven.

## Open questions (owner decision needed)
| Question | Raised | Context |
|---|---|---|
| (none open) | | |

## Decision log (append-only — never delete a row)
| Date | Decision | By |
|---|---|---|
| 2026-06-16 | Dogfood Massoh on itself — ran `massoh on`, this repo is now a Massoh project | owner |
| 2026-06-16 | Filled `agent-project/*`, seeded backlog from buildermethods Agent OS comparison | owner |
| 2026-06-16 | TASK-massoh-cli-verbs: product-scope **BUILD** all 3, sequenced, one PR | product-scope |
| 2026-06-16 | TASK-massoh-cli-verbs: arch/safety **CONDITIONAL YES** — blocked pending owner sign-off on `bin/massoh` | architecture-safety |
| 2026-06-16 | **Owner SIGNED OFF** on editing `bin/massoh` — build all 3 → `04` license issued | owner |
| 2026-06-16 | Implemented `discover`+`doctor`+`update` harden + STANDARDS template + tests; 21/21 green | implementer |
| 2026-06-16 | Review **APPROVE** (pending owner merge) — no scope creep, safety conditions held | reviewer-qa |
| 2026-06-16 | **Merged PR #1** (discover/doctor/update) → main `778e06a`; deployed via `massoh install` | owner |
| 2026-06-16 | TASK-version-notify: BUILD→APPROVE — version stamp + doctor update-check + CHANGELOG, 28/28 green | product-scope/impl/reviewer |
| 2026-06-16 | **Merged PR #2** → main `814df69`; deployed v0.2.0; `doctor` healthy | owner |
| 2026-06-17 | TASK-2026-06-17-cadence-cron: product-scope **BUILD** — wire standup/review/plan into cron tick + period boundary; route to architecture-safety | product-scope |
| 2026-06-17 | TASK-2026-06-17-cadence-cron: arch/safety **APPROVED** — 4 conditions: counter corruption-tolerance, post-serialization placement + `\|\| true`, dry-run gate, injectable ceremony cmds | architecture-safety |
| 2026-06-17 | TASK-2026-06-17-cadence-cron: **IMPLEMENTED** — cadence ceremonies in bin/massoh-cron, T10 (14 checks) + existing 64 checks = 78/78 green, v0.4.2 | implementer |
| 2026-06-17 | TASK-2026-06-17-cadence-cron: **REQUEST CHANGES** — blocking: `A&&B\|\|C` anti-pattern in ceremony wrappers (lines 33–35); T10f does not test failure path. Fix `if/else` + add suppression assertion. | reviewer-qa |
| 2026-06-17 | TASK-2026-06-17-cadence-cron: **rev2 fix** — replaced `A&&B\|\|C` with `if/else` in ceremony wrappers; added T10f assertion 3; 79/79 green | implementer |
| 2026-06-17 | TASK-2026-06-17-cadence-cron: **APPROVE** (rev2 final) — all 4 conditions verified, 79/79 green, scope clean, safety-critical files untouched | reviewer-qa |
| 2026-06-17 | TASK-2026-06-17-massoh-learn: product-scope **BUILD** — read-only heuristic miner; proposals to LEARNINGS.proposed.md; flags: --since/--write-proposals/--no-write; routes to architecture-safety | product-scope |
| 2026-06-17 | TASK-2026-06-17-massoh-learn: arch/safety **APPROVED** — 4 conditions: grep-guard `\|\| true`, write-lock to LEARNINGS.proposed.md, pattern strings as named vars, T11a-j all green | architecture-safety |
| 2026-06-17 | TASK-2026-06-17-massoh-learn: **IMPLEMENTED** — cmd_learn inline in bin/massoh; 26 new T11 checks; 105/105 green; v0.5.0; all 4 conditions verified (line numbers in 05_handoff) |
| 2026-06-17 | TASK-2026-06-17-massoh-learn: **APPROVE** — all 4 conditions independently verified; 105/105 green; scope clean; safety-critical files untouched; T11i confirmed non-stub | reviewer-qa | implementer |
| 2026-06-17 | TASK-2026-06-17-efficiency-v2: product-scope **BUILD** — 3 slices (A: cron-fix correctness bug, B: review-v2 KPIs, C: massoh recommend heuristic); order A→B→C; owner sign-off on record; routes to architecture-safety | product-scope |
| 2026-06-17 | TASK-2026-06-17-efficiency-v2: arch/safety **APPROVED all 3 slices** — A: 5 conditions (--every parsing safe, dry-run suppression, default-30 fallback, counter logic frozen, cmd_install crontab update); B: 5 conditions (git log %ct for dates — stat banned, || true on all greps, div-zero guard, append-only in snapshot block, --no-write checksum test); C: 6 conditions (write_recommend=0 default, >> append + awk || true, || true on all reads, <2-snapshot degrade, sole write target AGENT_SYNC.md, no cron auto-add); tests T12/T13/T14 specified | architecture-safety |
| 2026-06-17 | TASK-2026-06-17-efficiency-v2: **IMPLEMENTED** — Slice A (cron --every fix + tick_duration logging), Slice B (review-v2 KPIs: cycle_avg_days/rework_pct/throughput/wk), Slice C (massoh recommend R1–R5); all conditions A1-A5/B1-B5/C1-C6 met; 137/137 green (T12: 7, T13: 8, T14: 9 + 113 regression); VERSION 0.6.0; routing to reviewer-qa | implementer |
| 2026-06-17 | TASK-2026-06-17-efficiency-v2: **REQUEST CHANGES** — 1 blocking: T14g "no-write" checksum check vacuous (single-quote path bug in test/run.sh lines 759-761 causes b14g=a14g="" always). Product code correct; all A/B/C conditions verified in code; sole fix is 3-line test change to use cd+find pattern (same as T13g/T8). | reviewer-qa |
| 2026-06-17 | TASK-2026-06-17-efficiency-v2: **rev2 fix** — T14g test-only fix: replaced vacuous `md5sum '$RV14g/...'` with `cd "$RV14g" && find . ... \| md5sum` pattern (matches T8/T13g); product code unchanged; 137/137 green | implementer |
| 2026-06-17 | TASK-2026-06-17-efficiency-v2: **APPROVE** (FINAL) — T14g real test confirmed; all A1-A5/B1-B5/C1-C6 conditions independently verified; 137/137 green; scope clean; manifest/install/uninstall/block untouched | reviewer-qa |
| 2026-06-17 | TASK-2026-06-17-massoh-ledger: product-scope **BUILD** — time/token/cost ledger; verb `massoh ledger add <task-id> <stage> <tokens> <seconds>` (append-only TSV at `.agent_tasks/ledger.tsv`) + `massoh ledger` report; capture via orchestrator-called verb (SubagentStop hook noted as NEXT); routes to architecture-safety | product-scope |
| 2026-06-17 | TASK-2026-06-17-massoh-ledger: arch/safety **APPROVED** — 8 mandatory conditions: L1 (tab/newline sanitize task-id+stage), L2 (integer regex validation tokens+seconds), L3 (arg-count guard first), L4 (single-printf->> write, named LEDGER var + SAFETY comment), L5 (awk div-zero guard), L6 (awk skip malformed rows), L7 (|| true on all reads + absent-file degrade exit 0), L9 (free-form stage comment); ledger.tsv tracked in git (audit history, not gitignored); T15a-T15m specified | architecture-safety |
| 2026-06-17 | TASK-2026-06-17-massoh-ledger: **IMPLEMENTED** — cmd_ledger inline in bin/massoh (lines 698–790); 40 new T15 checks; 177/177 green; VERSION 0.7.0; all 8 conditions L1–L7,L9 met (line numbers in 05_handoff); routing to reviewer-qa |
| 2026-06-17 | TASK-2026-06-17-massoh-ledger: **APPROVE** — all 8 conditions L1–L7,L9 independently verified (line refs in 06_review_result); 177/177 green (independently run); scope clean; no deferred features; safety-critical files untouched; T15c/T15d assert zero file side-effects on rejection | reviewer-qa | implementer |
| 2026-06-17 | TASK-2026-06-17-massoh-meta: product-scope **BUILD** — Slice 1 (massoh meta CLI verb: ledger cost outliers, rework rate, backlog drift, repeated review findings; --write-proposals appends to META.proposed.md only; zero LLM); Slice 2 (massoh-meta-engineer.md role agent + 02_AGENT_ROLES.md/OPERATING_SYSTEM.md "6→7" doc updates); M1-M7 safety conditions; sign-off on record in 00_request.md; route to massoh-architecture-safety | product-scope |
| 2026-06-17 | TASK-2026-06-17-massoh-meta: arch/safety **APPROVED both slices** — 14 conditions: M1 (write isolation >> META.proposed.md named var + SAFETY comment), M2 (|| true on ALL grep/awk/git), M3 (degrade exit 0), M4 (write_meta=0 default), M5 (no internal cmd_learn/ledger calls), M6 (no new safety-critical designation), M7 (OUTLIER_FACTOR=2 + REPEAT_THRESHOLD=3 named vars), M8 ([meta] label prefix), M9 (verb registration + VERSION 0.8.0), M10 (no METRICS.md read for rework), M11 (agent prompt PROPOSE-ONLY explicit), M12 (manifest.yml unchanged — glob covers), M13 (doctor auto-adapts to 7 agents — dynamic enum confirmed), M14 (doc edits additive only); [meta]/[intake] namespace separation confirmed; T-meta-A–J (Slice 1) + T-meta-K–M (Slice 2) specified; owner sign-off covers both slices | architecture-safety |
| 2026-06-17 | TASK-2026-06-17-massoh-meta: **IMPLEMENTED** — cmd_meta in bin/massoh (lines 795–1019); massoh-meta-engineer.md (7th agent); 02_AGENT_ROLES.md 7 rows; OPERATING_SYSTEM.md §4; README roles; VERSION 0.8.0; CHANGELOG [0.8.0]; 204/204 green (29 new T-meta-A–M); all M1–M14 satisfied (line numbers in 05_handoff); routing to massoh-reviewer-qa | implementer |
| 2026-06-17 | TASK-2026-06-17-massoh-meta: **APPROVE** — M1 (write isolation, line 1017 only write, SAFETY comment lines 815–816), M2 (all 7 grep/awk/git guarded — full enumeration in 06_review_result), M3 (4 degrade paths + 3 awk div-zero guards) independently verified; T-meta-G real find-based snapshot; T-meta-D boundary=3 packets; T-meta-K doctor 7 ok agents; 204/204 green; scope clean; NB-1 AGENT_BACKLOG.md additive housekeeping (non-blocking); manifest/NON_NEGOTIABLES/install logic untouched | reviewer-qa |
| 2026-06-19 | **Merged backlog of approved packets to main** (recorded retroactively during dashboard reconciliation): cadence-cron→PR #8, massoh-learn→PR #9 (+fix #10), efficiency-v2→PR #12, massoh-ledger→PR #14, massoh-meta→PR #15; docs PRs #11 (README v0.5.1) #13 (north-star). HEAD `be97ed0`, VERSION 0.8.0 | owner |
| 2026-06-19 | TASK-2026-06-19-license-gate: product-scope **BUILD** — `massoh gate on/off` verb; pre-push hook + CI workflow; shared checker script; exempt list defined; 6 scoping questions resolved; target v0.9.0; route to massoh-architecture-safety (bin/massoh safety-critical, owner sign-off required) | product-scope |
| 2026-06-19 | TASK-2026-06-19-license-gate: arch/safety **CONDITIONAL YES** — blocked pending owner sign-off on `bin/massoh`; 14 conditions G1–G14 (hook create-if-missing/append-safe with namespace markers, set -euo pipefail, glob-safe path matching, null-SHA degrade, override-first guard, CI path correctness, manifest lockstep, idempotent on/off, project guard, verb registration, VERSION 0.9.0); 18 required tests T16a–T16r; target total 222; single most important risk = hook clobber (G3) | architecture-safety |
| 2026-06-19 | TASK-2026-06-19-license-gate: **Owner SIGNED OFF** on editing `bin/massoh` + `manifest.yml` (reviewed all 14 conditions G1–G14 + 18 tests T16a–T16r) → `04_implementation_packet.md` issued; route to massoh-implementer | owner |
| 2026-06-19 | TASK-2026-06-19-license-gate: **APPROVE** — G1–G14 all independently verified (line refs in 06_review_result); 236/236 green (independently run); scope clean; no deferred features built; safety-critical files untouched by existing verbs; NB-1 manifest documentation ambiguity (non-blocking); NB-2 T16n variable naming (non-blocking) | reviewer-qa |
| 2026-06-19 | TASK-2026-06-19-massoh-board: product-scope **BUILD** — `massoh board --push plane` verb; internal task model + Plane upsert; push-only (no two-way sync); append-only local id-map `.agent_tasks/.board-map.tsv`; task-level state in MVP (no real-time agent telemetry); config via env vars + gitignored `.env.massoh`; jq required (flagged as explicit dependency with startup guard); 12 acceptance criteria B1–B12; BLOCKED until license-gate merges (avoid parallel safety-critical bin/massoh edits); route to massoh-architecture-safety (first outbound-network + first secret-handling surface; owner sign-off on bin/massoh required) | product-scope |
| 2026-06-19 | TASK-2026-06-19-massoh-board: arch/safety **CONDITIONAL YES** — blocked pending owner sign-off on `bin/massoh`; 26 conditions BG1–BG26 (BG1–7 secret handling: token never in tracked file/output, header-only, gitignore-before-write, exit1 on missing; BG8–15 outbound network: curl timeouts, degrade exit0 no map corruption, non-2xx=fail, HTTPS, bounded retry, partial-push retry, no exfil; BG16–21 local writes append-only/idempotent/sanitized + manifest lockstep; BG22 jq guard confined to cmd_board; BG23–24 sign-off+lockstep; BG25 read-only isolation; BG26 issue body bounded + jq @json); 27 tests T17–T23; target total 263; highest risk = PLANE_API_TOKEN exposure (T17b live assertion) | architecture-safety |
| 2026-06-19 | TASK-2026-06-19-massoh-board: **Owner SIGNED OFF** on editing `bin/massoh` + `manifest.yml` (first credential + outbound-network surface; reviewed 26 conditions BG1–BG26 + 27 tests T17–T23) → `04_implementation_packet.md` issued; route to massoh-implementer | owner |
| 2026-06-19 | TASK-2026-06-19-license-gate: **MERGED** (squash) PR #16 → main `fc6dc0d`; VERSION 0.9.0 shipped; board now unblocked. Deploy to `~/.claude` via `massoh update` when owner chooses | owner |
| 2026-06-19 | Backlog additions: **RMT** (requirements traceability, PROPOSE-ONLY engine capability) + **Fleet layer** (multi-repo dashboard + cross-repo lessons + self-curing engine, EPIC) captured to AGENT_BACKLOG/NOW_NEXT + briefs under `agent-project/briefs/` | owner |
| 2026-06-19 | TASK-2026-06-19-massoh-board: **IMPLEMENTED** — cmd_board in bin/massoh (lines 1122–1619); _board_push_plane adapter; append-only .board-map.tsv; secret discipline BG1–BG7; network degrade BG8–BG15; jq guard BG22; manifest lockstep BG21/BG24; 280/280 green (44 new T17–T23 checks); VERSION 0.10.0; Plane API source: makeplane/developer-docs feat/add-new-api-docs; routing to massoh-reviewer-qa | implementer |
| 2026-06-19 | TASK-2026-06-19-massoh-board: **REQUEST CHANGES** — BG1–BG26 independently verified (line refs in 06_review_result); 280/280 green (independently run); T17b live-pass confirmed; 1 blocking: AGENT_BACKLOG.md edited out-of-scope + 3 Done rows deleted (NON_NEGOTIABLES append-only violation). Fix: `git checkout HEAD -- AGENT_BACKLOG.md`. Re-route to massoh-reviewer-qa (fast-track). | reviewer-qa |
| 2026-06-19 | TASK-2026-06-19-massoh-board: **APPROVED** (fast-track re-review) — prior BLOCK-1 resolved: board commit `5fb1788` has 7 approved files only (AGENT_BACKLOG.md absent); working-tree AGENT_BACKLOG.md restored all 3 deleted Done rows verbatim; bin/massoh additive (500 ins/1 del); BG1–BG26/280 green/T17b carried from prior full review. Ready to merge. | reviewer-qa |
| 2026-06-19 | **Owner BATCH-AUTHORIZED `bin/massoh` edits for the 24h queue** — items #3 (modularize), #4 (intake), #5 (auto-ledger hook), #6 (fleet rollup), #8 (board renderer), #9 (profiles), #10 (AGENTS.md), #11 (schema_version). Standing sign-off; per-item arch-safety + reviewer-qa + green tests still required; PRs left OPEN for owner merge (no auto-merge). Does NOT cover other safety-critical files (manifest install/uninstall/block logic, NON_NEGOTIABLES, global-block) — those still need fresh per-change sign-off. Revocable any time. | owner |
| 2026-06-19 | TASK-2026-06-19-modularize-bin: arch/safety **APPROVED** — 8 conditions MB1–MB8 (MB1: symlink-safe sourcing via $MASSOH_HOME; MB2: install wires lib/verbs/ + manifest lockstep; MB3: loud-fail on missing lib file; MB4: doctor verifies lib/verbs/; MB5: byte-identical CLI output; MB6: pure extraction no logic change; MB7: helpers defined before verbs; MB8: 280/280 suite green); test target 287 (7 new T-MB-* checks); single highest risk = installed-layout sourcing path (MB2); recommended split: keep safety-critical install/uninstall/block/on/off/status/doctor in bin/massoh (~340 lines), extract 12 verb units to lib/verbs/ (~1320 lines); impl BLOCKED until feat/massoh-board merges to main; route to massoh-implementer after board merge | architecture-safety |
| 2026-06-19 | TASK-2026-06-19-massoh-board: **MERGED** (squash) PR #17 → main `ce831e2`; VERSION 0.10.0; modularize (#3) unblocked. Deploy to `~/.claude` via `massoh update` when owner chooses | owner |
| 2026-06-19 | TASK-2026-06-19-modularize-bin: **IMPLEMENTED** — 12 verbs extracted to lib/verbs/*.sh; sourcing loop via $MASSOH_HOME; 301/301 green (280 + 21 T-MB); VERSION 0.11.0; MB1–MB8 all met; byte-identical CLI output proven; routing to massoh-reviewer-qa | implementer |
| 2026-06-19 | TASK-2026-06-19-modularize-bin: **APPROVE** — MB1–MB8 all independently verified (line refs in 06_review_result); 301/301 green (self-witnessed); pure-extraction byte-for-byte confirmed across all 12 verbs; safety-critical core (install/uninstall/backup/block) untouched in bin/massoh; no scope creep in product code; T-MB tests are substantive (non-vacuous); NB-1 deck/ untracked (non-blocking); NB-2 incorrect line range in handoff doc (non-blocking, code correct) | reviewer-qa |
| 2026-06-19 | TASK-2026-06-19-modularize-bin: **MERGED** (squash) PR #18 → main `fa83bcf`; VERSION 0.11.0; bin/massoh 1662→216 lines, 12 verbs in lib/verbs/; fan-out unlocked | owner |
| 2026-06-19 | **Owner revised policy → AUTO-MERGE-ON-GREEN** for the 24h queue (supersedes the "PRs open, no auto-merge" clause of the 2026-06-19 batch-authorization). Orchestrator squash-merges a batch-authorized PR once arch-safety + reviewer-qa pass AND the suite is green; owner reviews post-hoc and may revert. Still excludes other safety-critical files (manifest install/uninstall/block, NON_NEGOTIABLES, global-block) → those still need fresh sign-off. Revocable any time. | owner |

## Frozen (never delete without an explicit owner unfreeze)
None.

## Active task packets
| Task ID | Stage | Status |
|---|---|---|
| TASK-2026-06-16-massoh-cli-verbs | merged | DONE — PR #1 → main `778e06a` |
| TASK-2026-06-16-massoh-version-notify | merged | DONE — PR #2 → main `814df69`, deployed |
| TASK-2026-06-17-cadence-cron | merged | DONE — PR #8 |
| TASK-2026-06-17-massoh-learn | merged | DONE — PR #9 (+fix #10) |
| TASK-2026-06-17-efficiency-v2 | merged | DONE — PR #12 |
| TASK-2026-06-17-massoh-ledger | merged | DONE — PR #14 |
| TASK-2026-06-17-massoh-meta | merged | DONE — PR #15 → `be97ed0` |
| TASK-2026-06-19-license-gate | merged | DONE — PR #16 → main `fc6dc0d`, VERSION 0.9.0 |
| TASK-2026-06-19-massoh-board | merged | DONE — PR #17 → main `ce831e2`, VERSION 0.10.0 |
| TASK-2026-06-19-modularize-bin | merged | DONE — PR #18 → main `fa83bcf`, VERSION 0.11.0 |

## Last handoff
```
Agent: massoh-reviewer-qa
Mode: REVIEW_QA
Task: TASK-2026-06-19-modularize-bin — modularize bin/massoh → lib/verbs/*.sh (v0.11.0)
Status: APPROVED. 06_review_result.md written.
Branch: feat/modularize-bin (working tree, uncommitted — per batch-auth terms)
Decision: APPROVE. MB1–MB8 all independently verified. 301/301 green (self-witnessed).
  Pure extraction confirmed: all 12 verb bodies diffed byte-for-byte against ce831e2 base.
  Safety-critical core (install/uninstall/backup/block) stayed in bin/massoh. No scope creep.
  T-MB test assertions are substantive (T-MB-a real symlink, T-MB-e real MASSOH_HOME override,
  T-MB-d real install+remove+doctor, T-MB-f hardcoded string equality). T6 setup line addition
  confirmed non-assertion (cp -rp lib overlay line 96 in test/run.sh).
Checks run (self-witnessed):
  bash test/run.sh → ALL GREEN — 301 checks passed. PASS.
  git diff ce831e2 per-verb comparison (all 12) → IDENTICAL function bodies. PASS.
  bin/massoh dispatch case block → byte-identical to base. PASS.
  grep set +e lib/verbs/*.sh → no results. PASS.
  git diff ce831e2 -- templates/ agent-project/NON_NEGOTIABLES.md agent-os/policies/ → empty. PASS.
Non-blocking: NB-1 deck/ untracked (not in commit scope). NB-2 handoff doc line range off-by-one.
Next recommended agent: owner (merge feat/modularize-bin PR → main; deploy via massoh install)
Next action: owner merges PR on feat/modularize-bin
```
