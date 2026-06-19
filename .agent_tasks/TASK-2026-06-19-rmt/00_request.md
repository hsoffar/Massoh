# 00 — Request: Requirements Management & Traceability (RMT) — 24h queue #7

- **Task ID:** TASK-2026-06-19-rmt
- **Date:** 2026-06-19 · owner (24h queue #7).
- **Full spec:** `agent-project/briefs/RMT-requirements-traceability.md` (owner's verbatim brief).
- **Classification:** PROPOSE-ONLY engine change → `massoh-meta-engineer` drafts → gate.

## What
An OPT-IN, project-agnostic, dormant-until-enabled engine capability: an addressable, machine-checkable
requirements registry linked to code, with a CI validator (`req-check`), forward code/test/PR
traceability, append-only data + a safety-area guard. **No background automation.** Building a
requirement still flows through the existing gated workflow.

## Routing + the sign-off gate
`massoh-meta-engineer` (PROPOSE-ONLY) drafts the package on `feat/rmt`. Because it touches
`manifest.yml` (template registration) + edits to existing engine policy files (03/05/11/08
cross-links) + VERSION — both are **owner-gated** (manifest is safety-critical; engine adoption is the
owner's call). So:
- The meta-engineer may **write the NEW additive files** directly (policy 14, templates, req-check
  reference, the `req-check` skill) — additive, reversible, safe.
- It must **NOT apply** the safety-critical wiring (manifest entry, edits to existing policies, VERSION
  bump) — instead draft those as a clearly-labelled **adoption diff** in the proposal for owner
  sign-off + arch-safety.

After the proposal: `massoh-architecture-safety` → **owner sign-off** (manifest + adoption) →
`massoh-implementer` applies the wiring → `massoh-reviewer-qa` → owner merge.

## Hard constraints (from the brief)
Project-agnostic (zero elard/single-project strings in engine files; elard worked-example confined to
the policy doc). Opt-in/dormant (absent config+registry = no-op). Append-only requirements (removal =
status change + reason). `req-check` is config-driven, dependency-light (python stdlib + pyyaml,
adopters only). Next free policy number = **14** (confirmed).
