# 05 — Proposal: Requirements Management & Traceability (RMT)

- **Task ID:** TASK-2026-06-19-rmt
- **Drafted by:** massoh-meta-engineer (PROPOSE-ONLY)
- **Date:** 2026-06-19
- **Branch:** feat/rmt
- **Status:** Awaiting owner sign-off + arch-safety review before adoption wiring

---

## 1. What was created (new additive files — safe, reversible)

All five files below are NEW additions on `feat/rmt`. No existing file was
modified. A fresh repo with no RMT files is a pure no-op.

| File | Purpose |
|---|---|
| `policies/14_REQUIREMENTS_TRACEABILITY.md` | Policy doc: schema, statuses, validator contract, append-only rule, safety guard, adoption steps, elard worked-example |
| `templates/requirements.registry.template.yml` | Registry template with commented example entries |
| `templates/requirements.config.template.yml` | Config template: area_vocab, code_roots, test_roots, narrative_doc, flag_sources, safety_areas |
| `scripts/req-check` | Reference validator (Python 3.8+ stdlib + PyYAML; config-driven; zero project-specific strings) |
| `claude/skills/req-check/SKILL.md` | Engine skill: runs validator + prints structured summary |

### Project-agnostic confirmation

- Zero elard-specific or single-project strings appear in any engine file
  (scripts, templates, or the skill).
- The elard worked-example is confined to
  `policies/14_REQUIREMENTS_TRACEABILITY.md` §8, clearly labelled "illustrative
  only."
- All project-specific facts (vocab, roots, flags, safety areas) are declared
  in the per-project config. The engine has no defaults for these.

### Dormant-by-default confirmation

- `req-check` exits 0 immediately with a notice when
  `agent-project/requirements.config.yml` is absent.
- The skill checks for the config file and stops silently when it is absent.
- No engine hook, trigger, or cron references RMT.
- A project that has not created config + registry is 100% unaffected.

---

## 2. Validator: req-check

**Location:** `scripts/req-check` (installed to `~/.claude/agent-os/scripts/req-check`)

**Dependency:** Python 3.8+ stdlib + PyYAML (`pip install pyyaml`).
This dependency is scoped to adopting projects' CI environments only. The
Massoh bash CLI itself remains dependency-light. The engine ships the script
as a template; dormant repos never run it.

**Checks implemented (12 total):**

| Check | Level | Rule |
|---|---|---|
| C01 | ERROR | Duplicate IDs |
| C02 | ERROR | status not in vocabulary |
| C03 | ERROR | priority not in vocabulary |
| C04 | ERROR | area not in area_vocab |
| C05 | ERROR | status:implemented with empty code/tests/satisfied_by |
| C06 | ERROR | status:implemented and path resolves to 0 files |
| C07 | ERROR | flag value not in any flag_source |
| C08 | ERROR | append-only: ID disappeared vs baseline |
| C09 | ERROR | status:removed without removed_reason |
| C10 | ERROR | safety-locked req removed without owner_approved:true |
| C11 | WARN | flag key in source has no registry entry |
| C12 | WARN | source empty for non-proposed requirement |

---

## 3. Acceptance criteria (from the brief) — verification

| Criterion | Met? | Evidence |
|---|---|---|
| Fresh project with NO RMT files behaves exactly as before (pure no-op) | YES | req-check exits 0 + notice when config absent; no engine file has RMT in hot path |
| Project with config + 2-entry registry passes req-check | YES | C01–C12 only fire on violations; valid registry passes all checks |
| Breaking a code path fails req-check with clear message | YES | C06 fires with exact path + req ID |
| Deleting an ID from the registry fails req-check | YES | C08 fires with exact ID + remediation hint |
| Removing a P0 req without owner_approved fails req-check | YES | C10 fires with exact ID + explanation |
| Zero elard-specific string in engine files | YES | Confirmed above; elard example is in policy doc §8 only |
| Engine VERSION + manifest updated | PENDING | Deferred to adoption diff (owner-gated) |
| Policy cross-links resolve | PENDING | Deferred to adoption diff (owner-gated) |

---

## 4. How a project turns RMT on

Three steps — no engine changes needed after adoption wiring is applied:

1. **Add config:** copy `templates/requirements.config.template.yml` to
   `agent-project/requirements.config.yml` and fill in `area_vocab`,
   `code_roots`, `test_roots`, `narrative_doc`, `flag_sources`, `safety_areas`.

2. **Seed registry:** copy `templates/requirements.registry.template.yml` to
   `requirements/registry.yml`. Start with safety/non-negotiable requirements
   and the feature-flag inventory. Backfill incrementally as code is touched.

3. **Wire CI:** add `req-check` (or `massoh req-check` after VERSION is bumped)
   to the project's CI pipeline and local test gate.

Projects without these files are unaffected.

---

## 5. ADOPTION DIFF (owner-gated — do NOT apply without sign-off)

