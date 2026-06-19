# 06 — Review Result: RMT Adoption Diff (TASK-2026-06-19-rmt)

- **Reviewed by:** massoh-reviewer-qa
- **Date:** 2026-06-19
- **Branch:** feat/rmt (working tree, uncommitted)
- **Verdict:** APPROVE

---

## Summary

All 10 conditions (RG1–RG10) independently verified. GAP-1 and GAP-2 fixed and confirmed.
Additive-only policy edits confirmed for all 6 owner-gated files. Doctor healthy after fresh install.
T6 failure confirmed pre-existing (network-dependent) and unrelated to RMT. No scope creep. No
safety regressions. AGENT_SYNC.md and AGENT_BACKLOG.md untouched.

---

## Test suite result (self-witnessed, run 3 times)

```
1/449 checks FAILED.
  FAIL doctor flags 'update available'    [T6 — network; see below]
```

- Total: 449 checks
- Passed: 448
- Failed: 1 (pre-existing T6)
- New T-RMT checks: 31 (T-RMT-a...p, 16 test cases) — all 31 GREEN
- Target from arch-safety: >=434 — EXCEEDED (449 >= 434)

---

## T6 failure — pre-existing, not caused by RMT

T6 ("doctor flags 'update available'") requires a network fetch to origin/main to produce the
staleness check output. It fails when the test repo's constructed remote is not reachable, which is
a timing/network artifact present on main. Verified independently: stashed feat/rmt working tree,
ran test/run.sh on main baseline, got `1/418 checks FAILED` with the same T6 failure. Restored
stash. T6 is not related to RMT.

---

## GAP-1 lockstep — VERIFIED (CRITICAL)

`bin/massoh` cmd_install loop (line 67):
```
for p in OPERATING_SYSTEM.md policies templates docs manifest.yml VERSION lib/verbs scripts; do
```
`scripts` is present.

`bin/massoh` cmd_doctor loop (line 148):
```
for p in OPERATING_SYSTEM.md policies templates docs manifest.yml VERSION scripts; do
```
`scripts` is present.

Doctor smoke (live run via throwaway CLAUDE_CONFIG_DIR):
```
  ok   agent-os/scripts
  ...
healthy — install matches manifest.
```

`massoh install` copies `scripts/req-check` to `~/.claude/agent-os/scripts/req-check` — confirmed
by listing the installed path.

`manifest.yml` diff vs main: `scripts/` dir entry added under `global_install:`, `req-check` added
to skills owns list, 2 `create_if_missing` RMT template entries added. All additive.

---

## GAP-2 C07 KeyError guard — VERIFIED

`scripts/req-check` line 323:
```python
f"C07 {req.get('id', '<no-id>')}: flag {flag!r} not found in any configured flag_source"
```
No `req['id']` direct key access exists in C07 block. T-RMT-i exercises C07 path (exits 1, "C07"
in output, no KeyError). Code inspection confirms `req.get()` used consistently throughout the
per-entry loop (lines 232–242).

---

## RG1–RG10 independent verification

| Condition | Status | Evidence |
|---|---|---|
| RG1 bin/massoh lockstep | VERIFIED | Both loops contain `scripts`; doctor shows `ok agent-os/scripts`; live install confirmed |
| RG2 yaml.safe_load only | VERIFIED | Lines 68, 120, 339 all use `yaml.safe_load`; `yaml.load` absent (`grep yaml.load` returns 0 matches) |
| RG3 req-check read-only | VERIFIED | `grep "open.*w\|makedirs\|unlink\|rename\|truncate\|\.write" scripts/req-check` = empty; T-RMT-m md5 unchanged |
| RG4 PyYAML graceful exit | VERIFIED | Lines 48–52: `try: import yaml / except ImportError: print(...); sys.exit(2)`; T-RMT-l exit 2 + install hint confirmed |
| RG5 (GAP-2) C07 KeyError fix | VERIFIED | Line 323: `req.get('id', '<no-id>')`; T-RMT-i passes, no KeyError |
| RG6 policy 14 §8 label | VERIFIED | `policies/14_REQUIREMENTS_TRACEABILITY.md §8` header says "illustrative only"; zero elard strings outside policy 14 |
| RG7 ADOPTION DIFF additive-only | VERIFIED | `git diff main -- policies/03 policies/05 policies/08 policies/11 OPERATING_SYSTEM.md templates/CLAUDE.project.template.md \| grep '^-' \| grep -v '^---'` = empty on all 6 files |
| RG8 T-RMT-a…p tests | VERIFIED | 31 assertions in test/run.sh; all 31 green; target >=434 met (449) |
| RG9 VERSION with ADOPTION DIFF | VERIFIED | VERSION = 0.17.0; CHANGELOG [0.17.0] section present; applied together with manifest+bin/massoh |
| RG10 owner sign-off covers manifest + bin/massoh | CONFIRMED | AGENT_SYNC.md decision log 2026-06-19: "Owner SIGNED OFF on all 3 remaining queue items — #7 RMT (manifest.yml + bin/massoh install/doctor lockstep + policy 03/05/08/11 cross-links + VERSION 0.17.0)" |

