# 13 — Monitoring the agent system (portable)

You can't trust an autonomous team you can't observe. This is how the owner sees what the agents
did, catches drift early, and audits any decision. Monitoring here = **the agent system's own
health**, not the product's runtime telemetry (that's project-side).

## The four surfaces of record
| Surface | Answers | Updated by |
|---|---|---|
| `AGENT_SYNC.md` | what is the current state + last handoff + decision log | every agent, after work |
| `AGENT_BACKLOG.md` | what's queued / DOING / done (with PR links) | the cron + system-architect |
| `.agent_tasks/TASK-*/` | the full reasoning + handoff for each task | the agent of each stage |
| git history + PRs | the actual diffs, reviewable + revertible | the implementer |

Every autonomous action must be reconstructable from these four **without asking the agent**.

## The tick log (autonomous runs)
Each idle-cron tick records, in `AGENT_SYNC.md` (top entry) + the `AGENT_BACKLOG.md` Done row:
- **what** it picked and why (which backlog item, what rank),
- **what it changed** (branch, PR #, files),
- **the gate result** (tests/CI — verbatim pass/fail),
- **the decision** if any (chosen option + why; or BLOCKED + the owner-gated reason),
- **the outcome** (merged+deployed / PR left open / deferred).

Marker convention: prefix autonomous entries (e.g. `[cron]`) so the owner can scan unattended work.

## Health signals — green vs drift
Run `massoh status` / a quick scan for these:
| Healthy | Drift (investigate) |
|---|---|
| internal doc references all resolve | dangling refs (a boot file points to a missing path) |
| `AGENT_SYNC.md` updated within the last work session | stale sync (work happened, dashboard didn't move) |
| at most one item DOING | multiple DOING, or an item DOING for many ticks (stuck) |
| PRs merged or annotated | PRs left open with no note |
| every shipped change has a real test + green gate | merges past red, or stub-only tests |
| decision log append-only | rewritten/!deleted history |

## Owner review cadence (lightweight)
- **Glance (daily / when back):** the top of `AGENT_SYNC.md` + the `AGENT_BACKLOG.md` Done table +
  open PRs (`gh pr list`). That's the unattended-work digest.
- **Audit (any time):** a decision → read its task packet + the decision-log row + the PR diff. The
  trail is designed to answer "why did it do that?" from artifacts alone.

## Cheap metrics (optional, from the surfaces above)
items shipped / week · reverts (a revert = a guardrail miss to learn from) · items left BLOCKED ·
ticks-in-DOING before completion (stuck detector) · PRs auto-merged vs left for review.

## Alerting (project-side hook)
Massoh stays tool-agnostic. If the project wants push alerts, wire them to the same events:
"cron shipped X", "cron BLOCKED on owner-gated Y", "gate went red". Keep the artifacts as the
source of truth; alerts are a convenience layer.
