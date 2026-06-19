# 03 — Architecture / Safety Review
# TASK-2026-06-19-bats: test/run.sh → bats (24h queue #12, P3)

**Date:** 2026-06-19
**Agent:** massoh-architecture-safety
**Decision:** OPTION A — APPROVED (scoped/incremental pilot)

---

## 1. Material facts (verified)

| Fact | Verified value |
|---|---|
| `bats` installed locally | No (`which bats` → not found) |
| `bats` in Ubuntu apt | Yes — `bats 1.10.0-1` available |
| Current CI step | `bash test/run.sh` (`.github/workflows/ci.yml` line 21) — single `jq` dep only |
| Total `check()` calls | 457 (not 483 — live count from `grep -c 'check "'`) |
| Total test sections | 33 named sections (T1–T23, T-meta, T-MB, T-IK, T-FL, T-PR, T-BR, T-AM, T-RMT, T-SR) |
| File size | 3106 lines |
| Python3 mock servers | 23 inline `python3 -c` blocks (T18b/T18c/T18d/T19a) |
| Sleep calls | 6 (`sleep 0.3` before mock server readiness) |
| Helper functions | 8 repo-factory helpers (`mkcronrepo`, `mklearnrepo`, etc.) |
| Safety-critical checksums actively tested | `bin/massoh` + `manifest.yml` checksums asserted in T11i, T15l, T16r, T22b (cross-section) |
| CHARTER no-heavy-deps principle | "Pure-bash CLI… No runtime service… POSIX-bash, no non-portable deps" — applies to product, not test toolchain; but still a cultural signal |
| Value rating | P3 ("nicer UX") |
| Owner authorization | On record for bats in AGENT_SYNC.md 2026-06-19 row |

---

## 2. ROI / risk analysis of all three options

### Option A — Scoped/incremental pilot
Add a bats harness that runs alongside `test/run.sh` for one new section, or wraps the harness
invocation in a thin `.bats` file. `test/run.sh` stays as the source of truth and CI entry point.
The pilot proves out the workflow (bats install in CI, test authoring patterns, coverage mapping)
at low blast radius.

**Risks:**
- Adding `apt-get install -y bats` to CI adds ~5s and a new external dep; low risk, mirrors the
  existing `jq` install step pattern.
- A thin pilot `.bats` that shells out to `test/run.sh` gives no per-check granularity in the
  bats runner, but it does produce a bats-formatted report with no parity risk.
- If the pilot ports one section natively (e.g., T1 install/doctor — 6 checks), parity risk is
  confined to that section only; the rest of the suite stays green in its existing form.
- Rollback: remove the `.bats` file + revert the CI step; no assertions lost.

**Value delivered now:** bats infra wired + CI proven + one section ported as migration template.
Incremental migration of remaining sections can happen as each verb evolves.

**ROI at P3:** Reasonable. The scoped version delivers the infrastructure skeleton (the hard part)
and a documented migration pattern, without betting 457 checks on a single big port.

---

### Option B — Full big-bang port (all 457 checks)

Requires rewriting 3106 lines into `.bats` files, preserving:
- 8 repo-factory helper functions used across sections
- 23 inline Python3 mock HTTP server blocks (T18–T19) — need careful translation into setup/teardown
- 6 `sleep 0.3` mock-readiness delays
- cross-section state (e.g., `md5_massoh_before` captured in T11i and referenced in T15l/T16r/T22b
  — bats isolates `@test` scope, so cross-test variable sharing requires `load` helpers or file-based
  state, which is a significant design change)
- The `[ "$fails" -eq 0 ]` exit-code contract that CI depends on today

The cross-section `md5sum` variable sharing alone is a structural incompatibility with bats's
`@test` isolation model. Bats runs each `@test` in its own subshell. Variables set in one test
are not available in later tests unless written to a temp file and explicitly loaded — a pattern
bats calls "file-based shared state" and explicitly discourages for cross-test side effects.
This is not a cosmetic difference; it would require redesigning the checksum safety tests
(T11i/T15l/T16r/T22b) which are the most safety-important assertions in the suite.

**Coverage parity risk:** Very high. 457 checks × many helper dependencies + 23 embedded mock
servers + cross-test variable sharing = large surface for parity loss. The only way to prove
zero loss is a count/diff guard that the implementer must maintain manually — fragile.

**ROI at P3:** Not justified. The engineering cost (one full sprint) is disproportionate to
"nicer test UX" value. The current suite already produces clear `ok`/`FAIL` output and a pass
count. Bats adds TAP-formatted output and per-test timing, which are nice but P3.

---

### Option C — DEFER

The dependency risk and big-bang parity risk are real, but the owner authorized this item and
a scoped version (A) is clearly achievable. Defer would be appropriate only if even the scoped
version has unjustifiable risk, which it does not. Recommending A over C.

---

## 3. Recommended option: A (scoped/incremental)

