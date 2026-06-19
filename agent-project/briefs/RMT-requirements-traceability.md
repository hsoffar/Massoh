# Backlog brief — Requirements Management & Traceability (RMT)

- **Status:** BACKLOG (captured, not started). Enters the gated workflow via `/start-task` when picked.
- **Captured:** 2026-06-19
- **Raised by:** owner (verbatim spec below)
- **Classification when started:** PROPOSE-ONLY engine change → `massoh-meta-engineer` drafts, then
  the normal gate (product-scope → architecture-safety → implementer → reviewer-qa → owner adopt).
- **Backlog row:** `AGENT_BACKLOG.md` §Queue · `agent-project/NOW_NEXT_LATER.md` §NEXT.
- **First adopter:** `elard`.

> The engine must stay project-agnostic: nothing elard-specific (or any single-project string) lands
> in the engine files. The elard config is a worked *example* inside the policy doc only.

---

## Owner spec (verbatim)

ROLE / SCOPE
You are working inside the Massoh engine repo (github.com/hsoffar/Massoh,
installed at ~/.claude/agent-os/). Add a new OPT-IN engine capability:
"Requirements Management & Traceability" (RMT). Treat this as a PROPOSE-ONLY
engine change (massoh-meta-engineer): draft the files, do NOT alter the
safety/standards/binary invariants, and leave final adoption to the owner.
Bump VERSION + manifest.yml only as part of the proposal.

GOAL
Give any Massoh project an addressable, machine-checkable requirements
registry that is linked to code, WITHOUT adding background automation.
Adding/removing/changing a requirement is a normal manual edit; building it
still flows through the existing gated workflow (/start-task → architecture
→ implementer → reviewer). RMT only adds: (1) an addressable registry,
(2) forward code/test/PR traceability, (3) a CI validator. No triggers, no
watchers, no auto-dispatch.

HARD CONSTRAINTS (Massoh invariants — do not break)
- Project-AGNOSTIC. No language/framework/path assumptions. Everything
  project-specific is declared in a per-project config, never in the engine.
- OPT-IN / dormant-until-enabled, same model as the rest of Massoh
  (a project gets RMT only if it has the config + registry; absent = no-op).
- Owner-gated. PROPOSE-ONLY; do not auto-merge engine changes.
- Append-only data (generalize the "keep older data" rule): a requirement is
  never deleted — removal = status change + reason, entry retained.
- Mirror the existing "no hard-coded single-locale/region" principle
  (policy 12): RMT must not assume one project shape.

CAPABILITY SPEC

1) Registry file (per project): `requirements/registry.yml` — a list of:
   - id: REQ-<AREA>-<NNN>        # AREA from project config vocab; 3-digit
     title: <one line>
     area: <AREA>
     status: proposed|implemented|deferred|frozen|removed
     priority: P0..P3            # P0 = non-negotiable / safety-critical
     flag: <flag-key|null>       # null = core
     code:  [<path|glob>, ...]   # forward links satisfying the requirement
     tests: [<path|glob>, ...]
     satisfied_by: [<PR/commit ref>, ...]
     adr: [<ADR id>, ...]
     source: "<narrative-doc-anchor>"   # link to human prose, no data dup
     removed_reason: <str|null>         # required iff status: removed
     superseded_by: <REQ-ID|null>
     owner_approved: <bool>             # required true to remove a P0/SAFE req

2) Per-project config: `agent-project/requirements.config.yml` declaring:
   - area_vocab: [SAFE, DIAG, ...]      # project's controlled AREA list
   - code_roots: [...]                  # dirs req-check may resolve paths in
   - test_roots: [...]
   - narrative_doc: <path>              # the human requirements/prose file
   - flag_sources: [ {path, parser} ]   # 0..N declared flag-list locations
                                        # to cross-validate `flag:` values
   - safety_areas: [SAFE]               # areas treated as P0-locked
   Absent config = RMT disabled for that repo.

