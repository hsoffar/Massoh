# 06 — Review Result: schema-rename (24h queue #11)

**Reviewer:** massoh-reviewer-qa
**Date:** 2026-06-19
**Branch:** feat/schema-rename
**Task packet:** `.agent_tasks/TASK-2026-06-19-schema-rename/`
**Verdict:** APPROVE

---

## Verdict

**APPROVE — all SR1–SR7 conditions independently verified; 463/463 green (self-witnessed); fallback proven live; inline-copy byte-identical; scope clean.**

---

## SR1–SR7 verification (file:line)

**SR1 — Lockstep commit:**
`git diff --stat main` shows both `manifest.yml` and `bin/massoh` changed in the same working tree
diff. The only change to `manifest.yml` is the key rename (line 2 comment + line 8 value).
The only change to `bin/massoh` is the additive `manifest_schema_ver()` helper (lines 20–31).
Both files will be committed atomically. Condition MET.

**SR2 — `manifest_schema_ver()` reader (highest risk):**
- `bin/massoh` lines 20–31: function present.
- Line 25: `v=$(grep -m1 '^schema_version:' "$f" 2>/dev/null | awk '{print $2}') || true` — primary path, guarded.
- Line 26–28: `if [ -z "$v" ]` fallback to `grep -m1 '^version:'`, guarded `|| true`; if non-empty, deprecation note emitted to stderr (`>&2 || true`).
- Line 30: `printf '%s' "${v:-unknown}"` — never empty, never crashes.
- T-SR-4 proven live: synthetic manifest with only `version: 1` returns `1` + stderr contains `deprecated` (green).
- T-SR-5 proven live: manifest with neither key exits 0, output `unknown` (green).
Condition MET.

**SR3 — No other readers:**
Independent grep: `grep -rn "^version:" manifest.yml bin/ lib/ test/ templates/` — zero output.
Only the fallback grep inside `manifest_schema_ver()` (bin/massoh line 27) and the status output
string in `cmd_status` (which reads the VERSION file via `mver()`, not the manifest) remain.
The test/run.sh line 1727 `grep -q 'version:'` matches the status output line, not a manifest key.
Condition MET.

**SR4 — manifest.yml comment updated:**
- `manifest.yml` line 2: `# schema_version: 1` (was `# version: 1`).
- `manifest.yml` line 8: `schema_version: 1` (was `version: 1`).
Condition MET.

**SR5 — Three documentation references updated:**
- `CHANGELOG.md` line 4: `manifest.yml schema_version:` (was `manifest.yml version:`). Confirmed.
- `agent-project/CHARTER.md` line 43: `manifest.yml schema_version:` (was `manifest.yml version:`). Confirmed.
- `manifest.yml` line 2: updated (same as SR4). Confirmed.
Condition MET.

**SR6 — set -euo pipefail safe:**
All grep/awk in `manifest_schema_ver()` are guarded `|| true` (bin/massoh lines 25, 27, 28).
The deprecation printf is itself wrapped `|| true` on the same line as the conditional.
No unguarded subshell failures possible. Condition MET.

**SR7 — VERSION file untouched by rename logic:**
`mver()` (bin/massoh line 17): `cat "$MASSOH_HOME/VERSION"` — unchanged from main.
`git diff main -- bin/massoh` shows only the 12-line `manifest_schema_ver()` addition; `mver()` is
identical. `VERSION` file bumped 0.17.0 → 0.18.0 for the release only, not by rename logic.
T-SR-7 and T-SR-8 confirm `massoh status` and `massoh version` output unchanged. Condition MET.

---

## Test suite result (independently witnessed)

Run: `bash test/run.sh` — verbatim tail:

```
  ok   T-SR-1 schema_version: present in manifest.yml
  ok   T-SR-2 old '^version: ' absent from manifest.yml
  ok   T-SR-3 manifest_schema_ver() returns 1 (new key)
  ok   T-SR-4 fallback: old manifest returns 1
  ok   T-SR-4 fallback: deprecation note on stderr
  ok   T-SR-5 neither key: exits 0
  ok   T-SR-5 neither key: output is 'unknown'
  ok   T-SR-6 doctor --offline exits 0 on healthy install
  ok   T-SR-6 doctor output contains 'healthy'
  ok   T-SR-7 status prints '  version:' line (from VERSION, not manifest)
  ok   T-SR-8 version output matches semver pattern
  ok   T-SR-9 (T-MB-a regression) symlink status prints 'version:'
  ok   T-SR-10 manifest.yml unmutated during T-SR suite
  ok   T-SR-11 full suite green (enforced by harness exit code)

ALL GREEN — 463 checks passed.
```

T6 ("doctor flags update available") also passed in this environment (network available).
Pre-existing baseline on main: 449 checks (per AGENT_SYNC last handoff). +14 new T-SR check()
calls = 463 total. Matches handoff claim of 463/463.

Suite count breakdown: 11 required T-SR-* tests (T-SR-1 through T-SR-11) implemented as
14 check() calls (T-SR-4 has 2 assertions, T-SR-5 has 2, T-SR-6 has 2). All green.

---

## Backward-compat fallback proof

T-SR-4 (test/run.sh lines 3037–3048): Creates a synthetic `$SR4_MHOME/manifest.yml` with only
`version: 1\nnamespace: massoh\n` (no `schema_version:` key). Calls the inline helper with
`MASSOH_HOME="$SR4_MHOME"`. Asserts return value `1` and stderr contains `deprecated`.
Both assertions green. Fallback path is exercised against the real function logic.

T-SR-5 (test/run.sh lines 3050–3058): Creates a synthetic manifest with only `namespace: massoh`
(neither key). Asserts exit 0 and output `unknown`. Green.

