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

## [0.15.0] - 2026-06-19
### Added
- **`massoh board --local [--out <dir>]`** — emit a self-contained HTML kanban (`agent-project/board.html`)
  and an Obsidian-Kanban `BOARD.md` (`agent-project/BOARD.md`) from the same `_board_build_model` output.
  **No network, no jq, no secret reads on the `--local` path** (BR4/BR7).
  - `_board_html_escape` helper applies `&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`, `"`→`&quot;` (in order)
    to every interpolated field before `printf` into HTML (BR2 — XSS prevention).
  - BOARD.md cells sanitize `|`→`/` and newlines→space via `tr`/`sed`, no jq (BR3).
  - Sentinel-based clobber policy: writes sentinel `<!-- massoh-generated -->` on first emit;
    subsequent runs detect it and overwrite; refuses to overwrite hand-authored files (BR5).
  - `--out <dir>` always overwrites within the specified directory (BR5).
  - `--push plane` path is byte-identical; T17–T23 regression green (BR6).
  - `_board_build_model` is reused (exactly 2 call sites: push + local; no second scanner) (BR1).

## [0.14.0] - 2026-06-19
### Added
- **`agent-project/config.yml` (optional)** — project-level tunable overrides via a pure-bash
  YAML-lite reader (`lib/verbs/_config.sh`). Absent/empty/malformed config = byte-identical
  existing behavior (PC1 central guarantee). Supports flat `key: value` pairs; handles inline
  comments, quoted values, extra whitespace. No new dependencies (pure grep/sed, POSIX-bash).
  - **3 tunables wired (MVP scope):**
    - `meta_outlier_factor` — token-outlier multiplier for `massoh meta` (default 2).
    - `meta_repeat_threshold` — repeated-finding promotion threshold for `massoh meta` (default 3).
    - `cron_idle_min` — owner-idleness window for `massoh cron` (default 25).
  - **Precedence:** project (`agent-project/config.yml`) > built-in default. Global tier deferred.
  - **Secret guard:** keys matching `_token|_key|_secret|_password|_credential` warn to stderr
    and return the built-in default; config.yml is a committable file and must not hold secrets.
  - **Integer validation (PC2):** every config value used in arithmetic is validated with the
    ledger.sh L2 `case` pattern before use; malformed values fall back to built-in defaults.
  - No scaffold/manifest change (no-scaffold path); `massoh on` is unchanged.

## [0.13.0] - 2026-06-19
### Added
- **`massoh fleet [--root <dir>] [--no-cache]`** — read-only multi-repo rollup verb.
  Discovers opted-in Massoh repos (`.massoh` marker) under `--root` (bounded `find -maxdepth 3`,
  cap 200 repos) or via a `~/.claude/massoh/fleet.tsv` registry (one path per line), and prints
  per-repo stage counts (todo/doing/done), blocked count, and last-handoff agent/mode from
  `AGENT_SYNC.md`. **Writes nothing to any discovered repo** (structural write-isolation: FL1).
  - Degrade: per-repo failures produce `[SKIP] <path>: <reason>` and the loop continues (FL5).
  - Missing root or no registry: exit 0 with an informational message (FL2/FL3).
  - `fleet.tsv` sanitized with `while IFS= read -r`; paths validated with `[ -d ]`; lines
    >4096 chars discarded; never sourced or eval'd (FL3/FL4).
  - PRIVACY: local-only output, nothing uploaded (FL8). No network primitives (FL7).
  - Discovery root is a parameter (`--root` / `MASSOH_FLEET_ROOT`) — never hard-coded (expansion
    principle). `MASSOH_FLEET_TSV` overrides the registry path.

## [0.12.0] - 2026-06-19
### Added
- **`massoh intake "<idea>"`** — fast idea-capture verb: append one ranked row to a dedicated
  `## Intake inbox` section of `AGENT_BACKLOG.md` (bootstrapped via `>>` on first use, after
  Done/Frozen) + a one-line pointer to `memory/MEMORY.md`. Zero awk rewrite, zero sed -i,
  zero `> file` redirect. Queue / Done / Frozen sections are never touched.
  - **Priority heuristic (P0–P3, deterministic, zero LLM):** keyword scan on the lowercased idea.
    P0: bug/broken/crash/fail/urgent/security/block. P1: add/implement/ship/feature/new verb/
    enable/integrate. P2: improve/optimize/refactor/update/enhance. P3: everything else.
    Keywords documented in `lib/verbs/intake.sh` as named constants.
  - **Input sanitization:** strips `|`, `\n`, `\r`, tab from the idea string; truncates to 200
    chars; rejects empty-after-strip with a usage message (exit non-zero, write nothing).
  - **Arg guard first:** missing/empty arg → die, exit non-zero, write nothing.
  - **Idempotent:** `grep -qF` check on BACKLOG; if idea already present, prints notice and
    exits 0 without writing (prevents duplicate rows from re-runs).
  - **Memory pointer:** appends one `- [intake: <first 60 chars>](<ts>)` line to
    `memory/MEMORY.md` (append-only `>>`; failure is non-fatal via `|| true`).
  - **Massoh-project guard:** requires `.massoh` or `agent-project/` before any write.
  - **Degrade:** absent BACKLOG bootstraps the file (mkdir -p + section header via `>>`);
    all reads use `|| true`; exit 0 on success, non-zero on arg/sanitization failure only.
  - Read-only isolation: `cmd_intake` does NOT call `cmd_ledger`, `cmd_learn`, `cmd_meta`,
    or any other `cmd_*`.
  - Auto-wired by `cmd_install`'s existing `lib/verbs/` glob (no `manifest.yml` change).

