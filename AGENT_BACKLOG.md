# AGENT_BACKLOG.md — Massoh prioritized autonomous work queue

The queue the optional **idle cron** drains. When the owner is away, the cron takes the **top
unblocked TODO**, works it **to completion** (build → real test → local gate → PR → merge+deploy
only if flag-dark + additive + all green, else leave the PR open + a note), marks it **DONE**, and
re-syncs `AGENT_SYNC.md`. Full rules: `~/.claude/agent-os/docs/AUTONOMOUS_CRON.md`.

## Rules (summary)
- **Re-rank on add** (value × safety). **One at a time, to completion.**
- Every item obeys the guardrails (`~/.claude/agent-os/policies/09_GUARDRAILS.md`): flag-gate, never
  touch a designated safety-critical file/policy, keep-older-data, a **real** test, local gate
  before any PR.
- Flag-dark + additive + green → may auto-merge + deploy. Otherwise PR + note. Never force-merge
  past a failing required check.
- **Default to recommended when stuck** — take the safe/reversible/flag-dark option and proceed;
  only BLOCK + escalate for owner-gated calls (safety/policy, irreversible, significant cost).
- **Status:** TODO / DOING / DONE / BLOCKED / DEFERRED. Done items move to the bottom (kept, never deleted).

## Priority key
`P0` urgent/bug · `P1` high-value usability/functionality · `P2` nice-to-have · `P3` someday.

## Queue — the 24h plan (top = next; reconciled 2026-06-19)
Ordered by value × dependency. **`bin/massoh` is the serialization bottleneck** — items marked
`bin:Y` cannot run in parallel worktrees until #3 (modularize) lands; `bin:N` items are parallel-safe.

| # | Pri | Item | bin? | Status |
|---|-----|------|------|--------|
| 1 | P1 | **`massoh board --push plane`** — task-viz → Plane | Y | **DONE** — PR #17, v0.10.0 |
| 2 | P1 | **Dogfood the gate + CI** — GitHub Actions running `test/run.sh` on PRs | N | **DONE** — PR #19 |
| 3 | P1 | **Modularize `bin/massoh` → `lib/verbs/*.sh`** — the leverage move | Y | **DONE** — PR #18, v0.11.0 |
| 4 | P1 | **`massoh intake` (idea triage)** — append-only inbox + priority. See [[massoh-idea-intake]] | Y | **DONE** — PR #20, v0.12.0 |
| 5 | P1 | **Auto-ledger via SubagentStop hook** — capture tokens/time per stage | Y+hook | **DEFERRED** — hook payload lacks token/time/task-id; re-entry A/B/C in AGENT_SYNC |
| 6 | P1 | **Fleet slice 2** — repo registry + read-only multi-repo rollup. Slice of [[massoh-fleet-vision]]; brief `agent-project/briefs/fleet-multi-repo-self-curing.md` | Y | **DOING** — licensed, implementer next (→ v0.13.0) |
| 7 | P1 | **RMT slice 1** — policy doc + templates + `req-check` reference + skill (PROPOSE-ONLY). Spec `agent-project/briefs/RMT-requirements-traceability.md` | N (mostly) | TODO |
| 8 | P2 | **`board` local renderer** (HTML/Obsidian) — offline slice, no Plane needed | Y | TODO — after #1 merges |
| 9 | P2 | **Profiles + single `config.yml`** — archetypes; consolidate config | Y | TODO |
| 10 | P2 | **Emit `AGENTS.md`** from the roles — multi-harness portability | Y | TODO (re-entry: ≥2 repos through gates) |
| 11 | P2 | **Rename `manifest.yml version:` → `schema_version:`** — disambiguate from product VERSION | Y+manifest | TODO |
| 12 | P3 | **`test/run.sh` → bats** + commit-conv ratio in discover | N (tests) | TODO |

**Epics tracked separately (each yields more slices after the above):** RMT (full traceability,
slices 2+), Fleet layer (slices 3–4: cross-repo lessons pool → engine self-cure). See the briefs.

## 24h queue — acceptance stubs (so cron/impl has criteria)
- **#2 Dogfood+CI:** `.github/workflows/ci.yml` runs `bash test/run.sh` on PR + push, goes red on any
  failure; `massoh gate on` run here (hook installed, exempt list lets governance commits through);
  zero changes to existing verbs.
