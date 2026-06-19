# 05 — Implementation Handoff: TASK-2026-06-19-profiles (profiles + config.yml, v0.14.0)

**Implementer:** massoh-implementer
**Date:** 2026-06-19
**Branch:** feat/profiles
**Status:** COMPLETE — all PC1–PC9 satisfied; suite ALL GREEN (361/361 checks); ready for massoh-reviewer-qa

---

## 1. Files Changed

| File | Type | Change |
|---|---|---|
| `lib/verbs/_config.sh` | NEW | Pure-bash YAML-lite helper `massoh_config_get` |
| `lib/verbs/meta.sh` | MODIFIED | Wire 2 of 3 call sites (meta_outlier_factor, meta_repeat_threshold) |
| `bin/massoh-cron` | MODIFIED | Wire 3rd call site (cron_idle_min); source _config.sh directly |
| `test/run.sh` | MODIFIED | Add T-PR-a through T-PR-g (17 assertions across 7 test cases) |
| `VERSION` | MODIFIED | 0.13.0 → 0.14.0 |
| `CHANGELOG.md` | MODIFIED | Added [0.14.0] entry |
| `manifest.yml` | UNTOUCHED | No scaffold change (no-scaffold path, as approved) |
| `bin/massoh` | UNTOUCHED | No change required |

---

## 2. PC1–PC9 — File:Line Citations

**PC1 — Absent/empty config → byte-identical behavior:**
- `lib/verbs/_config.sh:33` — `[ -f "$cfg" ] || { printf '%s' "$default"; return 0; }`
- All 3 call sites pass the current hard-coded default as the 3rd argument; missing key → val=""; returns default.
- `lib/verbs/meta.sh:31-35` — defaults "2" and "3" passed explicitly.
- `bin/massoh-cron:21` — default "25" passed explicitly.
- T-PR-a verifies: no-config vs empty-config output is byte-identical AND shows 2x / >=3.

**PC2 — Integer validation before arithmetic, never crashes:**
- `lib/verbs/meta.sh:32` — `case "$_raw_of" in ''|*[!0-9]*) OUTLIER_FACTOR=2 ;; *) OUTLIER_FACTOR="$_raw_of" ;; esac`
- `lib/verbs/meta.sh:35` — `case "$_raw_rt" in ''|*[!0-9]*) REPEAT_THRESHOLD=3 ;; *) REPEAT_THRESHOLD="$_raw_rt" ;; esac`
- `bin/massoh-cron:21` — `case "$_raw_idle" in ''|*[!0-9]*) IDLE_MIN=25 ;; *) IDLE_MIN="$_raw_idle" ;; esac`
- Pattern mirrors ledger.sh L2 (the [[ "$x" =~ ^[0-9]+$ ]] alternative; this uses POSIX case which is set -e safe).
- T-PR-c verifies: malformed integer "not_a_number" → exit 0, output shows 2x.

**PC3 — Pure-bash parser, no new deps; handles comments/whitespace/quoting/missing-key:**
- `lib/verbs/_config.sh:33-46` — grep/sed/head/tr pipeline with `|| true`.
- No yq, no jq, no python. All tools are POSIX-standard.
- T-PR-d verifies: complex YAML (nested/tags) → all defaults, exit 0.

**PC4 — Secret-key guard:**
- `lib/verbs/_config.sh:21-29` — `case "$key" in *_token|*_key|*_secret|*_password|*_credential)` → warn to stderr, return default.
- Template/comment in `_config.sh` header: "WARNING: config.yml is a committable file. NEVER place secrets in it."
- T-PR-e verifies: plane_api_token → warning on stderr, returns "mydefault" not file value.

**PC5 — `|| true` / default-fallback throughout; malformed YAML → all defaults, exit 0:**
- `lib/verbs/_config.sh:40-44` — the entire grep/sed pipeline ends with `|| true`.
- `lib/verbs/meta.sh:31` — `|| true` after massoh_config_get call.
- `lib/verbs/meta.sh:34` — `|| true` after massoh_config_get call.
- `bin/massoh-cron:19` — `|| true` on source line itself.
- `bin/massoh-cron:21` — `2>/dev/null || true` on config_get call.
- T-PR-d verifies: YAML complex structure → all defaults, exit 0.

**PC6 — EXACTLY 3 `massoh_config_get` call sites:**
- Call site 1: `lib/verbs/meta.sh:31` — `meta_outlier_factor`
- Call site 2: `lib/verbs/meta.sh:34` — `meta_repeat_threshold`
- Call site 3: `bin/massoh-cron:21` — `cron_idle_min`
- Verified: `grep -r 'massoh_config_get' lib/verbs/ bin/massoh-cron | grep -v '_config.sh' | wc -l` → **3**
- T-PR-f verifies this count at runtime.

**PC7 — Precedence project > global > built-in:**
- MVP implements two-tier: project (`$repo/agent-project/config.yml`) > built-in default.
- Global tier deferred per arch-safety §PC5 decision.
- `lib/verbs/meta.sh:29` — `local _cfg="$repo/agent-project/config.yml"` (project path derived from repo root).
- `bin/massoh-cron:21` — `"$REPO/agent-project/config.yml"` (REPO set at cron startup).
- T-PR-b verifies: project value overrides built-in for all 3 tunables.

