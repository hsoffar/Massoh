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
