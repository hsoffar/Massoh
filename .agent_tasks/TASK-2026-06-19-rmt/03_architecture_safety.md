# 03 — Architecture & Safety Review: RMT (TASK-2026-06-19-rmt)

- **Reviewed by:** massoh-architecture-safety
- **Date:** 2026-06-19
- **Branch:** feat/rmt (uncommitted working tree)
- **Files reviewed:**
  - `.agent_tasks/TASK-2026-06-19-rmt/05_proposal.md`
  - `agent-project/briefs/RMT-requirements-traceability.md`
  - `policies/14_REQUIREMENTS_TRACEABILITY.md`
  - `templates/requirements.registry.template.yml`
  - `templates/requirements.config.template.yml`
  - `scripts/req-check`
  - `claude/skills/req-check/SKILL.md`
  - `agent-project/NON_NEGOTIABLES.md`
  - `manifest.yml` (current; ADOPTION DIFF NOT yet applied — confirmed)
  - `bin/massoh` (for install-loop lockstep analysis)

---

## 1. Backend / service impact

None. RMT is a pure offline capability (config file + registry YAML + Python validator script). There
is no server, daemon, webhook, or network call in the new additive files. `scripts/req-check` does
call `subprocess.run(["git", "show", ...])` to read a baseline ref — this is read-only and local.
`shell=True` is NOT used (confirmed); the command is a fixed list, not user-interpolated shell string.

## 2. Client / app impact

None. The Massoh bash CLI (`bin/massoh`) is not touched on this branch. No new verb is wired to
`bin/massoh` — the ADOPTION DIFF gates a `massoh req-check` alias, but that is owner-gated and not
applied here.

## 3. API impact

No API. The validator is invoked directly as `python3 scripts/req-check [args]` or via the
`/req-check` skill. No contract change to any existing CLI verb. No new HTTP surface.

## 4. DB / migration impact

No database. The requirements registry is a plain YAML file created by the project (create-if-missing
from template). Append-only semantics are enforced by check C08. No migration required — a project
that has never used RMT is not affected.

## 5. LLM / prompt impact

The new skill (`claude/skills/req-check/SKILL.md`) adds an agent-readable prompt layer. The skill
correctly instructs the agent to: (a) stop silently if config is absent, (b) be read-only, and (c)
never auto-edit the registry. Safety rules in the skill match the validator contract. No
certainty/over-claim language is present; the skill explicitly states "Do NOT auto-edit the
registry." No guardrail rules are relaxed.

## 6. Safety / guardrail risks

### RG1 — CRITICAL: bin/massoh install loop does not include scripts/ (lockstep gap)

The ADOPTION DIFF §5.1 adds a manifest entry:
```yaml
  - kind: dir
    dest: ~/.claude/agent-os/scripts/
    source: scripts/
    owns: [req-check]
```

However `bin/massoh:cmd_install` has a hardcoded `for p in` loop (line 67):
```
for p in OPERATING_SYSTEM.md policies templates docs manifest.yml VERSION lib/verbs; do
```
`scripts/` is NOT in this list. The manifest entry declares intent, but `bin/massoh:cmd_install` is
the actual installer; the two must be kept in lockstep (NON_NEGOTIABLES.md §1 + manifest.yml note:
"keep the two in sync"). The implementer MUST add `scripts` to both the `cmd_install` loop (line 67)
AND the `cmd_doctor` loop (line 148) when applying the ADOPTION DIFF. This is a mandatory condition
— without it, `req-check` will NOT be installed to `~/.claude/agent-os/scripts/req-check` and will
not be discoverable via the skill's fallback path.

Because `bin/massoh` is a designated safety-critical file, adding `scripts` to those loops requires
explicit owner sign-off (same category as manifest.yml). The ADOPTION DIFF as drafted in §5.1 is
incomplete: it addresses manifest.yml but not the bin/massoh lockstep. Both must be signed off
together.

