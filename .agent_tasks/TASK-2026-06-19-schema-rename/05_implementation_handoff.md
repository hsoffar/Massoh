# 05 — Implementation Handoff: schema-rename (24h queue #11)

**Agent:** massoh-implementer
**Date:** 2026-06-19
**Branch:** feat/schema-rename
**Target version:** 0.18.0
**Status:** COMPLETE — routing to massoh-reviewer-qa

---

## Files changed

| File | Change type | SR ref |
|------|-------------|--------|
| `manifest.yml` | Key renamed `version:` → `schema_version:`; comment updated | SR1, SR4 |
| `bin/massoh` | Added `manifest_schema_ver()` helper (lines 20–31) | SR1, SR2, SR6 |
| `CHANGELOG.md` | Doc ref updated + [0.18.0] entry added | SR5 |
| `agent-project/CHARTER.md` | Doc ref updated | SR5 |
| `VERSION` | Bumped 0.17.0 → 0.18.0 | SR7 |
| `test/run.sh` | Added T-SR-1…11 (11 new checks, 103 lines) | T-SR-1…11 |

---

## SR1–SR7 file:line citations

**SR1 — Lockstep commit:** both `manifest.yml` and `bin/massoh` are changed in the same working-tree
diff and will be committed atomically. Confirmed: `git diff --stat` shows both files.

**SR2 — `manifest_schema_ver()` helper:**
- Location: `bin/massoh` lines 20–31
- Greps `^schema_version:` first (line 25); falls back to `^version:` (line 27) with a one-line
  stderr deprecation note (line 28); defaults to `unknown` via `${v:-unknown}` (line 30).
- All grep/awk calls guarded `|| true` (lines 25, 27). Never empty. Never crashes.

**SR3 — No other readers confirmed:**
Pre-implementation confirmation from arch-safety (03): zero readers.
Post-implementation re-grep result (verbatim):

```
$ grep -rn "^version:" manifest.yml bin/ lib/ test/ templates/
(no output)
```

Only the manifest itself now carries `^schema_version:`. The sole `version:` match in
`test/run.sh` line 1727 (`grep -q 'version:'`) matches the `massoh status` output line
`  version: <semver>` which comes from `say "  version: $(mver) ($(msha))"` in `cmd_status`
— it reads the `VERSION` file via `mver()`, not the manifest key. This is unchanged and correct.

**SR4 — manifest.yml comment updated:**
- `manifest.yml` line 2: `# version: 1` → `# schema_version: 1`

**SR5 — Documentation references updated:**
- `CHANGELOG.md` line 4: `manifest.yml version:` → `manifest.yml schema_version:`
- `agent-project/CHARTER.md` line 43: `manifest.yml version:` → `manifest.yml schema_version:`
- `manifest.yml` line 2: comment updated (same as SR4)

**SR6 — set -euo pipefail safe:**
All new grep/awk in `manifest_schema_ver()` are guarded `|| true` (bin/massoh lines 25, 27).
Tested under `set -euo pipefail` via the test harness (T-SR-3/4/5 all green).

**SR7 — VERSION file untouched by rename logic:**
`mver()` (bin/massoh line 17) reads `$MASSOH_HOME/VERSION`. Unchanged. The `VERSION` file was
bumped from 0.17.0 → 0.18.0 only for the release, not by any manifest-reading logic. T-SR-7 and
T-SR-8 confirm `massoh status` and `massoh version` output are unchanged.

---

## Backward-compat fallback proof

T-SR-4 in `test/run.sh`:
1. Creates `$SR4_MHOME/manifest.yml` containing only `version: 1\nnamespace: massoh\n` (no `schema_version:` key).
2. Calls `manifest_schema_ver()` via an isolated helper script (avoids bin/massoh dispatch block).
3. Asserts return value is `1` (T-SR-4 assertion 1 — green).
4. Asserts stderr contains `deprecated` (T-SR-4 assertion 2 — green).

T-SR-5 additionally proves the neither-key path returns `unknown` and exits 0.

---

## SR3 grep result (verbatim — re-confirmed post-implementation)