Fallback proven.

---

## Inline-copy fidelity assessment

**FINDING: byte-identical — non-blocking (acceptable, with drift-risk note).**

The test helper `SR_HELPER` in test/run.sh lines 3015–3029 contains an inline copy of
`manifest_schema_ver()`. It was used because sourcing `bin/massoh` directly would trigger its
unconditional dispatch block (the `cmd_*` router at the bottom of the file), making isolated
function testing impossible without significant test harness surgery.

Comparison of the function body:

| Source | Lines | Status |
|--------|-------|--------|
| `bin/massoh` | 22–31 | authoritative |
| `test/run.sh` SR_HELPER | 3018–3027 | inline copy |

Both bodies are byte-identical — every line, every whitespace, the deprecation note string
including `compat until v0.19`, the `${v:-unknown}` default, and both `|| true` guards.

Risk: the inline copy could silently drift from the real function if `manifest_schema_ver()` is
updated in a future task without updating the helper. Mitigation options (non-blocking
recommendation for a future task): (a) extract a shareable helper that can be sourced without
the dispatch block, or (b) add a comment in test/run.sh cross-referencing the bin/massoh line
range so a future implementer is reminded to keep both in sync. This is not a blocker for this
task — the copy is correct today, and the test exercises the real logic faithfully.

---

## manifest-checksum baseline tests (T11i/T15l/T16r/T22b)

Confirmed: all four tests use capture-at-test-time before/after equality patterns (no hardcoded
MD5 values). T11i (test/run.sh lines 447–462) captures `md5_manifest_before` before the test
section and compares after. T15l (line 897), T16r (line 1233), T22b (line 1684) follow the same
pattern. The manifest key rename updates the captured content, but since the test verbs do not
mutate the manifest at runtime, all four still pass. All green (confirmed in the 463/463 run).

---

## Scope review

Files changed vs main (6 total — all within approved scope):
- `manifest.yml` — key rename, comment update (SR1, SR4) — APPROVED
- `bin/massoh` — additive: `manifest_schema_ver()` helper only (SR1, SR2, SR6) — APPROVED
- `CHANGELOG.md` — doc ref + [0.18.0] entry (SR5) — APPROVED
- `agent-project/CHARTER.md` — doc ref update (SR5) — APPROVED
- `VERSION` — bumped 0.17.0 → 0.18.0 (SR7, release bump) — APPROVED
- `test/run.sh` — T-SR-1…11 (103 lines, 14 check() calls) — APPROVED

AGENT_SYNC.md: untouched in working tree (confirmed `git diff main -- AGENT_SYNC.md` = empty).
AGENT_BACKLOG.md: untouched in working tree (confirmed `git diff main -- AGENT_BACKLOG.md` = empty).
Install/uninstall/block logic: untouched. `git diff main -- bin/massoh` shows 0 deletions,
12 lines added (the helper only). All core verbs byte-identical to main.
No frozen features touched. No broad refactor. No scope creep.

---

## Blocking issues

None.

---

## Non-blocking issues

**NB-1 — Inline-copy drift risk (test/run.sh lines 3015–3029):**
The SR_HELPER inline copy of `manifest_schema_ver()` is byte-identical today, but will silently
diverge if the function is updated in a future task. Recommended: add a comment in test/run.sh
above the SR_HELPER heredoc with the bin/massoh line range, or factor the function into a
sourceable helper in a future modularization pass. No action required for this task.

**NB-2 — T-SR-10 is a tautology within the T-SR suite:**
T-SR-10 captures `md5_manifest_sr_before` and `md5_manifest_sr_after` in back-to-back lines with
no intervening commands (test/run.sh lines 3094–3098). They will always be equal. The real
manifest mutation protection for the T-SR section comes from T11i/T15l/T16r/T22b earlier in the
suite. T-SR-10 is not harmful and does document intent, but it does not add real coverage.
Non-blocking — spec asked for this test, and it matches the spec description.

---

## Safety / guardrail concerns

None. manifest.yml and bin/massoh touched with owner sign-off on record (AGENT_SYNC.md
2026-06-19 decision row citing #11 schema-rename explicitly, under the batch-auth + per-item
sign-off covering manifest.yml for this task). NON_NEGOTIABLES.md lockstep rule satisfied.
No install/uninstall/block logic changed. No global-block marker changed.
POSIX-bash / set -euo pipefail safety verified (SR6).

---

## Acceptance criteria tracing

| Criterion | Result |
|-----------|--------|
| SR1 — lockstep commit | MET (both files in same diff) |
| SR2 — manifest_schema_ver() with fallback | MET (bin/massoh lines 20–31) |
| SR3 — zero other readers | MET (grep confirms) |
| SR4 — manifest comment updated | MET (manifest.yml line 2) |
| SR5 — 3 doc refs updated | MET (CHANGELOG line 4, CHARTER line 43, manifest line 2) |
| SR6 — set -euo pipefail safe | MET (all grep/awk guarded || true) |
| SR7 — VERSION file untouched by rename logic | MET (mver() unchanged; VERSION bumped for release only) |
| T-SR-1…11 green | MET (14 check() calls, all green, 463/463) |
| VERSION 0.18.0 + CHANGELOG [0.18.0] | MET |
| AGENT_SYNC.md + AGENT_BACKLOG.md untouched | MET |
| manifest↔bin lockstep | MET |

---

## Rollback plan (confirmed from packet)

Revert the PR; run `massoh install`. No data loss. Old binary has no manifest-key reader, so
old layout continues to function. The backward-compat fallback in the new binary handles the
one-release overlap window.

---

## Next action

Auto-merge feat/schema-rename per auto-merge-on-green policy.
Then unblock #12 (bats port — last item in 24h queue).
