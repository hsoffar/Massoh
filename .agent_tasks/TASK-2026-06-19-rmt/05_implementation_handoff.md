# 05 — Implementation Handoff: RMT Adoption Diff (TASK-2026-06-19-rmt)

- **Implementer:** massoh-implementer
- **Date:** 2026-06-19
- **Branch:** feat/rmt
- **Status:** COMPLETE — routing to massoh-reviewer-qa

---

## 1. Files changed

| File | Change type | What changed |
|---|---|---|
| `scripts/req-check` | GAP-2 fix | Line 323: `req['id']` → `req.get('id', '<no-id>')` in C07 error format |
| `manifest.yml` | ADOPTION DIFF §5.1 | Added `scripts/` dir entry (RMT capability); added `req-check` to skills owns; added 2 `create_if_missing` RMT template entries |
| `bin/massoh` | GAP-1 / ADOPTION DIFF | Added `scripts` to `cmd_install` `for p in` loop (~line 67) AND `cmd_doctor` `for p in` loop (~line 148) |
| `policies/03_AGENT_WORKFLOW.md` | ADOPTION DIFF §5.2 | Appended "Optional: REQ-ID link" section after the hard gate section |
| `policies/11_TASK_PACKET_SPEC.md` | ADOPTION DIFF §5.3 | Appended `req:` optional field row to the packet file table |
| `policies/05_REVIEW_CHECKLIST.md` | ADOPTION DIFF §5.4 | Appended RMT req-check assertion under §Guardrails |
| `policies/08_FEATURE_GATE_TEMPLATE.md` | ADOPTION DIFF §5.5 | Appended RMT flagged-req note to checklist |
| `OPERATING_SYSTEM.md` | ADOPTION DIFF §5.6 | Appended "Optional capability — RMT" paragraph before §2 |
| `templates/CLAUDE.project.template.md` | ADOPTION DIFF §5.7 | Appended "## Optional capabilities" section after §Skills |
| `VERSION` | ADOPTION DIFF §5.8 | 0.16.0 → 0.17.0 |
| `CHANGELOG.md` | ADOPTION DIFF §5.9 | Added [0.17.0] entry |
| `test/run.sh` | RG8 | Added `== T-RMT ==` block: 31 checks across T-RMT-a…p (16 test cases) |

---

## 2. What was implemented

Full ADOPTION DIFF from `05_proposal.md §5` applied verbatim, plus:
- **GAP-1 (CRITICAL):** `bin/massoh` install loop and doctor loop both updated with `scripts` entry, so `req-check` is actually installed to `~/.claude/agent-os/scripts/` and verified by doctor.
- **GAP-2 (MINOR):** `scripts/req-check` line 323 changed from `req['id']` to `req.get('id', '<no-id>')` — prevents KeyError on YAML entries with a non-null `flag:` but no `id:` field.
- **T-RMT-a…p (16 test cases, 31 assertions):** complete T-RMT block added to `test/run.sh`.

---

## 3. RG1–RG10 + GAP-1/GAP-2 citation

