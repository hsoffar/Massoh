# 04 — Implementation Packet (LICENSE TO CODE)

**Task:** TASK-2026-06-16-massoh-version-notify · **Branch:** `feat/massoh-version-notify` (off main)
**Authorized:** owner (deploy-question selection) + product-scope BUILD(01) + arch/safety YES(03).

## Scope (exactly this)
1. **`VERSION`** file at repo root, content `0.2.0`.
2. **`bin/massoh`**:
   - `cmd_version()` → prints `massoh <VERSION-file> (<git short SHA>)`. `MASSOH_VERSION` resolves
     from `$MASSOH_HOME/VERSION` (fallback `unknown`).
   - dispatch: `version|--version|-v) cmd_version ;;`. Add to usage string.
   - `cmd_status`: add a `version:` line.
   - `cmd_doctor`: after the checks, **best-effort update-check** — unless `MASSOH_NO_FETCH=1` or
     `--offline` arg: `git -C $MASSOH_HOME fetch -q origin 2>/dev/null || true`; if
     `HEAD` != `origin/main` and HEAD is an ancestor of origin/main → print
     `update available → massoh update`. **Never** change exit code from this.
   - install loop: add `VERSION` to `for p in ...`.
3. **`manifest.yml`**: add `VERSION` to the `agent-os/` global_install payload note (both-sides).
4. **`CHANGELOG.md`**: Keep-a-Changelog; `## [0.2.0] - 2026-06-16` covering discover/doctor/update
   + this version/notify work; `## [0.1.0]` initial.
5. **`test/run.sh`**: add T6 (version + update-check + offline-safe + VERSION install/uninstall).

## Out of scope
No auto-update, no telemetry, no migration runner, no `doctor --repair`. No other verb gains network.

## Required tests / acceptance
Per `03`. `doctor` stays FS-read-only (existing md5 snapshot test must still pass) + offline-safe +
exit-stable. All prior 21 checks green.

## Rollback
`git revert` the branch. Additive only.

## Handoff
implementer → `05` → reviewer-qa → `06` → PR (owner merge).
