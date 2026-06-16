# 04 — Implementation Packet (LICENSE TO CODE)

**Task:** TASK-2026-06-16-massoh-autonomous-fleet · **Branch:** `feat/massoh-autonomous-fleet`
**Authorized:** owner override (full fleet) + product-scope BUILD(01) + arch/safety YES(03,
conditional on safe defaults). All "mandatory safe defaults" are binding.

## Scope
1. **`bin/massoh-cron`** (new) — subcommands:
   - `once [--run|--dry-run] [--parallel N] [--auto-merge] [--no-idle-check] [--idle-min M]` —
     idleness gate → parse `AGENT_BACKLOG.md` top N unblocked TODO → per item: git worktree on
     `cron/<slug>`, invoke `$MASSOH_AGENT_CMD` (default `claude -p`), run `$MASSOH_GATE_CMD`,
     write result to `.agent_tasks/cron/<ts>-<slug>.md`; parent collects → marks DONE in backlog +
     appends ONE serialized `[cron]` block to `AGENT_SYNC.md`; remove worktrees (trap).
     `--auto-merge` (default off) merges `cron/<slug>`→`main` only if gate green.
   - `install [--every DUR] [--apply] [--yes-spend]` — generate a crontab line / systemd unit;
     print by default; only modify the user crontab with BOTH `--apply` and `--yes-spend`.
   - `off` — remove the installed schedule (if any).
   - `status` — print config + whether a schedule is installed.
2. **`bin/massoh`** — `cmd_cron()` forwards to `bin/massoh-cron`; dispatch `cron) ...`; usage string.
3. **`test/run.sh`** — T7 with a fixture repo + fake agent/gate (per `03`).
4. **`docs/AUTONOMOUS_CRON.md`** — append a "Wiring it (the runner)" section pointing at `massoh cron`.
5. **`CHANGELOG.md`** + **`VERSION`** → `0.3.0`.

## Mandatory safe defaults (binding)
dry-run default · auto-merge OFF default · idleness gate ON · `install` prints unless
`--apply --yes-spend` · injectable `MASSOH_AGENT_CMD`/`MASSOH_GATE_CMD` · serialized single-writer
AGENT_SYNC · worktree cleanup trap. No real `claude -p` call in tests (fakes only).

## Out of scope
Cross-repo fleet, cloud runner, computing file-disjointness automatically (owner/orchestrator ensures
items are independent), `--repair`.

## Acceptance
Per `03` test list. All prior 28 tests green. `massoh version` → 0.3.0.

## Rollback
Revert branch; `massoh cron off` removes any schedule artifact. Additive.

## Handoff
implementer → `05` → reviewer-qa → `06` → PR (owner merge).