---

## RG7 additive-only: per-file confirmation

Each of the 6 owner-gated policy/doc files verified individually:

- `policies/03_AGENT_WORKFLOW.md` — 7 lines added, 0 deleted. Appended "### Optional: REQ-ID link" section after the hard gate section.
- `policies/11_TASK_PACKET_SPEC.md` — 1 line added, 0 deleted. `req:` optional field row inserted in packet table.
- `policies/05_REVIEW_CHECKLIST.md` — 2 lines added, 0 deleted. RMT req-check assertion appended under §Guardrails.
- `policies/08_FEATURE_GATE_TEMPLATE.md` — 2 lines added, 0 deleted. RMT flagged-req note appended to checklist.
- `OPERATING_SYSTEM.md` — 5 lines added, 0 deleted. RMT capability paragraph inserted before §2.
- `templates/CLAUDE.project.template.md` — 4 lines added, 0 deleted. "## Optional capabilities" section appended after §Skills.

---

## Scope verification

Files changed vs main (`git diff main --stat`):
- `.agent_tasks/TASK-2026-06-19-rmt/` files — task packet artifacts (allowed)
- `agent-project/META.proposed.md` — new file, massoh meta proposal (additive, non-product-code artifact)
- `CHANGELOG.md` — additive, [0.17.0] entry
- `OPERATING_SYSTEM.md` — additive, RMT paragraph
- `VERSION` — 0.16.0 → 0.17.0
- `bin/massoh` — 2 lines changed (add `scripts` to 2 loops)
- `claude/skills/req-check/SKILL.md` — new additive file
- `manifest.yml` — additive entries only
- `policies/03_AGENT_WORKFLOW.md`, `05_REVIEW_CHECKLIST.md`, `08_FEATURE_GATE_TEMPLATE.md`, `11_TASK_PACKET_SPEC.md` — additive only
- `policies/14_REQUIREMENTS_TRACEABILITY.md` — new additive policy file
- `scripts/req-check` — new additive Python validator
- `templates/CLAUDE.project.template.md` — additive
- `templates/requirements.config.template.yml`, `templates/requirements.registry.template.yml` — new additive templates
- `test/run.sh` — 488 lines added (T-RMT block, 31 assertions)

**AGENT_SYNC.md: untouched** (git diff main = 0 bytes)
**AGENT_BACKLOG.md: untouched** (git diff main = 0 bytes)
**NON_NEGOTIABLES.md: untouched**

---

## Non-blocking findings

**NB-1: 11_TASK_PACKET_SPEC.md `req:` row format.**
The `req:` field is added as a standalone table row (between `04_implementation_packet.md` and
`05_implementation_handoff.md` rows) with `req:` in the "File" column. The proposal §5.3 said
"In the `04_implementation_packet.md` row description, append" — the intent was to annotate the
04 row, not create a separate file-row. The result is semantically clear but structurally
inconsistent (a field key appearing in a file-name column). Information is accurate and additive;
the policy still reads unambiguously. Non-blocking.

**NB-2: T-RMT-i tests C07 with an entry that has an id field** (not the exact no-id + flag
sub-case that GAP-2 guards against). The GAP-2 fix is a defensive guard in a new additive file
on the path that is exercised. The architecture-safety spec T-RMT-i description says "C07 orphaned
flag" and does not require the no-id sub-case. Code inspection confirms line 323 is correct.
Non-blocking.

---

## Blocking issues

None.

---

## Safety/guardrail concerns

None. Global-block markers unchanged. NON_NEGOTIABLES.md unchanged. Prohibited actions (overwrite
user CLAUDE.md, clobber existing project files, remove non-massoh-namespaced content) have no new
exposure. install/uninstall/backup_claude core logic: only 1-token additive change per loop.

---

## Dormant no-op: CONFIRMED

T-RMT-a verified live: `python3 scripts/req-check` in a repo with no
`agent-project/requirements.config.yml` exits 0 with "dormant" in stdout. No engine cron, hook, or
always-read file references RMT. AGENT_BACKLOG.md / AGENT_SYNC.md / any template unchanged relative
to their engine role.

---

## Expansion / localization concerns

None. All project-specific facts (area_vocab, code_roots, test_roots, safety_areas, flag_sources)
are declared in the per-project config. The engine has no defaults and no hard-coded paths.
Project-agnostic: zero elard strings in engine files (`grep -ril 'elard' scripts/ templates/
requirements*.yml claude/skills/req-check/` = 0 results).

---

## Owner decision needed

None. Owner sign-off was recorded in AGENT_SYNC.md 2026-06-19 decision log covering manifest.yml
+ bin/massoh for #7 RMT explicitly. All 10 conditions met. Ready to merge.

---

## Next recommended action

Orchestrator squash-merges feat/rmt PR → main; VERSION 0.17.0 ships. Deploy via
`massoh update` when owner chooses.