- **#3 Modularize:** each `cmd_*` moves to `lib/verbs/<verb>.sh`, sourced by `bin/massoh`; dispatch +
  usage unchanged in behavior; **full suite still green, byte-identical CLI output**; manifest lists
  the new lib files; no logic changes (pure extraction).
- **#4 intake:** `massoh intake "<idea>"` appends a ranked TODO row to this file (value×safety pri if
  unstated) + a one-line memory pointer; idempotent; never edits existing rows; read-only elsewhere.
- **#5 auto-ledger:** a SubagentStop hook (settings.json) calls `massoh ledger add` with the stage's
  tokens/seconds; degrades silently if ledger absent; no double-count; documented opt-in.
- **#6 fleet rollup:** `massoh fleet` lists `.massoh` repos under a root (or `~/.claude/massoh/fleet.tsv`)
  and prints a per-repo rollup (stage counts, blocked, last-handoff) — **read-only, no writes to any repo**.
- **#7 RMT slice 1:** policy `NN_REQUIREMENTS_TRACEABILITY.md` (verify next free number) + registry +
  config templates + `req-check` reference (python+yaml) + a `req-check` skill; a fresh repo with no
  RMT files is a pure no-op; elard worked-example confined to the policy doc.
- **#8 board renderer:** `massoh board --local` emits a self-contained HTML kanban + an
  Obsidian-Kanban `BOARD.md` from the same task model; no network; no token.
- **#9 profiles:** `agent-project/config.yml` (global default + project override) read by the verbs;
  absent = current defaults; additive.
- **#10 AGENTS.md:** generate `AGENTS.md` from the role files; idempotent; opt-in verb.
- **#11 schema_version:** rename in `manifest.yml` + `bin/massoh` reader in lockstep; one-release
  backward-compat (old key still read); doctor green.
- **#12 bats:** port `test/run.sh` checks to bats with identical coverage; CI runs bats.

## Done (newest first — kept, never deleted)
| Pri | Item | PR | Date |
|---|---|---|---|
| P1 | **Reconcile AGENT_BACKLOG drift** + seed 24h queue (this grooming) | — | 2026-06-19 |
| P1 | `massoh gate` — mechanical license-to-code enforcement (v0.9.0) | #16 → `fc6dc0d` | 2026-06-19 |
| P1 | `massoh meta` — self-improvement engineer + 7th PROPOSE-ONLY role (v0.8.0) | #15 → `be97ed0` | 2026-06-17 |
| P1 | `massoh ledger` — time/token/cost ledger (v0.7.0) | #14 | 2026-06-17 |
| P1 | efficiency-v2 — cycle-time/rework/recommend + cron fix (v0.6.0) | #12 | 2026-06-17 |
| P1 | `massoh learn` — learning-from-history loop (v0.5.0/0.5.1) | #9 (+fix #10) | 2026-06-17 |
| P1 | cadence ceremonies wired into cron — standup/review/plan (v0.4.2) | #8 | 2026-06-17 |
| P1 | `massoh cron` — autonomous parallel worktree loop runner (safe-by-default) | #4 → `1f02151` | 2026-06-16 |
| P1 | Version stamp (`massoh version`) + `doctor` update-check + `CHANGELOG.md` | #2 → `814df69` | 2026-06-16 |
| P1 | `massoh discover` + `STANDARDS.md`; harden `massoh update`; `doctor` + first test suite | #1 → `778e06a` | 2026-06-16 |

### — earlier granular rows (preserved verbatim; append-only, never delete) —
| P1 | v0.4 cadence ceremonies — `review` + `standup` + `plan` (KPIs, progress delta, queue+decisions) | #6 + this | 2026-06-16 |
| P1 | `massoh cron` — autonomous parallel worktree loop runner (safe-by-default) | #4 → main `1f02151` | 2026-06-16 |
| P1 | Version stamp (`massoh version`) + `doctor` update-check + `CHANGELOG.md` | TASK-version-notify (branch, pending merge) | 2026-06-16 |
| P1 | `massoh discover` + `STANDARDS.md` layer (wired into implementer/reviewer) | TASK-massoh-cli-verbs (branch, pending merge) | 2026-06-16 |
| P2 | `massoh doctor` + first CLI test suite (`test/run.sh`, 21 checks) | TASK-massoh-cli-verbs | 2026-06-16 |
| P1 | Harden `massoh update` (stash→pull→pop, fail-safe) | TASK-massoh-cli-verbs | 2026-06-16 |
