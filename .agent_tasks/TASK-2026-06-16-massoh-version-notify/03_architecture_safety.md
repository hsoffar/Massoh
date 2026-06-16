# 03 — Architecture / Safety

**Agent:** massoh-architecture-safety · **Date:** 2026-06-16

## Impact
- `bin/massoh`: +`cmd_version`, +`version`/`--version`/`-v` dispatch, `cmd_status` prints version,
  `cmd_doctor` gains an opt-out best-effort update-check, install copies `VERSION`.
- `manifest.yml`: document `VERSION` in the global-install payload (contract change — both sides:
  `cmd_install` install loop **and** manifest updated together, per CHARTER API-contract seam).
- New files: `VERSION`, `CHANGELOG.md`.

## API/contract (the seam)
Adding `VERSION` to the install set = a contract change → **ship both sides together**: edit the
`for p in OPERATING_SYSTEM.md policies templates docs manifest.yml` loop to include `VERSION`, **and**
add VERSION to `manifest.yml` global_install. `uninstall` already removes all of `agent-os/`, so
VERSION is covered (no uninstall change needed — verify in a test).

## Safety risks + mitigations
- `bin/massoh`/`manifest.yml` safety-critical → **owner authorized** (deploy-question selection). OK.
- `doctor` adds network (`git fetch`). Risks: hangs offline, or surprises a user. Mitigations:
  best-effort with `2>/dev/null || true`, **opt-out** (`MASSOH_NO_FETCH` / `--offline`), and it
  **must not** change `doctor`'s exit code (staleness ≠ drift) → existing read-only md5 test still
  must pass (fetch writes to `.git`, not to `~/.claude`; the doctor read-only test snapshots
  `$CLAUDE_CONFIG_DIR`, not the clone — still valid).
- No change to block markers, `backup_claude`, or the uninstall removal set.

## Required tests (extend test/run.sh — real paths)
- `massoh version` prints `^massoh [0-9]`.
- `doctor` healthy clone → exit 0, no "update available".
- behind-clone (reset clone one commit back vs a remote that's ahead) → "update available" + exit 0.
- `MASSOH_NO_FETCH=1 doctor` → exit 0, no network (point origin at a bogus URL to prove no hang/fail).
- install copies VERSION; uninstall removes it (agent-os wiped).
- all prior 21 checks still green.

## Rollback
Additive → revert branch. No state.

## Approved for implementation? **YES**
Owner-authorized the safety-critical edits; conditions: doctor stays FS-read-only + offline-safe +
exit-code-stable; manifest and install loop change **together**; network is opt-out.
