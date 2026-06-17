# Massoh — a portable agent operating system for Claude Code

Massoh turns any repo into one run by a small, disciplined **software team of AI agents** —
product-scope, architecture/safety, implementer, reviewer/QA, system-architect, history-maintainer,
meta-engineer — working through a **gated workflow** with guardrails, an auditable paper trail,
scheduled **ceremonies**, a **learning loop**, **self-measurement**, and an optional **autonomous mode**.

Install it **once, globally**. Every repo you open with Claude Code then has the team available — and
Massoh stays completely **out of the way** until you opt a repo in.

> **Philosophy — "post-agile for agents."** Keep agile's empirical core (iterate, small increments,
> test against reality, inspect-and-adapt). Drop the human-coordination ceremony (sprints, standups,
> story points) — agents sync instantly through files and run in parallel. **Add the hard gates agile
> under-specifies** — agents move fast and can do irreversible damage cheaply, so nothing ships
> without a license, an owner sign-off on safety-critical changes, and a real test.
> *Agile's discipline without agile's meetings — enforced, auditable, for AI agents.*

---

## Quickstart
```bash
git clone https://github.com/hsoffar/Massoh ~/dev/Massoh
~/dev/Massoh/bin/massoh install          # install the team into ~/.claude (backs up first; idempotent)
ln -s ~/dev/Massoh/bin/massoh ~/.local/bin/massoh   # put it on PATH (optional)

cd ~/dev/my-project
massoh on                                # scaffold this repo as a Massoh project (never overwrites)
massoh discover                          # mine the repo's conventions into agent-project/STANDARDS.md
claude                                    # the team is live here
```
A repo is a *Massoh project* only if it has an `agent-project/` directory **or** a `.massoh` marker.
Everywhere else, Claude Code behaves normally — zero footprint.

---

## The `massoh` CLI

**Lifecycle**
| Command | What |
|---|---|
| `massoh install` | install the team into `~/.claude` (backup first, idempotent). `--link` to symlink instead of copy. |
| `massoh update` | `git pull --ff-only` the clone + reinstall. **Hardened:** stashes local edits first; a non-ff pull aborts cleanly without losing them. |
| `massoh on` \| `init` | scaffold the current repo (`agent-project/` stubs, `AGENT_SYNC.md`, `AGENT_BACKLOG.md`, `memory/`, `CLAUDE.md`, `.massoh`). Never overwrites your files. |
| `massoh off` | go dormant in this repo (removes `.massoh`, keeps files). |
| `massoh enable` \| `disable` | global on/off (add/remove the `~/.claude/CLAUDE.md` block). |
| `massoh status` | installed? enabled? is this repo on? which version? |
| `massoh doctor` | verify the `~/.claude` install matches `manifest.yml`; warns when a newer version is available (offline-safe; `--offline`). |
| `massoh version` | the installed version + clone SHA. |
| `massoh work <repo>` | `cd <repo> && claude` — the selector. |
| `massoh uninstall` | remove the global footprint (after backup); per-repo files untouched. |

**Knowledge**
| Command | What |
|---|---|
| `massoh discover` | scan the repo and mine conventions (stack, test command, commit style, layout) into `agent-project/STANDARDS.md`. Read by the implementer + reviewer. `--force` to refresh. |
| `massoh learn` | **the learning loop** — mine completed task packets (review findings, risks), the decision log, and git reverts/fixups; print a *lessons* report. `--write-proposals` drafts STANDARDS / memory / ADR proposals into `agent-project/LEARNINGS.proposed.md` (you promote them). Read-only, zero LLM spend. |
| `massoh meta` | **the self-improvement loop** — mine the ledger (token outliers), rework rate, backlog drift, and repeated review findings; print a ranked bottleneck report. `--write-proposals` appends findings to `agent-project/META.proposed.md` (labeled `[meta]`; you promote them through the gate). Read-only by default, zero LLM spend. |

**Cadence ceremonies** (agent-native "meetings" — read-only, no humans, no spend)
| Command | What |
|---|---|
| `massoh standup` | progress delta: commits since `--since`, DOING + BLOCKED items, in-flight packets. |
| `massoh review` | KPI report: packets (open/reviewed), backlog counts, PRs merged, commits, reverts → appends a snapshot to `agent-project/METRICS.md`. |
| `massoh plan` | the prioritized queue + surfaced owner decisions (open questions) + BLOCKED. |

**Autonomy**
| Command | What |
|---|---|
| `massoh cron once` | one autonomous tick: idleness-gated, drains the top `AGENT_BACKLOG.md` TODO(s) in isolated **git worktrees**, runs the cadence ceremonies. **Safe by default:** dry-run unless `--run`; auto-merge off unless `--auto-merge`; `--parallel N`. |
| `massoh cron install` | generate a scheduler line (crontab); only applies with `--apply --yes-spend` (recurring paid spend = owner opt-in). `off` / `status`. |