### RG2 — yaml.safe_load confirmed; no yaml.load present

All three YAML parse sites use `yaml.safe_load` (lines 68, 120, 339 of `scripts/req-check`).
`yaml.load` with an Loader argument is not present. Untrusted registry data is parsed safely.

### RG3 — req-check is fully read-only

No `open(..., "w")`, `write`, `makedirs`, `unlink`, `rename`, `truncate`, or equivalent found in
`scripts/req-check`. The only `open` calls are `open(path, "r", ...)` (lines 67, 115). The script
never mutates the registry or any project file.

### RG4 — PyYAML import failure is graceful

If PyYAML is not installed, the `try: import yaml / except ImportError:` block (lines 48-52) prints
a clear install instruction and exits with code 2 (not crashes with a traceback). This is correct.
No change needed.

### RG5 — subprocess uses list form only (no shell injection risk)

`subprocess.run(["git", "show", f"{ref}:{path}"], ...)` is a list command with no `shell=True`.
The `ref` is the `--baseline` CLI arg (default `HEAD~1`); `path` is the registry path computed from
`--registry`. A malicious `--baseline` value could inject git-ref syntax, but this is a developer
CI tool; the risk is commensurate with any CI script that accepts a `--ref` arg. No stronger
sandboxing is required for this use case.

### RG6 — C07 references req['id'] without a .get() guard

In the C07 block (lines 314-323), when a flag value is not in `all_flag_keys`, the error message
is formatted as `f"C07 {req['id']}: ..."`. This uses `req['id']` (direct dict access), not
`req.get('id', '<no-id>')`. If an entry has no `id` field AND a non-null `flag` field, this will
raise `KeyError` and abort the validator instead of reporting a structured error. The C01 loop uses
`req.get("id", f"<no-id@index-{i}>")` as a safe fallback; C07 should match. This is a minor
correctness gap, not a safety issue for well-formed YAML. The implementer should fix it.
Condition: use `req.get("id", "<no-id>")` at line 323.

### RG7 — C04 skips area check when area_vocab is empty

Line 257: `if area_vocab and area not in area_vocab:` — when `area_vocab: []` (empty, as in the
template default), C04 is silently skipped. This is intentional per the brief (a project that has
not declared an area vocab should not have its entries rejected), but it means an
incompletely-configured project gets no validation of area values. This is the correct behavior for
the opt-in model. Confirm in documentation: the template should state that leaving `area_vocab: []`
disables area validation. The config template already states "Add all area tokens your project
uses" — acceptable.

### RG8 — Dormant / no-op guarantee confirmed

`run_checks()` returns `([], [])` immediately with a NOTICE when config is absent (line 190). The
skill checks for config presence and stops silently (SKILL.md step 1). No engine cron, hook, or
always-read file references RMT (confirmed: `grep -rn "req-check\|RMT\|14_REQUIRE"` on policies
03/05/08/11 returns empty — the cross-links are NOT yet applied). A repo with no config+registry is
100% unaffected.

## 7. Expansion / localization risks

None. All project-specific facts (area_vocab, code_roots, test_roots, safety_areas, flag_sources) are
declared in the per-project config. The engine has no defaults and no hard-coded paths or locale
assumptions. Policy 12 (EXPANSION_READY_ARCHITECTURE) is satisfied: the validator is config-driven
and treats every project as first-class. The elard example is confined to policy 14 §8, clearly
labelled "illustrative only."

## 8. Required tests

All tests are fixtures-based (no live network, no mutation). The implementer adds these to
`test/run.sh` as a `T-RMT-*` block targeting the test count (currently 418; RMT adds ~16 new checks
for a target of ~434).