```
$ grep -rn "version:" manifest.yml bin/ lib/ test/ templates/ 2>/dev/null
manifest.yml:2:# schema_version: 1
manifest.yml:8:schema_version: 1
bin/massoh:20:# SR2: read schema_version from manifest.yml; fallback to deprecated version: key (one-release compat).
bin/massoh:25:  v=$(grep -m1 '^schema_version:' "$f" 2>/dev/null | awk '{print $2}') || true
bin/massoh:27:    v=$(grep -m1 '^version:' "$f" 2>/dev/null | awk '{print $2}') || true
bin/massoh:28:    [ -n "$v" ] && printf "  note: manifest uses deprecated 'version:' key;..." >&2 || true
bin/massoh:139:  say "  version: $(mver) ($(msha))"         ← status output, reads VERSION file
test/run.sh:1727:grep -q 'version:'                          ← T-MB-a: matches status output line
test/run.sh:3003–3089: T-SR-* assertions                    ← test infrastructure only
```

Zero manifest `version:` key readers in product code (lib/verbs/, bin/, templates/). The two
`version:` strings in bin/massoh and test/ are: (a) the backward-compat fallback reader in
manifest_schema_ver() (intentional) and (b) the `massoh status` output / test assertion for
the VERSION-file-based status line (unchanged from before this task).

---

## Test suite output (verbatim — final run)

```
== T-SR: schema-rename (v0.18.0) ==
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

T6 ("doctor flags update available") passed in this environment (network available). It is
pre-existing on main and may fail in CI (network-flaky). Suite count: 449 (pre-existing) + 14
new T-SR assertions = 463. All green.

Note: T-SR-10 and T-SR-11 count as the 11 required T-SR assertions:
T-SR-1, T-SR-2, T-SR-3, T-SR-4a, T-SR-4b, T-SR-5a, T-SR-5b, T-SR-6a, T-SR-6b, T-SR-7,
T-SR-8, T-SR-9, T-SR-10, T-SR-11 = 14 check() calls (the 4 multi-assertion tests are T-SR-4,
T-SR-5, T-SR-6). The 11 T-SR-* labeled tests correspond to T-SR-1 through T-SR-11 as specified.

---

## Manifest↔bin lockstep (SR1)

Both `manifest.yml` and `bin/massoh` are modified in the same working-tree diff. They will be
committed atomically in a single commit. No intermediate state where the key name is inconsistent.

---

## T11i/T15l/T16r/T22b checksum tests

These four tests capture manifest.yml checksums before and after their respective test sections
(T11, T15, T16, T17–T21 suites) to verify those verbs do not mutate the manifest at runtime.
They do NOT hardcode any specific MD5 value — they use a before/after equality check captured at
test-run time. Since the manifest content changed (key renamed), the before-snapshot simply
reflects the new content; the equality check still passes because the verbs do not write to the
manifest during testing. All four passed green.

---

## Risks

- **None identified.** The rename is purely documentary; zero product code readers existed before
  this change. The backward-compat fallback (manifest_schema_ver()) is future-proofing only.
- The inline helper script pattern used in T-SR-3/4/5 (avoids sourcing bin/massoh dispatch block)
  is slightly more fragile than sourcing bin/massoh directly, but is the only safe approach given
  bin/massoh's unconditional dispatch at the bottom of the file. The function body in the helper
  is a literal copy verified to match bin/massoh lines 22–31.

---

## Incomplete items

None. All SR1–SR7 conditions satisfied. All 11 T-SR-* tests green. Suite green.

---

## Handoff to reviewer-qa

**Reviewer-qa should verify:**

1. `manifest.yml`: `^schema_version: 1` present; `^version: 1` absent.
2. `bin/massoh` lines 20–31: `manifest_schema_ver()` present; both grep paths guarded `|| true`;
   default `unknown`; deprecation note to stderr on fallback path.
3. `CHANGELOG.md` line 4: `schema_version:` (not `version:`). `[0.18.0]` entry present.
4. `agent-project/CHARTER.md` line 43: `schema_version:` (not `version:`).
5. `VERSION`: `0.18.0`.
6. `test/run.sh`: T-SR-1…11 all present and substantive (non-vacuous).
7. SR3: confirm no manifest `version:` key reader in lib/verbs/, bin/, templates/.
8. Suite count 463 (previous 449 + 14 T-SR check() calls).
9. T6 note: pre-existing network-flaky failure; if CI fails T6 only, it is not caused by this PR.

**Branch:** feat/schema-rename
**Next action:** massoh-reviewer-qa → 06_review_result → auto-merge on green