---

## How it works — the gated workflow

Every meaningful task flows through stages, each leaving a markdown artifact in
`.agent_tasks/TASK-*/`. **The one hard gate: no product code without a license** (an approved
`04_implementation_packet.md` or an approved issue with acceptance criteria).

```
Owner idea
  → Product Scope        build / defer / kill + the minimal version        → 00, 01
  → (UX, if user-facing)                                                   → 02
  → Architecture/Safety  impact, risks, approve/reject (a gate)            → 03
  → Implementation Packet  THE LICENSE TO CODE                             → 04
  → Implementer          code + a real test + handoff (on a branch)       → 05
  → Reviewer / QA        approve / request-changes / reject                → 06
  → Owner merge
```

### The team (`claude/agents/massoh-*.md`)
| Role | Decides | Edits code? |
|---|---|---|
| `massoh-product-scope` | build / defer / kill, scope, metric | no |
| `massoh-architecture-safety` | readiness-to-build, risk (a gate) | no (read-only checks) |
| `massoh-implementer` | nothing (executes approved scope) | **yes — with a license, on a branch** |
| `massoh-reviewer-qa` | approve / request-changes / reject | no (read-only verify) |
| `massoh-system-architect` | unblock, sequence, architecture calls | small safe seams |
| `massoh-history-maintainer` | what to keep / merge / archive | no (docs only) |
| `massoh-meta-engineer` | surface bottlenecks, rework, repeated findings; propose engine upgrades | no (PROPOSE-ONLY) |

Invoke the flow with the `/start-task` skill, or call agents directly. State lives in
`AGENT_SYNC.md` (the shared dashboard); detail lives in the task packets; decisions of record in
`docs/adr/`.

---

## Guardrails
Every agent enforces `policies/09_GUARDRAILS.md`:
- **No code without a license.** Branch + PR per feature. Keep older data (append-only). Real tests
  (a stub doesn't count). No broad refactors. No secrets in git. Honest reporting.
- **Owner-gated stops** — an autonomous agent must stop and get the owner for: a change to a
  designated safety-critical file/policy (`agent-project/NON_NEGOTIABLES.md`), an irreversible /
  destructive op, a production deploy, or significant cost (paid API spend). Everything else: take
  the safe/reversible/flag-dark option and proceed.

---

## The boundary — portable vs project vs memory
| Class | What | Where |
|---|---|---|
| **Portable** | roles, skills, workflow, policies, templates (this repo) | `~/.claude/` (installed) |
| **Project** | charter, non-negotiables, strategy, standards, ADRs | the host repo (`agent-project/`, root) |
| **Memory** | accreted, project-specific learnings | the host repo only; Massoh ships only the *schema* |

`manifest.yml` is the machine-readable boundary (what `install` writes, what `on` scaffolds) — and
`massoh doctor` checks the live install against it.

---

## How it fits Claude Code
Claude Code auto-loads `~/.claude/agents`, `~/.claude/skills`, and `~/.claude/CLAUDE.md` for **every**
repo, so Massoh installs there. The only always-on surface is a small, **marker-gated** block in
`~/.claude/CLAUDE.md`: *engage the workflow only in an opted-in repo; otherwise behave as normal
Claude Code.* Agents/skills are inert until invoked — zero cost when unused, clean uninstall.

## Map
```
OPERATING_SYSTEM.md      # how the system works
VERSION · CHANGELOG.md   # product version + changelog
policies/                # 02 roles · 03 workflow · 04 code-rules · 05 review · 08 flags
                         # 09 GUARDRAILS · 10 history-audit · 11 packets · 12 expansion · 13 MONITORING
claude/agents/           # the 7 massoh-* roles
claude/skills/           # start-task · sync · close-task · history-cleanup
templates/               # CLAUDE (project + global-block) · CHARTER · NON_NEGOTIABLES · STANDARDS
                         # strategy/metrics/now-next · AGENT_SYNC · AGENT_BACKLOG · MEMORY_SCHEMA
docs/AUTONOMOUS_CRON.md  # the optional "let it work while I'm away" loop
bin/massoh · bin/massoh-cron · sync.sh · manifest.yml · test/run.sh
```

## Proven on itself
Massoh is its own first project. Versions 0.1 → 0.5 were built **by the `massoh-*` agent team, on
Massoh, through Massoh's own gate** — including a feature where the reviewer caught a real bug and
sent it back before merge, and a `massoh learn` run that surfaced two of its own defects on day one.
Every change has a packet trail; nothing merged without a green test suite.

## Status
**v0.5.1.** Origin: a production agent OS proven on a real Android + FastAPI product, then extracted.
Project-specific UX/domain agents (localization, design, market) are a per-project "domain pack",
not shipped here. Tests: `bash test/run.sh`.