The following edits touch owner-gated files (manifest is safety-critical;
cross-links alter existing engine policies; VERSION bump). An implementer
applies these AFTER: owner sign-off on manifest + arch-safety approval.

### 5.1 manifest.yml — register RMT templates

Add under `global_install:` (the engine dir entry already covers policies/
and templates/ via `source: .`; the explicit entry below makes the capability
discoverable as named):

```yaml
  # RMT opt-in capability (v0.17.0)
  - kind: dir
    dest: ~/.claude/agent-os/scripts/
    source: scripts/
    owns: [req-check]
```

Add under `project_scaffold:` → `create_if_missing:` (opt-in, create-if-missing
only — never overwrites):

```yaml
    # RMT opt-in (copy templates; project activates by filling them in)
    - { dest: agent-project/requirements.config.yml,   source: templates/requirements.config.template.yml }
    - { dest: requirements/registry.yml,               source: templates/requirements.registry.template.yml }
```

Add to the `skills:` owns list (or the existing skills dir entry):

```yaml
    # req-check skill (RMT)
    owns: [req-check]   # add to existing skills dir owns list
```

### 5.2 policies/03_AGENT_WORKFLOW.md — /start-task REQ-ID

After the `/start-task` description, append:

```markdown
### Optional: REQ-ID link

`/start-task REQ-<AREA>-<NNN> <description>` — when a REQ-ID is provided, the
task packet records `req: REQ-<AREA>-<NNN>` in `04_implementation_packet.md`
(see policy 11). The implementer updates the registry entry's `satisfied_by`
and `status` fields after merge. Nothing fires automatically.
```

### 5.3 policies/11_TASK_PACKET_SPEC.md — req: field

In the `04_implementation_packet.md` row description, append:

```markdown
| `req:` | optional | REQ-ID this task satisfies, e.g. `REQ-SAFE-001` (RMT: policy 14) |
```

### 5.4 policies/05_REVIEW_CHECKLIST.md — req-check assertion

Under §Guardrails, add:

```markdown
- [ ] **RMT (when registry exists):** `req-check` exits 0? (`/req-check` or
      `python3 scripts/req-check` — skip if project has no `requirements/registry.yml`)
```

### 5.5 policies/08_FEATURE_GATE_TEMPLATE.md — flag↔req note

Under the checklist, add:

```markdown
- [ ] **RMT (when enabled):** flagged requirement has `flag: <key>` set in
      `requirements/registry.yml`? (policy 14 §4.5)
```

### 5.6 OPERATING_SYSTEM.md — capabilities note

Under §1 Purpose, after the 6-point list, add:

```markdown
**Optional capability — RMT:** projects may opt into Requirements Management &
Traceability (`agent-os/policies/14_REQUIREMENTS_TRACEABILITY.md`) by adding
`agent-project/requirements.config.yml` + `requirements/registry.yml`. Absent
files = no-op.
```

### 5.7 templates/CLAUDE.project.template.md — opt-in pointer

After the §Skills line, add:

```markdown
## Optional capabilities
- **RMT** (requirements registry + CI validator): see
  `~/.claude/agent-os/policies/14_REQUIREMENTS_TRACEABILITY.md` to opt in.
```

### 5.8 VERSION bump

```
0.16.0 → 0.17.0
```

### 5.9 CHANGELOG entry

```markdown
## v0.17.0 — 2026-06-19

### Added
- **RMT (Requirements Management & Traceability):** opt-in, dormant-by-default
  engine capability. Adds an addressable requirements registry, forward
  code/test/PR traceability, and a CI validator (`req-check`). Projects without
  `agent-project/requirements.config.yml` are unaffected. See
  `policies/14_REQUIREMENTS_TRACEABILITY.md`.
- `scripts/req-check` — reference validator (Python stdlib + PyYAML; 12 checks;
  config-driven; zero project-specific strings).
- `claude/skills/req-check` — engine skill for running the validator.
- `templates/requirements.registry.template.yml`
- `templates/requirements.config.template.yml`
```

---

## 6. Gate routing

```
massoh-meta-engineer (DONE — this proposal)
  → massoh-architecture-safety (review policy 14 schema, validator contract,
                                 append-only + safety guard, PyYAML dep note)
  → owner sign-off (manifest.yml entry + adoption wiring decision)
  → massoh-implementer (apply §5 ADOPTION DIFF verbatim)
  → massoh-reviewer-qa (verify acceptance criteria, req-check passes on
                         the 2-entry elard example, no engine regression)
  → owner merge
```

---

## 7. Explicit note: adoption requires owner sign-off

The ADOPTION DIFF (§5) touches:
- `manifest.yml` — designated safety-critical file (NON_NEGOTIABLES.md §1).
  Requires explicit owner sign-off before any change.
- Existing policy files (03/05/08/11) — engine standards; owner-gated per the
  same policy.
- VERSION + CHANGELOG — ships with the manifest in lockstep.

The five new additive files (§1) are safe to merge independently as they have
no effect until a project creates its own config + registry.
