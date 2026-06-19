<!-- massoh-generated -->
# Massoh Agent Team

| Role | Description | Edits code? |
|---|---|---|
| massoh-architecture-safety | Use for backend, API, DB, data-model, LLM/prompt, safety, auth, observability, migrations, localization/expansion, and deployment-risk review. A gate before implementation. | yes |
| massoh-history-maintainer | Use for cleaning old agent docs, merging duplicated instructions, archiving stale sync history, keeping AGENT_SYNC.md a dashboard, and maintaining the agent operating system. | yes |
| massoh-implementer | Use only for approved narrow implementation tasks that have acceptance criteria and an implementation packet (or an approved issue). The only normal coding agent. | yes |
| massoh-meta-engineer | Use to analyse Massoh's own operational data (ledger, packets, review findings) and surface bottlenecks, repeated mistakes, and engine-upgrade proposals. PROPOSE-ONLY — never auto-merges engine changes, never directly edits safety/standards/binary files. | yes |
| massoh-product-scope | Use proactively for product strategy, prioritization, MVP scope, activation metrics, feature gating, sequencing, segment choice, monetization experiments, and build/defer/kill decisions. | yes |
| massoh-reviewer-qa | Use after code changes to review scope, tests, safety/guardrails, API compatibility, DB migrations, deployment + rollback risk, localization readiness, and hidden feature creep. | yes |
| massoh-system-architect | Use to unblock a stalled/unfinished autonomous task, make or escalate a system-architecture decision, or (re-)sequence the backlog. The escalation target the idle cron hands a task to when the previous one is NOT finished or a decision is needed. | yes |

> Workflow: see [agent-os/policies/03_AGENT_WORKFLOW.md](agent-os/policies/03_AGENT_WORKFLOW.md)
