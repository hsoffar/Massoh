# Changelog

All notable changes to Massoh. Format: [Keep a Changelog](https://keepachangelog.com/).
Versioning is the product version in `VERSION` (the engine's `manifest.yml version:` is separate —
it stamps the install-boundary schema, not the product).

## How to update an existing install
```bash
massoh update      # git pull --ff-only (hardened: stashes local edits) + reinstall into ~/.claude
massoh doctor      # verify the install matches the manifest; warns if a newer version is available
massoh version     # show the installed version + clone SHA
```

## [0.7.0] - 2026-06-17
### Added
- **`massoh ledger`** — self-measuring primitive: cost capture and aggregated reporting.
  Zero LLM spend. Pure bash + awk.
  - **`massoh ledger add <task-id> <stage> <tokens> <seconds>`** — appends one TSV row to
    `.agent_tasks/ledger.tsv` (append-only; creates `.agent_tasks/` if absent so it can be called
    in CI before `massoh on`). Row format: `<ISO-8601-UTC>\t<task-id>\t<stage>\t<tokens>\t<seconds>`.
    Validation: exactly 4 args; `tokens` and `seconds` must be non-negative integers (`^[0-9]+$`,
    checked before any file touch); `task-id` and `stage` are tab/newline-stripped (never rejected
    for content, but empty-after-strip → error). Single `printf >> $LEDGER` write (atomic at
    POSIX PIPE_BUF). `stage` is free-form in v1 (future versions may enumerate).
  - **`massoh ledger`** (no args) — read-only awk report: tokens + seconds per task and per
    stage, totals, per-task `avg_tokens/stage`. Division-by-zero guarded (count=0 → "n/a").
    Malformed rows silently skipped (`NF < 5` or non-numeric field 4/5). Absent ledger →
    human-readable degraded message, exit 0, no file created.
  - `ledger.tsv` is tracked in git (audit history, same as `METRICS.md` and `AGENT_SYNC.md`).
    No `.gitignore` change.
  - Architectural note: verb-based capture (not SubagentStop hook) keeps the ledger
    harness-neutral: any orchestrator can call `massoh ledger add`. Hook auto-capture is a NEXT.

## [0.6.0] - 2026-06-17
### Added
- **`massoh cron once --every <DUR>`** — fixes a correctness bug: `period_ticks` was hardcoded
  to assume 30-minute ticks regardless of the installed schedule. Now `cmd_once` accepts `--every`
  (same case pattern as `cmd_install`) and derives `period_ticks = period_days * 1440 / every_mins`
  from the actual interval. Default-30 fallback preserved. `cmd_install` now passes `--every $every`
  to the generated crontab line.
- **Tick duration logging** — `massoh cron once --run` now prints `tick_duration=<N>s` at tick end
  (wall-clock seconds). Never appears in dry-run mode.
- **`massoh review` v2 KPIs** — three new efficiency metrics per review run:
  - `cycle_avg_days` — average 00→06 packet span in days (git commit timestamps; degrades to `n/a`
    if files not in git history).
  - `rework_pct` — % packets with a "REQUEST CHANGES" decision line in `06_review_result.md`.
  - `throughput/wk` — packets reviewed within the `--since` window, normalized to per-week.
  - `reverts` and `backlog_todo` also written as standalone snapshot fields for machine parsing.
  - All three appear in stdout AND in the `## Snapshot` block in `agent-project/METRICS.md`
    (append-only; `--no-write` remains inert).
  - `stat` is banned; all dates via `git log -1 --format=%ct`. Division-by-zero guarded. All
    new grep/awk calls `|| true`-guarded.
- **`massoh recommend`** — forward heuristic suggestions from METRICS.md snapshot trend.
  Zero LLM spend. Rules fire on parsed numeric snapshot fields:
  - R1: cycle_avg_days rising across 2 snapshots → tighten scope.
  - R2: rework_pct > 25% → deepen arch/safety review.
  - R3: reverts > 0 → add regression tests.
  - R4: backlog_todo growing while throughput/wk flat/falling (2 snapshots) → throughput bottleneck.
  - R5: no snapshots → run `massoh review` first.
  - Default (no rules fire): "No issues detected."
  - Read-only by default; `--write` appends `## [recommend] <ts>` to `AGENT_SYNC.md` only
    (sole permitted write target; `>>` append only). `< 2 snapshots` suppresses trend rules R1/R4.
  - awk parse `|| true` — malformed METRICS.md degrades to R5, not crash.

## [0.5.1] - 2026-06-17
### Fixed
- `massoh learn`: a code-citation mentioning "REQUEST CHANGES" (e.g. quoting `_PAT_REQUEST_CHANGES`)
  was mistaken for a blocking finding — now only a Decision line counts (`grep -iE "decision.*…"`).
- `massoh learn`: the "Risks seen" section printed the `## Risks` *heading* instead of the content —
  now extracts the bullets under the heading via awk. (Both surfaced by running `learn` on Massoh itself.)

## [0.5.0] - 2026-06-17
### Added
- `massoh learn` — the **learning-from-previous loop**: heuristic read-only miner over completed
  task packets, the decision log, and git history. Zero LLM spend (grep/awk only).
  - **Mines**: `.agent_tasks/*/06_review_result.md` (blocking + non-blocking findings, `REQUEST
    CHANGES` lines), `.agent_tasks/*/05_implementation_handoff.md` (risks), `AGENT_SYNC.md`
    decision log (rows containing "irreversible" → ADR candidates), and `git log` (revert +
    fixup counts).
  - **Always prints** a lessons report to stdout: recurring review findings (with counts), risks
    seen, ADR candidates, revert/fixup count.
  - **`--write-proposals`** (default OFF): appends a `## [learn] <ts>` block to
    `agent-project/LEARNINGS.proposed.md` (append-only, create-if-missing). NEVER writes to
    `STANDARDS.md`, `memory/`, `docs/adr/`, or any safety-critical file.
  - **`--since DAYS`** (default: all time): limits packet scan by file mtime.
  - **`--no-write`**: explicit no-op alias for the default (stdout only).
  - Graceful guards: non-Massoh-project → non-zero exit; no packets → exit 0 with "(none)" sections.
  - Pattern strings (`## Blocking`, `## Non-blocking`, `REQUEST CHANGES`, `## Decision log`,
    `irreversible`) extracted as named variables with `# task-packet-spec` comments for future
    multi-language projects.
  - Agent-OS-learning milestone: v0.5.0. The system now closes the knowledge-drift feedback loop:
    packet history → `massoh learn` → `LEARNINGS.proposed.md` → owner promotes to STANDARDS/memory/ADR.

## [0.4.2] - 2026-06-17
### Added
- `massoh cron once` now runs **cadence ceremonies** on every tick (when `--run`):
  - **Every tick:** `massoh standup` runs after the backlog serialization block, appending
    a `## [standup]` entry to `AGENT_SYNC.md`. Suppress with `--no-standup`.
  - **Every period boundary** (`period_ticks = period_days * 1440 / 30`): `massoh review`
    + `massoh plan` run, then the counter resets to 0. Default period = 7 days.
- New `cron once` flags: `--period-days N` (default 7), `--no-standup`.
- New `cron install` flag: `--period-days N` (passed through to generated crontab line).
- Period counter persisted in `.agent_tasks/cron/cadence_state` (create-if-missing,
  corruption-tolerant: defaults to 0 on any non-integer content).
- Ceremony commands are **injectable** via env vars `MASSOH_STANDUP_CMD`,
  `MASSOH_REVIEW_CMD`, `MASSOH_PLAN_CMD` (parallel to `MASSOH_AGENT_CMD` / `MASSOH_GATE_CMD`).
  Ceremony failures are wrapped in `|| true` — cannot abort a cron tick.
- Completes v0.4: "cron = do work; cadence = review + decide."

## [0.4.1] - 2026-06-16
### Added
- `massoh standup` — progress-delta ceremony: commits since `--since` (default 1d), DOING + BLOCKED
  backlog items, in-flight packets (licensed, unreviewed). Read-only; appends `## [standup]` to
  `AGENT_SYNC.md` unless `--no-write`.
- `massoh plan` — planning ceremony: the prioritized TODO queue + surfaced owner decisions
  (`AGENT_SYNC.md` §Open questions) + BLOCKED items. Read-only; appends `## [plan]` unless `--no-write`.
- Completes the v0.4 ceremony set (review + standup + plan); cron-wiring is a later slice.

## [0.4.0] - 2026-06-16
### Added
- `massoh review` — the KPI "review ceremony" (first slice of v0.4 cadence). Read-only: gathers
  packet / backlog / delivery (PRs, commits, reverts) / branch metrics from `.agent_tasks/` + git +
  `AGENT_BACKLOG.md`, prints them, and appends a `## Snapshot` block to `agent-project/METRICS.md`
  (append-only). Flags: `--since DAYS`, `--no-write`, `--run-tests`. Degrades gracefully outside a
  git repo / with no packets.

## [0.3.0] - 2026-06-16
### Added
- `massoh cron` — the autonomous loop runner (`bin/massoh-cron`). Drains `AGENT_BACKLOG.md`:
  idleness gate → top unblocked TODO(s) → isolated **git worktree per item** → injectable agent →
  local gate → marks DONE + one serialized `[cron]` `AGENT_SYNC.md` entry.
  - **Safe by default:** `once` is **dry-run** unless `--run`; **auto-merge OFF** unless
    `--auto-merge` (and only when the gate is green); **idleness gate ON**.
  - **Parallel:** `--parallel N` fans N disjoint items to worktree agents; the parent is the single
    writer of `AGENT_BACKLOG`/`AGENT_SYNC` + the only one that merges (no write-race).
  - **Injectable for zero-cost testing:** `MASSOH_AGENT_CMD` (default `claude -p`) +
    `MASSOH_GATE_CMD` — tests use fakes, no API spend.
  - `massoh cron install [--every DUR] [--apply --yes-spend]` generates a crontab line; only touches
    the user crontab with explicit `--apply --yes-spend` (recurring paid spend = owner opt-in).
    `massoh cron off` removes it. `massoh cron status` shows config.

## [0.2.0] - 2026-06-16
### Added
- `massoh discover` — scan a repo and mine conventions into `agent-project/STANDARDS.md`
  (the "standards" layer); read by `massoh-implementer` + `massoh-reviewer-qa`.
- `massoh doctor` — verify the `~/.claude` install matches the manifest; exits non-zero on drift.
- `massoh version` / `--version` — print the installed version + clone SHA; shown in `massoh status`.
- `doctor` best-effort **update-check** — fetches `origin` and prints "update available" when the
  clone is behind `origin/main`. Informational only (never changes exit code). Opt-out:
  `--offline` or `MASSOH_NO_FETCH=1`.
- `templates/STANDARDS.template.md`, `VERSION`, `CHANGELOG.md`.
- `test/run.sh` — first CLI test suite (runs against a throwaway `CLAUDE_CONFIG_DIR`).

### Changed
- `massoh update` hardened: `stash → pull --ff-only → pop`; never loses local edits; a non-ff pull
  aborts cleanly and a pop conflict leaves edits in `git stash list`.
- `VERSION` is now part of the `~/.claude/agent-os/` install payload.

## [0.1.0] - 2026-06-16
### Added
- Initial extraction: marker-gated global install, 6 `massoh-*` role agents, 4 skills, policies,
  templates, `bin/massoh` CLI (install/update/on/off/enable/disable/status/work/uninstall),
  optional idle-cron, task-packet workflow.