## [0.11.0] - 2026-06-19
### Changed
- **`bin/massoh` modularized** — 12 additive feature verbs extracted to `lib/verbs/*.sh`, sourced
  at startup. Zero behavior change: same output, same exit codes, same flags on all verbs.
  - `lib/verbs/`: discover, review, standup, plan, learn, recommend, ledger, meta, gate, board, cron, work.
  - Safety-critical core (install/uninstall/on/off/enable/disable/status/doctor/update/version) stays
    in `bin/massoh` (now ~216 lines instead of 1662).
  - **`cmd_install`** now copies `lib/verbs/` into `~/.claude/agent-os/lib/verbs/`.
  - **`cmd_doctor`** now verifies `~/.claude/agent-os/lib/verbs/` is present.
  - **`manifest.yml`** updated with `lib/verbs/` entry (in lockstep with `cmd_install`).
  - **Backward-compat**: `cmd_uninstall` removes `agent-os/` wholesale (includes `lib/verbs/`).
  - **MB1**: sourcing loop uses `$MASSOH_HOME` (symlink-safe). **MB3**: missing lib file → `die`. 

## [0.10.0] - 2026-06-19
### Added
- **`massoh board --push plane`** — push Massoh's file-based task state to a Plane kanban board
  (push-only; Plane is a read-only mirror). First credential + outbound-network surface in Massoh.
  - **Internal task model**: scans `.agent_tasks/TASK-*/`, derives `{task-id, title, description,
    stage, priority, last-agent, blocked, cost_tokens}` per task. Stage = highest packet file
    present (backlog / scoping / arch-safety / licensed / implementing / review / merged).
  - **Plane upsert**: POST to create (first run) → PATCH to update (subsequent runs). Idempotent
    via an append-only local id-map `.agent_tasks/.board-map.tsv`.
  - **Plane states**: ensures the 7 stage states exist in the project (check-before-create;
    idempotent; never duplicates a state).
  - **`massoh board --init-config`**: creates `.env.massoh` template (secret config; gitignored,
    create-if-missing) and `agent-project/board.conf` (non-secret slugs; committable).
  - **`massoh board --no-push`** / bare `massoh board`: prints task table, zero API calls.
  - **`massoh board --dry-run`**: prints what would be pushed, zero writes.
  - **Secret discipline (BG1–BG7)**: `PLANE_API_TOKEN` never written to any tracked file, never
    printed or logged, passed to Plane via `X-API-Key` header only. `.env.massoh` and
    `.agent_tasks/.board-map.tsv` added to `.gitignore` before any write (idempotent).
  - **Network discipline (BG8–BG15)**: `--connect-timeout 10 --max-time 30` on every curl; non-2xx
    → warn + skip + continue + exit 0; map row written only on confirmed 2xx; HTTPS enforced
    (reject `http://` unless `PLANE_ALLOW_HTTP=1`).
  - **`jq` startup guard (BG22)**: exits 1 with install instructions if jq is absent; jq confined
    to `cmd_board` only (no other verb gains a jq dependency).
  - **Adapter isolation**: model-building (`_board_build_model`) is separate from the push adapter
    (`_board_push_plane`); future `--push github` / `--push linear` adapters can be added without
    touching model code.
  - **`manifest.yml`** updated lockstep: `agent-project/board.conf` added to `project_scaffold`.
  - Plane REST API used per current docs (fetched from `makeplane/developer-docs` branch
    `feat/add-new-api-docs`, 2026-06-19). Auth: `X-API-Key` header.
  - POSIX bash, `set -euo pipefail`, zero LLM, zero Anthropic API calls.

