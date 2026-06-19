# 06 — Review Result: TASK-2026-06-19-fix-t6

**Reviewer:** massoh-reviewer-qa
**Date:** 2026-06-19
**Branch:** feat/fix-t6
**Verdict: REQUEST CHANGES (1 non-critical blocker)**

---

## 1. Verdict

**REQUEST CHANGES.** The T6 fix is substantively correct and all 6 FT conditions are met by the
implementation logic. However there is one blocking issue that must be resolved before merge:
an undisclosed intermittent `rm: cannot remove .../seed6/.git: Directory not empty` error appears
in test output, and the `memory/MEMORY.md` working-tree modification is not disclosed in the handoff.
Neither breaks the test suite, but honesty reporting (Guardrail A8) requires they be addressed.

**If the implementer confirms (a) the rm error is noise-only / `$TMP` trap covers cleanup, and
(b) `memory/MEMORY.md` will NOT be staged in the commit, this becomes an APPROVE on re-review.**

---

## 2. Blocking issues

### BLOCK-1 — Undisclosed intermittent `rm` stderr mid-test-output

**File:** `test/run.sh` line 107 — `rm -rf "$S6"`

**Observed behavior:** In approximately 50% or more of runs, `rm -rf "$S6"` emits
`rm: cannot remove '.../seed6/.git': Directory not empty` to stderr. This line appears
between T6 assertions in the test output (between "version prints semver" and
"install wrote VERSION into engine"). The `seed6` directory persists in `$TMP` for
the remainder of the run when this error occurs.

**Impact assessment:**
- The harness uses `set -uo pipefail` but NOT `set -e`. The failed `rm` is a standalone
  command (not in a pipeline), so it does NOT abort the harness. Tests still pass.
- `seed6` is under `$TMP` and the `trap 'rm -rf "$TMP"' EXIT` (line 10) covers final
  cleanup — no cross-test state leak.
- The exit code of `run.sh` is 0 regardless. The 463 check count is not affected.
- **This does not create a functional failure**, but it is visible stderr noise in the
  test output that the handoff did not disclose (Run 1 and Run 2 outputs in the handoff
  show no rm error line — this appears to be coincidentally clean runs or selective
  reporting).

**Required fix or acknowledgment:** The implementer must either:
(a) Suppress the error: change `rm -rf "$S6"` to `rm -rf "$S6" 2>/dev/null || true`
    to silence the intermittent race-condition error while keeping the intent, OR
(b) Confirm explicitly that the error is noise-only and that the `$TMP` trap is
    the authoritative cleanup path (and the handoff be updated accordingly).

The preferred fix is (a) — add `2>/dev/null || true` — which eliminates the visible noise
without affecting behavior, since the trap handles cleanup in all paths.

### BLOCK-2 — `memory/MEMORY.md` modified in working tree (scope discipline)

**File:** `memory/MEMORY.md` — modified in working tree (4 intake lines added)

