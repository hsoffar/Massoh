# 03 — Architecture / Safety Review: TASK-2026-06-19-fix-t6

**Reviewer:** massoh-architecture-safety (Massoh role)
**Date:** 2026-06-19
**Task:** Harden T6 doctor update-check — network-flaky in CI (inbox #13, P0 bug)

---

## 1. Root cause of the flakiness (T6 line references)

T6 lives at `test/run.sh` lines 89–111. The failure-prone path is at lines 101–103:

```
d6="$(MASSOH_HOME="$W6" CLAUDE_CONFIG_DIR="$CC6" "$W6/bin/massoh" doctor 2>&1)"; rc6=$?
check "doctor exit 0 even when behind"        "[ $rc6 -eq 0 ]"
check "doctor flags 'update available'"       "echo '$d6' | grep -q 'update available'"
```

`massoh doctor` calls `git fetch -q origin` (bin/massoh line 169) when `--offline` is not set. The
test constructs a bare local remote (`$B6` at `$TMP/bare6.git`) and clones it into `$W6`, then
advances the "upstream" in `$A6` (line 98: `git push -q origin main`). The fetch at doctor-time
therefore targets `$B6` — a filesystem path, not the real GitHub remote. This is already a local
fetch, not a live network call.

However the test as written has a latent structural problem that triggers the flakiness:

**The T6 repo `$W6` is a clone of `$B6`, but `$B6` is itself a bare clone of `$REPO_ROOT`**
(line 93: `git clone -q --bare "$REPO_ROOT" "$B6"`). If the test suite runs in an environment where
`$REPO_ROOT` has no `origin` remote configured (e.g., a GitHub Actions checkout is a shallow clone
or has an HTTPS remote that requires auth / TLS), and if any upstream `git` operation within the
setup inadvertently touches the real remote, the test can hang or fail. More directly: the `git
fetch` inside doctor (line 169) runs against `$W6`'s `origin`, which is `$B6` (a temp dir). This
is correct and local. BUT — in the `$A6` advance step (line 98), `git push -q origin main` pushes
from `$A6` to `$B6`. If that push fails for any reason (shallow clone ancestry issues in CI, race
condition, disk), `$B6` is not advanced and doctor never sees a divergence, so line 103
(`grep -q 'update available'`) fails.

Additionally: if the CI runner has git network timeouts configured that affect local `git fetch`
even against `file://` paths, or if `REPO_ROOT` itself has a live `origin` that `git clone --bare`
consults during setup, any transient network issue in CI makes line 93 or 96-98 fail.

The confirmed pre-existing flakiness trace (noted in AGENT_SYNC.md 2026-06-19 RMT APPROVE entry:
"T6 'doctor flags update available' confirmed pre-existing on main (1/418 baseline)") matches this:
the test passes locally when the repo has a reachable network remote for `git clone --bare`, but
can fail in CI on network flap during setup.

**Summary of the root cause:** T6's setup (lines 93–98) clones `REPO_ROOT` bare and then pushes an
advance commit. If any git operation in that chain silently fails (network flap during bare-clone
seeding, shallow-clone issue, push ancestry problem), the remote is not ahead of `$W6` and doctor
correctly reports no update — making the assertion on line 103 fail. The test is network-dependent
in its *setup* even though the doctor fetch itself targets a local path.

---

## 2. Recommended fix: Option A — local constructed remote, deterministic offline

**Verdict: Option A. Test-only. No `bin/massoh` change required. APPROVED.**

### Why A beats B and C

Option B (stub/inject version-comparison input) would require adding an env-var or flag to
`cmd_doctor` so the test can inject the result of the `git rev-parse` comparison without a fetch.
That is a change to `bin/massoh`, a designated safety-critical file requiring owner sign-off. It
also removes coverage of the real `git fetch + rev-parse` code path.

Option C (skip-with-pass on no network) reduces assertion coverage — it means CI never validates the
"update available" string format when the runner is offline. That violates the "keep a real
assertion" constraint.

Option A requires no changes outside `test/run.sh`. The entire T6 setup can be rewritten to build
its bare remote from a **local git init** with a synthetic commit, instead of cloning `REPO_ROOT`.
Because the remote is a temp-dir bare repo with no real origin, no network call is ever needed
anywhere in the T6 setup or in the doctor fetch. The fetch (line 169 in bin/massoh) already works
against `file://` paths; this is not a new capability.

### Concrete rewrite (Option A design)

Replace lines 93–99 of `test/run.sh` with a self-contained local-remote construction:

1. Create a fresh bare repo `$B6` via `git init --bare "$B6"` (no clone of REPO_ROOT).
2. Create a working clone `$W6` from `$B6`. Add a seed commit in `$W6` and push it to `$B6`.
   This seeds the "behind" state.
3. Overlay the current working-tree binary into `$W6` exactly as now (`cp "$MASSOH" "$W6/bin/massoh"`
   etc.).
4. Create a second clone `$A6` from `$B6`, add one commit, and push it back to `$B6`. This advances
   origin/main ahead of `$W6`. No network involved.
5. Run doctor from `$W6` against `$CC6`. The `git fetch -q origin` in doctor targets `$B6`
   (a local temp dir). Doctor detects `HEAD` != `origin/main` and emits "update available".
6. The offline-safe assertions at lines 105–108 remain unchanged (set a bogus remote URL,
   run `--offline`, verify no "update available").

All assertions (lines 100–111) remain substantive and non-vacuous. No product code changes.

The key insight: **do not clone REPO_ROOT at all in T6's bare-repo setup**. Construct a synthetic
git history from scratch. This fully severs any dependency on real network or the test runner's
REPO_ROOT remote.

---

## 3. Review dimensions

### 3.1 Backend / service impact
None. Test-only change. `bin/massoh` `cmd_doctor` is unchanged.

### 3.2 Client / app impact
None.

### 3.3 API / contract impact
None. No verb signatures change.

### 3.4 DB / migration impact
None.

### 3.5 LLM / prompt impact
None.

### 3.6 Safety / guardrail risks
Low. `bin/massoh` is designated safety-critical and is NOT touched. The test harness (`test/run.sh`)
is not in the safety-critical list. The fix is purely additive/corrective in the test file.

One risk to watch: the rewritten T6 setup must still verify that `lib/verbs/` is overlaid (line 96
existing: `cp -rp "$REPO_ROOT/lib" "$W6/"`). This overlay does not depend on REPO_ROOT's git remote
— it is a filesystem copy. Keep it verbatim.

### 3.7 Expansion / localization risks
None. The fix is test-internal. No hardcoding of region or locale.

### 3.8 Required tests

**FT1 (offline determinism):** T6 must pass when the real network is unavailable. Simulate by
running `test/run.sh` in an environment with no internet access (or block outbound git via
`GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="false"` in the shell). The test must still go green.

**FT2 (real "update available" assertion preserved):** The `check "doctor flags 'update available'"
"echo '$d6' | grep -q 'update available'"` assertion (line 103) must remain a live grep against
real `massoh doctor` output. The assertion may not be weakened to a no-op, a `true`, or a vacuous
path.

**FT3 (deterministic offline-safe path preserved):** The four existing offline assertions (lines
105–108: bogus remote, `--offline`, exit 0, no "update available") must remain intact and still
pass.

**FT4 (suite count unchanged):** Total check count stays at 463 (no checks added or removed by this
fix). The T6 rewrite replaces setup code, not assertion count.

**FT5 (no other test depends on T6 state):** Confirm that `$B6`, `$W6`, `$A6`, `$CC6` are all
under `$TMP` (already true per existing code) and that they are cleaned up by the `trap 'rm -rf
"$TMP"' EXIT` at the top of the harness. No other test section reads or writes these variables.
This is already true; the rewrite must preserve this isolation.

**FT6 (online CI passes):** The existing CI job (`bash test/run.sh` in `.github/workflows/ci.yml`
line 24) must continue to go green when the runner has normal network access. The rewritten T6
makes no outbound call, so this is trivially satisfied.

### 3.9 Rollback plan
This is a test-only change in `test/run.sh`. Rollback = `git revert <commit>` on the T6 rewrite
commit. No product state is affected. The revert is safe at any time, but it restores the flaky
test — so rollback is only appropriate if a different fix strategy is chosen.

---

## 4. Conditions (FT1–FT6)

| ID | Condition | Verification |
|----|-----------|-------------|
| FT1 | T6 passes with zero outbound network access | Run suite with git fetch blocked; all 463 green |
| FT2 | "doctor flags 'update available'" check remains a live grep (not vacuous) | Code inspection: assertion line present, grep target is real doctor output |
| FT3 | Four offline-safe assertions (lines 105–108 pattern) preserved intact | Code inspection + suite run |
| FT4 | Total check count = 463 (no net add or remove) | `bash test/run.sh 2>&1 \| tail -1` must show 463 |
| FT5 | T6 setup variables isolated to `$TMP`; no cross-test state | Code inspection: all vars use `$TMP/...` prefix; trap covers cleanup |
| FT6 | CI (`.github/workflows/ci.yml`) goes green end-to-end | GitHub Actions log on PR green |

---

## 5. Impact summary

| Dimension | Impact |
|-----------|--------|
| Backend/service | None |
| Client/app | None |
| API contract | None |
| DB/migration | None |
| LLM/prompt | None |
| Safety-critical files touched | None (`bin/massoh`, `manifest.yml`, templates, policies all untouched) |
| Owner sign-off required | No (test-only; not a designated safety-critical file) |
| Expansion risks | None |
| Conditions | 6 (FT1–FT6) |
| Required tests | FT1–FT6 above; target check count 463 |
| Rollback | `git revert` on the single test-file commit |

---

## 6. Verdict

**APPROVED for implementation. Test-only. No owner sign-off required.**

- Fix strategy: **Option A** — rewrite T6's bare-remote setup to use a synthetic local git repo
  (no clone of REPO_ROOT, no real network dependency anywhere in setup or doctor fetch path).
- Scope: `test/run.sh` only. `bin/massoh` is NOT touched.
- All 6 conditions (FT1–FT6) must be satisfied before routing to massoh-reviewer-qa.
- Route: massoh-implementer → massoh-reviewer-qa → auto-merge on green (per auto-merge-on-green
  policy; test-only change, no safety-critical file involved).
