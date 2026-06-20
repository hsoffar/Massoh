# 06 — Review Result: Fleet slice 3 — `massoh fleet learn`

- **Reviewer:** massoh-reviewer-qa
- **Date:** 2026-06-20
- **Branch:** `feat/fleet-learn`
- **Verdict:** APPROVE

---

## 1. Verdict

**APPROVE.**

All 8 mandatory conditions FLN1–FLN8 are independently verified. The promotion boundary is intact
(no engine file is ever written). Zero-LLM, zero-spend, and read-only-on-discovered-repos are all
independently reproduced. Suite 574/574 green (independently run twice). One non-blocking issue
noted (T-FLN-6a timestamp fragility, disclosed by implementer). No scope creep. No safety-critical
file modified.

---

## 2. Test Result (verbatim)

```
ALL GREEN — 574 checks passed.
```

Baseline: 544. New T-FLN checks: 30 assertions across T-FLN-1 through T-FLN-8.
(Handoff claimed 574; independently reproduced: 574. Count matches.)

---

## 3. Checklist Walk

### Scope
- [x] Only approved scope changed: `lib/verbs/fleet.sh` (+cmd_fleet_learn, +learn dispatch, +help
  text), `test/run.sh` (+T-FLN-* tests), `VERSION` (0.22.0→0.23.0), `CHANGELOG.md` ([0.23.0]).
  AGENT_SYNC.md contains additive prior-slice review records (rolling update, expected).
- [x] No broad refactor.
- [x] `scripts/massoh-dashboard` unmodified (browser learn-button PARKED, confirmed by
  `git diff HEAD -- scripts/massoh-dashboard` returning empty).
- [x] `bin/massoh` unmodified. `manifest.yml` unmodified.

### Correctness + Tests
- [x] T-FLN-1 through T-FLN-8: substantive tests, all exercise real execution path. No stubs.
- [x] Suite 574/574 green (independently run).
- [x] FLN4 promotion boundary: independently reproduced live (see §4 below).

### Guardrails
- [x] No safety-critical file modified (bin/massoh, manifest.yml, templates/, policies/,
  NON_NEGOTIABLES.md, global-block). Confirmed by: `git diff HEAD -- agent-os/ bin/massoh
  manifest.yml templates/ scripts/massoh-dashboard` → empty.
- [x] No prohibited content.
- [x] No frozen feature.
- [x] Append-only / keep-older-data: no destructive writes anywhere.

### Compatibility + Data
- [x] Additive subcommand. Existing `massoh fleet` behavior unchanged.
- [x] No migration needed.
- [x] No feature flag required (CLI tool; additive verb = default-off on existing installs).

### Ops + Trail
- [x] VERSION 0.23.0. CHANGELOG [0.23.0] accurate.
- [x] Rollback stated in 03: remove `learn)` dispatch + `cmd_fleet_learn` from fleet.sh.
- [x] AGENT_SYNC.md updated (rolling update with prior review rows + Last handoff).
- [x] 05_slice3_handoff.md written.

---

## 4. FLN Condition Verification (Independent)

### FLN1 — Zero LLM / zero network / zero spend

Static grep independently reproduced:
```
awk '/^cmd_fleet_learn\(\)/{f=1} f && /^\}$/{f=0; next} f' lib/verbs/fleet.sh \
    | grep -wE 'claude|curl|wget'   → (empty) PASS
awk '/^cmd_fleet_learn\(\)/{f=1} f && /^\}$/{f=0; next} f' lib/verbs/fleet.sh \
    | grep -vE 'agent-project|agent-os' | grep -wE 'agent'  → (empty) PASS
```
T-FLN-5a/b/c/d all green.

### FLN2 — Read-only on discovered repos

Live byte-snapshot reproduced:
```
repo-x before: ccbddc5a52f42ffdbfcb53fe5858ab19
repo-x after:  ccbddc5a52f42ffdbfcb53fe5858ab19   PASS
repo-y before: db8d25749e643c85452d85aa47101ee6
repo-y after:  db8d25749e643c85452d85aa47101ee6   PASS
```
T-FLN-2a/b green.