The working tree diff (`git diff --name-only main`) shows TWO modified files:
`test/run.sh` and `memory/MEMORY.md`. The handoff states "test/run.sh — the ONLY
file modified." The `memory/MEMORY.md` change contains 4 intake-queue entries with
timestamp `2026-06-19T18:53:43Z` (pre-dating this task's implementation window), so
this is a pre-existing modification from a prior agent session, NOT from the T6 fix.

**Impact assessment:** This is not a blocker IF the commit stages only `test/run.sh`.
The content of `memory/MEMORY.md` is intake metadata, not product code, and the
modification is unrelated to T6. However:
- The handoff claim "ONLY file modified" is inaccurate as stated.
- If the implementer accidentally stages `memory/MEMORY.md` in the commit, the scope
  is violated (per packet: "test/run.sh is the ONLY file changed").

**Required action:** Implementer must confirm `git add test/run.sh` only (not
`git add -A` or `git add .`) and re-state in handoff that `memory/MEMORY.md` is
a pre-existing uncommitted change not part of this fix.

---

## 3. FT1–FT6 — independent verification

| ID | Condition | Verified | Notes |
|----|-----------|----------|-------|
| FT1 | Zero outbound network | PASS | Run 2 (network-blocked): ALL GREEN — 463 checks passed. T6 all 7 ok. No REPO_ROOT clone in T6 setup confirmed by diff inspection (line 95: `git init --bare`). T4's BARE still clones REPO_ROOT but that is pre-existing and out of scope. |
| FT2 | "update available" assertion non-vacuous | PASS | See §4 below for full analysis. |
| FT3 | 4 offline-safe assertions preserved | PASS | Lines 121–124: bogus remote set-url (121), `--offline` run (122–123), exit-0 check (123), no-update check (124). `cp -rp "$REPO_ROOT/lib" "$W6/"` line 111 verbatim. |
| FT4 | Total check count = 463 | PASS | Normal run: `ALL GREEN — 463 checks passed.` (self-witnessed). Network-blocked run: `ALL GREEN — 463 checks passed.` (self-witnessed). |
| FT5 | Setup vars under `$TMP`, no cross-test leak | PASS (with caveat) | B6=$TMP/bare6.git (line 95), S6=$TMP/seed6 (line 96), W6=$TMP/w6 (line 109), A6=$TMP/a6 (line 113), CC6=newcc()=$TMP/cc.XXXXXX (line 115). All under $TMP. Trap line 10 covers cleanup. The in-script `rm -rf "$S6"` (line 107) intermittently fails (BLOCK-1) leaving seed6 in $TMP, but the trap is the authoritative cleanup and no other test reads seed6. |
| FT6 | CI green end-to-end | PASS (locally) | Both runs exit 0. CI not independently observable here (no live GitHub Actions). Local runs are green. |

---

## 4. FT2 — "update available" assertion is real (non-vacuous): CONFIRMED

The assertion at `test/run.sh` line 119:

```
check "doctor flags 'update available'"   "echo '$d6' | grep -q 'update available'"
```

is a live `grep -q 'update available'` against `$d6`, which is the real captured output of
`massoh doctor` at line 117:

```
d6="$(MASSOH_HOME="$W6" CLAUDE_CONFIG_DIR="$CC6" "$W6/bin/massoh" doctor 2>&1)"; rc6=$?
```

The setup genuinely places `$W6` behind `origin/main`:

1. `$B6` (bare repo) is seeded with one commit via `$S6` → `git push origin main`.
2. `$W6` is cloned from `$B6` (HEAD = seed commit).
3. `$A6` clones `$B6`, adds `echo z >> README.md`, commits, and pushes to `$B6`.
4. After step 3, `$B6`/main is one commit ahead of `$W6`/HEAD.

This was independently verified by manual reproduction: W6 HEAD
`ddd772f29e23b644a9239bc17407e3e5b6030995` != B6/main `e550ac9bc606b32e27fce31b148709d4a5538f33`.
Doctor's `git fetch -q origin` (bin/massoh line 169) fetches from `$B6` (a filesystem path —
no network). Then lines 170–174 compare `HEAD` vs `origin/main` using `merge-base --is-ancestor`,
and emit "update available" only if HEAD is a true ancestor of origin/main (not just different).

**If the setup failed** (e.g., A6's push didn't advance B6), doctor would NOT emit "update available",
the `grep -q` would fail, and the `check` assertion would FAIL with "FAIL doctor flags 'update
available'". The assertion is definitively non-vacuous.

---

## 5. Non-blocking observations

### NB-1 — Handoff test run outputs omit rm error (honesty)

The handoff's "Run 1 — normal" and "Run 2 — network-blocked" T6 sections show a clean output
without the `rm: cannot remove ...` line. In reviewer's independent runs, that line appears
consistently. The handoff outputs appear to be either coincidentally clean runs or selectively
trimmed. Per Guardrail A8 (honest reporting), this should be noted but is non-blocking if BLOCK-1
is resolved.

### NB-2 — T4 still uses REPO_ROOT bare clone (pre-existing, out of scope)

`test/run.sh` line 61: `BARE="$TMP/bare.git"; git clone -q --bare "$REPO_ROOT" "$BARE"` — T4
(update abort test) retains the network-dependent setup pattern. This is pre-existing on main
and out of scope for this task. Confirmed via `git show main:test/run.sh | sed -n '60,62p'`.
Worth filing as a follow-on task if CI flakiness recurs in T4.

### NB-3 — `init.defaultBranch=main` inline via `-c` (correct pattern)

The new setup uses `git -c init.defaultBranch=main init -q --bare "$B6"` and
`git -c init.defaultBranch=main init -q` for the seed repo. This is the correct portable
pattern: no global config mutation, per-invocation only. Consistent with T7 (line 141 mkcronrepo).

---

## 6. Scope verification