3) Validator: a reference `req-check` script (engine template; dependency-
   light; reference impl in Python stdlib + yaml). Contract — fail CI on:
   - duplicate IDs; status/priority/area outside declared vocab; bad schema
   - status: implemented ⇒ code+tests+satisfied_by non-empty AND every
     referenced path resolves to ≥1 real file under code_roots/test_roots
   - flag value not found in ANY configured flag_source ⇒ error
     (requirement↔flag drift); flag in a flag_source with no REQ ⇒ warn
   - append-only: compare against previous committed registry (git) — no ID
     may disappear; a removed req must carry removed_reason
   - safety guard: a req in safety_areas or priority P0 cannot move to
     `removed` unless owner_approved: true
   Script is config-driven; zero hard-coded project facts.

4) Traceability: forward (registry→code), enforced by req-check. Reverse is
   convention only — PR descriptions cite the REQ-ID (fold into the existing
   GitHub issue/PR linking rule). No mandatory code-comment tags.

5) NO automation trigger. /start-task may NAME a REQ-ID; the task packet
   records `req:`; the merged PR updates that entry's satisfied_by/status by
   hand. Nothing fires on its own.

ENGINE INTEGRATION (deliverables — propose, don't force-merge)
- New policy doc: next free number, e.g. policies/14_REQUIREMENTS_TRACEABILITY.md
  — defines schema, statuses, validator contract, append-only + safety guard,
  adoption steps. Cross-link from 03_AGENT_WORKFLOW, 05_REVIEW_CHECKLIST,
  11_TASK_PACKET_SPEC, 08_FEATURE_GATE_TEMPLATE.
- Templates: templates/requirements.registry.template.yml,
  templates/requirements.config.template.yml, and the req-check reference
- Workflow wiring: 03_AGENT_WORKFLOW — /start-task accepts an optional
  REQ-ID. 11_TASK_PACKET_SPEC — add optional `req:` field. 05_REVIEW_CHECKLIST
  — reviewer asserts `req-check` is green when a registry exists.
- Skill: add an engine skill `req-check` (run validator + summary). Optional
  `massoh req` CLI subcommand (list/show/check) if a CLI exists.
- manifest.yml: register the RMT capability as opt-in. Bump VERSION + note in
  OPERATING_SYSTEM.md. Add a one-line pointer in the CLAUDE project template
  so adopting repos learn about it at boot.

ADOPTION (how a project turns RMT on — document this)
1. Add agent-project/requirements.config.yml (declare vocab + roots + flags).
2. Add requirements/registry.yml (seed incrementally — start with the
   safety/non-negotiables and the feature-flag inventory; backfill the rest
   as code is touched).
3. Add req-check to the project's CI + local test gate.
Projects without these files are unaffected (dormant).

ACCEPTANCE CRITERIA
- A fresh project with NO RMT files behaves exactly as before (pure no-op).
- A project that adds config + a 2-entry registry passes req-check; breaking a
  code path, deleting an ID, or removing a P0 req without owner_approved each
  fails req-check with a clear message.
- Zero elard-specific (or any single-project) string in the engine files.
- Engine VERSION + manifest updated; policy cross-links resolve.

FIRST ADOPTER: elard. Its config will declare area_vocab from REQUIREMENTS.md,
flag_sources = [backend flags.py allowlist, Android FeatureFlags.DEFAULTS],
narrative_doc = docs/REQUIREMENTS.md, safety_areas = [SAFE]. Provide an elard
example config in the policy doc as the worked reference — but keep it OUT of
the engine defaults.

---

## Notes for whoever starts this (not part of the owner spec)
- This is the **governance wedge** made concrete — Massoh's positioning is exactly "machine-checkable
  governance," so RMT is high strategic value. Rank accordingly.
- Confirm the next free policy number at start time (don't assume `14` — check `~/.claude/agent-os/policies/`).
- `req-check` adds a **Python + PyYAML** dependency for adopting projects only (the engine ships the
  template; dormant repos never run it). Flag this dep explicitly in product-scope — the bash CLI
  itself stays dependency-light; the validator is a separate reference script.
- Keep the elard worked-example confined to the policy doc; engine defaults stay project-agnostic.
