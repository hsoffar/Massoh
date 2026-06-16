# 01 — Product Scope

**Agent:** massoh-product-scope · **Date:** 2026-06-16 · **Task:** TASK-2026-06-16-massoh-cli-verbs

## 1. Decision: **BUILD** (all three) — sequenced, one cohesive PR
All three are additive CLI verbs/behavior, reversible, and serve the v0.1 validation goal (make a
repo's opt-in → first-merge path faster + trustworthy). None hard-codes the wedge. Build.

## 2. Target segment
The owner using Massoh on any repo (the only segment). N/A "all" justification — single-segment tool.

## 3. Target region/locale
N/A (developer CLI, English). No locale hard-coding introduced.

## 4. Why now / why not
- `update` hardening — **now**: current `git pull --ff-only` aborts on a `--link`ed/edited clone;
  one bad `massoh update` erodes trust in the installer. De-risks the other two.
- `doctor` — **now**: nothing today verifies the global install matches `manifest.yml`; silent drift
  is the #1 way a portable installer rots. Read-only, cheap.
- `discover` + `STANDARDS.md` — **now**: top borrow; turns blank-stub onboarding into mined context
  and feeds the gates. Largest, so last.

## 5. Metric affected
`packet_merged` (activation-complete) + install trust → `second_repo` (retention). `discover`
directly shortens `repo_opted_in → packet_merged` (Implementer gets real standards, not stubs).

## 6. Minimal version (smallest slice that tests the hypothesis)
- **update**: before `git pull --ff-only`, detect a dirty/`--link` clone; `git stash` if dirty,
  pull, `stash pop`; on conflict, abort cleanly with a message + restore. No new flags.
- **doctor**: read `manifest.yml`; report present/missing/extra for the block, `massoh-*` agents,
  owned skills, `agent-os/`; print version + `git -C $MASSOH_HOME` short SHA; exit non-zero on drift.
  **Report only — never mutate.**
- **discover**: `massoh discover` writes `agent-project/STANDARDS.md` from a template, pre-filled by
  **heuristic scan** (detected language/build files, test command, commit convention, dir layout).
  Create-if-missing; `--force` to refresh. Add **one line** to `massoh-implementer` +
  `massoh-reviewer-qa`: "read `agent-project/STANDARDS.md` if present." Ship the `STANDARDS.template.md`.

## 7. Non-goals (explicit)
- No LLM-powered deep mining in v1 (heuristic only).
- No telemetry / `massoh report` (separate backlog item).
- No multi-harness `AGENTS.md` (deferred).
- `doctor` does not auto-fix (report only); fixing is a later `--repair`.

## 8. Required events (named, even if deferred)
`discover_run`, `doctor_run`, `doctor_drift_found` — counted by hand until `massoh report` exists.

## 9. Safety/guardrail impact
All three edit `bin/massoh` (designated safety-critical, `NON_NEGOTIABLES.md`); `doctor` reads the
manifest contract; `discover` adds a verb + writes a host file. ⇒ **Guardrail B owner-gated:** needs
explicit owner sign-off to touch `bin/massoh`. Architecture/Safety must approve. `bats` real tests
required (we have none today — `keep-older-data` + create-if-missing must be tested).

## 10. Expansion/localization impact
None. `discover` must not bake one language in — template stays language-agnostic; scan reports what
it finds, defaults to placeholders when unsure.

## 11. Acceptance criteria (testable)
- `massoh update` on a dirty/`--link` clone completes without data loss (stash→pull→pop; clean abort
  on conflict). `bats` test simulates a dirty clone.
- `massoh doctor` exits `0` on a matching install, non-zero + a diff list on drift (test: remove one
  `massoh-*` agent → non-zero). Never writes outside stdout.
- `massoh discover` creates `agent-project/STANDARDS.md` (non-empty, scan-filled), never overwrites
  without `--force`; the two role files reference it. `bats` test asserts create-if-missing.
- All existing `massoh status/on/off/install/uninstall` behavior unchanged (regression test).

## 12. Kill/defer criteria
Defer `discover` if the heuristic scan can't produce anything better than the blank template in
≤~60 lines of bash (then ship template-only + manual fill). Kill any item that would require mutating
`manifest.yml`'s contract (out of scope here).

## 13. Routing
**BUILD → route to `massoh-architecture-safety`** (technical + safety-critical files). UX skipped
(not user-facing) — recorded shortcut. No implementation packet until `03` approves **and** owner
signs off on touching `bin/massoh` (Guardrail B).

## 14. Sequencing
1) `update` hardening → 2) `doctor` → 3) `discover`. One branch, one PR (`feat: discover + doctor
verbs, harden update`) — cohesive CLI change; batching recorded as an explicit decision.
