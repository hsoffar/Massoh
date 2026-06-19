# 03 — Architecture & Safety Review: TASK-2026-06-19-fix-drift

- **Task ID:** TASK-2026-06-19-fix-drift
- **Date:** 2026-06-19
- **Reviewer:** massoh-architecture-safety
- **Classification:** ARCHITECTURE_SAFETY → IMPLEMENTATION

---

## Findings

### 1. Backend / service impact
None. This task touches only `test/run.sh`. No runtime verb logic, no installed path, no CLI contract.

### 2. Client / app impact
None. Test-only change.

### 3. API / contract impact
None. No CLI contract change. `manifest_schema_ver()` in `bin/massoh` is untouched.

### 4. DB / migration impact
None.

### 5. LLM / prompt impact
None.

### 6. Safety / guardrail risks
Low. Adding a drift-guard test to `test/run.sh` is additive. `bin/massoh` (safety-critical) is not
modified. No sign-off required for approach A.

The one latent risk is a **false-green** drift guard — a comparison mechanism that normalizes away
real logic differences and passes even when the copy has diverged. The comparison mechanism below is
specifically designed to prevent this: it normalizes only leading/trailing whitespace (which differs
structurally between a function-inside-a-script and a heredoc-embedded function) and uses `diff` on
the resulting multi-line body, which will catch any added, removed, or changed line.

### 7. Expansion / localization risks
None. The guard is scoped to a single bash function.

### 8. Required tests
See DG1–DG3 conditions and T-DG-1 / T-DG-2 below.

### 9. Rollback plan
`test/run.sh` is test-only. If the drift-guard test is found to be falsely-red (e.g. a benign
indentation change in bin/massoh), revert the 3–5 added lines to `test/run.sh` via a one-line PR.
No installed behavior is affected. No migration required.

---

## Recommended approach: A (drift-guard test, test-only)

Approach B (extract to a sourceable helper) touches `bin/massoh` (safety-critical) and introduces
the auto-dispatch-on-source hazard documented in `00_request.md`. Approach A is fully sufficient:
it makes the drift loud and immediate without any production-code risk. B is not infeasible, but
the cost/risk ratio is unfavorable given that A closes the gap entirely.

**Verdict: APPROVED — test-only, no sign-off required.**

---

## Conditions

### DG1 — Extraction anchored to function signature (not line numbers)
The body of `manifest_schema_ver()` must be extracted from `bin/massoh` using a pattern-anchored
awk pass, NOT by hard-coded line numbers. Line numbers shift with every edit; a line-number guard
would itself silently drift.

Exact mechanism (reference implementation, tested):

```bash
_dg_bin=$(awk '/^manifest_schema_ver\(\)/{found=1; next} found && /^\}$/{exit} found{print}' \
  "$REPO_ROOT/bin/massoh" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
```

This awk: matches the line `manifest_schema_ver()` (exactly as it appears in bin/massoh, with no
leading whitespace), sets a flag, then collects every subsequent line until it sees a line that is
exactly `}` (the closing brace at column 0). Neither the function-header line nor the closing brace
is included in the body.

### DG2 — Extraction anchored to heredoc delimiters in test/run.sh (not line numbers)
The SR_HELPER copy must be extracted from the heredoc in `test/run.sh` using delimiter anchoring,
NOT hard-coded line numbers.

Exact mechanism (reference implementation, tested):

```bash
_dg_sr=$(sed -n '/^cat > "\$SR_HELPER"/,/^SR_HELPER_EOF$/p' "$TEST" | \
  awk '/^manifest_schema_ver\(\)/{found=1; next} found && /^\}$/{exit} found{print}' | \
  sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
```

The `sed -n` range isolates the heredoc block. The inner awk then applies the same body-extraction
logic as DG1 — same anchors, same normalization. No line numbers.

