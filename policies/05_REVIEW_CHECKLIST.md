# 05 — Review checklist (portable)

The `massoh-reviewer-qa` agent walks this explicitly. Review **against the acceptance criteria** in
the packet/issue — not the implementer's summary.

## Scope
- [ ] Only the approved scope changed? (flag any extra, even if good = scope creep → block)
- [ ] No broad refactor smuggled in?

## Correctness + tests
- [ ] A **real test** exercises the actual path (not a stub)? Integration suite run?
- [ ] Gates green (build / lint / tests) — verbatim, not claimed?
- [ ] Edge cases + failure paths covered?

## Guardrails (`09_GUARDRAILS.md`)
- [ ] No designated safety-critical file/policy touched without sign-off?
- [ ] No project-prohibited content?
- [ ] Advisory products: calibration intact (confidence / hedges / disclaimers)? No false certainty?
- [ ] No frozen feature implemented?
- [ ] Keep-older-data respected (no hard-delete / overwrite)?
- [ ] **RMT (when registry exists):** `req-check` exits 0? (`/req-check` or
      `python3 scripts/req-check` — skip if project has no `requirements/registry.yml`)

## Compatibility + data
- [ ] API contract: unchanged, or both sides of the seam shipped together?
- [ ] Migration backward-compatible one release (expand→migrate→contract)? Idempotent?
- [ ] Feature flag present + default OFF (if required)?

## Localization / UX invariants
- [ ] Project UX invariants (e.g. RTL, primary language, a11y) intact on touched surfaces?
- [ ] No hard-coding of today's region/locale/segment against the expansion principle?

## Ops + trail
- [ ] Version bumped (if the project versions its client)?
- [ ] Rollback plan stated?
- [ ] `AGENT_SYNC.md` + task packet updated? Reviewer handoff exists?

## Verdict
**Approve / Request changes / Reject** — blocking findings must be specific + actionable
(file, area, exact change). Write `06_review_result.md`.
