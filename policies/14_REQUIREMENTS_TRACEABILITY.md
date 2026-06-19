# 14 — Requirements Management & Traceability (RMT) (portable)

> **OPT-IN / DORMANT.** A project activates RMT by adding
> `agent-project/requirements.config.yml` + `requirements/registry.yml`.
> Absent either file = no-op. Zero engine behavior changes for projects that
> have not opted in.

---

## 1. Purpose

Give any Massoh project an **addressable, machine-checkable requirements
registry** linked to code, tests, and PRs — without background automation.
Adding, changing, or closing a requirement is a normal manual edit that still
flows through the gated workflow (`/start-task` → architecture → implementer →
reviewer). RMT adds only:

1. An addressable registry with stable IDs.
2. Forward code/test/PR traceability, enforced by a CI validator.
3. An append-only + safety-area guard.

Nothing fires automatically.

---

## 2. Registry schema — `requirements/registry.yml`

Each entry is a YAML mapping. All fields not marked `(optional)` are required
for an entry once it leaves `proposed` status.

```yaml
# requirements/registry.yml  — one entry per requirement
requirements:
  - id: REQ-<AREA>-<NNN>          # AREA from config area_vocab; NNN = 3-digit zero-padded
    title: <one-line human title>
    area: <AREA>                  # must be in config area_vocab
    status: proposed              # proposed | implemented | deferred | frozen | removed
    priority: P1                  # P0 | P1 | P2 | P3  (P0 = non-negotiable / safety-critical)
    flag: null                    # <flag-key> | null   (null = core / always active)
    code:  []                     # forward links: file paths or globs under code_roots
    tests: []                     # file paths or globs under test_roots
    satisfied_by: []              # PR/commit refs, e.g. ["PR#42", "abc1234"]
    adr: []                       # ADR IDs, e.g. ["ADR-005"]
    source: ""                    # anchor in narrative_doc (human prose); no data duplication
    removed_reason: null          # REQUIRED (non-null) when status: removed
    superseded_by: null           # REQ-ID that replaces this one, or null
    owner_approved: false         # MUST be true before a P0 or safety-area req moves to removed
```

### 2.1 Status vocabulary

| Status | Meaning |
|---|---|
| `proposed` | Captured; not yet committed to build |
| `implemented` | Built, tested, merged — `code`, `tests`, `satisfied_by` must be non-empty; all paths must resolve |
| `deferred` | Deliberately postponed; entry retained |
| `frozen` | Blocked (dependency, decision pending); entry retained |
| `removed` | Cancelled / superseded; `removed_reason` required; entry **retained** (append-only) |

### 2.2 Priority vocabulary

| Priority | Meaning |
|---|---|
| `P0` | Non-negotiable / safety-critical — cannot be removed without `owner_approved: true` |
| `P1` | Must-have for next milestone |
| `P2` | Should-have |
| `P3` | Nice-to-have / stretch |

---

## 3. Per-project config — `agent-project/requirements.config.yml`

The config declares all project-specific facts. The engine contains zero
hard-coded paths or vocab.

```yaml
# agent-project/requirements.config.yml
area_vocab: []          # controlled list of AREA tokens, e.g. [SAFE, DIAG, PERF]
code_roots: []          # directories req-check may resolve code paths under, e.g. [src/, lib/]
test_roots: []          # directories req-check may resolve test paths under, e.g. [tests/, spec/]
narrative_doc: ""       # path to the human-prose requirements file, e.g. docs/REQUIREMENTS.md
flag_sources: []        # 0..N flag-list locations; each entry:
                        #   - path: <file>
                        #     parser: <key>   # "python-allowlist" | "yaml-keys" | "json-keys"
safety_areas: []        # AREAs treated as P0-locked, e.g. [SAFE]
```

**Absent config = RMT disabled for that repo** (no-op; `req-check` exits 0
immediately with a notice).

---

## 4. Validator contract — `req-check`

The reference implementation lives at `scripts/req-check` (Python stdlib +
PyYAML; no other dependencies). It is config-driven; zero project-specific
strings are hard-coded.

### 4.1 Invocation

```
req-check [--config agent-project/requirements.config.yml]
           [--registry requirements/registry.yml]
           [--baseline <git-ref>]   # default: HEAD~1 for append-only check
```

Exit 0 = all checks pass. Exit 1 = one or more ERRORs. Warnings are printed
but do not fail CI.

### 4.2 Checks (fail CI = ERROR; advisory = WARN)

| ID | Level | Rule |
|---|---|---|
| C01 | ERROR | Duplicate `id` values in the registry |
| C02 | ERROR | `status` not in the status vocabulary |
| C03 | ERROR | `priority` not in `P0..P3` |
| C04 | ERROR | `area` not in config `area_vocab` |
| C05 | ERROR | `status: implemented` but `code`, `tests`, or `satisfied_by` is empty |
| C06 | ERROR | `status: implemented` and a `code` or `tests` path resolves to zero files under `code_roots`/`test_roots` |
| C07 | ERROR | `flag` value present but not found in any configured `flag_source` |
| C08 | ERROR | Append-only: an ID present in the baseline registry has disappeared from the current registry |
| C09 | ERROR | `status: removed` but `removed_reason` is null or empty |
| C10 | ERROR | A req in `safety_areas` or with `priority: P0` has `status: removed` but `owner_approved` is not `true` |
| C11 | WARN | A flag key found in a `flag_source` has no corresponding registry entry with that `flag:` value |
| C12 | WARN | `source` field is empty for a non-proposed requirement |