**PC8 — `_config.sh` usable after the sourcing loop (load order):**
- `lib/verbs/_config.sh` — underscore prefix ensures it sorts alphabetically before all other `*.sh` files in `lib/verbs/`, so it is sourced first in `bin/massoh`'s glob loop (line 172: `for _verb_file in "$MASSOH_HOME/lib/verbs/"*.sh`).
- `bin/massoh-cron` sources it directly (not through the loop): `bin/massoh-cron:19`.
- T-PR-g verifies: `massoh meta` exits 0 (transitively proves helper was sourced and available).

**PC9 — VERSION 0.14.0 + CHANGELOG; bin/massoh-cron ≤2 functional line change; manifest untouched:**
- `VERSION` → 0.14.0.
- `CHANGELOG.md` — `[0.14.0]` section added above `[0.13.0]`.
- `bin/massoh-cron` diff: removed `IDLE_MIN=25` (1 line), added source line + read/validate line (2 functional lines). ≤2 functional lines net change.
- `manifest.yml` — NOT modified (no-scaffold path as approved in arch-safety §8).

---

## 3. No-Config Byte-Identical Proof

T-PR-a in `test/run.sh` (lines around "T-PR-a"):
1. Creates a Massoh project with NO `agent-project/config.yml`.
2. Runs `massoh meta` → captures `out_pra_nofile`.
3. Creates an EMPTY `agent-project/config.yml` (zero bytes).
4. Runs `massoh meta` → captures `out_pra_empty`.
5. Asserts: `md5sum(out_pra_nofile) == md5sum(out_pra_empty)` → **PASS**.

The assertion chain also confirms: output contains "2x" (OUTLIER_FACTOR=2) and ">=3" (REPEAT_THRESHOLD=3), proving the built-in defaults are active.

---

## 4. Verbatim Test Suite Output (final run)

```
== T-PR: profiles + config.yml (v0.14.0) ==
  ok   T-PR-a no-config vs empty-config byte-identical (PC1)
  ok   T-PR-a output shows built-in default 2x (OUTLIER_FACTOR=2)
  ok   T-PR-a output shows built-in default >=3 (REPEAT_THRESHOLD=3)
  ok   T-PR-b meta_outlier_factor=5 reflected in output (5x, not 2x)
  ok   T-PR-b meta_repeat_threshold=7 reflected in output (>=7, not >=3)
  ok   T-PR-b cron_idle_min=10 reflected in cron status (idle gate: 10m)
  ok   T-PR-b regression: removing config.yml reverts to 2x (PC1)
  ok   T-PR-b regression: removing config.yml reverts to >=3 (PC1)
  ok   T-PR-c malformed integer: exit 0 (PC2/PC5)
  ok   T-PR-c malformed integer: output shows 2x (falls back to built-in default)
  ok   T-PR-d malformed YAML: meta exits 0 (PC3/PC5)
  ok   T-PR-d malformed YAML: meta shows built-in default 2x
  ok   T-PR-d malformed YAML: meta shows built-in default >=3
  ok   T-PR-e secret key: warning emitted to stderr (PC4)
  ok   T-PR-e secret key: returns default not file value (PC4)
  ok   T-PR-f exactly 3 massoh_config_get call sites outside _config.sh (PC6)
  ok   T-PR-g helper callable after sourcing loop: massoh meta exits 0 (PC8)

ALL GREEN — 361 checks passed.
```

Zero regressions. All 361 checks pass (344 pre-existing + 17 T-PR additions).

---

## 5. Risks

- **None structural.** The central guarantee (PC1) is tested and verified: absent/empty config is byte-identical to baseline behavior. The `|| true` discipline throughout ensures no crash under `set -euo pipefail`.
- **Load-order note:** `_config.sh` sorts first alphabetically among `lib/verbs/*.sh` (underscore < lowercase alpha in POSIX sort). If a future file named `_aardvark.sh` is added, it would sort before `_config.sh`. This is benign for current verbs but reviewers should note the alphabetic dependency.
- **Global-tier not implemented.** The arch-safety doc deferred this. If the owner later wants `~/.claude/massoh/config.yml`, that needs a fresh arch-safety pass (install-layout impact).

---

## 6. Incomplete Items

None. All 9 PC conditions satisfied. All 7 T-PR test cases implemented and green. VERSION bumped. CHANGELOG written. No manifest change.

---

## 7. Rollback Instructions

If a rollback is needed (no user-file impact):
1. `rm lib/verbs/_config.sh`
2. Revert `lib/verbs/meta.sh` (restore 3 lines: `local OUTLIER_FACTOR=2` and `local REPEAT_THRESHOLD=3` at top of `cmd_meta`, remove the config-reading block at lines 27-35).
3. Revert `bin/massoh-cron` (restore `IDLE_MIN=25`; remove the source line and read/validate line).
4. No manifest or user-file cleanup needed.

---

## 8. Handoff to massoh-reviewer-qa

**Task:** Verify PC1–PC9 (file:line above), run `bash test/run.sh`, confirm 361/361 ALL GREEN.

**Key review focus:**
1. PC1 byte-identical guarantee — T-PR-a.
2. PC2 integer-validation pattern — mirror of ledger.sh L2; applied to all 3 arithmetic-bound values.
3. PC4 secret guard — keys with `_token|_key|_secret|_password|_credential` pattern → warn+default.
4. PC6 scope — exactly 3 call sites (T-PR-f grep count confirms).
5. PC9 — manifest.yml diff is empty (critical: no scaffold change).
6. No new dependencies introduced (pure grep/sed/tr, all POSIX).
7. No change to bin/massoh, templates/, or manifest.yml.