### FLN3 — Single named write var + SAFETY comment

```
lib/verbs/fleet.sh:923   local FLEET_LEARNINGS="$repo/agent-project/FLEET_LEARNINGS.proposed.md"  # SAFETY: only permitted write in cmd_fleet_learn
lib/verbs/fleet.sh:1151  } > "$FLEET_LEARNINGS"  # SAFETY: only permitted write in cmd_fleet_learn (FLN3)
```
The only `>` redirect in `cmd_fleet_learn` is at line 1151, targeting `$FLEET_LEARNINGS`.
No other output redirect or write operator present. Confirmed by exhaustive grep of `>` in function body.

### FLN4 — Promotion boundary: candidates-only, no engine write (CRITICAL)

Live run independently reproduced:
```
$ MASSOH_FLEET_ROOT=<tmp> massoh fleet learn --write-proposals

[generalizable-candidate] (repos=2, sources=beta, alpha): shared lesson: always guard grep calls
[project: gamma] (repos=1, sources=gamma): gamma-only unique lesson
[project: alpha] (repos=1, sources=alpha): alpha-only lesson about naming
```

Written file header (confirmed present):
```
> CANDIDATES ONLY — engine adoption is a separate owner/gated step.
```

Engine-untouched git diff: `git diff HEAD -- agent-os/ bin/massoh manifest.yml templates/ scripts/massoh-dashboard` → **empty**.

T-FLN-4a (lib/verbs unchanged), T-FLN-4b (agent-os unchanged), T-FLN-4c (bin/massoh unchanged),
T-FLN-4d (manifest.yml unchanged), T-FLN-4e (templates unchanged), T-FLN-4f (discovered repo
byte-snapshot unchanged) — all green.

No auto-promote-to-engine path exists anywhere in `cmd_fleet_learn`. Only one write statement
in the entire function, at line 1151, targeting `$FLEET_LEARNINGS` in this repo's
`agent-project/`.

### FLN5 — Leak guard

- Basename only: independently confirmed (no absolute path appears in stdout or written file;
  live test with `/tmp/...` path as fleet root → output says `my-project`, not the tmp path).
- Line cap: `head -c 500` at lines 1009, 1031; `head -n 100` at lines 1002, 1024.
- No raw dump: `grep -E '^\- '` extracts only bullet lines from proposals.
- Local only: FLN1 enforces zero network.

### FLN6 — `set -euo pipefail` + `|| true` + per-repo degrade

- `set -euo pipefail` at line 918.
- `grep ... 2>/dev/null ... || true` at lines 1002, 1024.
- Full awk+sort pipeline guarded with `|| true` at line 1080.
- Per-repo degrade confirmed live: no-proposals repo → `[skip] no-proposals: no LEARNINGS.proposed.md or META.proposed.md found`, exit 0. T-FLN-3a/b/c green.

### FLN7 — Idempotent (Pattern A: sentinel-regenerate)

Pattern A declared and implemented. File fully regenerated fresh each run.
No duplicate-entries risk. T-FLN-6b confirms content integrity across two runs.

See NB-1 below for test fragility note.

### FLN8 — Sanitize `|` + backticks; named threshold constant