### 4.3 Append-only rule (C08/C09)

`req-check` compares the current registry against the previously committed
version (via `git show <baseline>:requirements/registry.yml`). An entry may
never vanish — only its `status` and fields may change. Removing an entry
entirely is a hard error.

### 4.4 Safety guard (C10)

A requirement is "safety-locked" when:
- `area` is in config `safety_areas`, OR
- `priority` is `P0`

A safety-locked req may move to `status: removed` ONLY when
`owner_approved: true` is set. Without it, `req-check` fails with a clear
message naming the req ID.

### 4.5 Flag↔requirement drift (C07/C11)

When `flag_sources` are configured, `req-check`:
1. Parses each source file per its declared `parser` key to extract a set of flag keys.
2. ERRORs on any registry entry whose `flag:` value is not in any source set (orphaned flag ref).
3. WARNs on any flag key in a source set that has no matching registry entry (undocumented flag).

---

## 5. Traceability model

**Forward traceability** (registry → code) is machine-enforced by `req-check`
(checks C05/C06).

**Reverse traceability** (code → registry) is convention only:
- PR descriptions cite the REQ-ID in the human narrative (folds into the
  existing GitHub issue/PR linking rule).
- No mandatory code-comment annotation tags are required.

**Task-packet link:** when `/start-task` names a REQ-ID, the packet records a
`req:` field (see policy 11). The merged PR updates the registry entry's
`satisfied_by` and `status` fields by hand. Nothing fires automatically.

---

## 6. Append-only data rule

Requirements are **never deleted** from the registry. The lifecycle of a
requirement always ends with a status change (`removed` + `removed_reason`),
never a row deletion. This mirrors the Massoh keep-older-data invariant
(policy 09 §5).

---

## 7. Adoption steps

A project turns RMT on in three steps:

1. **Add config:** create `agent-project/requirements.config.yml` (declare
   `area_vocab`, roots, flags, safety areas). Copy from
   `templates/requirements.config.template.yml`.
2. **Seed registry:** create `requirements/registry.yml`. Start with
   safety/non-negotiable requirements and the feature-flag inventory; backfill
   incrementally as code is touched. Copy from
   `templates/requirements.registry.template.yml`.
3. **Wire CI:** add `req-check` to the project's CI pipeline and local test
   gate (`massoh req-check` or direct invocation).

Projects without these files are completely unaffected.

---

## 8. Worked example — elard project config

> This section is illustrative only. No elard-specific string exists anywhere
> in the engine defaults, scripts, or templates.

```yaml
# agent-project/requirements.config.yml  (elard — example only)
area_vocab: [SAFE, DIAG, PERF, UX, INFRA]
code_roots: [backend/, android/app/src/]
test_roots: [backend/tests/, android/app/src/test/]
narrative_doc: docs/REQUIREMENTS.md
flag_sources:
  - path: backend/flags.py
    parser: python-allowlist    # reads the ALLOWLIST / DEFAULTS dict keys
  - path: android/app/src/main/java/com/elard/FeatureFlags.kt
    parser: kotlin-object-keys  # reads object field names from a Kotlin object block
safety_areas: [SAFE]
```

```yaml
# requirements/registry.yml  (elard — 2-entry seed, example only)
requirements:
  - id: REQ-SAFE-001
    title: "All PII fields encrypted at rest"
    area: SAFE
    status: implemented
    priority: P0
    flag: null
    code:  [backend/crypto/pii_encrypt.py]
    tests: [backend/tests/test_pii_encrypt.py]
    satisfied_by: [PR#12]
    adr: [ADR-002]
    source: "docs/REQUIREMENTS.md#safe-at-rest"
    removed_reason: null
    superseded_by: null
    owner_approved: false

  - id: REQ-DIAG-001
    title: "Diagnostic log export available in settings"
    area: DIAG
    status: proposed
    priority: P2
    flag: diagnostic_export
    code:  []
    tests: []
    satisfied_by: []
    adr: []
    source: "docs/REQUIREMENTS.md#diag-export"
    removed_reason: null
    superseded_by: null
    owner_approved: false
```

---

## 9. Cross-references (post-adoption wiring)

After owner sign-off and arch-safety approval, an implementer applies these
cross-links (documented here as the canonical adoption diff — see
`.agent_tasks/TASK-2026-06-19-rmt/05_proposal.md` §ADOPTION DIFF):

- **03_AGENT_WORKFLOW.md** — `/start-task` accepts optional `REQ-<AREA>-<NNN>` argument.
- **11_TASK_PACKET_SPEC.md** — `04_implementation_packet.md` gains optional `req:` field.
- **05_REVIEW_CHECKLIST.md** — reviewer asserts `req-check` is green when a registry exists.
- **08_FEATURE_GATE_TEMPLATE.md** — note that a flagged requirement should set `flag:` in the registry.
- **OPERATING_SYSTEM.md** — one-line note pointing to policy 14 under §capabilities.
- **templates/CLAUDE.project.template.md** — one-line opt-in pointer.
- **manifest.yml** — register the RMT templates as an opt-in capability.
- **VERSION** — bump to next minor (v0.17.0).