**Rationale:**

1. The bats infra (install step + `.bats` file structure) is the hard part; it can be proven
   with a pilot that has bounded blast radius.
2. The full port (B) has a structural incompatibility (cross-test variable sharing for safety
   checksums) that makes it genuinely risky at P3 — not a reason to build it now.
3. The CHARTER POSIX-bash principle applies to the product CLI, not the test toolchain; adding
   bats to CI mirrors the existing `jq` pattern and is fine.
4. The suite is the project's safety spine (T11i/T15l/T16r/T22b assert that `bin/massoh` and
   `manifest.yml` are never mutated by feature commands). These must not regress.

**Scope of Option A (what to build):**

- Add `sudo apt-get install -y bats` to `.github/workflows/ci.yml` (mirrors the existing `jq`
  line — no new pattern).
- Create `test/massoh.bats` with a thin bats harness that:
  - In the MVP form: wraps the full `test/run.sh` invocation as a single `@test "full suite green"`
    block (TAP output, zero parity risk, CI proven).
  - Or: natively ports T1 (6 checks: install/doctor section) as a pilot of native bats authoring,
    keeping `test/run.sh` as the source of truth for all other sections.
- Document in a comment the migration path for future sections.
- `test/run.sh` stays in CI (`bash test/run.sh` step) — it is NOT removed.
- No changes to `bin/massoh`, `manifest.yml`, `templates/`, `NON_NEGOTIABLES.md`, or any
  safety-critical file.

The implementer may choose MVP-wrapper or native-T1-pilot; both are safe. If native T1, the
6 new bats assertions must be substantively equivalent to (not copies of) the T1 `check()` calls.

---

## 4. Impact analysis

**Backend/service impact:** None. Test-only change.

**Client/app impact:** None.

**API impact:** None. No contract change.

**DB/migration impact:** None.

**LLM/prompt impact:** None.

**Safety/guardrail risks:**
- The only safety risk is regression in the existing 457-check suite. Condition: `bash test/run.sh`
  must still exit 0 (all checks green) after the bats pilot is added. The bats pilot does not touch
  `test/run.sh`, so this risk is near-zero.
- No changes to designated safety-critical files (`bin/massoh`, `manifest.yml`, global-block
  markers, `templates/CLAUDE.project.template.md`).

**Expansion/localization risks:** None. Test-only.

---

## 5. Required tests (conditions for implementation approval)

| Condition | Requirement |
|---|---|
| BA1 | `bash test/run.sh` exits 0 with all existing checks green (count must be >= current 457) after any changes |
| BA2 | `bats test/massoh.bats` (or equivalent) exits 0 |
| BA3 | CI step `bash test/run.sh` is preserved; adding `bats test/massoh.bats` as an additional step is allowed but must not replace the existing step |
| BA4 | `apt-get install -y bats` added to CI before the bats step; mirrors the `jq` pattern |
| BA5 | No changes to `bin/massoh`, `manifest.yml`, `templates/`, `policies/`, or `NON_NEGOTIABLES.md` |
| BA6 | If native T1 pilot chosen: all 6 T1 bats assertions are substantive (not copy-paste of the bash one-liners; they must actually invoke `$MASSOH` and assert the result) |
| BA7 | The `.bats` file must not share or modify global state with `test/run.sh` (each harness is fully self-contained) |

**Test count target:** Existing 457 checks + at least 1 new bats `@test` block (CI-green proof).
If native T1 pilot: 457 + 6 new assertions (or ~463 total).

---

## 6. Rollback plan

If the bats CI step fails:
- Remove `test/massoh.bats` and the bats CI step.
- `test/run.sh` is untouched and remains the sole CI entry point.
- No data or product files are changed, so rollback is a single-file deletion + CI revert.
- Risk of rollback leaving the repo in a bad state: zero.

---

## 7. Explicit verdict

**OPTION A — APPROVED FOR IMPLEMENTATION.**

7 conditions (BA1–BA7). Test target: 457 existing green + 1–6 new bats assertions.

The single biggest risk is cross-test variable sharing in the safety-checksum tests
(T11i/T15l/T16r/T22b) — this is why Option B is blocked. Option A is safe because `test/run.sh`
is left intact as the source of truth and the bats pilot is purely additive.

---

## 8. Route

Route to `massoh-implementer` with this `03_architecture_safety.md` as the license.
The `04_implementation_packet.md` may be issued immediately (no additional owner sign-off required
for test-only changes; no safety-critical files touched; owner batch-authorization on record
covers test infrastructure).

Owner note: if the implementer finds that the chosen pilot section (T1 or wrapper) surfaces a
clean migration pattern, they should document it as a comment in `test/massoh.bats` to guide
future incremental section ports. The full big-bang port (B) can be reconsidered after
modularization makes sections more naturally isolated, or when bats is added to the project's
standard toolchain with explicit owner intent.
