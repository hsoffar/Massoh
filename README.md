# Massoh — a portable agent operating system for Claude Code

Massoh turns any repo into one with a small **software team**: product-scope, architecture/safety,
implementer, reviewer/QA, system-architect, and history-maintainer agents, plus a gated workflow,
guardrails, task packets, and an optional idle-time autonomous mode.

Install it **once, globally**. Every repo you open with Claude then has the team available — and it
stays **out of the way** until you opt a repo in.

## Quickstart
```bash
git clone https://github.com/hsoffar/Massoh ~/dev/Massoh
~/dev/Massoh/bin/massoh install        # installs the team into ~/.claude (backs up first)

cd ~/dev/my-project
~/dev/Massoh/bin/massoh on             # scaffold this repo as a Massoh project (fill in agent-project/*)
claude                                 # the team is live here
```
Put it on PATH for convenience: `ln -s ~/dev/Massoh/bin/massoh ~/.local/bin/massoh`.

## How it fits Claude Code
Claude Code auto-loads `~/.claude/agents`, `~/.claude/skills`, and `~/.claude/CLAUDE.md` for **every**
repo. So Massoh installs there. The only always-on surface is a small, **marker-gated** block in
`~/.claude/CLAUDE.md` that says: *engage the workflow only in a repo that opted in (has
`agent-project/` or a `.massoh` marker); otherwise behave as normal Claude Code.* Agents/skills are
inert until invoked — zero cost when unused.

## The `massoh` CLI
| Command | What |
|---|---|
| `massoh install` | install the team into `~/.claude` (backup first; idempotent). `--link` to symlink instead of copy. |
| `massoh update` | `git pull` the Massoh repo + re-install. |
| `massoh on` \| `init` | scaffold the current repo (`agent-project/` stubs, `AGENT_SYNC.md`, `AGENT_BACKLOG.md`, `memory/`, `CLAUDE.md`, `.massoh`) → engage here. Never overwrites your files. |
| `massoh off` | dormant in this repo (removes `.massoh`, keeps files). |
| `massoh enable` \| `disable` | global on/off (add/remove the `~/.claude/CLAUDE.md` block). |
| `massoh status` | installed? enabled? is this repo on? which version? |
| `massoh work <repo>` | `cd <repo> && claude` — the "selector". |
| `massoh uninstall` | remove the global footprint (after backup); per-repo files untouched. |

## The boundary — portable vs project vs memory
| Class | What | Where |
|---|---|---|
| **Portable** | roles, skills, workflow, policies, templates (this repo) | `~/.claude/` (installed) |
| **Project** | charter, non-negotiables, strategy, ADRs, ops | the host repo (`agent-project/`, root) |
| **Memory** | accreted learnings | the host repo only; Massoh ships only the *schema* |

`manifest.yml` is the machine-readable boundary (what install writes, what `on` scaffolds).

## Map
```
OPERATING_SYSTEM.md     # how the system works
policies/               # 02 roles · 03 workflow · 04 code-rules · 05 review · 08 flags
                        # 09 GUARDRAILS · 10 history-audit · 11 packets · 12 expansion · 13 MONITORING
claude/agents/          # the 6 massoh-* roles
claude/skills/          # start-task · sync · close-task · history-cleanup
templates/              # CLAUDE (project + global-block) · CHARTER · NON_NEGOTIABLES · strategy/metrics/now-next
                        # AGENT_SYNC · AGENT_BACKLOG skeletons · MEMORY_SCHEMA
docs/AUTONOMOUS_CRON.md # the optional "let it work while I'm away" loop
bin/massoh · sync.sh · manifest.yml
```

## Guardrails + monitoring
Every agent enforces `policies/09_GUARDRAILS.md` (no code without a license, flag-gate, keep-older-
data, branch+PR, owner-gated stops for safety/irreversible/cost). You can see everything the team
did via `policies/13_MONITORING.md` (sync dashboard + backlog + task packets + git/PRs).

## Status
v0.1 — first extraction. Origin: a production agent OS proven on a real Android+FastAPI product.
Project-specific UX/domain agents (e.g. localization, design) are a per-project "domain pack", not
shipped here.
