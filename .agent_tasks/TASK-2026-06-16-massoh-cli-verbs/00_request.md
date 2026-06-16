# 00 — Request

**Task ID:** TASK-2026-06-16-massoh-cli-verbs
**Date:** 2026-06-16
**Source:** owner, this session (dogfooding Massoh on itself)

## Verbatim request
> have you edited massoh files temaplte ... go on with update and doctor discover ,...etc

Expanded (owner-confirmed intent): add new `massoh` CLI capabilities from the seeded backlog —
1. `massoh discover` — scan the host repo, mine conventions into `agent-project/STANDARDS.md`,
   wire so `massoh-implementer` + `massoh-reviewer-qa` read it. (borrow from buildermethods Agent OS)
2. `massoh doctor` — verify the global install (`~/.claude`) matches `manifest.yml`: drift,
   version skew, orphaned `massoh-*` files.
3. harden `massoh update` — stash/diff local edits before the `git pull --ff-only` so it can't
   fail or clobber a `--link`ed/edited clone.

## Classification
**PRODUCT_SCOPE** (entry). No `04_implementation_packet.md` exists → hard gate (`09_GUARDRAILS.md` §1)
forbids implementation. Owner authorized *building*, but scope/sequencing/acceptance must be set
first. Mode is not `IMPLEMENTATION` yet.

## Requested mode
Build → so route: product-scope (this) → architecture/safety (touches safety-critical files) →
packet(s) → implementer → reviewer. **Not user-facing** → UX stage skipped (recorded shortcut).

## Code edits allowed?
**No** — not in PRODUCT_SCOPE. Code only after an approved `04` packet, on a non-default branch.

## Safety note
All three touch `bin/massoh`; #1 also adds a verb + writes a project file; #2 reads the install.
`bin/massoh` and `manifest.yml` are **designated safety-critical** (`NON_NEGOTIABLES.md`) → require
architecture/safety approval + owner sign-off before merge.

## Sequencing (proposed; product-scope to confirm)
One at a time, to completion (autonomous-cron rule). Proposed order by value×safety:
`update` hardening (smallest, de-risks the others) → `doctor` (read-only, additive) →
`discover` (largest, new verb + new file + agent wiring).
