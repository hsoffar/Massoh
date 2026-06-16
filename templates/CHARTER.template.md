# CHARTER — {{PROJECT}} (constant context)

The unchanging facts every agent needs. Keep it short; details go in `docs/`.

## 1. Mission
{{ one or two sentences: what this product is, for whom }}

## 2. Current wedge (focus, NOT a permanent constraint)
{{ the narrow MVP focus: region / locale / segment / platform / domain }}
**Expansion principle:** today's wedge is selectable, not hard-coded
(`~/.claude/agent-os/policies/12_EXPANSION_READY_ARCHITECTURE.md`). Single-valued-for-now: {{ list }}.

## 3. Architecture (one paragraph + the seams)
{{ stack + the main components }}
- **Swap seams** (small safe change points): {{ e.g. the LLM call, the payments adapter }}
- **API contract seam** (change both sides together): {{ e.g. backend schemas ↔ client DTOs }}

## 4. Environment / how to run
- Run: {{ command }}
- Test: {{ unit + integration commands; the integration flag }}
- Deploy: {{ who/how — note: deploy to a real-user env is owner-gated }}

## 5. Conventions
- Commits: Conventional Commits; trailer `Co-Authored-By: {{ name <email> }}`.
- Branching: branch + PR per feature; default branch is `{{ main }}`.
- Versioning: {{ how the client is versioned; bump rule }}.
- Never commit: `.env*`, local config, build outputs, datasets, secrets.
