# 06 — Review Result: bats infra (scoped) — 24h queue #12

**Date:** 2026-06-19
**Agent:** massoh-reviewer-qa
**Branch:** feat/bats (uncommitted working tree)
**Verdict:** APPROVE

---

## Checklist walkthrough (05_REVIEW_CHECKLIST.md)

### Scope
- [x] Only the approved scope changed — git diff shows ONLY 3 tracked-file changes vs main:
  `.github/workflows/ci.yml`, `CHANGELOG.md`, `VERSION`.
  New untracked file: `test/massoh.bats` (additive, new file). Task packet folder is additive-only.
  No scope creep detected.
- [x] No broad refactor smuggled in.

### Correctness + tests
- [x] Real tests: each @test invokes `$MASSOH` against a per-test `$BATS_TEST_TMPDIR`-derived
  CLAUDE_CONFIG_DIR and asserts a real filesystem/exit condition. Not stubs. (BA6 verified below.)
- [x] Both gates green — independently witnessed (verbatim below).
- [x] Edge cases: T1-5 (read-only snapshot) and T1-6 (drift/non-zero exit) cover key failure paths.

### Guardrails
- [x] No designated safety-critical file touched — confirmed below (BA5).
- [x] No prohibited content.
- [x] No frozen features.
- [x] Keep-older-data respected (additive-only).

### Compatibility + data
- [x] No API contract change. Test-only/CI change.
- [x] No migration required. Additive new file + additive CI steps.
- [x] No feature flag required (test tooling, not a CLI verb).

### Localization / UX invariants
- [x] CLI product POSIX-bash unchanged; bats is test-toolchain only (arch-safety confirmed this
  is not covered by the POSIX-bash invariant). No touched CLI surfaces.
- [x] No locale/region hardcoding.

### Ops + trail
- [x] VERSION bumped to 0.19.0 (verified).
- [x] CHANGELOG [0.19.0] present with accurate description.
- [x] Rollback plan in 04/05: delete `test/massoh.bats` + revert 2 CI lines; run.sh untouched
  throughout — zero rollback risk.
- [x] Task packet (00–05) complete. 06 = this file.
- [x] AGENT_SYNC.md + AGENT_BACKLOG.md untouched in working tree (verified via `git diff`).

---

## BA1–BA7 independent verification

### BA5 — ZERO changes to safety-critical / product files (most critical)

```
$ git diff --name-only main
.github/workflows/ci.yml
CHANGELOG.md
VERSION

$ git diff --name-only main -- bin/massoh manifest.yml templates/ agent-os/policies/ \
    agent-project/NON_NEGOTIABLES.md lib/verbs/ test/run.sh
(empty — no output)
```

Confirmed: `bin/massoh`, `manifest.yml`, `templates/`, `policies/`, `NON_NEGOTIABLES.md`,
`lib/verbs/`, and `test/run.sh` are NOT in the diff. The new file `test/massoh.bats` is
untracked (new, not a safety-critical file). BA5 SATISFIED.

### BA2 — bats test/massoh.bats exits 0 (independently run)

```
$ bats test/massoh.bats
1..6
ok 1 T1: install copies agent-os engine into CLAUDE_CONFIG_DIR
ok 2 T1: install copies massoh-* agent files
ok 3 T1: install adds massoh:start global block to CLAUDE.md
ok 4 T1: doctor exits 0 on healthy install
ok 5 T1: doctor wrote nothing (read-only)
ok 6 T1: doctor exits non-zero on agent drift
exit: 0
```

6/6 ok. Exit 0. BA2 SATISFIED.
bats version: Bats 1.10.0 (installed at /usr/bin/bats).

### BA1 — bash test/run.sh still green (independently run)

```
$ bash test/run.sh | tail -5
  ok   T-SR-9 (T-MB-a regression) symlink status prints 'version:'
  ok   T-SR-10 manifest.yml unmutated during T-SR suite
  ok   T-SR-11 full suite green (enforced by harness exit code)

ALL GREEN — 463 checks passed.
exit: 0
```

run.sh is byte-identical to main (`git diff main -- test/run.sh` = empty).
3106 lines, 457 check() calls — unchanged. BA1 SATISFIED.
(Note: 463 reported vs 457 check() calls; difference is non-check summary assertions in
T-SR-11/harness — pre-existing, not introduced here.)

### BA3 — CI run.sh step preserved; bats step additive

`/home/hossam/dev/Massoh/.github/workflows/ci.yml`:
- Line 23–24: `- name: Run test suite` / `run: bash test/run.sh` — preserved, unchanged.
- Lines 26–27: `- name: Run bats test suite` / `run: bats test/massoh.bats` — additive.
The run.sh step is NOT removed or replaced. BA3 SATISFIED.

### BA4 — apt-get install -y bats in CI before bats step

