# 04 — Implementation Packet (LICENSE TO CODE): modularize bin/massoh → lib/verbs

- **Task ID:** TASK-2026-06-19-modularize-bin (24h queue #3)
- **Date issued:** 2026-06-19
- **Issued after:** arch-safety **APPROVED** (`03_architecture_safety.md`, MB1–MB8) + **owner
  batch-authorization** for `bin/massoh` edits on the 24h queue (AGENT_SYNC decision log 2026-06-19).
  No separate per-item sign-off required.
- **Target VERSION:** 0.11.0 (additive; install-contract touched → bump)
- **Branch:** `feat/modularize-bin`
- **Base:** main `ce831e2` (post-board, v0.10.0) — `bin/massoh` includes `cmd_board`.

## Scope (build exactly this — no more)
**Pure extraction.** Move the 12 additive feature verbs out of `bin/massoh` into sourced
`lib/verbs/<verb>.sh` files. **Zero behavior change** — same output, same exit codes, same flags.

**Stays in `bin/massoh`** (the safety-critical core, ~340 lines):
bootstrap (shebang, `set -euo pipefail`, `SELF`/`MASSOH_HOME`/`CLAUDE_DIR`, `say`/`die`/`mver`/`msha`);
all safety-critical helpers (`backup_claude`, `wire`, `block_present`, `add_block`, `remove_block`,
`scaffold`); safety-critical verbs (`cmd_install`, `cmd_update`, `cmd_enable`, `cmd_disable`,
`cmd_on`, `cmd_off`, `cmd_version`, `cmd_status`, `cmd_doctor`, `cmd_uninstall`); gate markers; the
new sourcing loop; the dispatch `case`.

**Moves to `lib/verbs/`** (12 units): `discover.sh`, `review.sh`, `standup.sh`, `plan.sh`,
`learn.sh`, `recommend.sh`, `ledger.sh`, `meta.sh`, `gate.sh` (cmd_gate + _gate_on/_gate_off),
`board.sh` (cmd_board + _board_* + globals), `cron.sh`, `work.sh`.

Plus: `manifest.yml` lists `lib/verbs/` (lockstep); `cmd_install` wires them into `~/.claude`;
`cmd_doctor` verifies them; `VERSION`→0.11.0; `CHANGELOG` `[0.11.0]`.

## Out of scope
No logic changes, no flag/output renames, no opportunistic cleanup, no new features. Extraction only.

## Mandatory conditions — MB1–MB8 (from `03`; all required, cite file:line in `05`)
- **MB1** Sourcing resolves verb files from `$MASSOH_HOME` (derived via the existing
  `readlink -f "${BASH_SOURCE[0]}"` bootstrap) — **symlink-safe**, never `$PWD`/relative.
- **MB2** (highest risk) `cmd_install` copies `lib/verbs/` into the installed layout AND `manifest.yml`
  lists them — **both ship in the same commit**. Installed `massoh` (run from `$PATH`/symlink) must
  find its verbs. One-release backward-compat: old layout still uninstalls cleanly.
- **MB3** Missing/unreadable lib file → **fail loudly** (`die`), never silently skip a verb.
- **MB4** `cmd_doctor` verifies `lib/verbs/` presence against the manifest.
- **MB5** **Byte-identical CLI output** — capture `massoh help`/`status`/`version` (+ representative
  verb outputs) before vs after; diff must be empty. Add this as a test.
- **MB6** Pure extraction — no logic edits to any moved verb.
- **MB7** Helpers sourced/defined before any verb that calls them (load order correct).
- **MB8** Full suite green (280 today) + 7 new `T-MB-*` checks → **target 287**.

## Required tests — T-MB-a…g (7 new; suite 280 → 287)
Per `03` §tests: byte-identical output (MB5); missing-lib-file fails loudly (MB3); installed-layout
path resolution works (simulate `$MASSOH_HOME` ≠ cwd); symlinked-invocation works (MB1);
`doctor` flags a missing verb file (MB4); safety-critical core unchanged (`md5sum` of the
install/uninstall/block region invariant); every verb still dispatches (smoke each).

## Acceptance criteria (implementer self-checks before handoff)
1. MB1–MB8 satisfied — file:line for each in `05_implementation_handoff.md`.
2. **Byte-identical proof** — paste the empty diff of pre/post CLI output.
3. T-MB-a…g present + green; full suite ≥287; verbatim output.
4. `bin/massoh` shrinks to the safety-critical core; 12 `lib/verbs/*.sh` created; no verb logic changed
   (diff = moves only).
5. `manifest.yml` + `cmd_install` + `cmd_doctor` updated in lockstep; VERSION 0.11.0; CHANGELOG.
6. Existing safety-critical verbs (`install`/`uninstall`/`on`/`off`/`enable`/`disable`/`status`/
   `doctor`/`update`/`version`) behave identically.

## Rollback
Revert the v0.11.0 PR — verbs return to inline `bin/massoh`; no data/contract loss (additive layout).
Full plan in `03_architecture_safety.md`.

## Routing
`massoh-implementer` → `05_implementation_handoff.md` → `massoh-reviewer-qa` (06) → owner merge.
Branch `feat/modularize-bin`, one PR. **PR left OPEN for owner merge** (batch-auth terms).