| Condition | Status | Evidence |
|---|---|---|
| **GAP-1 / RG1 bin/massoh lockstep** | FIXED | `cmd_install` loop now: `for p in OPERATING_SYSTEM.md policies templates docs manifest.yml VERSION lib/verbs scripts` (line 67). `cmd_doctor` loop now: `for p in OPERATING_SYSTEM.md policies templates docs manifest.yml VERSION scripts` (line 148). Doctor smoke test confirms `ok   agent-os/scripts`. |
| **GAP-2 / RG5 C07 KeyError guard** | FIXED | `scripts/req-check` line 323: `req.get('id', '<no-id>')`. T-RMT-i exercises C07 with an orphaned flag — no KeyError, structured error emitted. |
| **RG2 yaml.safe_load only** | VERIFIED | Lines 68, 120, 339 of `scripts/req-check` all use `yaml.safe_load`. No `yaml.load` present. |
| **RG3 req-check read-only** | VERIFIED | No `open(..., "w")`, `write`, `makedirs`, `unlink`, `rename`, `truncate` found in `scripts/req-check`. T-RMT-m confirms registry md5 unchanged after run. |
| **RG4 PyYAML graceful exit** | VERIFIED | Lines 48-52: `try: import yaml / except ImportError: print(...); sys.exit(2)`. T-RMT-l confirms exit 2 + install hint. |
| **RG6 policy 14 §8 label** | VERIFIED | `policies/14_REQUIREMENTS_TRACEABILITY.md` §8 says "illustrative only" — no engine defaults. T-RMT-o confirms zero elard strings in engine files. |
| **RG7 ADOPTION DIFF additive-only** | VERIFIED | `git diff HEAD -- policies/03 policies/05 policies/08 policies/11 OPERATING_SYSTEM.md templates/CLAUDE.project.template.md \| grep '^-' \| grep -v '^---'` = empty output. Zero deletions. |
| **RG8 T-RMT-a…p tests** | COMPLETE | 31 assertions added to `test/run.sh`. All 31 pass. |
| **RG9 VERSION bump with ADOPTION DIFF** | DONE | VERSION = 0.17.0; CHANGELOG [0.17.0] present; applied together with manifest+bin/massoh in same session. |
| **RG10 owner sign-off covers manifest + bin/massoh** | CONFIRMED | AGENT_SYNC.md decision log 2026-06-19: "Owner SIGNED OFF on all 3 remaining queue items — #7 RMT (manifest.yml + bin/massoh install/doctor lockstep + policy 03/05/08/11 cross-links + VERSION 0.17.0)". |

---

## 4. Manifest ↔ bin/massoh lockstep proof

`manifest.yml` declares:
```yaml
  - kind: dir
    dest: ~/.claude/agent-os/scripts/
    source: scripts/
    owns: [req-check]
```

`bin/massoh cmd_install` loop (line 67):
```bash
for p in OPERATING_SYSTEM.md policies templates docs manifest.yml VERSION lib/verbs scripts; do
```

`bin/massoh cmd_doctor` loop (line 148):
```bash
for p in OPERATING_SYSTEM.md policies templates docs manifest.yml VERSION scripts; do
```

Doctor smoke result: `ok   agent-os/scripts` (healthy).

---

## 5. Test suite results (verbatim)

Suite run: `bash test/run.sh`

```
1/449 checks FAILED.
```

- **Total:** 449 checks
- **Passed:** 448
- **Failed:** 1 (pre-existing: "doctor flags 'update available'" in T6 — git network fetch flakiness; confirmed present before our changes: 1/418 failed on baseline)
- **New T-RMT checks:** 31 (T-RMT-a…p, 16 test cases)
- **Target:** ≥434 — EXCEEDED (449 ≥ 434)
- **Regressions:** 0 (same 1 pre-existing failure)

T-RMT results: all 31 assertions green:
- T-RMT-a: dormant no-op (exit 0, "dormant" in stdout)
- T-RMT-b: valid 2-entry registry passes (exit 0, "PASSED")
- T-RMT-c: C01 duplicate ID (exit 1, "C01")
- T-RMT-d: C08 append-only via git fixture (exit 1, "C08")
- T-RMT-e: C09 missing removed_reason (exit 1, "C09")
- T-RMT-f: C10 safety guard without owner_approved (exit 1, "C10")
- T-RMT-g: C10 with owner_approved:true (exit 0)
- T-RMT-h: C06 broken code path (exit 1, "C06")
- T-RMT-i: C07 orphaned flag — no KeyError (exit 1, "C07") [GAP-2 proof]
- T-RMT-j: C11 undocumented flag warn-only (exit 0, "C11")
- T-RMT-k: C05 empty satisfied_by (exit 1, "C05")
- T-RMT-l: PyYAML missing graceful exit (exit 2, install hint in stderr)
- T-RMT-m: read-only proof (registry md5 unchanged)
- T-RMT-n: skill SKILL.md has "Read-only" + "never edits" language
- T-RMT-o: no elard strings (3 assertions: scripts/, templates/, claude/skills/req-check/)
- T-RMT-p: C06 resolves via code_root (exit 0, "PASSED")