| Test ID | Assertion |
|---|---|
| T-RMT-a | No-config exit 0 (dormant no-op): run `req-check` against a temp dir with no `requirements.config.yml`; assert exit 0 and "RMT is dormant" in stdout |
| T-RMT-b | Valid 2-entry registry passes: fixture with config + 2 valid entries (one proposed, one implemented with real paths); assert exit 0, "PASSED" in stdout |
| T-RMT-c | C01 duplicate ID: fixture with two entries sharing the same `id`; assert exit 1 and "C01" in output |
| T-RMT-d | C08 append-only: fixture registry missing an ID that was in HEAD~1 baseline (via git fixture); assert exit 1 and "C08" in output |
| T-RMT-e | C09 removed_reason missing: entry with `status: removed` and `removed_reason: null`; assert exit 1 and "C09" in output |
| T-RMT-f | C10 safety guard: P0 entry with `status: removed` and `owner_approved: false`; assert exit 1 and "C10" in output |
| T-RMT-g | C10 passes with owner_approved: entry with `status: removed`, P0, `owner_approved: true`; assert exit 0 |
| T-RMT-h | C06 broken code path: implemented entry with a `code:` path that does not exist; assert exit 1 and "C06" in output |
| T-RMT-i | C07 orphaned flag: registry entry with `flag: missing_flag` not in flag_source; assert exit 1 and "C07" in output |
| T-RMT-j | C11 undocumented flag (warn only): flag_source has a key with no registry entry; assert exit 0 (warnings only) and "C11" in output |
| T-RMT-k | C05 implemented with empty satisfied_by: assert exit 1 and "C05" in output |
| T-RMT-l | PyYAML missing graceful exit: simulate by renaming `yaml` module (or a shell wrapper that sets PYTHONPATH to empty); assert exit 2 and install hint in stderr |
| T-RMT-m | req-check is read-only: run against a valid fixture, then assert md5sum of registry is unchanged after the run |
| T-RMT-n | skill SKILL.md: verify "Read-only" and "never edits" language present (grep assertion) |
| T-RMT-o | No elard strings in engine files: `grep -ri elard scripts/ templates/ claude/skills/req-check/` asserts zero matches |
| T-RMT-p | C06 passes when code path resolves under a declared code_root (not just as a direct path) |

## 9. Rollback plan

All five new additive files on `feat/rmt` are independent of any existing file. Rollback is:
`git revert` of the feat/rmt commit or deletion of the five new files. No existing file has been
modified; the engine is identical to HEAD. A project that has adopted RMT locally (created its own
config + registry) is unaffected by removing the engine template — its registry remains and
`req-check` can still be run directly.

The ADOPTION DIFF (§5), if applied, touches manifest.yml + policies + VERSION. Rollback of those
changes: revert the manifest entry (remove the `scripts/` and RMT scaffold lines); revert the
additive lines added to policies 03/05/08/11; revert VERSION. Because §5 edits are purely additive
(no deletions of existing policy content — confirmed below), revert is clean.

## 10. Conditions for the implementer (RG prefix)

The following conditions are MANDATORY before a passing implementation can be accepted:

**RG1 — bin/massoh lockstep (BLOCKING before ADOPTION DIFF can be applied):**
When applying §5.1 (manifest.yml), the implementer must also add `scripts` to:
- `bin/massoh` line 67 `for p in` loop (cmd_install)
- `bin/massoh` line 148 `for p in` loop (cmd_doctor)
This requires owner sign-off on `bin/massoh` (safety-critical, same gate as manifest.yml). The
ADOPTION DIFF as drafted is INCOMPLETE without this change.

**RG2 — yaml.safe_load is already compliant.** No action required. Verify in review (line refs:
68, 120, 339).

**RG3 — Read-only verified.** No action required. Verify in review.

**RG4 — PyYAML graceful exit is already implemented.** No action required.

**RG5 — C07 KeyError guard:**
Change line 323 of `scripts/req-check` from `req['id']` to `req.get('id', '<no-id>')` in the C07
error format string. This is a bug fix on a new additive file; it does not touch any safety-critical
file and does not require additional owner sign-off.