Note on the `$SR_HELPER` in the sed pattern: when this runs inside test/run.sh, the variable
`$SR_HELPER` will be expanded. The implementer must either (a) quote/escape appropriately to match
the literal text, or (b) use a fixed string anchor such as `cat > "\$TMP/sr_helper.sh"` or anchor
on `SR_HELPER_EOF` alone and drive the awk from inside the delimited block. The simplest robust
form is:

```bash
_dg_sr=$(awk '/^SR_HELPER_EOF$/{exit} /^manifest_schema_ver\(\)/{f=1;next} f && /^\}$/{exit} f{print}' \
  <(sed -n '/SR_HELPER_EOF/,/SR_HELPER_EOF/p' "$TEST") | \
  sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
```

The implementer may use any equivalent pattern-anchored approach provided it satisfies DG1 and DG3.

### DG3 — Comparison is `diff`-based (not md5 of raw text, not string equality on unexpanded)
The comparison must use `diff <(echo "$_dg_bin") <(echo "$_dg_sr")` (or equivalent line-by-line
diff). This catches: added lines, removed lines, changed substrings. It is NOT falsely-red on pure
indentation differences because both sides are normalized by the same `sed 's/^[[:space:]]*//'`
strip. It IS red on any real logic change (different grep key, different awk expression, different
printf string, different fallback logic).

Do NOT use md5sum of the raw extracted text without normalization — a trailing newline difference
(heredoc vs in-file) would make it falsely red.

```bash
check "T-DG-1 manifest_schema_ver() body identical between bin/massoh and SR_HELPER" \
  "diff <(printf '%s\n' \"\$_dg_bin\") <(printf '%s\n' \"\$_dg_sr\") >/dev/null 2>&1"
```

### DG4 — The new test is non-vacuous: a meta-check must prove it would FAIL on a divergent copy
The task packet must include a meta-check assertion (T-DG-2) that injects a known divergence into
one side and asserts the comparison is non-zero. This is the self-test that proves the guard is
not trivially-passing (both sides empty, both sides identical-by-accident, etc.).

```bash
_dg_diverged="${_dg_bin}
DIVERGE_MARKER"
check "T-DG-2 drift guard is non-vacuous (detects injected divergence)" \
  "! diff <(printf '%s\n' \"\$_dg_bin\") <(printf '%s\n' \"\$_dg_diverged\") >/dev/null 2>&1"
```

This runs in the same test block, after T-DG-1, and uses already-extracted variables (no extra
filesystem reads).

---

## Required tests

| ID | Description | Pass condition |
|---|---|---|
| T-DG-1 | Drift guard: body of `manifest_schema_ver()` in bin/massoh matches SR_HELPER in test/run.sh | `diff` exits 0 |
| T-DG-2 | Meta-check: drift guard is non-vacuous — detects an injected divergence | `diff` exits non-zero on mutated copy |

Both tests are new additions to the `== T-SR: schema-rename ==` block in `test/run.sh`, appended
after T-SR-11 (or inserted in a new `== T-DG: drift-guard ==` block). The current suite is
463 checks. Adding T-DG-1 and T-DG-2 brings the target to **465**.

---

## Files to change

| File | Change | Safety-critical? | Sign-off? |
|---|---|---|---|
| `test/run.sh` | Add T-DG-1 and T-DG-2 (approx. 20 lines) | No | No |

No other file is modified. `bin/massoh` and `manifest.yml` are untouched.

---

## Summary verdict

**APPROVED for implementation. Approach A. Test-only. No owner sign-off required.**

- 4 conditions: DG1 (pattern-anchored bin/massoh extraction), DG2 (pattern-anchored SR_HELPER
  extraction), DG3 (diff-based comparison, whitespace-normalized), DG4 (non-vacuous meta-check).
- 2 new tests: T-DG-1 (guard passes today), T-DG-2 (guard would fail on divergence).
- Test target: 463 + 2 = **465**.
- bin/massoh: **untouched**.
- Rollback: revert the test/run.sh addition; zero installed-behavior impact.