## [0.9.0] - 2026-06-19
### Added
- **`massoh gate on` / `massoh gate off`** — per-repo, opt-in license-to-code gate that
  mechanically enforces the "no code without an approved `04_implementation_packet.md`" guardrail.
  - **`massoh gate on`**: installs a pre-push git hook (`.git/hooks/pre-push`) and copies the CI
    workflow template (`.github/workflows/massoh-gate.yml`) into the current Massoh project. Both
    are create-if-missing; the pre-push hook is append-safe — if a user hook already exists it
    appends a namespaced `# massoh-gate:start … # massoh-gate:end` block without clobbering
    existing content. Requires a git repo and a Massoh project (`.massoh` or `agent-project/`).
  - **`massoh gate off`**: strips only the Massoh-namespaced block from the pre-push hook via awk
    (same pattern as the global block removal in `bin/massoh`). If the hook was created from
    scratch by `gate on`, it is removed entirely. The CI workflow file is left on disk (user-tracked;
    owner deletes manually per NON_NEGOTIABLES).
  - **Both commands are idempotent**: safe to run twice; no-op if already in target state.
  - **`scripts/massoh-gate-check`** — shared POSIX-bash checker. Runs in two modes:
    - Pre-push mode (default): reads `<local-ref> <local-sha> <remote-ref> <remote-sha>` from stdin.
    - CI mode (`--ci <base-ref>`): diffs `<base-ref>...HEAD` via git.
    - Exempt paths (never blocked): `*.md`, `.agent_tasks/*`, `agent-project/*`, `memory/*`,
      `AGENT_SYNC.md`, `AGENT_BACKLOG.md`, `.massoh`, `LICENSE`, `.gitignore`, `.gitattributes`,
      `.github/*`. Everything else (bin/, templates/, test/, manifest.yml, VERSION, …) is non-exempt.
    - If any non-exempt path is changed AND no `.agent_tasks/*/04_implementation_packet.md` exists:
      prints a blocking message and exits 1.
    - Escape hatches: `MASSOH_GATE_OVERRIDE=1` (prints warning, exits 0 — checked first, before
      any diff computation); `git push --no-verify` (standard git bypass; CI still checks).
    - Degrades safely: null-SHA (first push), empty diff, detached HEAD all exit 0.
  - **`templates/massoh-pre-push`** — hook wrapper installed into `.git/hooks/pre-push`.
  - **`templates/massoh-gate.yml`** — CI workflow template (GitHub Actions).
  - **`manifest.yml`** updated lockstep: new gate templates listed under `project_scaffold`;
    comment clarifies `.git/hooks/pre-push` is NOT manifest-tracked (per-repo ephemeral).
  - POSIX bash, `set -euo pipefail`, no non-portable deps. Zero LLM spend. Zero network.

## [0.8.0] - 2026-06-17
### Added
- **`massoh meta`** — the self-improvement loop: read-only heuristic miner (zero LLM spend).
  - **Finding 1 — Ledger cost outliers:** computes global mean tokens/row across `ledger.tsv`; flags
    any row where tokens > `OUTLIER_FACTOR` (2) × mean as an outlier stage candidate.
  - **Finding 2 — Rework rate:** counts packets where `06_review_result.md` has a
    `Decision.*REQUEST CHANGES` line; reports `rework_rate=%`. Flags if > 25%.
  - **Finding 3 — Backlog drift:** cross-references `AGENT_BACKLOG.md` TODO keywords against
    `AGENT_SYNC.md` decision log entries containing DONE/APPROVE/merged.
  - **Finding 4 — Repeated review findings:** counts keywords (5+ chars) in `## Blocking` sections
    across all `06_review_result.md` files; surfaces any class seen in >= `REPEAT_THRESHOLD` (3)
    packets as a "promote to enforced check" candidate.
  - Named constants: `OUTLIER_FACTOR=2`, `REPEAT_THRESHOLD=3` (auditable, patchable without re-read).
  - Degrades gracefully: absent ledger/packets/backlog → `(no X data)`, exit 0, no file created.
  - `--write-proposals`: appends `## [meta] <timestamp>` block to `agent-project/META.proposed.md`
    (append-only `>>`; the `[meta]` label namespaces vs. future `[intake]` entries; NEVER writes
    to STANDARDS/memory/adr/ledger/backlog/sync).
  - `--no-write` (default): read-only, prints to stdout only.
  - Non-Massoh-project guard: non-zero exit + "not a Massoh project" if no `.massoh` / `agent-project/`.
  - All `grep`/`awk`/`git` invocations guarded with `|| true` (set -euo pipefail safe).
  - Division-by-zero guarded in awk (mirrors `cmd_ledger` lines 766–777).
  - M5: standalone miner — does NOT call `cmd_learn`, `cmd_recommend`, or `cmd_ledger` internally.
- **`massoh-meta-engineer` role agent** (`claude/agents/massoh-meta-engineer.md`) — 7th agent in
  the team. Auto-installs via the existing `massoh-*.md` glob (no `manifest.yml` change). A
  PROPOSE-ONLY process/efficiency engineer: reads `massoh meta` output + ledger + packets; files
  engine-upgrade proposals to `agent-project/META.proposed.md` (labeled `[meta]`); routes all
  engine changes through the gate; never directly edits STANDARDS/memory/bin/massoh/safety files;
  never auto-merges engine changes.
- **`massoh doctor`** now finds 7 `massoh-*` agents (glob-enumerated dynamically; no code change).
- **Doc updates** (additive):
  - `policies/02_AGENT_ROLES.md`: 6 → 7 roles (added `massoh-meta-engineer` row).
  - `OPERATING_SYSTEM.md`: §4 routing updated to reference `@meta-engineer` + description of the
    7th role.
  - `README.md`: role table + introductory text + CLI reference updated to 7 roles.

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