**RG6 — Policy 14 §8 label already says "illustrative only."** No change needed; confirm in review.

**RG7 — ADOPTION DIFF must be additive-only:**
Implementer must confirm that edits to policies 03/05/08/11 + OPERATING_SYSTEM.md +
CLAUDE.project.template.md introduce NO deletions of existing content (append or insert only).
Reviewer-QA must verify with `git diff --stat` that no existing lines are removed from those files.

**RG8 — Add req-check self-test to test/run.sh:**
The implementer must add the T-RMT-a through T-RMT-p test block described in §8 above to
`test/run.sh`. Target suite count: current 418 + 16 new checks = 434.

**RG9 — VERSION bump is lockstep with manifest and bin/massoh changes:**
VERSION bumps from 0.16.0 to 0.17.0 only when the ADOPTION DIFF is applied (owner-gated).
The five new additive files alone do NOT warrant a version bump — they are dormant engine
additions. VERSION stays at 0.16.0 until owner sign-off on the full ADOPTION DIFF.

**RG10 — ADOPTION DIFF sign-off covers both manifest.yml AND bin/massoh:**
Because RG1 requires a bin/massoh change (install + doctor loops) and bin/massoh is also a
designated safety-critical file (NON_NEGOTIABLES.md §1), the owner sign-off must explicitly
authorize BOTH `manifest.yml` and `bin/massoh` for the ADOPTION DIFF. The batch-authorization
from 2026-06-19 covers bin/massoh for the 24h queue items #3,#4,#5,#6,#8,#9,#10,#11 — RMT (#7)
is also in that set, but the batch-auth note explicitly excludes "manifest install/uninstall/block
logic" from auto-coverage. Owner must grant fresh per-change sign-off for this manifest entry +
the accompanying bin/massoh loop additions.

---

## ADOPTION DIFF gate assessment (§5 of proposal)

### Applied to this branch? NO — confirmed.

`git diff HEAD` shows zero changes to: manifest.yml, policies/03_AGENT_WORKFLOW.md,
policies/05_REVIEW_CHECKLIST.md, policies/08_FEATURE_GATE_TEMPLATE.md,
policies/11_TASK_PACKET_SPEC.md, OPERATING_SYSTEM.md, templates/CLAUDE.project.template.md,
VERSION, CHANGELOG.md. The ADOPTION DIFF is correctly staged as proposal-only.

### Is the ADOPTION DIFF scoped to owner-gated files? YES.

All files in §5.1-§5.9 are either: (a) NON_NEGOTIABLES-designated safety-critical (manifest.yml,
bin/massoh via RG1), or (b) existing engine policies that are owner-gated (03/05/08/11,
OPERATING_SYSTEM.md, CLAUDE.project.template.md), or (c) VERSION/CHANGELOG which ship in lockstep
with manifest.

### Is the ADOPTION DIFF additive (no deletions of existing content)? YES — as drafted.

Each §5.x item appends text after an existing section or adds new rows. No existing policy line is
deleted or replaced. This is the correct pattern. Reviewer-QA must verify this holds after
implementation (`git diff` line count: deletions = 0 for each owner-gated policy file).

---

## Verdict

**APPROVED FOR IMPLEMENTATION — PENDING OWNER SIGN-OFF**

### New additive files (5 files on feat/rmt): SAFE TO LAND NOW

The five files (`policies/14_REQUIREMENTS_TRACEABILITY.md`, `templates/requirements.registry.template.yml`,
`templates/requirements.config.template.yml`, `scripts/req-check`, `claude/skills/req-check/SKILL.md`)
are additive, dormant, reversible, and project-agnostic. They have no effect on any existing engine
behavior. They may be merged independently of the ADOPTION DIFF. Fix RG5 (C07 KeyError guard) before
merging.

### ADOPTION DIFF (§5): BLOCKED pending owner sign-off