`/home/hossam/dev/Massoh/.github/workflows/ci.yml`:
- Lines 20–21: `- name: Install bats` / `run: sudo apt-get install -y bats`
- Appears after "Install dependencies" (jq, line 18) and before "Run test suite" (line 23).
  Order: checkout → jq → bats → run.sh → bats test. Valid: bats is installed before its step.
YAML syntax valid (confirmed via `python3 yaml.safe_load`). BA4 SATISFIED.

### BA6 — Real assertions; $MASSOH invoked; real output asserted

`test/massoh.bats`:
- T1-1 (line 43): `CLAUDE_CONFIG_DIR="$cc" "$MASSOH" install` + `[ -d "$cc/agent-os" ]` — real filesystem check.
- T1-2 (line 55): `ls "$cc"/agents/massoh-*.md` — real file glob check.
- T1-3 (line 65): `grep -qF 'massoh:start' "$cc/CLAUDE.md"` — real file content check.
- T1-4 (line 75): `CLAUDE_CONFIG_DIR="$cc" "$MASSOH" doctor` — real exit 0 check.
- T1-5 (lines 85–89): `md5sum` snapshot before/after doctor — real read-only proof.
- T1-6 (lines 100–104): drift via `rm -f massoh-implementer.md` + `run bash -c "... doctor"` +
  `[ "$status" -ne 0 ]` — real non-zero exit check; `run bash -c` pattern is bats-idiomatic for
  env-var scoping. No stub, no vacuous check. BA6 SATISFIED.

### BA7 — No shared global state with run.sh

- `setup_file()` resolves `$MASSOH` from `$BATS_TEST_FILENAME` (relative to the bats file's own
  location); no sourcing or `load` from `test/run.sh`.
- Each @test uses `mktemp -d "$BATS_TEST_TMPDIR/cc.XXXXXX"` — bats 1.10.0 provides a unique
  `$BATS_TEST_TMPDIR` per @test block; temp dirs do not cross test boundaries.
- No shared variables, no shared temp files, no side effects that cross the harness boundary.
  run.sh and massoh.bats are fully self-contained. BA7 SATISFIED.

---

## Blocking findings

None.

---

## Non-blocking findings

NB-1: The CI step ordering places "Install bats" (line 20) before "Run test suite" (line 23).
This means bats is installed even when only the run.sh step runs. This is correct (mirrors
the jq pattern: install first, use after) and not a problem — just documenting for clarity.

NB-2: `test/massoh.bats` line 103 redirects stdout/stderr AFTER `run`: `run bash -c "..." >/dev/null 2>&1`.
In bats, `run` captures stdout/stderr itself; the trailing redirect is silently ignored by bats.
The test still passes because the assertion is `[ "$status" -ne 0 ]` which reads the captured
exit code, not stdout. Non-breaking, cosmetically redundant. No fix required.

---

## Missing tests

None. 6 @test blocks cover all T1 checks (install/doctor section), including read-only proof and
drift/non-zero path. Scope matches the packet exactly.

---

## Safety / guardrail concerns

None. Safety-critical files untouched. No changes to install/uninstall/block/on/off logic.
The cross-test checksum safety tests (T11i/T15l/T16r/T22b) remain in run.sh, unmodified.
These are the most safety-critical assertions in the suite; the packet correctly defers their
migration and documents the constraint in the `test/massoh.bats` header (lines 13–14).

---

## Hidden scope concerns

None. Working tree diff is exactly: 3 modified tracked files + 1 new untracked file + task packet.
No extra product code, no refactoring, no new CLI verbs.

---

## Expansion / localization concerns

None. Test-only/CI change with no CLI surface impact.

---

## Suggested patch instructions

None required. Implementation is complete and correct.

---

## Owner decision needed

None.

---

## Summary

All 7 conditions BA1–BA7 independently verified:

| Condition | Result |
|---|---|
| BA1 bash test/run.sh green | 463/463 green, exit 0 (self-witnessed) |
| BA2 bats test/massoh.bats green | 6/6 ok, exit 0 (self-witnessed) |
| BA3 run.sh CI step preserved | ci.yml line 24, confirmed |
| BA4 apt-get install -y bats in CI | ci.yml lines 20-21, before bats step, confirmed |
| BA5 zero safety-critical file changes | git diff empty for all guarded paths, confirmed |
| BA6 real assertions invoking $MASSOH | all 6 @tests invoke binary + assert real state, confirmed |
| BA7 no shared global state with run.sh | per-test BATS_TEST_TMPDIR, no load/source of run.sh, confirmed |

VERSION 0.19.0 confirmed. CHANGELOG [0.19.0] present and accurate.
AGENT_SYNC.md and AGENT_BACKLOG.md untouched in working tree.

**APPROVE. Safe to auto-merge on green per 24h-queue policy.**
