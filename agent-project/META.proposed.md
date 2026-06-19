## [meta] 2026-06-19 — RMT engine capability proposal (TASK-2026-06-19-rmt)

**Finding:** Massoh lacks an addressable, machine-checkable requirements
registry. As the system ships more autonomous work, traceability between
requirements and code/tests/PRs becomes a governance gap — the "machine-checkable
governance" positioning has no enforcement layer for requirements themselves.

**Root cause (heuristic):** Requirements live only in human prose (REQUIREMENTS.md
or backlog briefs); there is no stable ID scheme, no CI check, and no append-only
guard. Review findings cannot reference a requirement ID, and rework caused by
misunderstood scope is invisible in the ledger.

**Suggested engine change:**
Add RMT as an opt-in, dormant-until-enabled capability (policy 14):
- Addressable registry with stable REQ-<AREA>-<NNN> IDs.
- Config-driven validator (`req-check`) enforcing: schema vocab, implemented↔code
  path resolution, flag↔flag_source drift, append-only (no ID disappears), safety
  guard (P0/safety-area removal needs owner_approved).
- Engine skill `/req-check` for on-demand validation.
- Workflow wiring: optional REQ-ID in /start-task, `req:` packet field, reviewer
  assertion when registry exists.

**Expected improvement:**
- Rework caused by scope drift becomes detectable (C06 catches broken code refs).
- Flag↔requirement drift is caught at CI time (C07/C11) rather than review time.
- Append-only rule enforces the keep-older-data invariant for requirements.
- Review findings can cite REQ-IDs → the ledger can eventually tag rework by req.

**Routing:**
massoh-meta-engineer (DONE — filed five new additive files on feat/rmt + 05_proposal.md)
→ massoh-architecture-safety (review policy 14 schema, validator contract, PyYAML dep)
→ owner sign-off (manifest.yml entry + cross-link adoption)
→ massoh-implementer (apply ADOPTION DIFF from 05_proposal.md §5)
→ massoh-reviewer-qa (verify acceptance criteria, green req-check on 2-entry example)
→ owner merge

**Files created (on feat/rmt):**
- `policies/14_REQUIREMENTS_TRACEABILITY.md`
- `templates/requirements.registry.template.yml`
- `templates/requirements.config.template.yml`
- `scripts/req-check`
- `claude/skills/req-check/SKILL.md`
- `.agent_tasks/TASK-2026-06-19-rmt/05_proposal.md`

**Owner actions needed:**
1. Review this proposal + `05_proposal.md` §5 ADOPTION DIFF.
2. Sign off on `manifest.yml` entry (safety-critical) to proceed with wiring.
3. Confirm arch-safety agent should review policy 14 + validator contract.