---

## 6. Doctor + install smoke results

`massoh install` + `massoh doctor --offline`:

```
massoh doctor → <tmpdir>
  ok   global block
  ok   agent massoh-architecture-safety.md
  ok   agent massoh-history-maintainer.md
  ok   agent massoh-implementer.md
  ok   agent massoh-meta-engineer.md
  ok   agent massoh-product-scope.md
  ok   agent massoh-reviewer-qa.md
  ok   agent massoh-system-architect.md
  ok   skill start-task
  ok   skill sync
  ok   skill close-task
  ok   skill history-cleanup
  ok   agent-os/OPERATING_SYSTEM.md
  ok   agent-os/policies
  ok   agent-os/templates
  ok   agent-os/docs
  ok   agent-os/manifest.yml
  ok   agent-os/VERSION
  ok   agent-os/scripts
  ok   agent-os/lib/verbs/
  repo  /home/hossam/dev/Massoh  v0.17.0 (55fe4d4)
healthy — install matches manifest.
```

`massoh install` copies `scripts/req-check` to `~/.claude/agent-os/scripts/req-check` — confirmed.

---

## 7. Risks

- **Low:** All policy edits additive-only; no existing content deleted; `git diff HEAD | grep '^-' | grep -v '^---'` on policy files = empty.
- **Low:** GAP-2 fix is a bug fix on a new additive file (not safety-critical). Replaces a potential KeyError with a structured error string.
- **Low:** bin/massoh changes are minimal (1 token `scripts` added to each of 2 existing loops). Smoke test confirms no regression.
- **None:** PyYAML dep scoped to adopting projects' CI only. Engine bash CLI unaffected.
- **None:** RMT is dormant until a project creates its own config + registry.

---

## 8. Incomplete items

None. All ADOPTION DIFF items from §5.1–§5.9 applied. All RG1–RG10 conditions met. All T-RMT-a…p tests green.

---

## 9. Handoff to reviewer-qa

Reviewer-QA should verify:

1. **RG7 additive-only:** `git diff HEAD -- policies/03_AGENT_WORKFLOW.md policies/05_REVIEW_CHECKLIST.md policies/08_FEATURE_GATE_TEMPLATE.md policies/11_TASK_PACKET_SPEC.md OPERATING_SYSTEM.md templates/CLAUDE.project.template.md | grep '^-' | grep -v '^---'` = empty (zero deletions).
2. **GAP-1 lockstep:** both `cmd_install` and `cmd_doctor` loops in `bin/massoh` contain `scripts`; doctor shows `ok   agent-os/scripts` after fresh install.
3. **GAP-2 guard:** `scripts/req-check` line 323 uses `req.get('id', '<no-id>')` not `req['id']`; T-RMT-i passes (no KeyError).
4. **RG2–RG4:** `yaml.safe_load` at lines 68/120/339; no write calls; PyYAML exit 2 with hint.
5. **RG8:** T-RMT-a…p all 31 assertions green; suite 449 total, 448 passed, 1 pre-existing failure (T6 network flakiness).
6. **RG9:** VERSION = 0.17.0, CHANGELOG [0.17.0] section present.
7. **No elard strings:** `grep -ril 'elard' scripts/ templates/requirements*.yml claude/skills/req-check/` = empty.
8. **Scope clean:** Only the 12 files listed above changed. AGENT_SYNC.md, AGENT_BACKLOG.md untouched.
9. **Manifest entries:** `create_if_missing` RMT template entries and `skills owns: [req-check]` present.
10. **Doctor smoke:** `massoh install` + `massoh doctor --offline` = healthy (0 problems).