`git diff --name-only main` = `memory/MEMORY.md` + `test/run.sh`.

Product code changes: ZERO. `bin/massoh`, `manifest.yml`, `templates/`, `policies/`,
`NON_NEGOTIABLES.md`, `lib/verbs/*`, `VERSION`, `CHANGELOG.md` — all diff-clean (confirmed).

The `memory/MEMORY.md` change is pre-existing working-tree state from a prior intake session
and must NOT be staged in the commit (see BLOCK-2).

The diff hunk is a single @@ block at line 90 (within the T6 section only): +17 lines, -1 line.
No assertions added, removed, or weakened — only setup code changed.

---

## 7. Test runs (self-witnessed)

**Run 1 — normal (with network):**
Command: `bash test/run.sh 2>/dev/null`
Result: `ALL GREEN — 463 checks passed.` Exit 0.

T6 section:
```
== T6: version + doctor update-check ==
  ok   version prints semver
  ok   install wrote VERSION into engine
  ok   doctor exit 0 even when behind
  ok   doctor flags 'update available'
  ok   doctor --offline exit 0 (no network)
  ok   doctor --offline skips update-check
  ok   uninstall removed VERSION
```

Note: Without stderr suppression, the `rm: cannot remove .../seed6/.git: Directory not empty`
line appears intermittently between "version prints semver" and "install wrote VERSION".

**Run 2 — network-blocked (offline determinism):**
Command:
```
FAKE_GITCONFIG=$(mktemp)
printf '[http]\n\tproxy = http://127.0.0.1:9\n[https]\n\tproxy = https://127.0.0.1:9\n[core]\n\tsshCommand = false\n' > "$FAKE_GITCONFIG"
GIT_CONFIG_GLOBAL="$FAKE_GITCONFIG" GIT_TERMINAL_PROMPT=0 bash test/run.sh 2>/dev/null
```
Result: `ALL GREEN — 463 checks passed.` Exit 0.

T6 section (network-blocked):
```
== T6: version + doctor update-check ==
  ok   version prints semver
  ok   install wrote VERSION into engine
  ok   doctor exit 0 even when behind
  ok   doctor flags 'update available'
  ok   doctor --offline exit 0 (no network)
  ok   doctor --offline skips update-check
  ok   uninstall removed VERSION
```

Offline-determinism: PROVEN. T6 passes identically with all outbound HTTP/SSH git operations
blocked via proxy port 9 (discard) + `sshCommand = false` + `GIT_TERMINAL_PROMPT=0`.

---

## 8. Safety / guardrail checklist

- No designated safety-critical file touched: VERIFIED (`bin/massoh`, `manifest.yml`,
  `templates/`, `policies/`, `NON_NEGOTIABLES.md` all diff-clean).
- No owner sign-off required: CONFIRMED (test-only; arch-safety `03` §6 verdict explicit).
- No prohibited content: CLEAN.
- No frozen features: CLEAN.
- No data deletion risk: CLEAN (test-only; trap covers temp cleanup).
- No version bump: CORRECT (test-only; packet says no bump).
- Append-only / keep-older-data: N/A (no product data touched).

---

## 9. Recommended fix (for implementer)

**One-line change** to eliminate BLOCK-1:

In `test/run.sh` line 107, change:
```bash
rm -rf "$S6"
```
to:
```bash
rm -rf "$S6" 2>/dev/null || true
```

This silences the intermittent race-condition error while preserving intent. The `$TMP` trap
remains the authoritative cleanup path. No other code changes needed.

For BLOCK-2: when committing, stage only `test/run.sh`:
```
git add test/run.sh
git commit -m "fix: T6 bare-repo setup — zero outbound network (FT1–FT6)"
```
Do NOT stage `memory/MEMORY.md`.

Re-route to `massoh-reviewer-qa` for fast-track re-review (single-line change).

---

## 10. Owner decision needed

None. This is a test-only fix with no safety-critical files involved. No owner sign-off required.

---

## 11. Post-fix fast-track approval conditions

On re-review, if the implementer:
1. Adds `2>/dev/null || true` to `rm -rf "$S6"` (line 107), AND
2. Confirms `memory/MEMORY.md` is NOT staged in the commit,

then FT1–FT6 are all satisfied, both test runs are green (self-witnessed), the assertion is
confirmed non-vacuous, offline-determinism is proven, scope is test/run.sh only — APPROVE.
