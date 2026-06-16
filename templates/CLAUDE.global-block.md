<!-- massoh:start (v1) — managed by `massoh`; edit in the Massoh repo, not here -->
## Massoh agent operating system (installed globally)

The Massoh agent team + skills are installed in `~/.claude/`. The engine is `~/.claude/agent-os/`.

**Engagement is opt-in per repo.** A repo is a *Massoh project* only if it contains an
`agent-project/` directory **or** a `.massoh` marker file.

- **In a Massoh project:** boot via the repo's `CLAUDE.md`, classify the task mode, and follow the
  gated workflow + guardrails (`~/.claude/agent-os/policies/`). Use the `massoh-*` agents + skills.
- **In any other repo:** stay out of the way. Do **not** impose the gated workflow, do not require
  packets, do not auto-invoke the `massoh-*` roles. Behave as normal Claude Code.

Turn a repo on/off with `massoh on` / `massoh off`. Turn this whole block off with `massoh disable`.
<!-- massoh:end -->
