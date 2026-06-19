# 00 — Request: license-to-code gate enforcement

- **Task ID:** TASK-2026-06-19-license-gate
- **Date:** 2026-06-19
- **Raised by:** owner
- **Source:** `agent-project/NOW_NEXT_LATER.md` §NEXT — the only open backlog item.

## Verbatim request
> license-to-code gate enforcement — make the "no code without an approved packet" rule mechanical
> via pre-commit/pre-push hook + CI check

## Context
Today the core Massoh guardrail — **"No implementation without a license"** (an approved
`04_implementation_packet.md` or an approved issue with acceptance criteria;
`policies/03_AGENT_WORKFLOW.md` §"the one hard gate") — is **policy-only**. Agents are asked to
honor it; nothing mechanically stops a code commit that has no licensing packet. This task makes the
rule enforceable: a local git hook (pre-commit and/or pre-push) and/or a CI check that fails when
code changes land without a corresponding approved packet.

## Classification
`PRODUCT_SCOPE` — no `04_implementation_packet.md` exists and no approved acceptance criteria exist,
so by the one hard gate this cannot enter IMPLEMENTATION yet. Route to `massoh-product-scope` to
decide build/defer/kill, the minimal version, and acceptance criteria.

## Requested mode
evaluate (decision artifacts, not code).

## Code edits allowed?
**No.** This packet stage produces `01_product_scope.md` only. No code until an approved
`04_implementation_packet.md` exists.

## Open scoping questions (for product-scope to resolve)
1. **Surface:** local git hook (pre-commit vs pre-push), CI check, or both? Which is MVP?
2. **What counts as "a license"** for the check: presence of an approved `04_implementation_packet.md`
   touching the changed paths? a packet in an approved state? a linked issue?
3. **What triggers the gate:** any change to code paths (e.g. `bin/`, non-markdown)? Markdown/docs
   always exempt (matches guardrail "markdown artifacts always allowed").
4. **Escape hatch:** how does an owner intentionally bypass (e.g. `--no-verify`, an explicit
   `MASSOH_OVERRIDE=1`, or a signed override row)? The gate must be reversible/non-trapping.
5. **Install path:** is the hook installed by a `massoh` verb (touches the install contract →
   `bin/massoh` is safety-critical), or left as an opt-in repo file? This decides whether the
   architecture-safety stage is mandatory (likely yes).
6. **Self-consistency:** the gate must not block Massoh's own markdown/sync/housekeeping commits.

## Routing
1. `massoh-product-scope` → `01_product_scope.md` (build/defer/kill + minimal version + acceptance criteria).
2. If **Build:** → `massoh-architecture-safety` (touches install contract / safety-critical files) → `04_implementation_packet.md` → implementer → reviewer-qa.

## Shortcuts taken
None. Full gated flow (this change plausibly touches safety-critical install logic).
