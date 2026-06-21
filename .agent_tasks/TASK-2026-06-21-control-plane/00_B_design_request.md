# 00 — Design request: Control plane track B (auth + write/exec) — DESIGN ONLY

- **Date:** 2026-06-21 · owner wants a full control plane over the fleet dashboard.
- **This is a DESIGN spec for OWNER SIGN-OFF — no build.** Track B = write/exec actions, owner-gated.

## Context
The fleet dashboard (`massoh fleet serve`, v0.23.0) is loopback-only, read-only, no auth. Owner wants
control actions FROM the dashboard. Track A (read views) builds now under the existing read-only model.
Track B (this) = write/exec; needs an architecture + safety + AUTH design before any build.

## Track B scope to design (NOT build)
Owner-requested control actions, roughly increasing risk:
1. **Submit a new idea → `massoh intake`** (FLAGSHIP / pilot — append-only inbox write, no exec, no
   safety-critical file: the LOWEST-risk write; design the POST+auth pattern here first).
2. Open/queue tasks; manage tickets/issues (writes to backlog).
3. Change agent personality (edit `claude/agents/massoh-*.md` — engine/behavior files).
4. Add/edit hooks (settings.json — auto-running automation).
5. Issue server restart; `massoh update` (EXEC; restart/deploy).

## The design must answer (the load-bearing parts)
- **AUTH model:** the server has none today. A control plane that can edit hooks / restart / update
  MUST authenticate. Design it: localhost-single-user token? a per-session CSRF token on every POST
  form? a confirm-step? What's the minimal-but-real model so a stray browser tab / drive-by / other
  local process cannot trigger writes/exec? (CSRF on an unauthenticated localhost server is the core threat.)
- **Risk tiers + gating:** classify each action (append-only write / safety-critical-file edit / exec)
  and which require a fresh OWNER sign-off vs which the auth-token covers. Hooks + agent-personality +
  restart/update are safety-critical — likely each its own sign-off + arch conditions.
- **Per-action safety:** intake (append-only, sanitized — reuse intake's IK rules); agent-personality
  edits (these are PROPOSE-ONLY engine-behavior changes → gate, never raw-overwrite from web);
  hooks (auto-run code → highest scrutiny); restart/update (exec → confirm + audit).
- **Pilot design (intake button):** the concrete POST→`massoh intake` flow: form, CSRF token,
  validation, append-only write, success/echo, audit-log line. Smallest end-to-end write to prove the model.
- **Audit:** every control action logged (who/what/when) to an append-only audit file.

## Deliverable
`.agent_tasks/TASK-2026-06-21-control-plane/01_B_design.md` — the auth model, risk tiers + per-action
gating, the intake-button pilot design end-to-end, audit, and a sliced build order (pilot first). Mark
clearly what needs OWNER SIGN-OFF before each slice. This is design-for-approval; NOTHING ships from B
until the owner signs off on this design + the per-action gates.

## Routing
`massoh-system-architect` → `01_B_design.md` → owner reviews + signs off → then (and only then) the
pilot (intake button) goes to impl under the auth model.
