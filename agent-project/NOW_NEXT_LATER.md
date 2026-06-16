# NOW / NEXT / LATER — Massoh

## NOW (in flight)
None. Repo just opted in (`massoh on`, 2026-06-16). Awaiting first `/start-task`.

## NEXT (queued, agreed)
- `massoh discover` + a `STANDARDS.md` layer wired into Implementer/Reviewer (top borrow from
  buildermethods Agent OS).
- Enforce the license-to-code gate mechanically (pre-commit / pre-push + CI check).
- `bats` test suite for the CLI + `massoh doctor` (verify install vs `manifest.yml`).

## LATER (someday / maybe)
- Emit `AGENTS.md` → multi-harness (Cursor / Codex / Antigravity).
- Profiles (global default + project override) + a single `config.yml`.
- `massoh report` — aggregate packet outcomes (cycle time, reject/kill rate) from `.agent_tasks/`.
- Package as a Claude Code plugin / marketplace entry.

## FROZEN (do not build without an explicit owner unfreeze)
None yet. Mirror the authoritative list in `AGENT_SYNC.md` §Frozen.

## DEFERRED / KILLED (kept — never deleted)
| Item | Decision | Reason | Re-entry condition | Date |
|---|---|---|---|---|
| Multi-harness (`AGENTS.md`) | Defer | Prove Claude-Code flow first | ≥2 repos through gates | 2026-06-16 |