The ADOPTION DIFF must NOT be applied by an implementer until:
1. **Owner explicitly signs off on manifest.yml** — designates safety-critical per NON_NEGOTIABLES.md §1.
2. **Owner explicitly signs off on bin/massoh** — the RG1 lockstep addition (scripts/ in install +
   doctor loops) requires bin/massoh edits, which are also safety-critical. The batch-authorization
   of 2026-06-19 does NOT cover manifest install/uninstall/block logic. Fresh sign-off is required.
3. The implementer applies the full ADOPTION DIFF including the RG1 bin/massoh fix as a single
   atomic change (manifest + bin/massoh + policies + VERSION + CHANGELOG), so the install contract
   never has a partial state.

---

## Summary for the owner sign-off request

The owner must explicitly authorize:
- **manifest.yml** — add `scripts/` dir entry (RMT capability) + two `create_if_missing` scaffold
  entries (config + registry templates)
- **bin/massoh** — add `scripts` to `cmd_install` loop (line 67) and `cmd_doctor` loop (line 148)

These two changes must ship together (atomically) with the policy cross-links and VERSION bump.

---

## Condition count: 10 (RG1–RG10)

| Condition | Blocking? | Needs owner sign-off? |
|---|---|---|
| RG1 bin/massoh lockstep addition | YES | YES (bin/massoh safety-critical) |
| RG2 yaml.safe_load compliant | verify-only | no |
| RG3 read-only confirmed | verify-only | no |
| RG4 PyYAML graceful exit | verify-only | no |
| RG5 C07 KeyError guard fix | YES (minor bug) | no (new file) |
| RG6 policy 14 §8 label | verify-only | no |
| RG7 ADOPTION DIFF additive-only | YES (review gate) | no |
| RG8 T-RMT-a through T-RMT-p tests in test/run.sh | YES | no |
| RG9 VERSION bump only with full ADOPTION DIFF | YES | no |
| RG10 owner sign-off covers both manifest + bin/massoh | YES | YES |

---

## Contract gaps found

**GAP-1 (CRITICAL):** The ADOPTION DIFF §5.1 proposes a manifest.yml `scripts/` entry but does not
include the matching `bin/massoh` install-loop and doctor-loop additions. The manifest NOTE says "keep
the two in sync" — this gap would leave `req-check` installed to `~/.claude/agent-os/scripts/` by
the manifest record but NOT actually copied/linked there by `cmd_install`. The script would exist
in the engine repo but not in the live installed path, breaking the skill's fallback lookup.

**GAP-2 (MINOR):** C07 error message uses `req['id']` direct key access. A YAML entry with no `id`
field but a non-null `flag:` field would raise `KeyError` instead of a structured error. Fix:
use `req.get('id', '<no-id>')`.

**No other contract gaps found.** C01–C12 are all implemented correctly. Append-only (C08/C09),
safety guard (C10), flag drift (C07/C11), implemented path resolution (C05/C06), and vocab checks
(C02/C03/C04) match the brief's specification exactly.

---

## Project-agnostic: CONFIRMED

`grep -ri "elard" scripts/ templates/ claude/skills/req-check/` returns zero matches. The elard
worked example is confined to `policies/14_REQUIREMENTS_TRACEABILITY.md` §8, clearly labelled
"illustrative only" and containing no engine default values.

---

## Biggest single risk

**RG1 / GAP-1**: The manifest + bin/massoh lockstep gap. If the ADOPTION DIFF is applied as drafted
(manifest.yml only, without the bin/massoh loop additions), the `req-check` script will be present
in the engine repo on disk but will NOT be installed to `~/.claude/agent-os/scripts/` on `massoh
install` or `massoh update`. Users who run the skill's fallback path will get "script not found."
This is a user-facing silent failure for adopters. The fix (add `scripts` to two `for p in` loops)
is trivial but requires owner sign-off because bin/massoh is safety-critical.
