# 05 — Implementation Handoff: TASK-2026-06-19-fix-drift

- **Task ID:** TASK-2026-06-19-fix-drift
- **Implementer:** massoh-implementer
- **Date:** 2026-06-19
- **Branch:** feat/fix-drift
- **Status:** READY FOR REVIEW

---

## 1. Files changed

| File | Change |
|---|---|
| `test/run.sh` | Added `== T-DG ==` block (31 lines) after T-SR-11, before final summary (lines 3120–3149) |

No other file was modified. `bin/massoh`, `manifest.yml`, `VERSION`, `CHANGELOG`, and all `lib/verbs/` are untouched.

---

## 2. What was implemented

Added a drift-guard test block (`== T-DG: drift-guard — manifest_schema_ver() inline copy ==`) to `test/run.sh` that:

- Extracts the body of `manifest_schema_ver()` from `bin/massoh` using a pattern-anchored awk pass (DG1).
- Extracts the same function body from the SR_HELPER heredoc in `test/run.sh` using heredoc-delimiter-anchored sed + the same awk body-extraction (DG2).
- Normalizes both via `sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'` (same sed on both sides), then compares with `diff` (DG3).
- T-DG-1: asserts `diff` exits 0 (bodies are identical today).
- T-DG-2: injects `DIVERGE_MARKER` into one copy and asserts `diff` exits non-zero (non-vacuous meta-check, DG4).

---

## 3. DG1–DG4 file:line references

| Condition | Description | File | Lines |
|---|---|---|---|
| DG1 | Pattern-anchored awk extraction from `bin/massoh` (function signature → closing `}`) | `test/run.sh` | 3124–3125 |
| DG2 | Pattern-anchored extraction from SR_HELPER heredoc (sed delimiter range → awk body-extraction) | `test/run.sh` | 3134–3136 |
| DG3 | Whitespace-normalized diff comparison `diff <(printf ...) <(printf ...)` | `test/run.sh` | 3141–3142 |
| DG4 | Non-vacuous meta-check: `_dg_diverged` injects `DIVERGE_MARKER`, asserts diff exits non-zero | `test/run.sh` | 3144–3149 |

---

## 4. T-DG diff (what the diff comparison looks at)

The extracted and normalized body of `manifest_schema_ver()` (8 lines from both sides — identical):

```
local f="$MASSOH_HOME/manifest.yml"
local v
v=$(grep -m1 '^schema_version:' "$f" 2>/dev/null | awk '{print $2}') || true
if [ -z "$v" ]; then
v=$(grep -m1 '^version:' "$f" 2>/dev/null | awk '{print $2}') || true
[ -n "$v" ] && printf "  note: manifest uses deprecated 'version:' key; update to 'schema_version:' (compat until v0.19)\n" >&2 || true
fi
printf '%s' "${v:-unknown}"
```

`diff` of the two extractions produces no output (exit 0) — T-DG-1 passes.

---

## 5. Suite output (465 green)

```
== T-DG: drift-guard — manifest_schema_ver() inline copy ==
  ok   T-DG-1 manifest_schema_ver() body identical between bin/massoh and SR_HELPER
  ok   T-DG-2 drift guard is non-vacuous (detects injected divergence)

ALL GREEN — 465 checks passed.
```

---

## 6. Temp-divergence proof (T-DG-1 went RED)

Temporary edit made to `bin/massoh` line 25: changed `'^schema_version:'` to `'^schema_XXX:'`.

Result of `bash test/run.sh` with the diverged copy:

```
== T-DG: drift-guard — manifest_schema_ver() inline copy ==
  FAIL T-DG-1 manifest_schema_ver() body identical between bin/massoh and SR_HELPER [diff <(printf '%s\n' "$_dg_bin") <(printf '%s\n' "$_dg_sr") >/dev/null 2>&1]
  ok   T-DG-2 drift guard is non-vacuous (detects injected divergence)
1/465 checks FAILED.
```

T-DG-1 went RED exactly as expected. T-DG-2 remained green (still proves the guard is non-vacuous). The temp edit was then reverted. `git diff bin/massoh` is clean.

---

## 7. Risks

None. Test-only change. Zero installed-behavior impact. Rollback = revert test/run.sh addition.

---

## 8. Incomplete items

None. All DG1–DG4 conditions met; both T-DG-1 and T-DG-2 green; suite is 465/465.

---

## 9. Handoff to reviewer-qa

- Verify `diff <(awk ...)` extractions produce non-empty strings on both sides.
- Independently run `bash test/run.sh` → expect 465 green.
- Verify `git diff --name-only` shows only `test/run.sh` (plus `.agent_tasks/` artifacts).
- Confirm DG1 awk pattern anchors on line starting with `manifest_schema_ver()` at column 0 in bin/massoh (line 22).
- Confirm DG2 sed pattern anchors on literal text `^cat > "$SR_HELPER"` in test/run.sh (line 3031) and `^SR_HELPER_EOF$` (line 3045).
- Confirm T-DG-2 `_dg_diverged` is non-empty (it equals `_dg_bin` + newline + `DIVERGE_MARKER`), so `! diff` is genuinely non-vacuous.
- Route to auto-merge on green per policy.
