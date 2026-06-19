# 05 — Implementation Handoff: bats infra (scoped) — 24h queue #12

**Date:** 2026-06-19
**Agent:** massoh-implementer
**Branch:** feat/bats
**Target version:** 0.19.0

---

## Files changed

| File | Change |
|---|---|
| `test/massoh.bats` | NEW — 6 bats @test blocks (T1 native pilot: install/doctor) |
| `.github/workflows/ci.yml` | Added "Install bats" step + "Run bats test suite" step (additive) |
| `VERSION` | 0.18.0 → 0.19.0 |
| `CHANGELOG.md` | Added [0.19.0] entry (bats infra + migration template note) |

No other files touched. Zero changes to `bin/massoh`, `manifest.yml`, `templates/`, `policies/`,
or `NON_NEGOTIABLES.md` (BA5).

---

## BA1–BA7 verification (file:line)

**BA1** — `bash test/run.sh` exits 0, all existing checks green.
Result: `ALL GREEN — 463 checks passed.`
Command run: `bash test/run.sh`
Note: T6 (doctor update-check network) passed in this run. Pre-existing flakiness noted in
arch-safety doc and AGENT_SYNC.md — not caused by this change (test/run.sh not touched).

**BA2** — `bats test/massoh.bats` exits 0.
Result: TAP 1..6, all 6 `ok`. Output:
```
1..6
ok 1 T1: install copies agent-os engine into CLAUDE_CONFIG_DIR
ok 2 T1: install copies massoh-* agent files
ok 3 T1: install adds massoh:start global block to CLAUDE.md
ok 4 T1: doctor exits 0 on healthy install
ok 5 T1: doctor wrote nothing (read-only)
ok 6 T1: doctor exits non-zero on agent drift
```

**BA3** — CI step `bash test/run.sh` preserved.
File: `.github/workflows/ci.yml` line 24: `run: bash test/run.sh`
The bats step (line 27: `run: bats test/massoh.bats`) is additive; the run.sh step is kept intact.

**BA4** — `apt-get install -y bats` added to CI before the bats step.
File: `.github/workflows/ci.yml` lines 20-21: step "Install bats" / `run: sudo apt-get install -y bats`
This step appears after "Install dependencies" (jq) and before "Run test suite", consistent with
the jq pattern.

**BA5** — Zero changes to safety-critical files.
Verified: `git diff --name-only HEAD` = `.github/workflows/ci.yml CHANGELOG.md VERSION` only.
New untracked: `test/massoh.bats` (new file, not a safety-critical file).
`bin/massoh`, `manifest.yml`, `templates/`, `policies/`, `NON_NEGOTIABLES.md` — all untouched.

**BA6** — All 6 bats @test blocks invoke `$MASSOH` and assert real output/exit codes.
- `test/massoh.bats` lines 43, 53, 63, 73, 83-86, 97-103: every @test calls `"$MASSOH"` with
  `CLAUDE_CONFIG_DIR` set to a throwaway tmpdir, then asserts a real filesystem condition or exit code.
- T1-5 (read-only): uses `find`+`ls -la`+`md5sum` snapshot pattern — same as `test/run.sh` lines 26-29.
- T1-6 (drift): uses `run bash -c "CLAUDE_CONFIG_DIR='$cc' '$MASSOH' doctor"` then `[ "$status" -ne 0 ]`.
  (Note: `run` in bats does not accept inline `VAR=val cmd` env-var syntax, so a subshell is required
  — this is the correct bats-idiomatic pattern; verified no warnings in final run.)

**BA7** — `.bats` shares no global state with `test/run.sh`.
- `test/massoh.bats` uses `setup_file()` to set `$MASSOH` from its own `$BATS_TEST_FILENAME`-relative path.
- Each @test uses `$BATS_TEST_TMPDIR` (bats 1.10.0: unique per @test) for throwaway CLAUDE_CONFIG_DIR.
- No variables, files, or side effects cross the harness boundary. run.sh and massoh.bats each
  create and clean up their own temp dirs independently.

---

## bats run result

**bats installed:** `sudo apt-get install -y bats` → `bats 1.10.0-1` (Ubuntu 24.04 apt)
**bats binary:** `/usr/bin/bats` (Bats 1.10.0)
**Result:** GREEN — 6/6 @test blocks pass, no warnings, clean TAP output.

Command: `bats test/massoh.bats`
Exit code: 0

---

## run.sh result

Command: `bash test/run.sh`
Result: `ALL GREEN — 463 checks passed.`
Exit code: 0
T6 network: passed in this run (T6 is pre-existing env-flaky, not caused by this change).

---

## CI yaml diff

```diff
+      - name: Install bats
+        run: sudo apt-get install -y bats
+
       - name: Run test suite
         run: bash test/run.sh
+
+      - name: Run bats test suite
+        run: bats test/massoh.bats
```

The existing "Run test suite" step is line 24 (unchanged). Bats install is at line 20, bats run is line 27.

---

## Risks

1. **None material.** bats is an additive CI step; if bats fails for any reason, rollback is: delete
   `test/massoh.bats` + revert the two CI lines. `test/run.sh` is untouched throughout.
2. **T1-6 subshell pattern:** using `run bash -c "..."` for the drift test is bats-idiomatic when env
   vars must prefix a command. Verified no warnings with this pattern in bats 1.10.0.
3. **T6 network flakiness:** pre-existing, not introduced here. run.sh T6 passed in this run.

---

## Incomplete items

None. All BA1–BA7 conditions satisfied. The migration template comment in `test/massoh.bats` (lines 7–16)
documents future porting constraints (cross-test checksum chain, inline mock servers) as requested.

---

## Handoff to reviewer-qa

Route: massoh-reviewer-qa — check the following:

1. **BA1:** Run `bash test/run.sh` → expect ALL GREEN (463 checks). Note: T6 network may vary by env.
2. **BA2:** Run `bats test/massoh.bats` → expect 6/6 ok, exit 0.
3. **BA3:** `.github/workflows/ci.yml` line 24: `bash test/run.sh` step intact.
4. **BA4:** `.github/workflows/ci.yml` lines 20-21: "Install bats" step before "Run bats test suite".
5. **BA5:** `git diff --name-only HEAD feat/bats` must NOT include `bin/massoh`, `manifest.yml`,
   any file under `templates/`, `policies/`, or `NON_NEGOTIABLES.md`.
6. **BA6:** Each @test in `test/massoh.bats` invokes `"$MASSOH"` and asserts a real condition.
7. **BA7:** `test/massoh.bats` uses only `$BATS_TEST_TMPDIR`-derived state; no shared vars with run.sh.
8. **VERSION:** `VERSION` file = `0.19.0`.
9. **CHANGELOG:** `[0.19.0]` entry present in `CHANGELOG.md` with bats infra + migration template note.

No deferred features. No scope creep. Safe to auto-merge on green per the 24h-queue policy.