- `FLEET_REPEAT_THRESHOLD=2` named constant at line 926.
- Sanitization: `sed 's/|/ /g; s/\`/'"'"'/g'` at lines 1009, 1031.
- Live test: lesson containing `| pipe and \`backtick\`` → no raw `|` or `` ` `` in output.
- `printf '%s'` with named variables only; no unquoted `$()` in write block.
- T-FLN-8b/c/d green.

---

## 5. Blocking Issues

None.

---

## 6. Non-Blocking Issues

### NB-1 — T-FLN-6a timestamp fragility (test fragility, not a product bug)

Pattern A regenerates the file with a `Generated: <timestamp>` line on every run. Two runs that
cross a second boundary produce files with different timestamps, hence different md5 sums. The test
T-FLN-6a (`check "... identical md5"`) passes only because consecutive bash commands typically land
within the same second.

The implementer disclosed this: "Two runs within the same second produce identical md5." The
product behavior is correct (no duplicate entries, no corruption) and FLN7's core requirement
("must not duplicate entries endlessly") is fully met.

Recommendation for a follow-up patch: strip or exclude the `Generated:` line when computing
the idempotency md5, or compare content minus the timestamp line. Example fix for T-FLN-6a:
```
fln6_md5_run1="$(grep -v '^> Generated:' "$FLEET_LEARN_FILE" | md5sum | awk '{print $1}')"
# ... second run ...
fln6_md5_run2="$(grep -v '^> Generated:' "$FLEET_LEARN_FILE" | md5sum | awk '{print $1}')"
```
This is a test improvement, not a product fix. Does not block merge.

### NB-2 — awk associative-array ordering for same-count lessons

The handoff correctly notes that `sort -k2 -rn` sorts by recurrence count descending, but
within the same count, awk associative-array iteration order is unspecified. In testing (3 runs
on the same dataset), the output was stable, but this is not guaranteed across awk implementations.
For the MVP this is acceptable (candidates list is for human review, not machine parsing).
Does not block merge.

### NB-3 — AGENT_SYNC.md rolling updates from prior slices

The working-tree AGENT_SYNC.md contains additive approval rows for slices 1b and 1c (which the
prior reviewer confirmed in the 1c review NB-1). These pre-date this slice 3 implementation and
are not modifications introduced by the slice 3 implementer.

---

## 7. Safety / Guardrail Concerns

None. The promotion boundary (FLN4) is the highest-risk requirement and it is verified:
- One named write variable (`$FLEET_LEARNINGS`).
- One write statement in the function (line 1151).
- Targets this repo's `agent-project/FLEET_LEARNINGS.proposed.md` only.
- Engine files (agent-os/, lib/verbs/, bin/massoh, manifest.yml, templates/) are bytewise
  identical before and after a run. Confirmed by T-FLN-4a–f and by live git diff.
- No auto-promote-to-engine path exists. The file header explicitly states "CANDIDATES ONLY."

---

## 8. Hidden Scope Concerns

None. The implementation is precisely within the approved scope:
- New `cmd_fleet_learn` function in `lib/verbs/fleet.sh`.
- `learn)` dispatch in `cmd_fleet`.
- Updated help text in `cmd_fleet`.
- T-FLN tests in `test/run.sh`.
- VERSION + CHANGELOG.

`scripts/massoh-dashboard` is confirmed unmodified (browser button PARKED).

---

## 9. Expansion / Localization Concerns

None. Repo basenames are locale-neutral identifiers. `FLEET_REPEAT_THRESHOLD` is a named constant
suitable for future configurability. No hard-coded locale or region.

---

## 10. Owner Decision Needed

None. All decisions are within the 8h away-autonomy grant.

Remaining PARKED items (not built in this slice, require owner return):
- Browser learn-button (POST handler in scripts/massoh-dashboard).
- Engine ADOPTION of any FLEET_LEARNINGS.proposed.md candidate.

---

## 11. Summary for orchestrator

| Item | Value |
|---|---|
| **Verdict** | APPROVE |
| **Test count** | 574/574 green (independently run) |
| **Engine-untouched (git diff empty)** | YES — `git diff HEAD -- agent-os/ bin/massoh manifest.yml templates/ scripts/massoh-dashboard` returns empty |
| **Zero-LLM/spend** | YES — static grep clean (no claude/curl/wget/agent in cmd_fleet_learn) |
| **Candidates-only** | YES — header "CANDIDATES ONLY — engine adoption is a separate owner/gated step."; zero writes to any engine file |
| **Read-only on discovered repos** | YES — live byte-snapshot: repo-x md5 identical before/after, repo-y md5 identical before/after |
| **FLN4 promotion boundary** | VERIFIED — [generalizable-candidate] at >=2 repos; [project: basename] at 1 repo; confirmed live |
| **Blockers** | 0 |
| **Non-blocking** | NB-1 (T-FLN-6a timestamp fragility), NB-2 (awk ordering), NB-3 (AGENT_SYNC rolling update) |
| **Ready to merge** | YES |
