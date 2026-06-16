# 09 — Guardrails (portable)

The invariants every Massoh agent enforces. Two layers: **portable** (always true, shipped by
Massoh) and **project-defined** (filled in by the host's `agent-project/NON_NEGOTIABLES.md`). An
agent that cannot satisfy a guardrail **stops and routes**, it does not work around it.

## A. Portable invariants (always on)
1. **No code without a license.** Product code changes require an approved
   `04_implementation_packet.md` or an approved issue with acceptance criteria. No license → route
   to `massoh-product-scope`. (Markdown artifacts are editable in any mode.)
2. **Branch + PR per feature.** Never commit straight to the default branch. One feature → one
   branch → one PR. (`12`/project may add branch protection.)
3. **Keep older data.** Append-only / soft-delete / versioned. **Never hard-delete or overwrite
   history** — neither product data nor agent history (packets, decision log, ADRs, sync entries).
4. **Feature flags (if the project opts in).** New user-facing behavior ships behind a flag,
   default OFF (`08_FEATURE_GATE_TEMPLATE.md`). Flag-dark = no behavior change for existing users.
5. **Real tests.** Every implementation adds a test that exercises the **real path** — a stub-only
   test is not acceptance. Run the project's integration suite, not just unit fakes.
6. **No broad refactors** unless explicitly requested. Reuse before adding; match existing patterns.
7. **No secrets in git.** Never commit `.env*`, local config, credentials, keys, build outputs, or
   datasets.
8. **Honest reporting.** If tests fail, say so with the output. If a step was skipped, say so. Done
   means verified, not assumed.
9. **Scope discipline.** Implement exactly the approved scope. No "while I'm here" additions.

## B. Owner-gated actions (an autonomous agent must STOP and get the owner)
These are reversible only at high cost or not at all — never do them on an unattended tick:
- changing a **designated safety-critical file/policy** (listed in `NON_NEGOTIABLES.md`);
- **irreversible / destructive ops**: data deletion, production-data mutation, force-push, history
  rewrite, dropping a column/table without expand→contract;
- **production deploy** to an environment serving real users (ship code via PR; the deploy itself
  is owner-run/owner-approved);
- anything with **significant cost** (paid API spend, infra spin-up, quota purchase);
- unfreezing a **frozen** feature (`AGENT_SYNC.md` §Frozen).

Everything else: when a decision is needed, **take the recommended safe/reversible/flag-dark option
and proceed** — record what you chose and why. Don't stall waiting for the owner on reversible calls.

## C. Project-defined guardrails (the host fills these in `NON_NEGOTIABLES.md`)
Massoh ships the *slots*; the project supplies the *content*:
- **Designated safety-critical files/policies** — the exact paths agents may not touch without
  sign-off (e.g. a safety filter, a prompt's safety rules, an auth boundary, a billing calc).
- **Prohibited content** — domain output the product must never produce.
- **Over-claim / advisory rules** — if the product is advisory, the calibration it must keep
  (confidence, hedges, disclaimers) and what would constitute false certainty.
- **Localization / UX invariants** — e.g. RTL, a primary language, accessibility floors.
- **Migration policy** — e.g. backward-compatible one release (expand→migrate→contract).
- **Expansion principle** — which of today's region/locale/segment choices are a *wedge*, not a
  permanent constraint (`12_EXPANSION_READY_ARCHITECTURE.md`).

## D. Enforcement points (who checks what)
| Stage | Agent | Guardrail focus |
|---|---|---|
| before build | `massoh-architecture-safety` | A1, B, C — approve readiness; block unsafe design |
| during build | `massoh-implementer` | A (self-check); declares flag + test + rollback up front |
| after build | `massoh-reviewer-qa` | every invariant; rejects scope creep / missing real test / guardrail regression |
| unblocking | `massoh-system-architect` | B (decide vs escalate), keeps moves reversible |

## E. Autonomous-cron guardrails
Idle-gated (act only when the owner is away). One item at a time, to completion. Auto-merge +
deploy **only** when flag-dark **and** additive/low-risk **and** all gates/CI green — otherwise
leave the PR open + a note. Never force-merge past a failing required check. Escalate per §B.
